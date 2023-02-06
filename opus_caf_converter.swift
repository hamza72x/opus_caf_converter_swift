import UIKit

var greeting = "Hello, playground"

struct FourByteString {
    var data: [UInt8]
    
    init(string str: String) {
        data = Array(str.utf8)
    }
}

let ChunkTypeAudioDescription = FourByteString(string: "desc")
let ChunkTypeChannelLayout = FourByteString(string: "chan")
let ChunkTypeInformation = FourByteString(string: "info")
let ChunkTypeAudioData = FourByteString(string: "data")
let ChunkTypePacketTable = FourByteString(string: "pakt")
let ChunkTypeMidi = FourByteString(string: "midi")

struct ChunkHeader {
    var chunkType: FourByteString
    var chunkSize: Int64
}



struct AudioFormat {
    var sampleRate: Float64
    var formatID: FourByteString
    var formatFlags: UInt32
    var bytesPerPacket: UInt32
    var framesPerPacket: UInt32
    var channelsPerPacket: UInt32
    var bitsPerChannel: UInt32
}

struct PacketTableHeader {
    var numberPackets: Int64
    var numberValidFrames: Int64
    var primingFrames: Int32
    var remainderFrames: Int32
}

struct PacketTable {
    var header: PacketTableHeader
    var entry: [UInt64]
    
    func decode(from reader: Data) throws {
        var cursor = reader.startIndex
        
        header.numberPackets = reader.read(from: &cursor, as: Int64.self)
        header.numberValidFrames = reader.read(from: &cursor, as: Int64.self)
        header.primingFrames = reader.read(from: &cursor, as: Int32.self)
        header.remainderFrames = reader.read(from: &cursor, as: Int32.self)
        
        entry = []
        for _ in 0 ..< Int(header.numberPackets) {
            let value = try reader.readVarInt(from: &cursor)
            entry.append(value)
        }
    }
    
    func encode() -> Data {
        var data = Data()
        
        data.append(header.numberPackets, as: Int64.self)
        data.append(header.numberValidFrames, as: Int64.self)
        data.append(header.primingFrames, as: Int32.self)
        data.append(header.remainderFrames, as: Int32.self)
        
        for value in entry {
            try! data.appendVarInt(value)
        }
        
        return data
    }
}


struct File {
    var fileHeader: FileHeader
    var chunks: [Chunk]
}


extension File {
    func decode(reader: Data) throws {
        let data = reader.withUnsafeBytes {
            [UInt8](UnsafeBufferPointer(start: $0, count: reader.count))
        }
        var index = 0
        fileHeader = try FileHeader.decode(data: data, index: &index)
        chunks = []
        while index < data.count {
            let chunk = try Chunk.decode(data: data, index: &index)
            chunks.append(chunk)
        }
    }
    func encode() throws -> Data {
        var data = fileHeader.encode()
        for chunk in chunks {
            data.append(contentsOf: try chunk.encode())
        }
        return data
    }
}


struct Information {
    var key: String
    var value: String
}

func readString(from reader: Reader) throws -> String {
    var bs = [UInt8]()
    var b = [UInt8](repeating: 0, count: 1)
    while true {
        let count = try reader.read(&b)
        if count == 0 {
            throw ReaderError.endOfStream
        }
        bs.append(b[0])
        if b[0] == 0 {
            break
        }
    }
    return String(bytes: bs, encoding: .utf8)!
}

func writeString(to writer: Writer, _ string: String) throws {
    let data = string.data(using: .utf8)!
    try writer.write(data)
}

extension Information {
    mutating func decode(from reader: Reader) throws {
        key = try readString(from: reader)
        value = try readString(from: reader)
    }
    
    func encode(to writer: Writer) throws {
        try writeString(to: writer, key)
        try writeString(to: writer, value)
    }
}

struct CAFStringsChunk {
    var numEntries: UInt32
    var strings: [Information]
}

extension CAFStringsChunk {
    mutating func decode(from reader: Reader) throws {
        numEntries = try reader.read(UInt32.self)
        strings = [Information]()
        for _ in 0..<numEntries {
            var info = Information()
            try info.decode(from: reader)
            strings.append(info)
        }
    }
    
    func encode(to writer: Writer) throws {
        try writer.write(numEntries)
        for info in strings {
            try info.encode(to: writer)
        }
    }
}

struct Chunk {
    var header: ChunkHeader
    var contents: Any
}

