import SwiftUI

struct BereanSimpleModeView: View {
    @State private var question = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Simple Mode")
                    .font(.system(size: 30, weight: .bold))
                Text("Large, clear actions for a calmer Berean experience.")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)

                TextField("Ask Berean", text: $question, axis: .vertical)
                    .font(.system(size: 20))
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
        Button(action: {}) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
            }
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
