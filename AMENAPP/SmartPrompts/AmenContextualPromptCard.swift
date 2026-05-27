import SwiftUI
import UserNotifications

// MARK: - Contextual Prompt Card

struct AmenContextualPromptCard: View {
    let prompt: AmenContextualPrompt
    @ObservedObject var engine: AmenPromptIntelligenceEngine

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Drag indicator
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
                .padding(.bottom, 22)
                .accessibilityHidden(true)

            // Icon + header
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(prompt.iconTint.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: prompt.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(prompt.iconTint)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(prompt.title)
                        .font(.custom("OpenSans-SemiBold", size: 17))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(prompt.body)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
            }

            // Principles — only shown when there's more than one
            if prompt.principles.count > 1 {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(prompt.principles) { p in
                        Label(p.label, systemImage: p.icon)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.52))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                    }
                }
                .padding(14)
                .background(principlesBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 18)
            }

            Spacer(minLength: 24)

            // Primary action
            Button {
                handlePrimary()
            } label: {
                Text(prompt.primaryLabel)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.green.opacity(0.82))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Completes the suggested action and dismisses this prompt."))

            // Secondary action
            Button {
                engine.dismissNotNow()
            } label: {
                Text(prompt.secondaryLabel)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.white.opacity(0.48))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityHint(Text("Closes this prompt. It may appear again later."))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .background(cardBackground.ignoresSafeArea())
    }

    // MARK: - Actions

    private func handlePrimary() {
        switch prompt.primaryAction {
        case .requestSystemNotifications:
            Task {
                engine.confirmPrimary()
                _ = try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
            }
        case .enableQuietMode:
            engine.confirmPrimary()
            NotificationCenter.default.post(name: .amenPromptEnableQuietMode, object: nil)
        case .openPrayer:
            engine.confirmPrimary()
            NotificationCenter.default.post(name: Notification.Name("amen.openPrayerComposer"), object: nil)
        case .openSelah:
            engine.confirmPrimary()
            NotificationCenter.default.post(name: .amenPromptOpenSelah, object: nil)
        case .resumeNote:
            engine.confirmPrimary()
            NotificationCenter.default.post(
                name: .amenPromptResumeChurchNote,
                object: prompt.metadata["noteId"]
            )
        case .continueScrolling:
            engine.confirmPrimary()
        }
    }

    // MARK: - Backgrounds

    private var cardBackground: some View {
        Group {
            if reduceTransparency {
                Color(white: 0.09)
            } else {
                Color.black.opacity(0.88)
                    .background(.ultraThinMaterial)
            }
        }
    }

    private var principlesBackground: some View {
        Group {
            if reduceTransparency {
                Color(white: 0.14)
            } else {
                Color.white.opacity(0.06)
            }
        }
    }
}

// MARK: - View Modifier

struct AmenContextualPromptModifier: ViewModifier {
    @ObservedObject var engine: AmenPromptIntelligenceEngine

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $engine.isPresented) {
                if let prompt = engine.activePrompt {
                    AmenContextualPromptCard(prompt: prompt, engine: engine)
                        .presentationDetents([.fraction(0.50)])
                        .presentationDragIndicator(.hidden)
                        .presentationCornerRadius(28)
                        .presentationBackground(Color.clear)
                }
            }
    }
}

extension View {
    /// Attach to the root view to enable contextual prompts using the shared engine.
    func amenContextualPrompts() -> some View {
        modifier(AmenContextualPromptModifier(engine: AmenPromptIntelligenceEngine.shared))
    }

    /// Attach to the root view with an explicit engine (e.g. for testing).
    func amenContextualPrompts(engine: AmenPromptIntelligenceEngine) -> some View {
        modifier(AmenContextualPromptModifier(engine: engine))
    }
}

// MARK: - Preview

#Preview {
    @Previewable @StateObject var engine = AmenPromptIntelligenceEngine()
    Color.black.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AmenContextualPromptCard(
                prompt: .make(.prayerReplyNotifications),
                engine: engine
            )
            .presentationDetents([.fraction(0.50)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
            .presentationBackground(Color.clear)
        }
}
