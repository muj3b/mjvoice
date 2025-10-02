import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum DashboardItem: String, Hashable, CaseIterable {
    case home
    case tone
    case hotkeys
    case dictionary
    case snippets
    case notes
    case notifications
    case account
    case help
}

struct DashboardView: View {
    @State private var selection: DashboardItem = .home
    @ObservedObject private var usage = UsageStore.shared
    @ObservedObject private var snippetStore = SnippetStore.shared
    @ObservedObject private var eventLog = EventLogStore.shared
    @State private var showingPreferences = false
    @State private var customVocabulary = PreferencesStore.shared.current.customVocab.sorted()
    @State private var newTerm: String = ""
    @State private var showingAddSnippet = false
    @State private var snippetTitle: String = ""
    @State private var snippetBody: String = ""
    @State private var selectedNote: TranscriptionRecord?

    private var username: String {
        let full = NSFullUserName()
        if !full.isEmpty {
            return full.split(separator: " ").first.map(String.init) ?? full
        }
        let user = NSUserName()
        return user.isEmpty ? "Friend" : user
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(minWidth: 1024, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingPreferences) {
            PreferencesView()
                .frame(width: 560)
        }
        .sheet(isPresented: $showingAddSnippet) {
            snippetComposer
                .frame(width: 420, height: 320)
        }
        .onAppear { refreshVocabulary() }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardNavigate)) { note in
            if let raw = note.object as? String, let item = DashboardItem(rawValue: raw) {
                selection = item
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("mjvoice")
                    .font(.title2).bold()
                Text("Basic")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.horizontal, 20)
            List(selection: $selection) {
                Section {
                    SidebarRow(icon: "house.fill", title: "Home", item: .home, selection: $selection)
                    SidebarDisclosure(title: "Personalization", icon: "slider.horizontal.3", selection: $selection) {
                        SidebarRow(icon: "sparkles", title: "Tone", item: .tone, selection: $selection)
                        SidebarRow(icon: "keyboard", title: "Hotkeys", item: .hotkeys, selection: $selection)
                    }
                    SidebarRow(icon: "text.book.closed", title: "Dictionary", item: .dictionary, selection: $selection)
                    SidebarRow(icon: "note.text", title: "Snippets", item: .snippets, selection: $selection)
                    SidebarRow(icon: "square.and.pencil", title: "Notes", item: .notes, selection: $selection)
                }
                Section {
                    SidebarCTA(title: "Try mjvoice Pro", subtitle: "Unlock unlimited dictation", icon: "sparkles")
                    SidebarLink(title: "Invite teammates", icon: "person.badge.plus")
                    SidebarLink(title: "Get 2 free months", icon: "gift")
                    SidebarRow(icon: "gearshape.fill", title: "Settings", item: .account, selection: $selection)
                    SidebarRow(icon: "bell", title: "Notifications", item: .notifications, selection: $selection)
                    SidebarRow(icon: "questionmark.circle", title: "Help", item: .help, selection: $selection)
                }
            }
            .listStyle(.sidebar)
        }
        .frame(width: 240)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .home:
            homeView
        case .tone:
            personalizationView
        case .hotkeys:
            hotkeysView
        case .dictionary:
            dictionaryView
        case .snippets:
            snippetsView
        case .notes:
            notesView
        case .notifications:
            notificationsView
        case .account:
            accountView
        case .help:
            helpView
        }
    }

    private var homeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome back, \(username)")
                            .font(.largeTitle).bold()
                        HStack(spacing: 16) {
                            Label("\(usage.weeklyStreak) weeks", systemImage: "flame.fill")
                            Label("\(usage.totalWords.formatted()) words", systemImage: "chart.line.uptrend.xyaxis")
                            Label(String(format: "%.0f WPM", usage.averageWPM), systemImage: "trophy.fill")
                        }
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Preferences") { showingPreferences = true }
                        .buttonStyle(.borderedProminent)
                }
                promotionalCard
                historySection
            }
            .padding(32)
        }
    }

    private var personalizationView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Personalization")
                .font(.title)
            Text("Adjust tone presets, grammar rules, and per-app behaviors.")
                .foregroundStyle(.secondary)
            Button("Open Preferences") { showingPreferences = true }
            Spacer()
        }
        .padding(32)
    }

    private var hotkeysView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hotkeys")
                .font(.title)
            Text("Change your push-to-talk shortcut and choose between press-and-hold, latch, or toggle modes.")
                .foregroundStyle(.secondary)
            Button("Open Preferences") { showingPreferences = true }
            Spacer()
        }
        .padding(32)
    }

    private var dictionaryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Custom Dictionary")
                        .font(.title)
                    Text("Terms are used to bias the transcription engine and reduce spelling mistakes.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: importVocabulary) {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
            }
            HStack {
                TextField("Add new term", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addVocabularyTerm)
                Button("Add", action: addVocabularyTerm)
                    .buttonStyle(.bordered)
            }
            List {
                ForEach(customVocabulary, id: \.self) { term in
                    HStack {
                        Text(term)
                        Spacer()
                        Button(role: .destructive) {
                            removeVocabularyTerm(term)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(32)
    }

    private var snippetsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Snippets")
                    .font(.title)
                Spacer()
                Button {
                    showingAddSnippet = true
                } label: {
                    Label("New Snippet", systemImage: "plus")
                }
            }
            Text("Save templated responses and insert them with a single click.")
                .foregroundStyle(.secondary)

            List {
                ForEach(snippetStore.snippets) { snippet in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(snippet.title)
                                .font(.headline)
                            Spacer()
                            if let last = snippet.lastUsedAt {
                                Text("Used " + last.relativeDescription())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(snippet.content)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)

                        HStack {
                            Button {
                                insertSnippet(snippet)
                            } label: {
                                Label("Insert", systemImage: "text.insert")
                            }
                            Button {
                                copySnippet(snippet)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            Button(role: .destructive) {
                                snippetStore.remove(snippet)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(32)
    }

    private var notesView: some View {
        let noteGroups = usage.groupedHistory().map { (date: $0.date, records: $0.records.filter { $0.destination == .notes }) }.filter { !$0.records.isEmpty }
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Notes")
                    .font(.title)
                Spacer()
                Button {
                    NotesWindow.shared.makeKeyAndOrderFront(nil)
                } label: {
                    Label("Open Scratchpad", systemImage: "square.and.pencil")
                }
            }
            Text("Dictation sessions captured in Notes mode are stored here.")
                .foregroundStyle(.secondary)

            if noteGroups.isEmpty {
                Spacer()
                EmptyStateView(title: "No notes yet", systemImage: "note.text", message: "Hold your hotkey and switch to Notes mode to start collecting ideas.")
                Spacer()
            } else {
                List {
                    ForEach(noteGroups, id: \.date) { group in
                        Section(header: Text(group.date, style: .date)) {
                            ForEach(group.records) { record in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(record.timestamp, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(record.text)
                                        .font(.body)
                                    HStack {
                                        Button("Copy") { copyToPasteboard(record.text) }
                                        Button("Open in Notes") {
                                            NotesWindow.shared.makeKeyAndOrderFront(nil)
                                            NotesWindow.shared.append(text: "\n---\n" + record.text)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(32)
    }

    private var notificationsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Activity")
                    .font(.title)
                Spacer()
                Button("Mark all read") { eventLog.markAllRead() }
                    .disabled(eventLog.entries.allSatisfy { $0.isRead })
            }
            Text("mjvoice keeps a local audit trail for clipboard fallbacks, downloads, and snippet actions.")
                .foregroundStyle(.secondary)

            if eventLog.entries.isEmpty {
                Spacer()
                EmptyStateView(title: "No activity yet", systemImage: "bell.slash", message: "You'll see recent events here once you start dictating.")
                Spacer()
            } else {
                List(eventLog.entries) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: entry.type))
                            .foregroundStyle(color(for: entry.type))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.message)
                            Text(entry.date.relativeDescription())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .opacity(entry.isRead ? 0.5 : 1)
                }
            }
        }
        .padding(32)
    }

    private var accountView: some View {
        let prefs = PreferencesStore.shared.current
        return VStack(alignment: .leading, spacing: 16) {
            Text("Account & Settings")
                .font(.title)
            Form {
                LabeledContent("Mode") { Text(prefs.defaultMode.rawValue.capitalized) }
                LabeledContent("PTT") { Text(prefs.pttMode.rawValue) }
                LabeledContent("ASR Model") {
                    Text(modelSummary(for: prefs))
                }
                LabeledContent("Noise Model") {
                    Text(prefs.selectedNoiseModelID ?? prefs.noiseModel.rawValue)
                }
                LabeledContent("Offline Mode") { Text(prefs.offlineMode ? "Enabled" : "Disabled") }
            }
            Spacer()
        }
        .padding(32)
    }

    private var helpView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Help & Support")
                .font(.title)
            Text("Need a refresher? Open the guides, watch the quickstart, or contact mjvoice support.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    openURL("https://docs.mjvoice.app/guide")
                    EventLogStore.shared.record(type: .helpOpened, message: "Opened user guide")
                } label: {
                    Label("User Guide", systemImage: "book")
                }
                Button {
                    openURL("https://docs.mjvoice.app/shortcuts")
                    EventLogStore.shared.record(type: .helpOpened, message: "Viewed keyboard shortcuts")
                } label: {
                    Label("Keyboard Shortcuts", systemImage: "keyboard")
                }
                Button {
                    openURL("mailto:support@mjvoice.app")
                    EventLogStore.shared.record(type: .helpOpened, message: "Drafted support email")
                } label: {
                    Label("Email Support", systemImage: "envelope")
                }
            }
            Spacer()
        }
        .padding(32)
    }

    private var promotionalCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tag text anywhere")
                    .font(.title3).bold()
                Text("mjvoice automatically formats and inserts text with context-aware prompts.")
                    .foregroundStyle(.secondary)
                Button("Learn more") {}
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
            Image(systemName: "text.magnifyingglass")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .foregroundColor(.accentColor)
                .padding()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.15))
        )
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent activity")
                .font(.title2).bold()
            if usage.transcriptions.isEmpty {
                Text("Start dictating to see your history here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(usage.groupedHistory(), id: \.date) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.date, style: .date)
                            .font(.headline)
                        ForEach(group.records) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(record.timestamp, style: .time)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(String(format: "%.0f WPM", record.wpm))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Text(record.text)
                                    .lineLimit(3)
                                HStack(spacing: 12) {
                                    if let app = record.appName {
                                        Label(app, systemImage: "app.dashed")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Label("\(record.words) words", systemImage: "character.book.closed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Label(record.destination.rawValue.capitalized, systemImage: "arrowshape.turn.up.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor).opacity(0.2)))
                        }
                    }
                }
            }
        }
    }
}

