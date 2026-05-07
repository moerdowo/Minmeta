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
            queue[i].phase = .waiting
            queue[i].startedAt = nil
            queue[i].detail = ""
            queue[i].aiPreview = nil
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
    var phase: Phase = .waiting
    var startedAt: Date? = nil
    var detail: String = ""
    var resolved: SongMetadata? = nil
    /// Short preview of the metadata the model proposed, kept around so the
    /// queue can keep showing it while the writer runs and after a skip.
    var aiPreview: String? = nil

    enum Status: String {
        case pending    = "PENDING"
        case processing = "WORKING"
        case done       = "DONE"
        case failed     = "FAILED"
        case skipped    = "SKIPPED"
    }

    /// Sub-state during `.processing`. Drives the per-row chip, LED colour,
    /// and progress bar in the queue UI.
    enum Phase: String {
        case waiting   // queued but not yet started
        case reading   // pulling existing tags off disk
        case asking    // calling the model
        case writing   // committing tags to file
        case finished  // wrapped up successfully or as a deliberate skip
        case errored   // unrecoverable failure

        var label: String {
            switch self {
            case .waiting:  return "WAIT"
            case .reading:  return "READ"
            case .asking:   return "AI"
            case .writing:  return "TAG"
            case .finished: return "OK"
            case .errored:  return "X"
            }
        }

        var fraction: Double {
            switch self {
            case .waiting:  return 0.05
            case .reading:  return 0.25
            case .asking:   return 0.65
            case .writing:  return 0.90
            case .finished: return 1.00
            case .errored:  return 1.00
            }
        }
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
