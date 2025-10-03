import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum DashboardItem: String, Hashable, CaseIterable {
    case overview
    case personalization
    case hotkeys
    case dictionary
    case snippets
    case notes
    case activity
    case settings
    case support
}

struct DashboardView: View {
    @State private var selection: DashboardItem = .overview
    @ObservedObject private var usage = UsageStore.shared
    @ObservedObject private var snippetStore = SnippetStore.shared
    @ObservedObject private var eventLog = EventLogStore.shared
    @State private var showingPreferences = false
    @State private var showingAddSnippet = false
    @State private var snippetTitle: String = ""
    @State private var snippetBody: String = ""
    @State private var vocabularySheet = false
    @State private var customVocabulary = PreferencesStore.shared.current.customVocab.sorted()
    @State private var newVocabularyTerm = ""

    private let gradientBackground = LinearGradient(colors: [Color(red: 0.09, green: 0.10, blue: 0.20), Color(red: 0.04, green: 0.06, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing)

    private var greeting: String {
        let full = NSFullUserName()
        if !full.isEmpty {
            return full.split(separator: " ").first.map(String.init) ?? full
        }
        let user = NSUserName()
        return user.isEmpty ? "Guest" : user
    }

    var body: some View {
        ZStack {
            gradientBackground.ignoresSafeArea()
            HStack(spacing: 0) {
                sidebar
                Divider().background(Color.white.opacity(0.1))
                content
            }
            .frame(minHeight: 680)
        }
        .sheet(isPresented: $showingPreferences) {
            PreferencesView().frame(width: 560)
        }
        .sheet(isPresented: $showingAddSnippet) { snippetComposer }
        .sheet(isPresented: $vocabularySheet) { vocabularyComposer }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardNavigate)) { note in
            if let raw = note.object as? String, let destination = DashboardItem(rawValue: raw) {
                selection = destination
            }
        }
        .onAppear(perform: refreshVocabulary)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 28) {
            headerBadge
            VStack(alignment: .leading, spacing: 12) {
                ForEach(primaryEntries) { entry in
                    SidebarButton(entry: entry, selection: $selection)
                }
            }
            Divider().background(Color.white.opacity(0.12))
            VStack(alignment: .leading, spacing: 12) {
                ForEach(secondaryEntries) { entry in
                    SidebarButton(entry: entry, selection: $selection)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                SidebarLink(title: "Invite collaborators", systemImage: "person.2.badge.gear") {
                    openURL("https://mjvoice.app/invite")
                }
                SidebarLink(title: "Activate Pro trial", systemImage: "sparkles") {
                    openURL("https://mjvoice.app/pro")
                }
            }
            .padding(.bottom, 24)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 26)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.vertical, 20)
        )
    }

    private var headerBadge: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.white.opacity(0.18)).frame(width: 38, height: 38)
                Text("MJ")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("mjvoice")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text("Everywhere dictation")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
    }

    private var primaryEntries: [SidebarEntry] {
        [
            SidebarEntry(icon: "rectangle.grid.2x2", label: "Overview", item: .overview),
            SidebarEntry(icon: "slider.horizontal.3", label: "Personalization", item: .personalization),
            SidebarEntry(icon: "keyboard", label: "Hotkeys", item: .hotkeys),
            SidebarEntry(icon: "character.book.closed", label: "Dictionary", item: .dictionary),
            SidebarEntry(icon: "text.badge.plus", label: "Snippets", item: .snippets),
            SidebarEntry(icon: "note.text", label: "Notes", item: .notes)
        ]
    }

    private var secondaryEntries: [SidebarEntry] {
        [
            SidebarEntry(icon: "waveform.path.ecg", label: "Activity", item: .activity),
            SidebarEntry(icon: "gearshape", label: "Settings", item: .settings),
            SidebarEntry(icon: "questionmark.circle", label: "Support", item: .support)
        ]
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .overview:
            overviewTab
        case .personalization:
            personalizationTab
        case .hotkeys:
            hotkeysTab
        case .dictionary:
            dictionaryTab
        case .snippets:
            snippetsTab
        case .notes:
            notesTab
        case .activity:
            activityTab
        case .settings:
            settingsTab
        case .support:
            supportTab
        }
    }

    private var overviewTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 30) {
                overviewHeader
                statCards
                quickActions
                recentSessions
            }
            .padding(.vertical, 36)
            .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.04))
    }

    private var overviewHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Good to see you, \(greeting)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                Text("Keep capturing ideas and let mjvoice handle the busywork.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            Spacer()
            Button {
                showingPreferences = true
            } label: {
                Label("Preferences", systemImage: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(GlowButtonStyle(color: Color.white))
        }
    }

    private var statCards: some View {
        let streak = usage.weeklyStreak
        let wordCount = usage.totalWords
        let average = usage.averageWPM
        return LazyVGrid(columns: adaptiveColumns, spacing: 20) {
            MetricCard(icon: "flame", accent: .orange, title: "Weekly streak", value: streak.description, detail: streak == 1 ? "Week active" : "Weeks active")
            MetricCard(icon: "character.cursor.ibeam", accent: .cyan, title: "Words captured", value: wordCount.formatted(.number.grouping(.automatic)), detail: "Total across sessions")
            MetricCard(icon: "speedometer", accent: .pink, title: "Average pace", value: String(format: "%.0f", average), detail: "Words per minute")
        }
    }

    private var adaptiveColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 240), spacing: 18, alignment: .top)]
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Quick actions")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
            LazyVGrid(columns: adaptiveColumns, spacing: 16) {
                ActionTile(title: "Install Fluid runtime", subtitle: "Enable Fluid ASR locally", icon: "shippingbox", color: .purple) {
                    PreferencesWindowController.shared.show()
                    NotificationCenter.default.post(name: .dashboardNavigate, object: DashboardItem.settings.rawValue)
                }
                ActionTile(title: "Launch Notes scratchpad", subtitle: "Drop ideas into the persistent window", icon: "square.and.pencil", color: .cyan) {
                    NotesWindow.shared.makeKeyAndOrderFront(nil)
                }
                ActionTile(title: "View release notes", subtitle: "Catch up on the latest improvements", icon: "sparkle.magnifyingglass", color: .orange) {
                    openURL("https://mjvoice.app/changelog")
                }
            }
        }
    }

    private var recentSessions: some View {
        let groups = usage.groupedHistory().prefix(3)
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Recent sessions")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                Spacer()
            }
            if groups.isEmpty {
                EmptyTimelineView()
            } else {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(groups), id: \.date) { group in
                        TimelineGroup(date: group.date, records: group.records.prefix(3))
                    }
                }
            }
        }
    }

    // MARK: - Other tabs (brief unique layouts)

    private var personalizationTab: some View {
        InfoCalloutView(
            title: "Personalization",
            message: "Tune tone, grammar preferences, and per-app behaviours inside Preferences.",
            buttonTitle: "Open Preferences"
        ) {
            showingPreferences = true
        }
    }

    private var hotkeysTab: some View {
        InfoCalloutView(
            title: "Hotkeys",
            message: "Switch between press-to-talk modes, set dedicated shortcuts, and preview focus management.",
            buttonTitle: "Configure Hotkeys"
        ) {
            showingPreferences = true
        }
    }

    private var dictionaryTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Custom dictionary")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.white)
                Spacer()
                Button("Import CSV") {
                    vocabularySheet = true
                }
                .buttonStyle(GlowButtonStyle(color: .white))
            }
            Text("Add preferred spellings and domain-specific jargon to bias the recogniser.")
                .foregroundStyle(Color.white.opacity(0.65))
            List {
                ForEach(customVocabulary, id: \.self) { term in
                    HStack {
                        Text(term)
                        Spacer()
                        Button(role: .destructive) { removeVocabularyTerm(term) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 6)
                }
            }
            .frame(maxHeight: 360)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.04))
    }

    private var snippetsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Snippets")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.white)
                Spacer()
                Button {
                    showingAddSnippet = true
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(GlowButtonStyle(color: .white))
            }
            Text("Reusable phrases and responses.")
                .foregroundStyle(Color.white.opacity(0.7))
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
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        Text(snippet.content)
                            .font(.body)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(3)
                        HStack {
                            Button("Insert") { insertSnippet(snippet) }
                            Button("Copy") { copySnippet(snippet) }
                            Button(role: .destructive) { snippetStore.remove(snippet) } label: { Text("Remove") }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.04))
    }

    private var notesTab: some View {
        NotesOverviewView()
    }

    private var activityTab: some View {
        ActivityView(eventLog: eventLog)
    }

    private var settingsTab: some View {
        SettingsSnapshotView()
    }

    private var supportTab: some View {
        SupportView(openURL: openURL)
    }

    // MARK: - Vocabulary helpers

    private func refreshVocabulary() {
        customVocabulary = PreferencesStore.shared.current.customVocab.sorted()
    }

    private func addVocabularyTerm() {
        PreferencesStore.shared.addCustomVocabularyTerm(newVocabularyTerm)
        newVocabularyTerm = ""
        refreshVocabulary()
    }

    private func removeVocabularyTerm(_ term: String) {
        PreferencesStore.shared.removeCustomVocabularyTerm(term)
        refreshVocabulary()
    }

    private func insertSnippet(_ snippet: Snippet) {
        snippetStore.markUsed(snippet)
        let outcome = TextInserter.shared.insert(text: snippet.content)
        if case .clipboard = outcome {
            EventLogStore.shared.record(type: .clipboardFallback, message: "Snippet copied to clipboard")
        } else {
            EventLogStore.shared.record(type: .snippetInserted, message: "Inserted snippet \(snippet.title)")
        }
    }

    private func copySnippet(_ snippet: Snippet) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(snippet.content, forType: .string)
        snippetStore.markUsed(snippet)
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private var snippetComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create snippet")
                .font(.title2).bold()
            TextField("Title", text: $snippetTitle)
            TextEditor(text: $snippetBody)
                .frame(height: 150)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
            HStack {
                Spacer()
                Button("Cancel") { showingAddSnippet = false }
                Button("Save") {
                    snippetStore.add(title: snippetTitle, content: snippetBody)
                    EventLogStore.shared.record(type: .snippetCreated, message: "Created snippet \(snippetTitle)")
                    snippetTitle = ""
                    snippetBody = ""
                    showingAddSnippet = false
                }
                .disabled(snippetTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || snippetBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 420)
    }

    private var vocabularyComposer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add vocabulary term")
                .font(.title3).bold()
            TextField("Term", text: $newVocabularyTerm)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addVocabularyTerm)
            HStack {
                Spacer()
                Button("Done") { vocabularySheet = false }
                Button("Add") {
                    addVocabularyTerm()
                    EventLogStore.shared.record(type: .dictionaryImport, message: "Added \(newVocabularyTerm)")
                }
                .disabled(newVocabularyTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }
}

