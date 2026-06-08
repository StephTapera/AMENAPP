// LateNightPauseView.swift
// AMENAPP
//
// Shown when a user starts a media session after 10 PM local time.
// Frames rest as a spiritual discipline rather than an app-imposed limit.
// Gated by `lateNightPauseEnabled`.

import SwiftUI

struct LateNightPauseView: View {

    let onContinue: () -> Void
    let onSleep: () -> Void

    @ObservedObject private var flags = AMENFeatureFlags.shared

    var body: some View {
        if !flags.lateNightPauseEnabled {
            EmptyView()
                .onAppear { onContinue() }
        } else {
            overlayContent
        }
    }

    // MARK: - Overlay

    private var overlayContent: some View {
        ZStack {
            // Dark full-screen backdrop
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            // Glass card
            VStack(spacing: 24) {

                // Moon icon
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.blue)
                    .padding(.top, 4)

                // Copy block
                VStack(spacing: 10) {
                    Text("It's getting late")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    Text("Rest is a spiritual discipline. Your content will still be here tomorrow.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: onSleep) {
                        Text("I'll rest now")
                            .font(.body)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }

                    Button(action: onContinue) {
                        Text("Continue watching")
                            .font(.body)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial)
                            .foregroundStyle(.primary)
                            .clipShape(Capsule())
                    }
                }

                // Settings nudge
                Text("You can disable late night pause in Settings.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)
            }
            .padding(28)
            .background {
                RoundedRectangle(cornerRadius: 28)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 12)
            }
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Static Helper

    /// Returns `true` when it is 10 PM or later in the user's local time zone
    /// and the late night pause flag is enabled.
    static func shouldShow() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 22 && AMENFeatureFlags.shared.lateNightPauseEnabled
    }
}
