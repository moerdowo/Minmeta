import Foundation
import SwiftUI
import OSLog

/// Drives the queue: pulls pending items, looks up canonical metadata for
/// each track, fetches album art, merges with on-disk tags, and writes the
/// result back into the file.
///
/// Resolution strategy (per file):
///   1. Read existing tags + technical info via AVFoundation.
///   2. Extract artist / album / title hints from the filename + 1–2
///      parent folder names + existing tags.
///   3. Search the iTunes Search API. If the first hit's artist+title
///      match the hints with score ≥ 4, **trust iTunes** as the primary
///      source — title / artist / album / year / genre / track + cover art.
///   4. If iTunes scored < 4 AND an AI key is configured, fall back to
///      OpenAI to interpret the filename (good for messy names + non-
///      catalog music). Then re-search iTunes with the AI result for
///      art and any backfill.
///   5. If neither path produced metadata, mark the row SKIPPED.
///
/// Reliability notes:
/// - Worker-pool of N tasks each pulling next pending — easier to reason
///   about than a producer/consumer task group.
/// - processOne() has a `defer` that guarantees the item leaves
///   `.processing` even if a path is missed — the queue can never get
///   visually stuck.
/// - Every state transition emits an OSLog line; filter on
///   `subsystem:id.moerdowo.minmeta` from Console.app to debug a stuck
///   queue.
@MainActor
final class ProcessingEngine {
    private weak var state: AppState?
    private var task: Task<Void, Never>?

    private let concurrency = 3
    private let confidentScore = 4

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

        // --- 1) READ existing tags + tech info ------------------------------
        update(id: id) {
            $0.phase = .reading
            $0.detail = "READING EXISTING TAGS & TECH INFO…"
        }
        state.statusMessage = "WORKING · " + url.lastPathComponent
        let read = await MetadataReader.read(url: url)
        log.info("processOne[\(short)]: read tags=\(self.countSet(read.meta)) bitrate=\(read.tech.bitrateKbps ?? 0)kbps")

        update(id: id) { $0.tech = read.tech }

        // --- 2) iTunes primary lookup ---------------------------------------
        // Hints come from existing tags first, then filename + parent folders.
        let hints = extractHints(url: url, existing: read.meta)
        log.info("processOne[\(short)]: hints artist=\(hints.artist ?? "—") title=\(hints.title ?? "—") album=\(hints.album ?? "—")")

        update(id: id) {
            $0.phase = .art
            $0.detail = "SEARCHING ITUNES · " + (hints.title ?? hints.artist ?? "—")
        }

        let lookup = await ITunesArtClient.lookup(
            artist: hints.artist,
            album:  hints.album,
            title:  hints.title,
            timeoutSeconds: 8
        )
        if let lookup = lookup {
            log.info("processOne[\(short)]: iTunes score=\(lookup.score) album=\(lookup.albumName ?? "—")")
        } else {
            log.info("processOne[\(short)]: iTunes no result")
        }

        let confident = (lookup?.score ?? 0) >= confidentScore

        // --- 3) Decide path: trust iTunes, AI fallback, or skip -------------
        let aiAvailable = !state.apiKey.isEmpty
        var finalMeta: SongMetadata = read.meta
        var finalArt: Artwork? = nil
        var sourceTag = ""

