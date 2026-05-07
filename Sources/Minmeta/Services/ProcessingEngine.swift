import Foundation
import SwiftUI
import OSLog

/// Drives the queue: pulls pending items, asks the model for missing fields,
/// fetches album art, merges with what we read off-disk, and writes the result
/// back into the file.
///
/// Reliability notes:
/// - Uses a worker-pool pattern (N workers each pulling next pending) — easier
///   to reason about than a producer/consumer task group.
/// - processOne() has a `defer` that guarantees the item leaves `.processing`
///   even if a path is missed — so the queue never gets stuck visually.
/// - Every state transition emits an OSLog line so a stuck queue is debuggable
///   from Console.app: filter on `subsystem:id.moerdowo.minmeta`.
@MainActor
final class ProcessingEngine {
    private weak var state: AppState?
    private var task: Task<Void, Never>?

    /// Number of files processed in parallel.
    private let concurrency = 3

    init(state: AppState) { self.state = state }

    func kick() {
        if task != nil {
            log.info("kick: already running, no-op")
            return
        }
        log.info("kick: starting new run task")
        task = Task { [weak self] in
            await self?.run()
            self?.task = nil
        }
    }

    private func run() async {
        guard let state = state else { return }
        state.isProcessing = true
        log.info("run: enter, queueSize=\(state.queue.count)")
        defer {
            state.isProcessing = false
            if state.queue.contains(where: { $0.status == .pending }) == false {
                state.statusMessage = "READY · IDLE"
            }
            log.info("run: exit")
        }

        await withTaskGroup(of: Void.self) { group in
            for w in 0..<concurrency {
                group.addTask { [weak self] in
                    while let id = await self?.takeNextPendingId() {
                        log.info("worker[\(w)]: picked id=\(id.uuidString.prefix(8))")
                        await self?.processOne(id: id)
                    }
                    log.info("worker[\(w)]: exit (no more pending)")
                }
            }
        }
    }

    /// Atomically claims the next pending item by flipping it to `.processing`.
    /// Returns the item's id, or nil if no pending work remains.
    private func takeNextPendingId() -> UUID? {
        guard let state = state,
              let idx = state.queue.firstIndex(where: { $0.status == .pending })
        else { return nil }
        var item = state.queue[idx]
        item.status = .processing
        item.phase = .waiting
        item.detail = "STARTING…"
        item.startedAt = Date()
        state.queue[idx] = item
        return item.id
    }