// MARK: - Reusable components

private struct SidebarEntry: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let item: DashboardItem
}

private struct SidebarButton: View {
    let entry: SidebarEntry
    @Binding var selection: DashboardItem

    var isSelected: Bool { selection == entry.item }

    var body: some View {
        Button {
            selection = entry.item
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.7))
                    .frame(width: 28)
                Text(entry.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.75))
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.35 : 0.08), lineWidth: 1)
            )
            .shadow(color: isSelected ? Color.black.opacity(0.12) : .clear, radius: 10, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarLink: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote)
                    .opacity(0.4)
            }
            .foregroundStyle(Color.white.opacity(0.8))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

private struct GlowButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(configuration.isPressed ? 0.25 : 0.18)))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(color.opacity(configuration.isPressed ? 0.6 : 0.3), lineWidth: 1)
            )
            .foregroundStyle(Color.black)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: color.opacity(0.35), radius: configuration.isPressed ? 4 : 10, y: configuration.isPressed ? 3 : 8)
    }
}

private struct MetricCard: View {
    let icon: String
    let accent: Color
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct ActionTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
                    .padding(10)
                    .background(color.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TimelineGroup: View {
    let date: Date
    let records: ArraySlice<TranscriptionRecord>

    private var label: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
            ForEach(records) { record in
                TimelineEntry(record: record)
            }
        }
    }
}