        if confident, let l = lookup {
            // Path A — iTunes is good enough on its own.
            finalMeta = applyITunes(read.meta, l)
            finalArt = l.artwork
            sourceTag = "ITUNES"
        } else if aiAvailable {
            // Path B — iTunes wasn't sure. Ask the model to interpret the
            // filename (handles messy names + non-catalog music). Then
            // search iTunes a second time with the AI's canonical artist /
            // title for cleaner art and any final backfill.
            update(id: id) {
                $0.phase = .asking
                $0.detail = "NO ITUNES MATCH · ASKING \(state.model.uppercased())"
            }

            let client = OpenAIClient(apiKey: state.apiKey,
                                      baseURL: state.baseURL,
                                      model: state.model)
            do {
                let aiResolved = try await client.completeMetadata(
                    filename: url.lastPathComponent,
                    relativePath: relativePath(for: url),
                    existing: read.meta
                )
                log.info("processOne[\(short)]: AI returned title=\(aiResolved.title ?? "—")")

                let aiMerged = mergeAI(existing: read.meta, ai: aiResolved)

                update(id: id) {
                    $0.phase = .art
                    $0.detail = "AI DONE · LOOKING UP ITUNES ART · \(self.describe(aiMerged))"
                }

                let secondLookup = await ITunesArtClient.lookup(
                    artist: aiMerged.artist,
                    album:  aiMerged.album,
                    title:  aiMerged.title,
                    timeoutSeconds: 8
                )

                finalMeta = backfill(aiMerged, with: secondLookup)
                finalArt = secondLookup?.artwork ?? lookup?.artwork
                sourceTag = "AI"
            } catch {
                log.error("processOne[\(short)]: AI failed — \(error.localizedDescription)")
                update(id: id) {
                    $0.status = .failed
                    $0.phase = .errored
                    $0.detail = "AI FAILED — \(error.localizedDescription)"
                }
                return
            }
        } else {
            // Path C — no AI configured and iTunes couldn't identify the
            // track. Nothing to write. Skip with a useful note.
            log.info("processOne[\(short)]: SKIPPED — no iTunes match and no AI key")
            update(id: id) {
                $0.status = .skipped
                $0.phase = .finished
                $0.detail = "NO ITUNES MATCH · SET API KEY IN CFG TO ENABLE AI FALLBACK"
                $0.aiPreview = self.describe(read.meta)
            }
            return
        }

        let preview = describe(finalMeta)
        let artNote = finalArt == nil ? "no art" : "with art"

        // --- 4) WRITE -------------------------------------------------------
        update(id: id) {
            $0.phase = .writing
            $0.aiPreview = preview
            $0.resolved = finalMeta
            $0.artwork = finalArt
            $0.detail = "WRITING TAG · \(sourceTag) · \(preview) · \(artNote)"
        }

