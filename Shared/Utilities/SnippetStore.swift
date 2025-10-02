import Foundation
import AppKit

struct Snippet: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var content: String
    let createdAt: Date
    var lastUsedAt: Date?
}

@MainActor
final class SnippetStore: ObservableObject {
    static let shared = SnippetStore()

    @Published private(set) var snippets: [Snippet] = []

    private let queue = DispatchQueue(label: "com.mjvoice.snippets", qos: .utility)
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("mjvoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("snippets.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    func add(title: String, content: String) {
        let snippet = Snippet(id: UUID(), title: title, content: content, createdAt: Date(), lastUsedAt: nil)
        snippets.insert(snippet, at: 0)
        persist()
        EventLogStore.shared.record(type: .snippetCreated, message: "Snippet \"\(title)\" created")
    }

    func update(snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index] = snippet
        persist()
    }

    func remove(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        persist()
    }

    func markUsed(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index].lastUsedAt = Date()
        persist()
        EventLogStore.shared.record(type: .snippetInserted, message: "Inserted snippet \"\(snippets[index].title)\"")
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? decoder.decode([Snippet].self, from: data) {
            snippets = decoded
        }
    }

    private func persist() {
        let current = snippets
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let data = try self.encoder.encode(current)
                try data.write(to: self.url, options: [.atomic])
            } catch {
                NSLog("[SnippetStore] Failed to persist snippets: \(error)")
            }
        }
    }
}
