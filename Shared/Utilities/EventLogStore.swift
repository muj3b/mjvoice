import Foundation
import AppKit

struct EventLogEntry: Identifiable, Codable {
    enum EventType: String, Codable {
        case clipboardFallback
        case modelDownload
        case modelDownloadFailed
        case snippetInserted
        case noteCaptured
        case helpOpened
        case snippetCreated
        case dictionaryImport
    }

    let id: UUID
    let date: Date
    let type: EventType
    let message: String
    var isRead: Bool
}

@MainActor
final class EventLogStore: ObservableObject {
    static let shared = EventLogStore()

    @Published private(set) var entries: [EventLogEntry] = []

    private let queue = DispatchQueue(label: "com.mjvoice.eventlog", qos: .utility)
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("mjvoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("events.json")
        encoder.outputFormatting = [.prettyPrinted]
        load()
    }

    func record(type: EventLogEntry.EventType, message: String) {
        let entry = EventLogEntry(id: UUID(), date: Date(), type: type, message: message, isRead: false)
        entries.insert(entry, at: 0)
        persist()
    }

    func markAllRead() {
        entries = entries.map { entry in
            var copy = entry
            copy.isRead = true
            return copy
        }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? decoder.decode([EventLogEntry].self, from: data) {
            entries = decoded
        }
    }

    private func persist() {
        queue.async { [entries] in
            do {
                let data = try self.encoder.encode(entries)
                try data.write(to: self.url, options: [.atomic])
            } catch {
                NSLog("[EventLogStore] Failed to persist events: \(error)")
            }
        }
    }
}