        do {
            try await writeIfPossible(metadata: finalMeta, artwork: finalArt, to: url)
            log.info("processOne[\(short)]: wrote tag OK (\(sourceTag))")
            update(id: id) {
                $0.status = .done
                $0.phase = .finished
                let artBit = finalArt == nil ? "" : " · ART"
                $0.detail = "\(sourceTag) · \(preview)\(artBit)"
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

    private func update(id: UUID, _ mutate: (inout QueueItem) -> Void) {
        guard let state = state,
              let i = state.queue.firstIndex(where: { $0.id == id }) else { return }
        var item = state.queue[i]
        mutate(&item)
        state.queue[i] = item
    }

    /// 1–2 parent folder names that often hold "Artist/Album" structure.
    private func relativePath(for url: URL) -> String {
        let parents = url.deletingLastPathComponent().pathComponents.suffix(2)
        return parents.joined(separator: "/")
    }

    /// Pull artist / title / album hints from existing tags first, then from
    /// the filename and 1–2 parent folder names. Used to seed iTunes search.
    private func extractHints(url: URL, existing: SongMetadata) -> SongMetadata {
        // Existing tags trump everything when both artist+title are set.
        if let a = existing.artist, !a.isEmpty,
           let t = existing.title,  !t.isEmpty {
            return SongMetadata(title: t, artist: a, album: existing.album)
        }

        // Strip extension, common YouTube-style noise, bracketed video IDs.
        var name = (url.lastPathComponent as NSString).deletingPathExtension
        let noise = #"\s*[\(\[](Official(\s+(Music\s+)?(Audio|Video|Lyric Video|Music Video))?|HD|1080p|4K|Audio|Lyrics|Live|Remastered|Visualizer)[^\)\]]*[\)\]]"#
        name = name.replacingOccurrences(of: noise,
                                          with: "",
                                          options: [.regularExpression, .caseInsensitive])
        // Trailing 8+ char alphanumeric IDs in brackets, e.g. YouTube IDs.
        name = name.replacingOccurrences(of: #"\s*\[[A-Za-z0-9_-]{8,}\]"#,
                                          with: "",
                                          options: .regularExpression)
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try common dash-separated patterns. " - " is the usual separator,
        // but some files use just "-" or "_".
        var parts = name.components(separatedBy: " - ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count < 2 {
            parts = name.components(separatedBy: "_")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        var artist: String? = existing.artist
        var title:  String? = existing.title
        var album:  String? = existing.album

        if parts.count >= 2 {
            // Drop a leading track number "01", "01.", "Track 01" if present.
            let leadIsTrackNum = parts[0].range(of: #"^(track\s+)?\d+\.?$"#,
                                                options: [.regularExpression, .caseInsensitive]) != nil
            let body = leadIsTrackNum ? Array(parts.dropFirst()) : parts
            if body.count >= 2 {
                if artist == nil { artist = body[0] }
                if title == nil  { title  = body.dropFirst().joined(separator: " - ") }
            } else if body.count == 1, title == nil {
                title = body[0]
            }
        } else if title == nil {
            title = name
        }

        // Folder context: "<Artist>/<Album>/file.mp3" is a common layout —
        // populate album/artist from the last two path components.
        if album == nil || artist == nil {
            let parents = url.deletingLastPathComponent().pathComponents
            if parents.count >= 2 {
                let albumFolder  = parents[parents.count - 1]
                let artistFolder = parents[parents.count - 2]
                if album == nil, !albumFolder.isEmpty,
                   !["Music", "Downloads", "Desktop", "iTunes Media", "Songs"]
                       .contains(albumFolder) {
                    album = albumFolder
                }
                if artist == nil, !artistFolder.isEmpty,
                   !["Music", "Downloads", "Desktop", "iTunes Media", "Songs"]
                       .contains(artistFolder) {
                    artist = artistFolder
                }
            }
        }

        return SongMetadata(title: title, artist: artist, album: album)
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

    /// Apply iTunes match as the primary source, keeping any non-empty
    /// existing-disk values that iTunes doesn't itself provide (composer,
    /// copyright, lyrics).
    private func applyITunes(_ existing: SongMetadata,
                             _ lookup: ITunesArtClient.Match) -> SongMetadata {
        SongMetadata(
            title:       lookup.trackName   ?? existing.title,
            artist:      lookup.artistName  ?? existing.artist,
            album:       lookup.albumName   ?? existing.album,
            albumArtist: lookup.artistName  ?? existing.albumArtist,
            year:        lookup.year        ?? existing.year,
            genre:       lookup.genre       ?? existing.genre,
            track:       lookup.trackNumber ?? existing.track,
            composer:    existing.composer,
            copyright:   existing.copyright,
            lyrics:      existing.lyrics
        )
    }

    /// AI values win over what's on disk when both are present.
    private func mergeAI(existing: SongMetadata, ai: SongMetadata) -> SongMetadata {
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
            lyrics:      existing.lyrics
        )
    }

    /// Fill empty fields on `m` with values from the iTunes lookup. Never
    /// overrides a field already set — iTunes is a backstop here.
    private func backfill(_ m: SongMetadata,
                          with lookup: ITunesArtClient.Match?) -> SongMetadata {
        guard let lookup = lookup else { return m }
        var out = m
        if isEmpty(out.album)       { out.album       = lookup.albumName }
        if isEmpty(out.artist)      { out.artist      = lookup.artistName }
        if isEmpty(out.title)       { out.title       = lookup.trackName }
        if isEmpty(out.albumArtist) { out.albumArtist = lookup.artistName }
        if isEmpty(out.year)        { out.year        = lookup.year }
        if isEmpty(out.genre)       { out.genre       = lookup.genre }
        if isEmpty(out.track)       { out.track       = lookup.trackNumber }
        return out
    }

    private func isEmpty(_ s: String?) -> Bool {
        (s?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
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
