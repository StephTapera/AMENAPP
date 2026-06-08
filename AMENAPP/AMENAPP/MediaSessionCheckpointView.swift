// MediaSessionCheckpointView.swift
// AMENAPP
//
// Presents a mid-session "check in" card at defined item or time thresholds.
// Encourages intentional consumption without forcing the user to stop.
// Gated by `mediaSessionCheckpointsEnabled`.

import SwiftUI

// MARK: - Checkpoint Card

struct MediaSessionCheckpointView: View {

    let itemsConsumed: Int
    let minutesInSession: Int
    let onContinue: () -> Void
    let onEnd: () -> Void

    @State private var showSummaryAlert = false
    @ObservedObject private var flags = AMENFeatureFlags.shared

    var body: some View {
        guard flags.mediaSessionCheckpointsEnabled else { return AnyView(EmptyView()) }
        return AnyView(checkpointCard)
    }

    private var checkpointCard: some View {
        ZStack {
            // Background blur
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            // Glass card
            VStack(spacing: 20) {

                // Header
                VStack(spacing: 6) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.blue)

                    Text("Check in")
                        .font(.title2)
                        .fontWeight(.bold)
                }

                // Summary sentence
                Text("You've watched \(itemsConsumed) video\(itemsConsumed == 1 ? "" : "s") in \(minutesInSession) minute\(minutesInSession == 1 ? "" : "s").")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Inline stats row
                HStack(spacing: 0) {
                    statCell(label: "Time", value: "\(minutesInSession)m")
                    Divider()
                        .frame(height: 36)
                    statCell(label: "Items", value: "\(itemsConsumed)")
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )

                // Primary actions
                VStack(spacing: 10) {
                    Button(action: onContinue) {
                        Text("Keep watching")
                            .font(.body)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }

                    Button(action: onEnd) {
                        Text("I'm done")
                            .font(.body)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial)
                            .foregroundStyle(.primary)
                            .clipShape(Capsule())
                    }
                }

                // Session summary link
                Button {
                    showSummaryAlert = true
                } label: {
                    Text("See your session summary")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .underline()
                }
                .alert("Session Summary", isPresented: $showSummaryAlert) {
                    Button("Done", role: .cancel) {}
                } message: {
                    Text("You've watched \(itemsConsumed) video\(itemsConsumed == 1 ? "" : "s") over \(minutesInSession) minute\(minutesInSession == 1 ? "" : "s") in this session.")
                }
            }
            .padding(28)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
            }
            .padding(.horizontal, 28)
        }
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

// MARK: - Modifier

struct MediaSessionCheckpointModifier: ViewModifier {

    @Binding var isPresented: Bool
    let itemsConsumed: Int
    let minutesInSession: Int
    let onContinue: () -> Void
    let onEnd: () -> Void

    func body(content: Content) -> some View {
        ZStack {
            content
            if isPresented {
                MediaSessionCheckpointView(
                    itemsConsumed: itemsConsumed,
                    minutesInSession: minutesInSession,
                    onContinue: {
                        isPresented = false
                        onContinue()
                    },
                    onEnd: {
                        isPresented = false
                        onEnd()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isPresented)
    }
}

// MARK: - View Extension

extension View {
    /// Overlays a `MediaSessionCheckpointView` when `isPresented` is true.
    func sessionCheckpoint(
        isPresented: Binding<Bool>,
        itemsConsumed: Int,
        minutesInSession: Int,
        onContinue: @escaping () -> Void,
        onEnd: @escaping () -> Void
    ) -> some View {
        modifier(MediaSessionCheckpointModifier(
            isPresented: isPresented,
            itemsConsumed: itemsConsumed,
            minutesInSession: minutesInSession,
            onContinue: onContinue,
            onEnd: onEnd
        ))
    }
}
