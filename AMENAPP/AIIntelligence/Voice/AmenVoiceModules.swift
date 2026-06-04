import SwiftUI

@MainActor
final class AmenVoiceSessionManager: ObservableObject {
    @Published var transcript = ""
    @Published var detectedLanguageCode = "en"
    @Published var isRunning = false

    func start() { isRunning = true }
    func stop() { isRunning = false }
}

struct AmenLiveTranscriptView: View {
    let transcript: String
    var body: some View {
        Text(transcript.isEmpty ? "Live transcript will appear here." : transcript)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AmenVoiceIntentChips: View {
    let onTap: (String) -> Void
    private let intents = ["Pray", "Reflect", "Summarize", "Turn into post", "Save to Church Notes"]

    var body: some View {
        AmenLiquidGlassControlDock(placement: .bottom) {
            ForEach(intents, id: \.self) { intent in
                AmenLiquidGlassPillButton(title: intent, systemImage: "sparkles", isLoading: false, isDisabled: false) {
                    onTap(intent)
                }
            }
        }
    }
}

struct AmenVoicePermissionView: View {
    var body: some View {
        Text("Microphone + speech permissions are required. Nothing is posted automatically.")
            .font(.footnote)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AmenRealtimeVoiceView: View {
    @StateObject private var session = AmenVoiceSessionManager()

    var body: some View {
        VStack(spacing: 12) {
            AmenVoicePermissionView()
            AmenLiveTranscriptView(transcript: session.transcript)
            AmenVoiceIntentChips { _ in }
        }
        .background(Color.white)
    }
}

struct AmenVoiceCompanionSheet: View {
    var body: some View {
        // TODO: enable when implemented — BT2 Voice Companion
        if AMENFeatureFlags.shared.amenRealtimeVoiceEnabled {
            AmenLiquidGlassBottomSheet(
                title: "Voice Companion",
                subtitle: "Realtime captions and intent actions",
                aiDisclosure: "AI-assisted voice draft"
            ) {
                AmenRealtimeVoiceView()
            } footer: {
                AmenLiquidGlassControlDock(placement: .bottom) {
                    AmenLiquidGlassPillButton(title: "Start", systemImage: "mic.fill", isLoading: false, isDisabled: false, action: {})
                    AmenLiquidGlassPillButton(title: "Close", systemImage: "xmark", isLoading: false, isDisabled: false, action: {})
                }
            }
        }
    }
}

enum AmenVoiceAnalytics {
    static let voiceSessionStarted = "amen_voice_session_started"
    static let voiceSessionEnded = "amen_voice_session_ended"
    static let voiceSessionFailed = "amen_voice_session_failed"
}