private struct TimelineEntry: View {
    let record: TranscriptionRecord

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(record.timestamp, style: .time)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.8))
                    Spacer()
                    if let app = record.appName ?? record.appBundleID {
                        Text(app)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                Text(record.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(4)
                HStack(spacing: 16) {
                    Label("\(record.words) words", systemImage: "character.cursor.ibeam")
                    Label(String(format: "%.0f WPM", record.wpm), systemImage: "speedometer")
                    Label(record.destination == .notes ? "Sent to Notes" : "Inserted", systemImage: "paperplane")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

private struct EmptyTimelineView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 32))
                .foregroundStyle(Color.white.opacity(0.6))
            Text("Capture your first dictation")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
            Text("Hit your push-to-talk key to start logging sessions here.")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

private struct InfoCalloutView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.white)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button(buttonTitle, action: action)
                .buttonStyle(GlowButtonStyle(color: .white))
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.04))
    }
}

private struct NotesOverviewView: View {
    var body: some View {
        InfoCalloutView(
            title: "Notes scratchpad",
            message: "Notes mode delivers uninterrupted writing. Open the floating scratchpad to capture freeform text while dictating.",
            buttonTitle: "Open Notes"
        ) {
            NotesWindow.shared.makeKeyAndOrderFront(nil)
        }
    }
}

