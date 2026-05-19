// AmenThinkFirstGuard.swift
// AMENAPP
// Wraps the post/comment composer. Intercepts before publish with a mindful pause
// when the content safety classifier returns a warn-level decision.

import SwiftUI

/// Call site: wrap the send/publish button action.
///
///     ThinkFirstGuard(decision: safetyDecision) {
///         publisher.publish(draft)
///     }
struct ThinkFirstGuard: ViewModifier {
    let decision: SafetyDecision?
    let onProceed: () -> Void

    @State private var showSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onChange(of: decision?.action) { newAction in
                if newAction == .promptBeforePost {
                    showSheet = true
                }
            }
            .sheet(isPresented: $showSheet) {
                ThinkFirstSheet(
                    decision: decision,
                    onProceed: {
                        showSheet = false
                        onProceed()
                    },
                    onEdit: { showSheet = false }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
    }
}

private struct ThinkFirstSheet: View {
    let decision: SafetyDecision?
    let onProceed: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
                .padding(.top, 28)

            VStack(spacing: 8) {
                Text("Take a moment")
                    .font(.title3.bold())
                Text(decision?.userFacingMessage ?? "Before you post, consider how this might affect others in your community.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            VStack(spacing: 12) {
                Button(action: onEdit) {
                    Text("Edit Post")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                Button(action: onProceed) {
                    Text("Post Anyway")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
    }
}

extension View {
    func thinkFirstGuard(decision: SafetyDecision?, onProceed: @escaping () -> Void) -> some View {
        modifier(ThinkFirstGuard(decision: decision, onProceed: onProceed))
    }
}
