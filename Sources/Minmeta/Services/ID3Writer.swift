import Foundation

/// Minimal ID3v2.3 tag writer for MP3 files. Replaces any existing ID3v2 tag at
/// the start of the file with a new tag containing the supplied frames. Audio
/// data (and any trailing ID3v1 tag) is preserved.
///
/// Supported frames (ID3v2.3):
///   TIT2 title · TPE1 artist · TALB album · TPE2 album artist
///   TYER year  · TCON genre  · TRCK track · TCOM composer
///   TCOP copyright · USLT lyrics · APIC attached picture
enum ID3Writer {

    enum WriteError: Error { case readFailed, writeFailed }

    static func write(metadata: SongMetadata,
                      artwork: Artwork?,
                      to url: URL) throws {
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
        appendTextFrame(id: "TCOM", text: metadata.composer,    into: &frames)
        appendTextFrame(id: "TCOP", text: metadata.copyright,   into: &frames)
        appendLyricsFrame(text: metadata.lyrics,                into: &frames)
        if let art = artwork {
            appendPictureFrame(artwork: art, into: &frames)
        }

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

    // MARK: - Text frames

    private static func appendTextFrame(id: String, text: String?, into data: inout Data) {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              id.count == 4 else { return }

        // Encoding 0x01 = UTF-16 with BOM. Terminator is two zero bytes.
        var payload = Data()
        payload.append(0x01)
        payload.append(utf16WithBOM(raw))
        payload.append(contentsOf: [0x00, 0x00])

        appendFrameHeader(id: id, payloadSize: payload.count, into: &data)
        data.append(payload)
    }

    // MARK: - USLT (Unsynchronized lyrics)
    //
    // Frame body: <text encoding> <language (3 bytes)> <content descriptor null-terminated> <lyrics>

    private static func appendLyricsFrame(text: String?, into data: inout Data) {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return }

        var payload = Data()
        payload.append(0x01)                              // encoding: UTF-16
        payload.append(contentsOf: Array("eng".utf8))     // language
        // content descriptor (empty) + null terminator (UTF-16)
        payload.append(contentsOf: [0xFF, 0xFE, 0x00, 0x00])
        payload.append(utf16WithBOM(raw))

        appendFrameHeader(id: "USLT", payloadSize: payload.count, into: &data)
        data.append(payload)
    }

    // MARK: - APIC (Attached picture)
    //
    // Frame body: <text encoding> <MIME null-terminated ascii> <picture type (1B)>
    //             <description null-terminated> <picture data>

    private static func appendPictureFrame(artwork: Artwork, into data: inout Data) {
        let mime = artwork.mime.isEmpty ? "image/jpeg" : artwork.mime
        var payload = Data()
        payload.append(0x00)                            // encoding: ISO-8859-1 (for description)
        payload.append(contentsOf: Array(mime.utf8))    // MIME
        payload.append(0x00)                            // null terminator
        payload.append(0x03)                            // picture type 0x03 = front cover
        payload.append(0x00)                            // description: empty + null
        payload.append(artwork.data)                    // picture bytes

        appendFrameHeader(id: "APIC", payloadSize: payload.count, into: &data)
        data.append(payload)
    }

    // MARK: - Helpers

    private static func appendFrameHeader(id: String, payloadSize: Int, into data: inout Data) {
        data.append(contentsOf: Array(id.utf8))
        data.append(uint32BE(UInt32(payloadSize)))
        data.append(contentsOf: [0x00, 0x00])           // frame flags
    }

    private static func utf16WithBOM(_ s: String) -> Data {
        var out = Data()
        out.append(contentsOf: [0xFF, 0xFE])            // little-endian BOM
        for scalar in s.unicodeScalars {
            for unit in String(scalar).utf16 {
                out.append(UInt8(unit & 0xFF))
                out.append(UInt8((unit >> 8) & 0xFF))
            }
        }
        return out
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
