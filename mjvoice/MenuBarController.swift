import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarController {
    let menu: NSMenu = NSMenu()

    private var isPaused: Bool = false
    private var engineMode: String = "Local"
    private let openDashboardHandler: () -> Void
    private let snippetStore = SnippetStore.shared
    private let usageStore = UsageStore.shared
    private var cancellables = Set<AnyCancellable>()

    init(openDashboard: @escaping () -> Void) {
        self.openDashboardHandler = openDashboard
        rebuildMenu()
        snippetStore.$snippets
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
        usageStore.$transcriptions
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .mjvoiceOfflineModeChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .asrEngineModeChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                if let mode = note.object as? String { self?.engineMode = mode }
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let statusTitle = isPaused ? "Resume mjvoice" : "Pause mjvoice"
        let toggleItem = NSMenuItem(title: statusTitle, action: #selector(toggleActive), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let offline = PreferencesStore.shared.current.offlineMode
        let offlineItem = NSMenuItem(title: offline ? "Offline Mode: On" : "Offline Mode: Off", action: #selector(toggleOffline), keyEquivalent: "")
        offlineItem.target = self
        menu.addItem(offlineItem)

        let engineItem = NSMenuItem(title: "ASR Engine: \(engineMode)", action: nil, keyEquivalent: "")
        engineItem.isEnabled = false
        menu.addItem(engineItem)

        menu.addItem(NSMenuItem.separator())
        let startItem = NSMenuItem(title: "Start Dictation", action: #selector(startDictation), keyEquivalent: "")
        startItem.target = self
        menu.addItem(startItem)

        let stopItem = NSMenuItem(title: "Stop Dictation", action: #selector(stopDictation), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())
        let dashboardItem = NSMenuItem(title: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "d")
        dashboardItem.keyEquivalentModifierMask = [.command]
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        let snippetManagerItem = NSMenuItem(title: "Open Snippet Manager", action: #selector(openSnippetManager), keyEquivalent: "s")
        snippetManagerItem.keyEquivalentModifierMask = [.command]
        snippetManagerItem.target = self
        menu.addItem(snippetManagerItem)

        let snippetsMenu = NSMenu()
        for snippet in snippetStore.snippets.prefix(5) {
            let snippetItem = NSMenuItem(title: snippet.title, action: #selector(insertSnippet(_:)), keyEquivalent: "")
            snippetItem.target = self
            snippetItem.representedObject = snippet
            snippetsMenu.addItem(snippetItem)
        }
        if snippetsMenu.items.isEmpty {
            let empty = NSMenuItem(title: "No snippets yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            snippetsMenu.addItem(empty)
        }
        let snippetsRoot = NSMenuItem(title: "Snippets", action: nil, keyEquivalent: "")
        snippetsRoot.submenu = snippetsMenu
        menu.addItem(snippetsRoot)

        let recentMenu = NSMenu()
        for record in usageStore.transcriptions.prefix(5) {
            let summary = record.text.split(separator: "\n").first.map(String.init) ?? record.text
            let trimmed = summary.trimmingCharacters(in: .whitespaces)
            let title = trimmed.prefix(40)
            let item = NSMenuItem(title: String(title), action: #selector(copyTranscript(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = record.text
            recentMenu.addItem(item)
        }
        if recentMenu.items.isEmpty {
            let empty = NSMenuItem(title: "No transcripts yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
        }
        let recentRoot = NSMenuItem(title: "Recent Transcripts", action: nil, keyEquivalent: "")
        recentRoot.submenu = recentMenu
        menu.addItem(recentRoot)

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())
        let notesItem = NSMenuItem(title: "Open Notes", action: #selector(openNotes), keyEquivalent: "n")
        notesItem.keyEquivalentModifierMask = [.command, .shift]
        notesItem.target = self
        menu.addItem(notesItem)

        let helpItem = NSMenuItem(title: "Help & Guides", action: #selector(openHelp), keyEquivalent: "?")
        helpItem.keyEquivalentModifierMask = [.command]
        helpItem.target = self
        menu.addItem(helpItem)

        let quitItem = NSMenuItem(title: "Quit mjvoice", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func toggleActive() {
        isPaused.toggle()
        rebuildMenu()
        NotificationCenter.default.post(name: .mjvoiceActiveChanged, object: !isPaused)
    }

    @objc private func toggleOffline() {
        PreferencesStore.shared.update { $0.offlineMode.toggle() }
        rebuildMenu()
        NotificationCenter.default.post(name: .mjvoiceOfflineModeChanged, object: PreferencesStore.shared.current.offlineMode)
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.show()
    }

    @objc private func openDashboard() {
        openDashboardHandler()
    }

    @objc private func startDictation() {
        NotificationCenter.default.post(name: .pttStart, object: nil)
    }

    @objc private func stopDictation() {
        NotificationCenter.default.post(name: .pttStop, object: nil)
    }

    @objc private func openNotes() {
        NotesWindow.shared.makeKeyAndOrderFront(nil)
    }

    @objc private func openHelp() {
        openDashboardHandler()
        NotificationCenter.default.post(name: .dashboardNavigate, object: DashboardItem.support.rawValue)
    }

    @objc private func openSnippetManager() {
        openDashboardHandler()
        NotificationCenter.default.post(name: .dashboardNavigate, object: DashboardItem.snippets.rawValue)
    }

    @objc private func insertSnippet(_ sender: NSMenuItem) {
        guard let snippet = sender.representedObject as? Snippet else { return }
        let outcome = TextInserter.shared.insert(text: snippet.content)
        snippetStore.markUsed(snippet)
        if case .clipboard = outcome {
            EventLogStore.shared.record(type: .clipboardFallback, message: "Snippet copied to clipboard")
        }
    }

    @objc private func copyTranscript(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let mjvoiceActiveChanged = Notification.Name("mjvoiceActiveChanged")
    static let mjvoiceOfflineModeChanged = Notification.Name("mjvoiceOfflineModeChanged")
}

extension Notification.Name {
    static let asrEngineModeChanged = Notification.Name("asrEngineModeChanged")
}
