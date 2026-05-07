import Foundation

/// Looks up album cover art via Apple's free iTunes Search API. No key,
/// public endpoint. Returns the largest reasonable JPEG we can pull.
enum ITunesArtClient {

    /// Try to find cover art for the given metadata. Returns nil if no
    /// good match is found within the time budget.
    static func fetchArtwork(artist: String?,
                             album: String?,
                             title: String?,
                             timeoutSeconds: TimeInterval = 8) async -> Artwork? {
        let term = buildSearchTerm(artist: artist, album: album, title: title)
        guard !term.isEmpty else { return nil }

        let entity: String = (album?.isEmpty == false) ? "album" : "musicTrack"
        guard let encoded = term.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        guard let url = URL(string:
            "https://itunes.apple.com/search?term=\(encoded)&entity=\(entity)&limit=1")
        else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = timeoutSeconds
            let (data, _) = try await URLSession.shared.data(for: request)
            let result = try JSONDecoder().decode(SearchResponse.self, from: data)
            guard let first = result.results.first,
                  let small = first.artworkUrl100,
                  let big = upscale(small)
            else { return nil }

            guard let bigURL = URL(string: big) else { return nil }
            var imgReq = URLRequest(url: bigURL)
            imgReq.timeoutInterval = timeoutSeconds
            let (imgData, imgResp) = try await URLSession.shared.data(for: imgReq)
            guard let http = imgResp as? HTTPURLResponse, http.statusCode < 300,
                  imgData.count > 1024 else { return nil }
            let mime = http.value(forHTTPHeaderField: "Content-Type") ?? "image/jpeg"

            return Artwork(
                data: imgData,
                mime: mime.lowercased().contains("png") ? "image/png" : "image/jpeg",
                source: "iTunes \(big.contains("600x600") ? "600x600" : "art")"
            )
        } catch {
            return nil
        }
    }

    /// iTunes returns a "100x100bb" thumbnail by default. Swap that for a
    /// 600x600 version for embedding without bloating the file.
    private static func upscale(_ url: String) -> String? {
        let candidates = ["600x600bb", "1200x1200bb"]
        for token in candidates {
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
        if let a = album?.trimmingCharacters(in: .whitespacesAndNewlines),
           !a.isEmpty { parts.append(a) }
        if parts.isEmpty,
           let t = title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !t.isEmpty { parts.append(t) }
        return parts.joined(separator: " ")
    }

    private struct SearchResponse: Decodable {
        let results: [Item]
        struct Item: Decodable {
            let artworkUrl100: String?
            let artistName: String?
            let collectionName: String?
        }
    }
}
