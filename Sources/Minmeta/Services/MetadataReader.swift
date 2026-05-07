import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox

enum MetadataReader {
    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "mp4", "aac", "flac", "wav", "aiff", "aif", "ogg"
    ]

    struct ReadResult {
        var meta: SongMetadata
        var tech: TechInfo
    }

    /// Reads metadata + technical info from a file using AVFoundation +
    /// AudioToolbox. Returns whatever it can parse; fields it can't discover
    /// stay nil.
    static func read(url: URL) async -> ReadResult {
        async let metaTask: SongMetadata = readTags(url: url)
        async let techTask: TechInfo     = readTech(url: url)
        let (meta, tech) = await (metaTask, techTask)
        return ReadResult(meta: meta, tech: tech)
    }

    // MARK: - Tag reading

    private static func readTags(url: URL) async -> SongMetadata {
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
        case k.contains("composer") && meta.composer == nil:
            meta.composer = value
        case k.contains("copyright") && meta.copyright == nil:
            meta.copyright = value
        case (k.contains("lyrics") || k.contains("uslt")) && meta.lyrics == nil:
            meta.lyrics = value
        default:
            break
        }
    }

    // MARK: - Technical info

    private static func readTech(url: URL) async -> TechInfo {
        var tech = TechInfo()
        let asset = AVURLAsset(url: url)

        // Duration
        if let dur = try? await asset.load(.duration) {
            let secs = CMTimeGetSeconds(dur)
            if secs.isFinite, secs > 0 { tech.durationSeconds = secs }
        }

        // Audio track props
        if let track = try? await asset.loadTracks(withMediaType: .audio).first {
            if let descs = try? await track.load(.formatDescriptions),
               let desc = descs.first {
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                    if asbd.mSampleRate > 0 {
                        tech.sampleRateHz = Int(asbd.mSampleRate)
                    }
                    tech.channels = Int(asbd.mChannelsPerFrame)
                    tech.codec = fourCharCode(asbd.mFormatID)
                }
            }
            if let bitsPerSec = try? await track.load(.estimatedDataRate) {
                let kbps = Int((Double(bitsPerSec) / 1000.0).rounded())
                if kbps > 0 { tech.bitrateKbps = kbps }
            }
        }

        return tech
    }

    private static func fourCharCode(_ value: AudioFormatID) -> String? {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8)  & 0xFF),
            UInt8( value        & 0xFF)
        ]
        let s = String(bytes: bytes, encoding: .ascii) ?? ""
        let trimmed = s.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: .controlCharacters)
        return trimmed.isEmpty ? nil : trimmed
    }
}