extension AudioFormat {
    mutating func decode(from reader: Reader) throws {
        try reader.read(&self)
    }
    
    func encode(to writer: Writer) throws {
        try writer.write(self)
    }
}

struct ChannelDescription {
    var channelLabel: UInt32
    var channelFlags: UInt32
    var coordinates: [Float32]
}

struct UnknownContents {
    var data: [UInt8]
}

typealias Midi = [UInt8]

struct ChannelLayout {
    var ChannelLayoutTag: UInt32
    var ChannelBitmap: UInt32
    var NumberChannelDescriptions: UInt32
    var Channels: [ChannelDescription]
    
    mutating func decode(from reader: inout Data) throws {
        ChannelLayoutTag = try reader.read(as: UInt32.self, endianess: .big)
        ChannelBitmap = try reader.read(as: UInt32.self, endianess: .big)
        NumberChannelDescriptions = try reader.read(as: UInt32.self, endianess: .big)
        
        for i in 0..<NumberChannelDescriptions {
            var channelDesc = ChannelDescription()
            try channelDesc.decode(from: &reader)
            Channels.append(channelDesc)
        }
    }
    
    func encode(to writer: inout Data) throws {
        try writer.write(ChannelLayoutTag, endianess: .big)
        try writer.write(ChannelBitmap, endianess: .big)
        try writer.write(NumberChannelDescriptions, endianess: .big)
        for i in 0..<NumberChannelDescriptions {
            try Channels[i].encode(to: &writer)
        }
    }
}

struct Data {
    var EditCount: UInt32
    var Data: [Byte]
    
    
    mutating func decode(from reader: inout Data, header: ChunkHeader) throws {
        EditCount = try reader.read(as: UInt32.self, endianess: .big)
        if header.ChunkSize == -1 {
            Data = try reader.readUntilEnd()
        } else {
            let dataLength = header.ChunkSize - 4
            Data = try reader.read(count: dataLength)
        }
    }
    
    func encode(to writer: inout Data) throws {
        try writer.write(EditCount, endianess: .big)
        try writer.write(Data)
    }
}

func decode(from reader: inout Data) throws {
    var header = ChunkHeader()
    try header.decode(from: &reader)
    switch header.chunkType {
    case .audioDescription:
        let cc = AudioFormat()
        try cc.decode(from: &reader)
        contents = cc
    case .channelLayout:
        let cc = ChannelLayout()
        try cc.decode(from: &reader)
        contents = cc
    case .information:
        let cc = CAFStringsChunk()
        try cc.decode(from: &reader)
        contents = cc
    case .audioData:
        let cc = Data(header: header)
        try cc.decode(from: &reader)
        contents = cc
    case .packetTable:
        let cc = PacketTable()
        try cc.decode(from: &reader)
        contents = cc
    case .midi:
        let size = header.chunkSize
        let cc = reader.readData(ofLength: size)
        contents = cc as Any
    default:
        let size = header.chunkSize
        let cc = reader.readData(ofLength: size)
        contents = UnknownContents(data: cc)
    }
}


func Encode(chunk: inout Chunk, to writer: inout Data) throws {
    var header = chunk.header
    try writer.write(from: &header, size: MemoryLayout<ChunkHeader>.size)
    switch chunk.header.chunkType {
    case .audioDescription:
        let audioFormat = chunk.contents as! AudioFormat
        try audioFormat.encode(to: &writer)
    case .channelLayout:
        let channelLayout = chunk.contents as! ChannelLayout
        try channelLayout.encode(to: &writer)
    case .information:
        let cafStringsChunk = chunk.contents as! CAFStringsChunk
        try cafStringsChunk.encode(to: &writer)
    case .audioData:
        let data = chunk.contents as! Data
        try data.encode(to: &writer)
    case .packetTable:
        let packetTable = chunk.contents as! PacketTable
        try packetTable.encode(to: &writer)
    case .midi:
        let midi = chunk.contents as! Midi
        writer.append(midi)
    default:
        let unknownContents = chunk.contents as! UnknownContents
        writer.append(unknownContents.data)
    }
}

struct FileHeader {
    var fileType: FourByteString
    var fileVersion: Int16
    var fileFlags: Int16
}


