import SwiftUI

struct BereanSimpleModeView: View {
    @State private var question = ""
    @StateObject private var berean = BereanStudyService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Simple Mode")
                    .font(.systemScaled(30, weight: .bold))
                Text("Large, clear actions for a calmer Berean experience.")
                    .font(.systemScaled(17))
                    .foregroundStyle(.secondary)

                TextField("Ask Berean", text: $question, axis: .vertical)
                    .font(.systemScaled(20))
                    .padding(16)
                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(spacing: 12) {
                    simpleAction("Ask Berean", icon: "bubble.left.and.text.bubble.right")
                    simpleAction("Explain Scripture", icon: "book")
                    simpleAction("Pray With Me", icon: "hands.sparkles")
                    simpleAction("Explain This Simply", icon: "text.bubble")
                    simpleAction("Read Today’s Verse", icon: "sun.max")
                    simpleAction("Help Me Make a Decision", icon: "compass")
                }
            }
            .padding(24)
        }
        .navigationTitle("Berean Simple")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func simpleAction(_ title: String, icon: String) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                switch title {
                case "Ask Berean":
                    _ = await berean.studyPlan(topic: q.isEmpty ? "general faith questions" : q)
                case "Explain Scripture":
                    _ = await berean.explainVerse(ref: q.isEmpty ? "John 3:16" : q)
                case "Pray With Me":
                    _ = await berean.prayerFromPassage(ref: q.isEmpty ? "Psalm 23" : q, context: q.isEmpty ? nil : q)
                case "Explain This Simply":
                    _ = await berean.explainVerse(ref: q.isEmpty ? "John 3:16" : q, context: "Explain in very simple language")
                case "Read Today’s Verse":
                    _ = await berean.explainVerse(ref: q.isEmpty ? "Psalm 119:105" : q)
                case "Help Me Make a Decision":
                    _ = await berean.studyPlan(topic: q.isEmpty ? "godly decision making" : q)
                default:
                    _ = await berean.studyPlan(topic: q.isEmpty ? title : q)
                }
            }
        }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.systemScaled(22, weight: .semibold))
                Text(title)
                    .font(.systemScaled(22, weight: .semibold))
                Spacer()
            }
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
