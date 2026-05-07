import Foundation

struct OpenAIClient {
    let apiKey: String
    let baseURL: String
    let model: String

    enum ClientError: Error, LocalizedError {
        case badResponse(Int, String)
        case noChoices
        case decodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .badResponse(let code, let body):
                return "HTTP \(code): \(body.prefix(160))"
            case .noChoices:
                return "Model returned no choices"
            case .decodeFailed(let reason):
                return "Decode failed: \(reason)"
            }
        }
    }

    func completeMetadata(filename: String,
                          relativePath: String,
                          existing: SongMetadata) async throws -> SongMetadata {
        let endpoint = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) +
                       "/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw ClientError.decodeFailed("invalid base URL")
        }

        let system = """
        You are a music metadata expert. Given a song's filename, its relative \
        folder path, and any currently known metadata (which may be empty, partial, \
        or wrong), identify the most likely correct, canonical metadata for the \
        track.

        RULES:
        1. The filename and folder path are strong hints — they often follow patterns \
           like "Artist - Title", "01 - Title", "Artist/Album/01 Title.mp3", or \
           "Artist - Album - 01 - Title". Strip noise like "[Official]", "(HD)", \
           "320kbps", "lyrics", trailing release tags, and file extensions.
        2. Prefer existing metadata only when it is internally consistent and matches \
           a known release. Fix obvious errors (e.g. mojibake, ALL CAPS noise, \
           "Track 1" placeholders).
        3. Return CANONICAL release values — artist as credited on the official \
           release, album as the original studio album when applicable (not greatest \
           hits / compilations / soundtracks unless the track only exists there).
        4. Year: 4-digit year of the original studio release, not re-issues.
        5. Genre: a single common label ("Rock", "Pop", "Hip-Hop", "Jazz", \
           "Electronic", "R&B", "Classical", "Country", "Metal", "Folk", "Reggae", \
           "Soundtrack"). Avoid hyper-specific subgenres unless very well known.
        6. Track: plain integer string when known with high confidence. No "01/12".
        7. album_artist: usually equals artist; for compilations use "Various Artists".
        8. If a field is unknown or your confidence is low (<70%), return an empty \
           string for that field. Do NOT invent or guess plausible-sounding fakes.
        9. Names must use proper title case as on the official release. Preserve \
           original-language characters and diacritics.

        OUTPUT: ONLY a JSON object, no prose, with this exact schema and key order:
        {"title":"","artist":"","album":"","album_artist":"","year":"","genre":"","track":""}
        """

        let existingJSON = (try? String(data: JSONEncoder().encode(existing),
                                        encoding: .utf8)) ?? "{}"
        let user = """
        FILENAME: \(filename)
        FOLDER_PATH: \(relativePath)
        EXISTING_METADATA: \(existingJSON)
        """

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user",   "content": user]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
            let txt = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.badResponse(http.statusCode, txt)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw ClientError.noChoices
        }

        guard let jsonData = content.data(using: .utf8) else {
            throw ClientError.decodeFailed("non-utf8 content")
        }
        let raw = try JSONDecoder().decode(RawMeta.self, from: jsonData)
        return raw.normalized()
    }

    /// Sanity-checks the API key + base URL by hitting `/models` (or any cheap GET).
    /// Returns nil on success or a human-readable error message on failure.
    func verify() async -> String? {
        let endpoint = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) +
                       "/models"
        guard let url = URL(string: endpoint) else { return "invalid base URL" }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "no response" }
            if http.statusCode >= 300 {
                let txt = String(data: data, encoding: .utf8) ?? ""
                return "HTTP \(http.statusCode): \(txt.prefix(120))"
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }
        let choices: [Choice]
    }

    private struct RawMeta: Decodable {
        var title: String?
        var artist: String?
        var album: String?
        var album_artist: String?
        var year: String?
        var genre: String?
        var track: String?

        func normalized() -> SongMetadata {
            func clean(_ s: String?) -> String? {
                guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !s.isEmpty
                else { return nil }
                return s
            }
            return SongMetadata(
                title:       clean(title),
                artist:      clean(artist),
                album:       clean(album),
                albumArtist: clean(album_artist),
                year:        clean(year),
                genre:       clean(genre),
                track:       clean(track)
            )
        }
    }
}
