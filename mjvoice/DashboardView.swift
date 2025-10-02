import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum DashboardItem: Hashable {
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
    @State private var showingPreferences = false

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
            Text("Custom Dictionary")
                .font(.title)
            Text("Import domain vocabulary and manage pronunciations.")
                .foregroundStyle(.secondary)
            Button("Import CSV…", action: importVocabulary)
            Spacer()
        }
        .padding(32)
    }

    private var snippetsView: some View {
        PlaceholderView(title: "Snippets", message: "Create reusable text snippets and voice shortcuts.")
    }

    private var notesView: some View {
        PlaceholderView(title: "Notes", message: "Review your scratchpad entries and export them as Markdown.")
    }

    private var notificationsView: some View {
        PlaceholderView(title: "Notifications", message: "Manage desktop alerts for clipboard fallback and model updates.")
    }

    private var accountView: some View {
        PlaceholderView(title: "Account", message: "Sign in to sync settings across devices (coming soon).")
    }

    private var helpView: some View {
        PlaceholderView(title: "Help", message: "Browse guides, FAQs, and contact support.")
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
        HStack {
            Image(systemName: icon)
            Text(title)
        }
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
        }
    }
}
