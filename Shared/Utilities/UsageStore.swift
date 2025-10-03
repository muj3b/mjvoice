import Foundation
import AppKit

struct TranscriptionRecord: Codable, Identifiable {
    enum Destination: String, Codable {
        case insertion
        case clipboard
        case notes
    }

    let id: UUID
    let timestamp: Date
    let text: String
    let appBundleID: String?
    let appName: String?
    let destination: Destination
    let words: Int
    let duration: TimeInterval
    let wpm: Double
}

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var transcriptions: [TranscriptionRecord] = []

    private let fileManager = FileManager.default
    private let url: URL
    private let decoder = JSONDecoder()

    private init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("mjvoice", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("usage.json")
        load()
    }

    func logTranscription(text: String,
                          destination: TranscriptionRecord.Destination,
                          appBundleID: String?,
                          startedAt: Date?,
                          endedAt: Date = Date()) {
        guard !text.isEmpty else { return }
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        let duration = max(endedAt.timeIntervalSince(startedAt ?? endedAt), 1)
        let wpm = Double(words) / (duration / 60.0)
        let appName: String?
        if let bundle = appBundleID,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first {
            appName = app.localizedName
        } else {
            appName = nil
        }
        let record = TranscriptionRecord(id: UUID(),
                                         timestamp: endedAt,
                                         text: text,
                                         appBundleID: appBundleID,
                                         appName: appName,
                                         destination: destination,
                                         words: words,
                                         duration: duration,
                                         wpm: wpm)
        transcriptions.insert(record, at: 0)
        let snapshot = transcriptions
        persistAsync(records: snapshot)
    }

    var totalWords: Int {
        transcriptions.reduce(0) { $0 + $1.words }
    }

    var averageWPM: Double {
        guard !transcriptions.isEmpty else { return 0 }
        let totalDurationMinutes = transcriptions.reduce(0.0) { $0 + ($1.duration / 60.0) }
        guard totalDurationMinutes > 0 else { return 0 }
        return Double(totalWords) / totalDurationMinutes
    }

    var weeklyStreak: Int {
        guard let first = transcriptions.first else { return 0 }
        let calendar = Calendar.current
        let currentWeek = calendar.component(.weekOfYear, from: Date())
        let currentYear = calendar.component(.yearForWeekOfYear, from: Date())
        var seenWeeks = Set<String>()
        for record in transcriptions {
            let year = calendar.component(.yearForWeekOfYear, from: record.timestamp)
            let week = calendar.component(.weekOfYear, from: record.timestamp)
            let key = "\(year)-\(week)"
            seenWeeks.insert(key)
        }
        // Count backwards from current week until missing
        var streak = 0
        var week = currentWeek
        var year = currentYear
        for _ in 0..<seenWeeks.count {
            let key = "\(year)-\(week)"
            if seenWeeks.contains(key) {
                streak += 1
                week -= 1
                if week <= 0 {
                    week = calendar.range(of: .weekOfYear, in: .yearForWeekOfYear, for: first.timestamp)?.count ?? 52
                    year -= 1
                }
            } else {
                break
            }
        }
        return streak
    }

    func groupedHistory() -> [(date: Date, records: [TranscriptionRecord])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: transcriptions) { record -> Date in
            calendar.startOfDay(for: record.timestamp)
        }
        return groups.keys.sorted(by: >).map { key in
            (date: key, records: groups[key]!.sorted { $0.timestamp > $1.timestamp })
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            let decoded = try decoder.decode([TranscriptionRecord].self, from: data)
            transcriptions = decoded
        } catch {
            NSLog("[UsageStore] Failed to decode usage: \(error)")
        }
    }

    private func persistAsync(records: [TranscriptionRecord]) {
        let destinationURL = url
        Task.detached(priority: .utility) {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted]
                let data = try encoder.encode(records)
                try data.write(to: destinationURL, options: [.atomic])
            } catch {
                NSLog("[UsageStore] Failed to persist usage: \(error)")
            }
        }
    }
}
