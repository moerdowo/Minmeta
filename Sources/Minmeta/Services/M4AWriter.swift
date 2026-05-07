import Foundation
import AVFoundation

/// Writes iTunes-style metadata atoms into an M4A / MP4-audio container by
/// re-exporting through AVAssetExportSession with passthrough audio.
enum M4AWriter {

    enum WriteError: Error, LocalizedError {
        case unsupportedAsset
        case exportFailed(String)
        case replaceFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedAsset:        return "Asset cannot be exported"
            case .exportFailed(let r):     return "Export failed: \(r)"
            case .replaceFailed(let r):    return "Replace failed: \(r)"
            }
        }
    }

    static func write(metadata: SongMetadata,
                      artwork: Artwork?,
                      to url: URL) async throws {
        let asset = AVURLAsset(url: url)

        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetPassthrough)
        else { throw WriteError.unsupportedAsset }

        let tmpDir = FileManager.default.temporaryDirectory
        let tmpURL = tmpDir.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        session.outputURL = tmpURL
        session.outputFileType = .m4a
        session.shouldOptimizeForNetworkUse = true
        session.metadata = buildMetadata(from: metadata, artwork: artwork)

        await session.export()

        switch session.status {
        case .completed:
            break
        case .failed, .cancelled:
            throw WriteError.exportFailed(session.error?.localizedDescription ?? "unknown")
        default:
            throw WriteError.exportFailed("status \(session.status.rawValue)")
        }

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
        } catch {
            throw WriteError.replaceFailed(error.localizedDescription)
        }
    }

    private static func buildMetadata(from m: SongMetadata,
                                      artwork: Artwork?) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []

        func addText(_ key: AVMetadataIdentifier, _ value: String?) {
            guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !v.isEmpty else { return }
            let item = AVMutableMetadataItem()
            item.identifier = key
            item.value = v as NSString
            item.extendedLanguageTag = "und"
            items.append(item)
        }

        addText(.iTunesMetadataSongName,        m.title)
        addText(.iTunesMetadataArtist,          m.artist)
        addText(.iTunesMetadataAlbum,           m.album)
        addText(.iTunesMetadataAlbumArtist,     m.albumArtist)
        addText(.iTunesMetadataReleaseDate,     m.year)
        addText(.iTunesMetadataUserGenre,       m.genre)
        addText(.iTunesMetadataComposer,        m.composer)
        addText(.iTunesMetadataCopyright,       m.copyright)
        addText(.iTunesMetadataLyrics,          m.lyrics)

        // Track number — dedicated number-typed atom when parseable.
        if let trk = m.track,
           let n = Int(trk.trimmingCharacters(in: .whitespacesAndNewlines)),
           n > 0 {
            let item = AVMutableMetadataItem()
            item.identifier = .iTunesMetadataTrackNumber
            item.value = NSNumber(value: n)
            items.append(item)
        }

        // Cover art atom (covr).
        if let art = artwork {
            let item = AVMutableMetadataItem()
            item.identifier = .iTunesMetadataCoverArt
            item.value = art.data as NSData
            item.dataType = "com.apple.metadata.datatype.JPEG"
            items.append(item)
        }

        // Mirror into common keys for broader reader support.
        addText(.commonIdentifierTitle,        m.title)
        addText(.commonIdentifierArtist,       m.artist)
        addText(.commonIdentifierAlbumName,    m.album)

        return items
    }
}
