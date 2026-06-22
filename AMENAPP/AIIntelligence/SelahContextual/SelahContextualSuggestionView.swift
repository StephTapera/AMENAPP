import SwiftUI

// MARK: - Selah Contextual Suggestion Card
// A single restrained glass card that renders the controller's top suggestion. Visual
// language matches SelahSessionShapingCard (frosted material, soft accent border) so the
// ambient surface feels native, not bolted on. Only ever shows one suggestion at a time —
// restraint is the product.

struct SelahContextualSuggestionCard: View {
    let suggestion: SelahContextualSuggestion
    let onPrimary: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        switch suggestion.feature.cluster {
        case .inTheRoom:      return .teal
        case .acrossTheWeek:  return .indigo
        case .flowOfLife:     return .blue
        case .restraintSpine: return .green
        case .trustAndDepth:  return .purple
        }
    }

    private var icon: String {
        switch suggestion.surface {
        case .restScreen:   return "moon.stars"
        case .queueForLater: return "clock.arrow.circlepath"
        case .notification: return "bell.badge"
        case .inline, .silent: return "sparkles"
        }
    }

    private var primaryLabel: String {
        switch suggestion.surface {
        case .restScreen:    return "Rest"
        case .queueForLater: return "Remind me"
        default:             return suggestion.scriptureRefs.isEmpty ? "Open" : "Read"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(accent.opacity(0.12)).frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(suggestion.feature.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color(.tertiarySystemBackground)))
                }
                .accessibilityLabel("Dismiss \(suggestion.feature.displayName)")
            }

            Text(suggestion.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !suggestion.scriptureRefs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestion.scriptureRefs, id: \.self) { ref in
                            Text(ref)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(accent.opacity(0.10)))
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button(action: onPrimary) {
                    Text(primaryLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(accent))
                }
                .accessibilityLabel(primaryLabel)

                Button(action: onDismiss) {
                    Text("Not now")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(accent.opacity(0.10)))
                }
                .accessibilityLabel("Not now")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark
                      ? AnyShapeStyle(.ultraThinMaterial)
                      : AnyShapeStyle(Color(.secondarySystemBackground)))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accent.opacity(0.14), lineWidth: 0.5)
                )
                .shadow(color: accent.opacity(0.08), radius: 12, y: 4)
        )
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Selah Contextual Host

/// Mounts the ambient suggestion surface as a top overlay and drives evaluation on
/// foreground/appear. Entirely gated by `selah_contextual_enabled` — renders nothing
/// and runs nothing when the master flag is OFF.
struct SelahContextualHostModifier: ViewModifier {
    @ObservedObject private var flags = AMENFeatureFlags.shared
    @ObservedObject private var controller = SelahContextualController.shared
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if flags.selahContextualEnabled, let suggestion = controller.currentSuggestion {
                    SelahContextualSuggestionCard(
                        suggestion: suggestion,
                        onPrimary: { controller.handlePrimary(suggestion) },
                        onDismiss: { controller.dismiss(suggestion) }
                    )
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.32, dampingFraction: 0.85), value: suggestion.id)
                    .zIndex(996)
                }
            }
            .sheet(item: $controller.presentedReader) { request in
                SelahContextualReaderSheet(request: request)
            }
            .task(id: flags.selahContextualEnabled) { await evaluate() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await evaluate() } }
            }
    }

    @MainActor
    private func evaluate() async {
        guard flags.selahContextualEnabled else { return }
        // Intentional clipboard scripture catch — only when feature + permission are granted.
        var clipboardRefs: [String] = []
        if SelahContextualFlags.isFeatureFlagEnabled(.copiedVerseCatch),
           controller.preferences.enabledFeatures.contains(.copiedVerseCatch),
           controller.preferences.grantedPermissions.contains(.clipboardOrShareSheet) {
            clipboardRefs = SelahContextualSignalProvider().scanClipboardForScripture()
        }
        // Heavier, already-consented detector: fuse church-presence confidence into the
        // In-the-Room cluster. Empty unless attending + cluster enabled.
        let external = SelahContextualChurchBridge.inTheRoomConfidences()
        // Real session load drives the rest / doomscroll cues (Restraint Spine).
        let sessionSeconds = AppUsageTracker.shared.continuousSessionSeconds
        await controller.refresh(
            sessionDurationSeconds: sessionSeconds,
            clipboardScriptureRefs: clipboardRefs,
            externalConfidences: external
        )
    }
}

extension View {
    /// Mount the Selah Contextual ambient surface. No-op while the master flag is OFF.
    func selahContextualHost() -> some View {
        modifier(SelahContextualHostModifier())
    }
}
