import SwiftUI

struct SmartStudyModeView: View {
    let session: SmartStudySession
    let relatedMessages: [String]
    let prayerRequests: [String]
    var onAskBerean: (String) -> Void
    var onSave: () -> Void
    var onShare: () -> Void
    var onExport: () -> Void

    var body: some View {
        List {
            SmartStudyScripturePanel(scriptures: session.scriptures, onAskBerean: onAskBerean)
            SmartStudyQuestionsPanel(scriptures: session.scriptures, topics: session.topics)
            Section("Topics") { rows(session.topics) }
            Section("Group Notes") { rows(session.notes.isEmpty ? ["No notes yet."] : session.notes) }
            Section("Related Messages") { rows(relatedMessages) }
            Section("Prayer Requests") { rows(prayerRequests) }
            Section {
                Button("Save", systemImage: "tray.and.arrow.down", action: onSave)
                Button("Share", systemImage: "square.and.arrow.up", action: onShare)
                Button("Export", systemImage: "doc", action: onExport)
            }
        }
        .navigationTitle(session.title)
    }

    private func rows(_ items: [String]) -> some View {
        ForEach(items, id: \.self) { item in Text(item) }
    }
}

struct SmartStudyScripturePanel: View {
    let scriptures: [String]
    var onAskBerean: (String) -> Void

    var body: some View {
        Section("Scriptures") {
            if scriptures.isEmpty {
                Text("No scriptures detected.").foregroundStyle(.secondary)
            } else {
                ForEach(scriptures, id: \.self) { scripture in
                    Button(scripture, systemImage: "book") { onAskBerean(scripture) }
                }
            }
        }
    }
}

struct SmartStudyQuestionsPanel: View {
    let scriptures: [String]
    let topics: [String]

    var body: some View {
        Section("Discussion Questions") {
            Text("What stands out most in \(scriptures.first ?? topics.first ?? "this discussion")?")
            Text("What question should the group answer before moving on?")
            Text("What would faithful application look like this week?")
        }
    }
}
