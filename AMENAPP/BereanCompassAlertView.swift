// BereanCompassAlertView.swift
// AMENAPP
//
// Berean Compass — gentle slide-up intervention card for DM manipulation detection.
// Never accusatory. Opens a door of awareness, never a door of fear.

import SwiftUI

// MARK: - BereanCompassAlertView

struct BereanCompassAlertView: View {

    let signal: CompassSignal
    var onDismiss: () -> Void
    var onGetSupport: () -> Void

    // Design tokens
    private let compassBlue   = Color(red: 0.25, green: 0.60, blue: 0.95)
    private let tealAccent    = Color(red: 0.20, green: 0.78, blue: 0.72)
    private let cardBG        = Color(red: 0.07, green: 0.09, blue: 0.13)
    private let cardStroke    = Color(white: 1, opacity: 0.08)
    private let labelPrimary  = Color.white
    private let labelSecondary = Color(white: 0.65)

    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Slide-up card
            VStack(alignment: .leading, spacing: 0) {
                // Handle bar
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(white: 1, opacity: 0.20))
                    .frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 18)

                // Header
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [compassBlue.opacity(0.25), tealAccent.opacity(0.20)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        Image(systemName: "compass.drawing")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(compassBlue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Berean Compass")
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundColor(labelPrimary)
                        Text(stageSubtitle)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundColor(labelSecondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)

                // Main message
                Text(interventionMessage)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundColor(labelPrimary.opacity(0.90))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                // Patterns section (soft, non-alarming)
                if !signal.patterns.isEmpty {
                    patternsList
                        .padding(.top, 14)
                }

                // Action buttons
                actionButtons
                    .padding(.top, 20)
                    .padding(.horizontal, 20)

                // Dismiss link
                Button(action: onDismiss) {
                    Text("I'm fine, dismiss")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(labelSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                Spacer().frame(height: 4)
            }
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(cardBG)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(cardStroke, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.40), radius: 24, x: 0, y: -4)
            )
            .offset(y: isVisible ? 0 : 320)
            .animation(.spring(response: 0.45, dampingFraction: 0.80), value: isVisible)
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.80)) {
                isVisible = true
            }
        }
    }

    // MARK: - Stage Messaging

    private var stageSubtitle: String {
        switch signal.stage.stageNumber {
        case 1: return "A gentle check-in"
        case 2: return "Worth a moment to reflect"
        default: return "Something to consider"
        }
    }

    private var interventionMessage: String {
        // Use the Cloud Function's intervention message if available, otherwise fall back
        guard signal.interventionMessage.isEmpty else {
            return signal.interventionMessage
        }
        switch signal.stage.stageNumber {
        case 1:
            return "You've been talking with this person for a while. It's always good to check in with someone you trust — a parent, mentor, or close friend."
        case 2:
            return "We noticed this conversation has become quite personal. Is there a trusted adult or friend you could share this with? Sometimes a fresh perspective helps."
        default:
            return "You're navigating an important conversation. Consider reaching out to someone you trust."
        }
    }

    // MARK: - Patterns List

    private var patternsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Patterns noticed")
                .font(.custom("OpenSans-SemiBold", size: 12))
                .foregroundColor(compassBlue.opacity(0.80))
                .kerning(0.8)
                .textCase(.uppercase)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(signal.patterns.prefix(3), id: \.self) { pattern in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(compassBlue.opacity(0.40))
                            .frame(width: 5, height: 5)
                            .padding(.top, 5)
                        Text(pattern)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundColor(labelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(compassBlue.opacity(0.06))
                    .padding(.horizontal, 14)
            )
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            // Primary: Talk to a trusted person
            Button(action: onGetSupport) {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 15, weight: .medium))
                    Text("Talk to a trusted person")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [compassBlue, tealAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)

            // Secondary: Resources
            if !signal.resources.isEmpty {
                resourcesButton
            }
        }
    }

    private var resourcesButton: some View {
        Menu {
            ForEach(signal.resources) { resource in
                Button(action: {
                    if let url = URL(string: resource.deepLink) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Label(resource.title, systemImage: resource.icon)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "book.pages")
                    .font(.system(size: 14, weight: .medium))
                Text("Resources")
                    .font(.custom("OpenSans-SemiBold", size: 15))
            }
            .foregroundColor(compassBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(compassBlue.opacity(0.35), lineWidth: 1.5)
            )
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Stage 1 — Isolation") {
    ZStack {
        Color.black.ignoresSafeArea()
        BereanCompassAlertView(
            signal: CompassSignal(
                stage: .awareness(stage: 1),
                interventionMessage: "",
                patterns: [
                    "Repeated \"only I understand you\" framing",
                    "Discouraging contact with family members"
                ],
                resources: [.trustCircle, .safetyGuide]
            ),
            onDismiss: {},
            onGetSupport: {}
        )
    }
}

#Preview("Stage 2 — Identity Shift") {
    ZStack {
        Color.black.ignoresSafeArea()
        BereanCompassAlertView(
            signal: CompassSignal(
                stage: .awareness(stage: 2),
                interventionMessage: "",
                patterns: [
                    "\"You're special / not like others\" language",
                    "Building an exclusive bond narrative"
                ],
                resources: [.trustCircle, .counselingLine]
            ),
            onDismiss: {},
            onGetSupport: {}
        )
    }
}
#endif