extension FileHeader {
    func decode(from reader: Data) throws {
        let headerData = reader.withUnsafeBytes { Data(bytes: $0, count: MemoryLayout<FileHeader>.size) }
        var header = headerData.map { $0 }
        header = header.reversed()
        fileType = Array(header[0...3]).reversed()
        fileVersion = UInt16(bytes: (header[4], header[5]))
        fileFlags = UInt16(bytes: (header[6], header[7]))
        
        guard String(bytes: fileType, encoding: .ascii) == "caff" else {
            throw NSError(domain: "Invalid CAFF header", code: 0, userInfo: nil)
        }
    }
    
    func encode() -> Data {
        var header = [UInt8]()
        header.append(contentsOf: fileType.reversed())
        header.append(contentsOf: fileVersion.bytes.reversed())
        header.append(contentsOf: fileFlags.bytes.reversed())
        return Data(header)
    }
}



// Opus

import Foundation

enum OggError: Error {
    case nilStream
    case badIDPageSignature
    case badIDPageType
    case badIDPageLength
    case badIDPagePayloadSignature
    case shortPageHeader
}

func newWith(stream: Data) throws -> (OggReader, OggHeader) {
    let reader = OggReader(stream: stream)
    let header = try readHeaders(reader: reader)
    return (reader, header)
}

struct OggPageHeader {
    var sig: [UInt8]
    var version: UInt8
    var headerType: UInt8
    var granulePosition: UInt64
    var serial: UInt32
    var index: UInt32
    var segmentsCount: UInt8
}

struct OggHeader {
    var version: UInt8
    var channels: UInt8
    var preSkip: UInt16
    var sampleRate: UInt32
    var outputGain: UInt16
    var channelMap: UInt8
}

func readHeaders() throws -> OggHeader {
    let (segments, pageHeader, error) = try parseNextPage()
    if error != nil {
        throw error
    }
    
    let header = OggHeader()
    
    let pageHeaderSignature = "OggS"
    if String(bytes: pageHeader.sig, encoding: .utf8) != pageHeaderSignature {
        throw "Bad ID Page Signature"
    }
    
    let pageHeaderTypeBeginningOfStream: UInt8 = 1
    if pageHeader.headerType != pageHeaderTypeBeginningOfStream {
        throw "Bad ID Page Type"
    }
    
    let idPagePayloadLength = 28
    if segments[0].count != idPagePayloadLength {
        throw "Bad ID Page Length"
    }
    
    let idPageSignature = "OpusHead"
    if String(bytes: Array(segments[0][0...7]), encoding: .utf8) != idPageSignature {
        throw "Bad ID Page Payload Signature"
    }
    
    header.version = segments[0][8]
    header.channels = segments[0][9]
    header.preSkip = segments[0][10...11].withUnsafeBytes { $0.load(as: UInt16.self) }
    header.sampleRate = segments[0][12...15].withUnsafeBytes { $0.load(as: UInt32.self) }
    header.outputGain = segments[0][16...17].withUnsafeBytes { $0.load(as: UInt16.self) }
    header.channelMap = segments[0][18]
    
    return header
}

class OggReader {
    let stream: InputStream
    
    init(stream: InputStream) {
        self.stream = stream
    }
    
    
    
    func parseNextPage() -> ([[UInt8]], OggPageHeader?, Error?) {
        var h = [UInt8](repeating: 0, count: pageHeaderLen)
        
        let n = stream.read(&h, maxLength: h.count)
        if n < h.count {
            return ([], nil, errShortPageHeader)
        }
        
        let pageHeader = OggPageHeader(
            sig: [h[0], h[1], h[2], h[3]],
            version: h[4],
            headerType: h[5],
            granulePosition: h.withUnsafeBytes { $0.load(fromByteOffset: 6, as: UInt64.self) },
            serial: h.withUnsafeBytes { $0.load(fromByteOffset: 14, as: UInt32.self) },
            index: h.withUnsafeBytes { $0.load(fromByteOffset: 18, as: UInt32.self) },
            segmentsCount: h[26]
        )
        
        var sizeBuffer = [UInt8](repeating: 0, count: Int(pageHeader.segmentsCount))
        let _ = stream.read(&sizeBuffer, maxLength: sizeBuffer.count)
        
        var newArr = [Int]()
        for (i, size) in sizeBuffer.enumerated() {
            if size == 255 {
                var sum = Int(size)
                i += 1
                while i < sizeBuffer.count && sizeBuffer[i] == 255 {
                    sum += Int(sizeBuffer[i])
                    i += 1
                }
                if i < sizeBuffer.count {
                    sum += Int(sizeBuffer[i])
                }
                newArr.append(sum)
            } else {
                newArr.append(Int(size))
            }
        }
        
        var segments = [[UInt8]]()
        
        for s in newArr {
            var segment = [UInt8](repeating: 0, count: s)
            let _ = stream.read(&segment, maxLength: segment.count)
            
            segments.append(segment)
        }
        
        return (segments, pageHeader, nil)
    }
    
