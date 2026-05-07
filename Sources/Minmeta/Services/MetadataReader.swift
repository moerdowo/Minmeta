import Foundation
import AVFoundation

enum MetadataReader {
    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "mp4", "aac", "flac", "wav", "aiff", "aif", "ogg"
    ]

    /// Reads metadata from a file using AVFoundation. Returns whatever it can parse;
    /// fields that cannot be discovered remain nil.
    static func read(url: URL) async -> SongMetadata {
        var meta = SongMetadata()
        let asset = AVURLAsset(url: url)
        do {
            let formats = try await asset.load(.availableMetadataFormats)
            for format in formats {
                let items = try await asset.loadMetadata(for: format)
                for item in items {
                    let value = try? await item.load(.stringValue)
                    let key = identifierKey(for: item)
                    apply(value: value, key: key, into: &meta)
                }
            }
        } catch {
            // best-effort
        }
        return meta
    }

    private static func identifierKey(for item: AVMetadataItem) -> String {
        if let ident = item.identifier?.rawValue { return ident.lowercased() }
        if let key = item.commonKey?.rawValue { return key.lowercased() }
        return ""
    }

    private static func apply(value: String?, key: String, into meta: inout SongMetadata) {
        guard let value = value, !value.isEmpty else { return }
        let k = key
        switch true {
        case k.contains("title") && meta.title == nil:
            meta.title = value
        case k.contains("album") && k.contains("artist") && meta.albumArtist == nil:
            meta.albumArtist = value
        case (k.contains("artist") && !k.contains("album")) && meta.artist == nil:
            meta.artist = value
        case k.contains("album") && meta.album == nil:
            meta.album = value
        case (k.contains("year") || k.contains("date") || k.contains("creationdate"))
              && meta.year == nil:
            meta.year = String(value.prefix(4))
        case k.contains("genre") && meta.genre == nil:
            meta.genre = value
        case (k.contains("track") || k.contains("tracknumber")) && meta.track == nil:
            meta.track = value
        default:
            break
        }
    }
}
