// ContextBeforeCommentGateView.swift
// AMENAPP — Camera OS + Community
// Context-before-comment: creator can require watching N% of content before comments unlock.
// Anti-reactive. Encourages understanding over hot takes.
// Shown to viewers who haven't yet met the watch threshold.

import SwiftUI

// MARK: - ContextBeforeCommentGateView (Viewer)

/// Compact overlay shown at the comment input area for viewers who haven't
/// yet watched the required fraction of the content.
struct ContextBeforeCommentGateView: View {

    // MARK: Props

    let settings: ContextBeforeCommentSettings
    let currentWatchFraction: Double   // 0.0 – 1.0
    let onClose: () -> Void

    // MARK: State

    @State private var isUnlocked = false

    // MARK: Accent

    private let amber = Color(red: 1.0, green: 0.84, blue: 0.0)

    // MARK: Computed

    private var progressFraction: Double {
        min(currentWatchFraction / max(settings.minimumWatchFraction, 0.001), 1.0)
    }

    private var messageText: String {
        settings.messageForViewers.isEmpty
            ? "Watch \(Int(settings.minimumWatchFraction * 100))% to unlock comments"
            : settings.messageForViewers
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: isUnlocked ? "checkmark.bubble.fill" : "text.bubble.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isUnlocked ? Color.green : amber)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    // Message
                    Text(isUnlocked ? "Comments are now unlocked!" : messageText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .accessibilityLabel(isUnlocked
                            ? "Comments are now unlocked"
                            : "Comment gate: \(messageText)"
                        )

                    // Progress bar
                    if !isUnlocked {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.white.opacity(0.15))
                                    .frame(height: 4)

                                Capsule()
                                    .fill(amber)
                                    .frame(
                                        width: geo.size.width * progressFraction,
                                        height: 4
                                    )
                                    .animation(.easeInOut(duration: 0.4), value: progressFraction)
                            }
                        }
                        .frame(height: 4)
                        .accessibilityLabel(
                            "Watch progress: \(Int(progressFraction * 100)) percent of required"
                        )
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .padding(.trailing, 36)  // room for dismiss button
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(amber.opacity(0.3), lineWidth: 0.8)
                    )
            }

            // Dismiss button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.6))
            }
            .accessibilityLabel("Dismiss comment gate notice")
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
        .onChange(of: currentWatchFraction) { _, newValue in
            if newValue >= settings.minimumWatchFraction && !isUnlocked {
                withAnimation(.easeInOut(duration: 0.4)) {
                    isUnlocked = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    onClose()
                }
            }
        }
        .onAppear {
            if currentWatchFraction >= settings.minimumWatchFraction {
                isUnlocked = true
            }
        }
    }
}

// MARK: - ContextBeforeCommentSettingsView (Creator)

/// Full settings panel for the content creator to configure the comment gate.
struct ContextBeforeCommentSettingsView: View {

    // MARK: Props

    @Binding var settings: ContextBeforeCommentSettings

    // MARK: Accent

    private let amber = Color(red: 1.0, green: 0.84, blue: 0.0)

    // MARK: Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {

                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Context Before Comments")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)

                    Text(
                        "Require viewers to watch a portion of your content before they can comment. Encourages thoughtful engagement."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                }

                // Enable toggle
                glassRow {
                    Toggle(isOn: $settings.isEnabled) {
                        HStack(spacing: 10) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(amber)
                                .accessibilityHidden(true)

                            Text("Enable")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                    .tint(amber)
                    .accessibilityLabel("Enable context before comments")
                }

                // Expanded settings — shown only when enabled
                if settings.isEnabled {
                    VStack(alignment: .leading, spacing: 20) {

                        // Watch fraction slider
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Required watch amount")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.55))

                            glassRow {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("\(Int(settings.minimumWatchFraction * 100))%")
                                            .font(.system(size: 22, weight: .bold))
                                            .foregroundStyle(amber)
                                            .accessibilityLabel(
                                                "Required watch fraction: \(Int(settings.minimumWatchFraction * 100)) percent"
                                            )
                                        Spacer()
                                    }

                                    Slider(
                                        value: $settings.minimumWatchFraction,
                                        in: 0.25...1.0,
                                        step: 0.25
                                    )
                                    .tint(amber)
                                    .accessibilityLabel("Watch fraction slider")
                                    .accessibilityValue("\(Int(settings.minimumWatchFraction * 100)) percent")

                                    // Step labels
                                    HStack {
                                        ForEach(["25%", "50%", "75%", "100%"], id: \.self) { label in
                                            Text(label)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.white.opacity(0.4))
                                            if label != "100%" { Spacer() }
                                        }
                                    }
                                }
                            }
                        }

                        // Custom message field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Message for viewers")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.55))

                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                                    )
                                    .frame(height: 48)

                                if settings.messageForViewers.isEmpty {
                                    Text("Watch more to join the conversation")
                                        .font(.system(size: 15))
                                        .foregroundStyle(.white.opacity(0.3))
                                        .padding(.horizontal, 16)
                                        .allowsHitTesting(false)
                                }

                                TextField("", text: $settings.messageForViewers)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                            }
                            .accessibilityLabel("Message shown to viewers, editable")
                        }

                        // Live preview
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Preview")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.55))

                            ContextBeforeCommentGateView(
                                settings: settings,
                                currentWatchFraction: 0.0,
                                onClose: {}
                            )
                            .allowsHitTesting(false)
                            .accessibilityLabel("Preview of comment gate as viewers see it")
                        }

                        // Ambient note
                        Text("Comments unlock automatically. No manual action needed.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                            .accessibilityLabel(
                                "Note: comments unlock automatically, no manual action needed"
                            )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeInOut(duration: 0.28), value: settings.isEnabled)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color.black.opacity(0.88).ignoresSafeArea())
    }

    // MARK: - Glass row helper

    @ViewBuilder
    private func glassRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                    )
            }
    }
}

// MARK: - Previews

#Preview("Gate — locked") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            ContextBeforeCommentGateView(
                settings: .defaultSettings,
                currentWatchFraction: 0.2,
                onClose: {}
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Gate — unlocked") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            ContextBeforeCommentGateView(
                settings: .defaultSettings,
                currentWatchFraction: 1.0,
                onClose: {}
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Settings — creator") {
    ContextBeforeCommentSettingsView(
        settings: .constant(.defaultSettings)
    )
    .preferredColorScheme(.dark)
}
