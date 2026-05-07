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
                    state.queue[idx].detail = "queued…"
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
              let idx = state.queue.firstIndex(where: { $0.id == id }) else { return }

        let url = state.queue[idx].url
        state.queue[idx].detail = "reading metadata…"
        state.statusMessage = "WORKING · " + url.lastPathComponent

        let existing = await MetadataReader.read(url: url)

        if let i2 = state.queue.firstIndex(where: { $0.id == id }) {
            state.queue[i2].detail = "asking model…"
        }

        let client = OpenAIClient(apiKey: state.apiKey,
                                  baseURL: state.baseURL,
                                  model: state.model)

        do {
            let resolved = try await client.completeMetadata(
                filename: url.lastPathComponent,
                relativePath: relativePath(for: url, in: state),
                existing: existing
            )
            let merged = merge(existing: existing, ai: resolved)

            if let i2 = state.queue.firstIndex(where: { $0.id == id }) {
                state.queue[i2].detail = "writing tag…"
                state.queue[i2].resolved = merged
            }

            try await writeIfPossible(metadata: merged, to: url)

            if let i2 = state.queue.firstIndex(where: { $0.id == id }) {
                state.queue[i2].status = .done
                state.queue[i2].detail = describe(merged)
            }
        } catch {
            if let i2 = state.queue.firstIndex(where: { $0.id == id }) {
                state.queue[i2].status = .failed
                state.queue[i2].detail = error.localizedDescription
            }
        }
    }

    /// Folder context that helps the model anchor "Artist/Album/01 Track.mp3" layouts.
    private func relativePath(for url: URL, in state: AppState) -> String {
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
            // Other formats: read-only suggestion mode for now.
            throw RuntimeError.unsupportedFormat(ext)
        }
    }

    private func merge(existing: SongMetadata, ai: SongMetadata) -> SongMetadata {
        // Prefer AI values when present; otherwise keep what was already on disk.
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
