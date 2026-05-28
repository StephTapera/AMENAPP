import SwiftUI

struct AmenCreatorKitHome: View {
    let actions = ["Mic", "Captions", "Translate", "Explain", "Summarize", "Improve", "Create Graphic", "Prayer Points", "Action Items", "Discussion Questions"]

    @State private var showBerean = false
    @State private var bereanQuery: String = ""
    @State private var showVoice = false

    var body: some View {
        VStack(spacing: 12) {
            Text("Amen Creator Kit")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            if AMENFeatureFlags.shared.isLivingHeroEnabled(for: .creatorKit) {
                AmenLivingHeroView(
                    scene: AmenLivingHeroContentResolver.creatorKit(),
                    onPrimaryAction: {
                        bereanQuery = "Help me create compelling, faith-centered content."
                        showBerean = true
                    }
                )
                .padding(.horizontal, 16)
            }

            AmenLiquidGlassControlDock(placement: .top) {
                ForEach(actions, id: \.self) { action in
                    AmenLiquidGlassPillButton(
                        title: action,
                        systemImage: systemImage(for: action),
                        isLoading: false,
                        isDisabled: false
                    ) {
                        if action == "Mic" {
                            showVoice = true
                        } else {
                            bereanQuery = bereanPrompt(for: action)
                            showBerean = true
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top)
        .background(AmenTheme.Colors.backgroundPrimary)
        .sheet(isPresented: $showBerean) {
            BereanChatView(
                initialMode: .scholar,
                initialQuery: bereanQuery,
                conversationTitle: "Creator Kit"
            )
        }
        .sheet(isPresented: $showVoice) {
            AmenVoiceCreatorSheet()
        }
    }

    private func systemImage(for action: String) -> String {
        switch action {
        case "Mic":               return "mic.fill"
        case "Captions":          return "captions.bubble.fill"
        case "Translate":         return "globe"
        case "Explain":           return "info.circle.fill"
        case "Summarize":         return "text.compress"
        case "Improve":           return "wand.and.sparkles"
        case "Create Graphic":    return "photo.artframe"
        case "Prayer Points":     return "hands.and.sparkles.fill"
        case "Action Items":      return "checklist"
        case "Discussion Questions": return "bubble.left.and.bubble.right.fill"
        default:                  return "sparkles"
        }
    }

    private func bereanPrompt(for action: String) -> String {
        switch action {
        case "Captions":          return "Write engaging, faith-centered captions for my content."
        case "Translate":         return "Help me translate or adapt this message for a different audience or language."
        case "Explain":           return "Help me explain this scripture or faith concept clearly and accessibly."
        case "Summarize":         return "Summarize the key points of this content for a faith community."
        case "Improve":           return "Help me improve this content to make it more impactful and spiritually resonant."
        case "Create Graphic":    return "Suggest visual elements and design ideas for faith-based content."
        case "Prayer Points":     return "Generate focused prayer points based on this content."
        case "Action Items":      return "Extract practical action items and next steps from this message."
        case "Discussion Questions": return "Create thoughtful discussion questions for a small group based on this content."
        default:                  return "Help me with \(action.lowercased()) for this content."
        }
    }
}

// MARK: - Voice Creator Sheet

private struct AmenVoiceCreatorSheet: View {
    @StateObject private var sessionManager = AmenVoiceSessionManager()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                AmenVoicePermissionView()
                    .padding(.horizontal)

                AmenLiveTranscriptView(transcript: sessionManager.transcript)
                    .padding(.horizontal)
                    .frame(maxHeight: 200)

                Spacer()

                AmenVoiceIntentChips { _ in
                    dismiss()
                }

                Button(sessionManager.isRunning ? "Stop Recording" : "Start Recording") {
                    sessionManager.isRunning ? sessionManager.stop() : sessionManager.start()
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom)
            }
            .navigationTitle("Voice Creator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
