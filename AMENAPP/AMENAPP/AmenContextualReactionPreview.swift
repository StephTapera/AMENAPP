import SwiftUI

#Preview("Amen Contextual Reactions") {
    AmenContextualReactionPreview()
}

struct AmenContextualReactionPreview: View {
    @StateObject private var observer = AmenMagicWordComposerObserver()
    @State private var previewText = "Psalm 139 says God knows me fully. Please pray for me."
    @State private var presentation: AmenContextualReactionPresentation?

    private let engine = AmenContextualReactionEngine.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Contextual Reactions")
                    .font(.system(size: 30, weight: .bold))

                Text("Threads-style hidden delight, aligned to Amen.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.black.opacity(0.6))

                VStack(alignment: .leading, spacing: 12) {
                    TextField("Type a phrase…", text: $previewText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("contextual_preview_textfield")
                        .onChange(of: previewText) { _, newValue in
                            observer.update(text: newValue)
                        }

                    AmenContextualReactionLayer(results: observer.results, maxVisible: 4)

                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white)
                            .frame(height: 180)
                            .shadow(color: .black.opacity(0.06), radius: 18, y: 12)

                        AmenContextualReactionEffectHost(presentation: presentation)
                            .padding()
                    }

                    HStack(spacing: 18) {
                        AmenContextualReactionButton(
                            icon: "heart",
                            activeIcon: "heart.fill",
                            isActive: false,
                            accessibilityLabel: "Like testimony post",
                            longPressAccessibilityLabel: "Touch and hold to open hidden reactions",
                            accessibilityIdentifier: "contextual_preview_like_button",
                            contentText: "God brought me back slowly. This is my testimony.",
                            contentType: .testimonyPost,
                            action: {}
                        ) { _ in
                        } onPresentationChanged: { newPresentation in
                            presentation = newPresentation
                        }

                        Button("Save Scripture") {
                            if let result = engine.reactionForSave(contentText: previewText) {
                                presentation = AmenContextualReactionPresentation(result: result)
                                clear(result.durationMs)
                            }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("contextual_preview_save_button")

                        Button("Share Prayer") {
                            if let result = engine.reactionForShare(contentText: previewText) {
                                presentation = AmenContextualReactionPresentation(result: result)
                                clear(result.durationMs)
                            }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("contextual_preview_share_button")
                    }
                }
            }
            .padding(24)
        }
        .background(Color(red: 0.972, green: 0.972, blue: 0.965).ignoresSafeArea())
        .onAppear {
            observer.update(text: previewText)
        }
        .accessibilityIdentifier("contextual_reaction_preview")
    }

    private func clear(_ durationMs: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(durationMs) / 1000) {
            presentation = nil
        }
    }
}
