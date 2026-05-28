import SwiftUI

struct SmartDiscussionInsightSheet: View {
    let insight: SmartDiscussionInsight
    var onStartStudy: () -> Void
    var onAskBerean: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Summary") { Text(insight.summary) }
                listSection("Key Takeaways", insight.keyTakeaways)
                listSection("Scriptures Mentioned", insight.scriptures)
                listSection("Prayer Requests", insight.prayerRequests)
                listSection("Action Items", insight.actionItems)
                listSection("Unresolved Questions", insight.unresolvedQuestions)
            }
            .navigationTitle("Discussion Insight")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Start Study", systemImage: "book.closed", action: onStartStudy)
                    Button("Ask Berean", systemImage: "sparkles", action: onAskBerean)
                }
            }
        }
    }

    private func listSection(_ title: String, _ items: [String]) -> some View {
        Section(title) {
            if items.isEmpty {
                Text("None found").foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.self) { Text($0) }
            }
        }
    }
}