    private func processOne(id: UUID) async {
        let short = id.uuidString.prefix(8)
        guard let state = state,
              let initialIdx = state.queue.firstIndex(where: { $0.id == id })
        else {
            log.error("processOne[\(short)]: item gone before processing")
            return
        }

        let url = state.queue[initialIdx].url
        log.info("processOne[\(short)]: \(url.lastPathComponent)")

        // GUARANTEE the item leaves .processing even if something below
        // returns/throws past our handlers. A "stuck pending/working" row is
        // the worst UX bug we can ship — this defer is the safety net.
        defer {
            update(id: id) { item in
                if item.status == .processing {
                    log.error("processOne[\(short)]: defer rescue — status was still processing")
                    item.status = .failed
                    item.phase = .errored
                    if item.detail.isEmpty || !item.detail.lowercased().contains("fail") {
                        item.detail = "INTERNAL — TASK ENDED WITHOUT FINAL STATUS"
                    }
                }
            }
        }

        // --- 1) READ existing tags + tech info -------------------------------
        update(id: id) {
            $0.phase = .reading
            $0.detail = "READING EXISTING TAGS & TECH INFO…"
        }
        state.statusMessage = "WORKING · " + url.lastPathComponent
        let read = await MetadataReader.read(url: url)
        let foundCount = countSet(read.meta)
        log.info("processOne[\(short)]: read tags=\(foundCount) bitrate=\(read.tech.bitrateKbps ?? 0)kbps sr=\(read.tech.sampleRateHz ?? 0)Hz dur=\(Int(read.tech.durationSeconds ?? 0))s")

        update(id: id) {
            $0.tech = read.tech
        }

        // --- 2) ASK the model -----------------------------------------------
        update(id: id) {
            $0.phase = .asking
            let foundLine = foundCount == 0
                ? "NO EXISTING TAGS"
                : "\(foundCount) TAG\(foundCount == 1 ? "" : "S") ON DISK"
            $0.detail = "ASKING \(state.model.uppercased()) · \(foundLine)"
        }

        let client = OpenAIClient(apiKey: state.apiKey,
                                  baseURL: state.baseURL,
                                  model: state.model)

        let resolved: SongMetadata
        do {
            resolved = try await client.completeMetadata(
                filename: url.lastPathComponent,
                relativePath: relativePath(for: url),
                existing: read.meta
            )
            log.info("processOne[\(short)]: AI returned title=\(resolved.title ?? "—") artist=\(resolved.artist ?? "—")")
        } catch {
            log.error("processOne[\(short)]: AI failed — \(error.localizedDescription)")
            update(id: id) {
                $0.status = .failed
                $0.phase = .errored
                $0.detail = "AI FAILED — \(error.localizedDescription)"
            }
            return
        }

        let merged = merge(existing: read.meta, ai: resolved)
        let preview = describe(merged)

        // --- 3) FETCH cover art (best-effort, time-boxed) -------------------
        update(id: id) {
            $0.phase = .art
            $0.aiPreview = preview
            $0.resolved = merged
            $0.detail = "LOOKING UP COVER ART · \(preview.isEmpty ? "—" : preview)"
        }

        let artwork: Artwork? = await ITunesArtClient.fetchArtwork(
            artist: merged.artist,
            album:  merged.album,
            title:  merged.title,
            timeoutSeconds: 8
        )
        if artwork != nil {
            log.info("processOne[\(short)]: artwork OK (\(artwork?.data.count ?? 0) bytes)")
        } else {
            log.info("processOne[\(short)]: artwork not found")
        }
        update(id: id) {
            $0.artwork = artwork
        }

        // --- 4) WRITE tag (or skip if container unsupported) ----------------
        update(id: id) {
            $0.phase = .writing
            let artNote = artwork == nil ? "no art" : "with art"
            $0.detail = preview.isEmpty
                ? "WRITING — NO FIELDS RESOLVED (\(artNote))"
                : "WRITING TAG · \(preview) · \(artNote)"
        }

        do {
            try await writeIfPossible(metadata: merged, artwork: artwork, to: url)
            log.info("processOne[\(short)]: wrote tag OK")
            update(id: id) {
                $0.status = .done
                $0.phase = .finished
                let artBit = artwork == nil ? "" : " · ART"
                $0.detail = preview.isEmpty
                    ? "DONE — NO FIELDS RESOLVED\(artBit)"
                    : "\(preview)\(artBit)"
            }
        } catch RuntimeError.unsupportedFormat(let ext) {
            log.info("processOne[\(short)]: SKIPPED unsupported writer for .\(ext)")
            update(id: id) {
                $0.status = .skipped
                $0.phase = .finished
                $0.detail = "SKIPPED · \(ext.uppercased()) WRITER NOT IMPLEMENTED"
                    + (preview.isEmpty ? "" : " — \(preview)")
            }
        } catch {
            log.error("processOne[\(short)]: write failed — \(error.localizedDescription)")
            update(id: id) {
                $0.status = .failed
                $0.phase = .errored
                $0.detail = "WRITE FAILED — \(error.localizedDescription)"
            }
        }
    }

    /// Mutates the queue item with the given id in-place. The closure runs on
    /// the main actor and the assignment back into `state.queue` triggers the
    /// SwiftUI republish so each phase transition is visible immediately.
    private func update(id: UUID, _ mutate: (inout QueueItem) -> Void) {
        guard let state = state,
              let i = state.queue.firstIndex(where: { $0.id == id }) else { return }
        var item = state.queue[i]
        mutate(&item)
        state.queue[i] = item
    }

    /// Folder context that helps the model anchor "Artist/Album/01 Track.mp3" layouts.
    private func relativePath(for url: URL) -> String {
        let parents = url.deletingLastPathComponent().pathComponents.suffix(2)
        return parents.joined(separator: "/")
    }

    private func writeIfPossible(metadata: SongMetadata,
                                 artwork: Artwork?,
                                 to url: URL) async throws {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp3":
            try ID3Writer.write(metadata: metadata, artwork: artwork, to: url)
        case "m4a", "mp4", "aac":
            try await M4AWriter.write(metadata: metadata, artwork: artwork, to: url)
        default:
            throw RuntimeError.unsupportedFormat(ext)
        }
    }

    private func merge(existing: SongMetadata, ai: SongMetadata) -> SongMetadata {
        SongMetadata(
            title:       ai.title       ?? existing.title,
            artist:      ai.artist      ?? existing.artist,
            album:       ai.album       ?? existing.album,
            albumArtist: ai.albumArtist ?? existing.albumArtist,
            year:        ai.year        ?? existing.year,
            genre:       ai.genre       ?? existing.genre,
            track:       ai.track       ?? existing.track,
            composer:    ai.composer    ?? existing.composer,
            copyright:   ai.copyright   ?? existing.copyright,
            lyrics:      existing.lyrics  // never AI-generated
        )
    }

    private func describe(_ m: SongMetadata) -> String {
        let parts = [m.artist, m.title, m.album, m.year]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private func countSet(_ m: SongMetadata) -> Int {
        [m.title, m.artist, m.album, m.albumArtist, m.year, m.genre, m.track,
         m.composer, m.copyright, m.lyrics]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .count
    }
}

enum RuntimeError: Error, LocalizedError {
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "write skipped — \(ext.uppercased()) container not supported yet"
        }
    }
}