private struct ActivityView: View {
    @ObservedObject var eventLog: EventLogStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Activity feed")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.white)
                Spacer()
                Button("Mark all read") { eventLog.markAllRead() }
                    .buttonStyle(GlowButtonStyle(color: .white))
                    .disabled(eventLog.entries.allSatisfy { $0.isRead })
            }
            if eventLog.entries.isEmpty {
                EmptyTimelineView()
            } else {
                List(eventLog.entries) { entry in
                    HStack(spacing: 16) {
                        Image(systemName: icon(for: entry.type))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(color(for: entry.type))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.message)
                                .font(.system(size: 13, weight: .medium))
                            Text(entry.date.relativeDescription())
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .opacity(entry.isRead ? 0.45 : 1.0)
                }
                .scrollContentBackground(.hidden)
                .frame(maxHeight: 420)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.04))
    }

    private func icon(for type: EventLogEntry.EventType) -> String {
        switch type {
        case .clipboardFallback: return "doc.on.doc"
        case .modelDownload: return "arrow.down.circle"
        case .modelDownloadFailed: return "exclamationmark.triangle"
        case .noteCaptured: return "square.and.pencil"
        case .helpOpened: return "questionmark.circle"
        case .snippetInserted: return "text.badge.checkmark"
        case .snippetCreated: return "star"
        case .dictionaryImport: return "tray.and.arrow.down"
        }
    }

    private func color(for type: EventLogEntry.EventType) -> Color {
        switch type {
        case .clipboardFallback: return .blue
        case .modelDownload: return .green
        case .modelDownloadFailed: return .red
        case .noteCaptured: return .orange
        case .helpOpened: return .purple
        case .snippetInserted: return .teal
        case .snippetCreated: return .yellow
        case .dictionaryImport: return .pink
        }
    }
}

private struct SettingsSnapshotView: View {
    var body: some View {
        let prefs = PreferencesStore.shared.current
        return VStack(alignment: .leading, spacing: 20) {
            Text("Current configuration")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.white)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                snapshotRow(label: "Default mode", value: prefs.defaultMode.rawValue.capitalized)
                snapshotRow(label: "PTT", value: prefs.pttMode.rawValue)
                snapshotRow(label: "ASR model", value: prefs.selectedASRModelID ?? prefs.asrModel.rawValue)
                snapshotRow(label: "Noise model", value: prefs.selectedNoiseModelID ?? prefs.noiseModel.rawValue)
                snapshotRow(label: "Language", value: prefs.language)
                snapshotRow(label: "Offline mode", value: prefs.offlineMode ? "Enabled" : "Disabled")
            }
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.04))
    }

    private func snapshotRow(label: String, value: String) -> some View {
        GridRow {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white)
        }
    }
}

private struct SupportView: View {
    let openURL: (String) -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("We're here to help")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.white)
            Text("Access documentation, shortcuts, and contact options without leaving the app.")
                .foregroundStyle(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            VStack(spacing: 12) {
                SupportLink(title: "Open quickstart guide", icon: "book.fill", color: .blue) {
                    openURL("https://docs.mjvoice.app/guide")
                    EventLogStore.shared.record(type: .helpOpened, message: "Opened quickstart guide")
                }
                SupportLink(title: "Keyboard shortcut cheat sheet", icon: "command", color: .purple) {
                    openURL("https://docs.mjvoice.app/shortcuts")
                    EventLogStore.shared.record(type: .helpOpened, message: "Viewed shortcut cheat sheet")
                }
                SupportLink(title: "Chat with support", icon: "bubble.left.and.bubble.right.fill", color: .green) {
                    openURL("mailto:support@mjvoice.app")
                    EventLogStore.shared.record(type: .helpOpened, message: "Requested support conversation")
                }
            }
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.04))
    }
}

private struct SupportLink: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Circle().fill(color.opacity(0.18)).frame(width: 44, height: 44)
                    .overlay(Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(color))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                Spacer()
                Image(systemName: "arrow.uturn.up")
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Extensions

extension Notification.Name {
    static let dashboardNavigate = Notification.Name("dashboardNavigate")
}

extension Date {
    func relativeDescription() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
