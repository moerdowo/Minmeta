import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var apiKey: String = ""
    @Published var baseURL: String = "https://api.openai.com/v1"
    @Published var model: String = "gpt-4o-mini"

    @Published var queue: [QueueItem] = []
    @Published var isProcessing: Bool = false
    @Published var statusMessage: String = "READY"

    @Published var showSettings: Bool = false

    private var engine: ProcessingEngine?

    init() {
        if let key = Keychain.read(account: "openai_api_key") {
            self.apiKey = key
        }
        if let stored = UserDefaults.standard.string(forKey: "minmeta.baseURL"),
           !stored.isEmpty {
            self.baseURL = stored
        }
        if let stored = UserDefaults.standard.string(forKey: "minmeta.model"),
           !stored.isEmpty {
            self.model = stored
        }
    }

    var isUnlocked: Bool { !apiKey.isEmpty }

    func saveAPIKey(_ key: String, baseURL: String, model: String) {
        let trimmed       = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBase   = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel  = model.trimmingCharacters(in: .whitespacesAndNewlines)

        Keychain.save(account: "openai_api_key", value: trimmed)
        UserDefaults.standard.set(trimmedBase,  forKey: "minmeta.baseURL")
        UserDefaults.standard.set(trimmedModel, forKey: "minmeta.model")

        self.apiKey  = trimmed
        self.baseURL = trimmedBase.isEmpty  ? "https://api.openai.com/v1" : trimmedBase
        self.model   = trimmedModel.isEmpty ? "gpt-4o-mini"               : trimmedModel
    }

    func clearAPIKey() {
        Keychain.delete(account: "openai_api_key")
        apiKey = ""
        showSettings = false
    }

    // MARK: - Queue

    func enqueue(urls: [URL]) {
        let supported = MetadataReader.supportedExtensions
        var newItems: [QueueItem] = []
        for url in urls {
            collectAudioFiles(from: url, supported: supported, into: &newItems)
        }
        let existingPaths = Set(queue.map { $0.url.path })
        let deduped = newItems.filter { !existingPaths.contains($0.url.path) }
        queue.append(contentsOf: deduped)
        startProcessingIfNeeded()
    }

    private func collectAudioFiles(from url: URL,
                                   supported: Set<String>,
                                   into items: inout [QueueItem]) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        if isDir.boolValue {
            if let enumerator = fm.enumerator(at: url,
                                              includingPropertiesForKeys: nil,
                                              options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if supported.contains(fileURL.pathExtension.lowercased()) {
                        items.append(QueueItem(url: fileURL))
                    }
                }
            }
        } else if supported.contains(url.pathExtension.lowercased()) {
            items.append(QueueItem(url: url))
        }
    }

    func clearQueue() {
        queue.removeAll { $0.status != .processing }
    }

    func retryFailed() {
        for i in queue.indices where queue[i].status == .failed {
            queue[i].status = .pending
            queue[i].detail = ""
        }
        startProcessingIfNeeded()
    }

    private func startProcessingIfNeeded() {
        if engine == nil { engine = ProcessingEngine(state: self) }
        engine?.kick()
    }
}

struct QueueItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var status: Status = .pending
    var detail: String = ""
    var resolved: SongMetadata? = nil

    enum Status: String {
        case pending    = "PENDING"
        case processing = "WORKING"
        case done       = "DONE"
        case failed     = "FAILED"
        case skipped    = "SKIPPED"
    }

    static func == (l: QueueItem, r: QueueItem) -> Bool { l.id == r.id }
}

struct SongMetadata: Codable, Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var year: String?
    var genre: String?
    var track: String?
}