    func convertOpusToCaf(i: String, o: String) {
        guard let file = FileHandle(forReadingAtPath: i) else {
            fatalError("Failed to open input file")
        }
        
        guard let ogg = NewWith(file: file), let header = header else {
            fatalError("Failed to create ogg and header")
        }
        
        var audioData = Data()
        var frameSize = 0
        var trailingData = [UInt64]()
        let packetTableLength = 24
        
        repeat {
            guard let segments = ogg.parseNextPage(), let header = header else {
                break
            }
            
            if segments[0].hasPrefix("OpusTags") {
                continue
            }
            
            for segment in segments {
                trailingData.append(UInt64(segment.count))
                audioData.append(segment)
            }
            
            if header.index == 2 {
                let tmpPacket = segments[0]
                if !tmpPacket.isEmpty {
                    let tmptoc = tmpPacket[0] & 255
                    let tocConfig = tmptoc >> 3
                    let length = UInt32(tocConfig & 3)
                    if tocConfig < 12 {
                        frameSize = Int(max(480, 960 * Int(length)))
                    } else if tocConfig < 16 {
                        frameSize = 480 << (tocConfig & 1)
                    } else {
                        frameSize = 120 << (tocConfig & 3)
                    }
                }
            }
        } while true
        
        let lenAudio = audioData.count
        let packets = trailingData.count
        let frames = frameSize * packets
        
        for i in 0..<packets {
            let value = UInt32(trailingData[i])
            var numBytes = 0
            if (value & 0x7f) == value {
                numBytes = 1
            } else if (value & 0x3fff) == value {
                numBytes = 2
            } else if (value & 0x1fffff) == value {
                numBytes = 3
            } else if (value & 0x0fffffff) == value {
                numBytes = 4
            } else {
                numBytes = 5
            }
            packetTableLength += numBytes
        }
        
        let cf = FileHeader(fileType: FourByteString(99, 97, 102, 102), fileVersion: 1, fileFlags: 0)
        var chunks = [Chunk]()
        
        let c = Chunk(header: ChunkHeader(chunkType: ChunkTypeAudioDescription, chunkSize: 32), contents: AudioFormat(sampleRate: 48000, formatID: FourByteString(111, 112, 117, 115), formatFlags: 0x00000000, bytesPerPacket: 0, framesPerPacket: UInt32(frameSize), bitsPerChannel: 0, channelsPerPacket: UInt32(header.channels)))
        chunks.append(c)
        
        var channelLayoutTag: UInt32
        if header.channels == 2 {
            channelLayoutTag = 6619138
        } else {
            channelLayoutTag = 6553601
        }
        
        let c1 = Chunk(header: ChunkHeader(chunkType: ChunkTypeChannelLayout, chunkSize: 12), contents: ChannelLayout(channelLayoutTag: channelLayoutTag, channelBitmap: 0x0, numberChannelDescriptions: 0, channels: []))
        chunks.append(c1)
        
        let c2 = Chunk(header: ChunkHeader(chunkType: ChunkTypeInformation, chunkSize: 26), contents: CAFStringsChunk(numEntries: 1, strings: [Information(key: "encoder\0", value: "Lavf59.27.100\0")]))
        chunks.append(c2)
        
        let c3 = Chunk(header: ChunkHeader(chunkType: ChunkTypeAudioData, chunkSize: Int64(lenAudio + 4)), contents: Data(data: audioData))
        chunks.append(c3)
        
        let c4 = Chunk(header: ChunkHeader(chunkType: ChunkTypePacketTable, chunkSize: Int64(packetTableLength)), contents: PacketTable(header: PacketTableHeader(numberPackets: Int64(packets), numberValidFrames: Int64(frames), primingFrames: 0, remainderFrames: 0), entry: trailingData))
        chunks.append(c4)
        
        let outputBuffer = Data()
        cf.encode(to: outputBuffer)
        let output = outputBuffer.bytes
        if let outfile = FileHandle(forWritingAtPath: o) {
            outfile.write(output)
            outfile.closeFile()
        }
        
        
    }
}

