import Foundation
import SwiftUI

/// Drives the queue: pulls pending items, asks the model for missing fields,
/// merges with what we read off-disk, and writes the result back into the file.
@MainActor
final class ProcessingEngine {
    private weak var state: AppState?
    private var task: Task<Void, Never>?

    /// Number of files processed in parallel.
    private let concurrency = 3

    init(state: AppState) { self.state = state }

    func kick() {
        if task != nil { return }
        task = Task { [weak self] in
            await self?.run()
            self?.task = nil
        }
    }

    private func run() async {
        guard let state = state else { return }
        state.isProcessing = true
        defer {
            state.isProcessing = false
            if state.queue.contains(where: { $0.status == .pending }) == false {
                state.statusMessage = "READY · IDLE"
            }
        }

        await withTaskGroup(of: Void.self) { group in
            var inflight = 0
            while true {
                while inflight < concurrency, let idx = nextPendingIndex() {
                    state.queue[idx].status = .processing
                    state.queue[idx].phase = .waiting
                    state.queue[idx].detail = "QUEUED — WAITING FOR SLOT"
                    let id = state.queue[idx].id
                    inflight += 1
                    group.addTask { [weak self] in
                        await self?.processOne(id: id)
                    }
                }
                if inflight == 0 { break }
                _ = await group.next()
                inflight -= 1
            }
        }
    }

    private func nextPendingIndex() -> Int? {
        state?.queue.firstIndex(where: { $0.status == .pending })
    }

    private func processOne(id: UUID) async {
        guard let state = state,
              let initialIdx = state.queue.firstIndex(where: { $0.id == id })
        else { return }

        let url = state.queue[initialIdx].url

        // 1) Reading existing tags off disk
        update(id: id) {
            $0.phase = .reading
            $0.startedAt = Date()
            $0.detail = "READING EXISTING TAGS…"
        }
        state.statusMessage = "WORKING · " + url.lastPathComponent

        let existing = await MetadataReader.read(url: url)
        let foundCount = countSet(existing)

        // 2) Asking the model
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
                existing: existing
            )
        } catch {
            update(id: id) {
                $0.status = .failed
                $0.phase = .errored
                $0.detail = "AI FAILED — \(error.localizedDescription)"
            }
            return
        }

        let merged = merge(existing: existing, ai: resolved)
        let preview = describe(merged)

        // 3) Writing tag (or skipping if container unsupported)
        update(id: id) {
            $0.phase = .writing
            $0.aiPreview = preview
            $0.resolved = merged
            $0.detail = preview.isEmpty
                ? "WRITING — NO FIELDS RESOLVED"
                : "WRITING TAG · \(preview)"
        }

        do {
            try await writeIfPossible(metadata: merged, to: url)
            update(id: id) {
                $0.status = .done
                $0.phase = .finished
                $0.detail = preview.isEmpty ? "DONE — NO FIELDS RESOLVED" : preview
            }
        } catch RuntimeError.unsupportedFormat(let ext) {
            update(id: id) {
                $0.status = .skipped
                $0.phase = .finished
                $0.detail = "SKIPPED · \(ext.uppercased()) WRITER NOT IMPLEMENTED"
                    + (preview.isEmpty ? "" : " — \(preview)")
            }
        } catch {
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

    private func writeIfPossible(metadata: SongMetadata, to url: URL) async throws {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp3":
            try ID3Writer.write(metadata: metadata, to: url)
        case "m4a", "mp4", "aac":
            try await M4AWriter.write(metadata: metadata, to: url)
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
            track:       ai.track       ?? existing.track
        )
    }

    private func describe(_ m: SongMetadata) -> String {
        let parts = [m.artist, m.title, m.album, m.year]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private func countSet(_ m: SongMetadata) -> Int {
        [m.title, m.artist, m.album, m.albumArtist, m.year, m.genre, m.track]
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
