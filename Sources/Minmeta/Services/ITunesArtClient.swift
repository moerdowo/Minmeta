import Foundation

/// iTunes Search API client. Apple's free public endpoint — no key.
///
/// Used for two things:
///  1. **Backfill** — when the model leaves a field empty (it's prompted to
///     do so when uncertain), iTunes' track record gives us the canonical
///     album, artist, title, year, genre, and track number for songs in the
///     Apple Music catalog. We never override a value the model returned.
///  2. **Cover art** — the search result links to a 100×100 JPEG which we
///     swap to 600×600 for embedding.
enum ITunesArtClient {

    struct Match {
        var albumName: String?
        var artistName: String?
        var trackName: String?
        var year: String?
        var genre: String?
        var trackNumber: String?
        var artwork: Artwork?
    }

    static func lookup(artist: String?,
                       album: String?,
                       title: String?,
                       timeoutSeconds: TimeInterval = 8) async -> Match? {
        let term = buildSearchTerm(artist: artist, album: album, title: title)
        guard !term.isEmpty,
              let encoded = term.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed)
        else { return nil }

        // Track-level entity returns album/artist/title/year/genre/track
        // in one response — exactly what we need for backfill.
        let entity = (title?.isEmpty == false) ? "song" : "album"
        guard let url = URL(string:
            "https://itunes.apple.com/search?term=\(encoded)&entity=\(entity)&limit=5")
        else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = timeoutSeconds
            let (data, _) = try await URLSession.shared.data(for: request)
            let result = try JSONDecoder().decode(SearchResponse.self, from: data)

            // Pick the result whose artist+title best matches what we sent in,
            // not just the top hit — iTunes' relevance ranking sometimes
            // bubbles up remixes / covers / "feat." versions.
            guard let pick = bestMatch(in: result.results,
                                       wantArtist: artist,
                                       wantTitle: title)
            else { return nil }

            var match = Match(
                albumName:   pick.collectionName,
                artistName:  pick.artistName,
                trackName:   pick.trackName,
                year:        pick.releaseDate.flatMap { String($0.prefix(4)) },
                genre:       pick.primaryGenreName,
                trackNumber: pick.trackNumber.map { String($0) }
            )

            if let small = pick.artworkUrl100,
               let big   = upscale(small),
               let bigURL = URL(string: big) {
                var imgReq = URLRequest(url: bigURL)
                imgReq.timeoutInterval = timeoutSeconds
                if let (imgData, imgResp) = try? await URLSession.shared.data(for: imgReq),
                   let http = imgResp as? HTTPURLResponse, http.statusCode < 300,
                   imgData.count > 1024 {
                    let mime = (http.value(forHTTPHeaderField: "Content-Type") ?? "image/jpeg")
                        .lowercased()
                    match.artwork = Artwork(
                        data: imgData,
                        mime: mime.contains("png") ? "image/png" : "image/jpeg",
                        source: "iTunes \(big.contains("600x600") ? "600x600" : "art")"
                    )
                }
            }

            return match
        } catch {
            return nil
        }
    }

    /// Score each candidate by how well its artist + title match what we
    /// asked for. Falls back to the first result if we have nothing to
    /// compare against (e.g. only album was provided).
    private static func bestMatch(in items: [SearchResponse.Item],
                                  wantArtist: String?,
                                  wantTitle: String?) -> SearchResponse.Item? {
        guard !items.isEmpty else { return nil }
        let wa = norm(wantArtist)
        let wt = norm(wantTitle)
        if wa.isEmpty && wt.isEmpty { return items.first }

        var best: (score: Int, item: SearchResponse.Item)?
        for item in items {
            let ia = norm(item.artistName)
            let it = norm(item.trackName ?? item.collectionName)
            var score = 0
            if !wa.isEmpty, !ia.isEmpty {
                if ia == wa             { score += 4 }
                else if ia.contains(wa) || wa.contains(ia) { score += 2 }
            }
            if !wt.isEmpty, !it.isEmpty {
                if it == wt             { score += 4 }
                else if it.contains(wt) || wt.contains(it) { score += 2 }
            }
            if score > (best?.score ?? Int.min) { best = (score, item) }
        }
        // Require at least *some* match if we had something to match on; a
        // score of 0 means the top result is wildly different — skip it.
        if (best?.score ?? 0) == 0, !wa.isEmpty || !wt.isEmpty { return nil }
        return best?.item ?? items.first
    }

    private static func norm(_ s: String?) -> String {
        (s ?? "")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isPunctuation }
    }

    /// iTunes returns "100x100bb"; swap for higher res versions for embed.
    private static func upscale(_ url: String) -> String? {
        for token in ["600x600bb", "1200x1200bb"] {
            let upgraded = url.replacingOccurrences(of: "100x100bb", with: token)
            if upgraded != url { return upgraded }
        }
        return url
    }

    private static func buildSearchTerm(artist: String?,
                                        album: String?,
                                        title: String?) -> String {
        var parts: [String] = []
        if let a = artist?.trimmingCharacters(in: .whitespacesAndNewlines),
           !a.isEmpty { parts.append(a) }
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !t.isEmpty { parts.append(t) }
        if let a = album?.trimmingCharacters(in: .whitespacesAndNewlines),
           !a.isEmpty, parts.count < 2 { parts.append(a) }
        return parts.joined(separator: " ")
    }

    private struct SearchResponse: Decodable {
        let results: [Item]
        struct Item: Decodable {
            let artistName: String?
            let collectionName: String?
            let trackName: String?
            let trackNumber: Int?
            let releaseDate: String?
            let primaryGenreName: String?
            let artworkUrl100: String?
        }
    }
}
