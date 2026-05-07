import Foundation

/// Minimal ID3v2.3 tag writer for MP3 files. Replaces any existing ID3v2 tag at the
/// start of the file with a new tag containing the supplied frames. Audio data
/// (and any trailing ID3v1 tag) is preserved.
enum ID3Writer {

    enum WriteError: Error { case readFailed, writeFailed }

    static func write(metadata: SongMetadata, to url: URL) throws {
        let original = try Data(contentsOf: url)
        let audioStart = existingTagSize(in: original)
        let audioData = original.subdata(in: audioStart..<original.count)

        var frames = Data()
        appendTextFrame(id: "TIT2", text: metadata.title,       into: &frames)
        appendTextFrame(id: "TPE1", text: metadata.artist,      into: &frames)
        appendTextFrame(id: "TALB", text: metadata.album,       into: &frames)
        appendTextFrame(id: "TPE2", text: metadata.albumArtist, into: &frames)
        appendTextFrame(id: "TYER", text: metadata.year,        into: &frames)
        appendTextFrame(id: "TCON", text: metadata.genre,       into: &frames)
        appendTextFrame(id: "TRCK", text: metadata.track,       into: &frames)

        // Padding allows future tag growth without rewrites.
        let padding = Data(count: 256)
        let body = frames + padding

        var header = Data()
        header.append(contentsOf: [0x49, 0x44, 0x33]) // "ID3"
        header.append(contentsOf: [0x03, 0x00])       // v2.3.0
        header.append(0x00)                            // flags
        header.append(synchsafe(UInt32(body.count)))   // size

        let output = header + body + audioData
        try output.write(to: url, options: .atomic)
    }

    private static func appendTextFrame(id: String, text: String?, into data: inout Data) {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              id.count == 4 else { return }

        // Encoding 0x01 = UTF-16 with BOM. Terminator is two zero bytes.
        var payload = Data()
        payload.append(0x01)
        payload.append(contentsOf: [0xFF, 0xFE]) // little-endian BOM
        for scalar in raw.unicodeScalars {
            for unit in String(scalar).utf16 {
                payload.append(UInt8(unit & 0xFF))
                payload.append(UInt8((unit >> 8) & 0xFF))
            }
        }
        payload.append(contentsOf: [0x00, 0x00])

        data.append(contentsOf: Array(id.utf8))
        data.append(uint32BE(UInt32(payload.count)))
        data.append(contentsOf: [0x00, 0x00])    // frame flags
        data.append(payload)
    }

    private static func uint32BE(_ value: UInt32) -> Data {
        var data = Data(count: 4)
        data[0] = UInt8((value >> 24) & 0xFF)
        data[1] = UInt8((value >> 16) & 0xFF)
        data[2] = UInt8((value >> 8) & 0xFF)
        data[3] = UInt8(value & 0xFF)
        return data
    }

    private static func synchsafe(_ value: UInt32) -> Data {
        var data = Data(count: 4)
        data[0] = UInt8((value >> 21) & 0x7F)
        data[1] = UInt8((value >> 14) & 0x7F)
        data[2] = UInt8((value >> 7) & 0x7F)
        data[3] = UInt8(value & 0x7F)
        return data
    }

    private static func existingTagSize(in data: Data) -> Int {
        guard data.count >= 10 else { return 0 }
        guard data[0] == 0x49, data[1] == 0x44, data[2] == 0x33 else { return 0 }
        let s0 = UInt32(data[6] & 0x7F) << 21
        let s1 = UInt32(data[7] & 0x7F) << 14
        let s2 = UInt32(data[8] & 0x7F) << 7
        let s3 = UInt32(data[9] & 0x7F)
        let bodySize = Int(s0 | s1 | s2 | s3)
        return 10 + bodySize
    }
}