private struct SidebarRow: View {
    let icon: String
    let title: String
    let item: DashboardItem
    @Binding var selection: DashboardItem

    var body: some View {
        Button {
            selection = item
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarDisclosure<Content: View>: View {
    let title: String
    let icon: String
    @Binding var selection: DashboardItem
    let content: Content
    @State private var expanded = true

    init(title: String, icon: String, selection: Binding<DashboardItem>, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            content
                .padding(.leading, 8)
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarCTA: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .font(.headline)
            }
            Text(subtitle)
                .font(.caption)
            Button("Learn more") {}
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor).opacity(0.2)))
    }
}

private struct SidebarLink: View {
    let title: String
    let icon: String
    var body: some View {
        Button {
            NotificationCenter.default.post(name: .dashboardNavigate, object: DashboardItem.help.rawValue)
        } label: {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 300)
        }
        .padding()
    }
}

private struct PlaceholderView: View {
    let title: String
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title)
            Text(message)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(32)
    }
}

extension DashboardView {
    private func importVocabulary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let count = PreferencesStore.shared.importCustomVocab(from: url)
            NSLog("[Dashboard] Imported \(count) custom vocabulary entries")
            refreshVocabulary()
        }
    }

    private func addVocabularyTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        PreferencesStore.shared.addCustomVocabularyTerm(term)
        newTerm = ""
        refreshVocabulary()
    }

    private func removeVocabularyTerm(_ term: String) {
        PreferencesStore.shared.removeCustomVocabularyTerm(term)
        refreshVocabulary()
    }

    private func refreshVocabulary() {
        customVocabulary = PreferencesStore.shared.current.customVocab.sorted()
    }

    private var snippetComposer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Snippet")
                .font(.title2)
            TextField("Title", text: $snippetTitle)
            TextEditor(text: $snippetBody)
                .frame(minHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            HStack {
                Spacer()
                Button("Cancel") {
                    showingAddSnippet = false
                    snippetTitle = ""
                    snippetBody = ""
                }
                Button("Save") {
                    let title = snippetTitle.isEmpty ? "Snippet" : snippetTitle
                    snippetStore.add(title: title, content: snippetBody)
                    showingAddSnippet = false
                    snippetTitle = ""
                    snippetBody = ""
                }
                .disabled(snippetBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }

    private func insertSnippet(_ snippet: Snippet) {
        let outcome = TextInserter.shared.insert(text: snippet.content)
        snippetStore.markUsed(snippet)
        if case .clipboard = outcome {
            EventLogStore.shared.record(type: .clipboardFallback, message: "Snippet copied to clipboard")
        }
    }

    private func copySnippet(_ snippet: Snippet) {
        copyToPasteboard(snippet.content)
        snippetStore.markUsed(snippet)
    }

    private func icon(for type: EventLogEntry.EventType) -> String {
        switch type {
        case .clipboardFallback: return "doc.on.clipboard"
        case .modelDownload: return "arrow.down.circle"
        case .modelDownloadFailed: return "exclamationmark.triangle"
        case .snippetCreated: return "plus.square.on.square"
        case .snippetInserted: return "text.insert"
        case .noteCaptured: return "note.text"
        case .helpOpened: return "questionmark.circle"
        }
    }

    private func color(for type: EventLogEntry.EventType) -> Color {
        switch type {
        case .clipboardFallback: return .blue
        case .modelDownload: return .green
        case .modelDownloadFailed: return .red
        case .snippetCreated: return .purple
        case .snippetInserted: return .purple
        case .noteCaptured: return .orange
        case .helpOpened: return .mint
        }
    }

    private func modelSummary(for prefs: UserPreferences) -> String {
        prefs.selectedASRModelID ?? "\(prefs.asrModel.rawValue.capitalized) \(prefs.modelSize.rawValue.capitalized)"
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyToPasteboard(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}

private extension Date {
    func relativeDescription() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

extension Notification.Name {
    static let dashboardNavigate = Notification.Name("dashboardNavigate")
}
