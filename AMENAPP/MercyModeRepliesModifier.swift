// MercyModeRepliesModifier.swift
// AMENAPP
// Intercepts potentially harsh replies and prompts the user to soften before posting.

import SwiftUI

/// Wrap a reply/send button action with this modifier.
/// When `isFlagged` flips to `true`, a sheet appears before the post goes through.
///
///     sendButton
///         .mercyModeGuard(isFlagged: classifier.isHarsh) { submitReply() }
struct MercyModeRepliesModifier: ViewModifier {
    let isFlagged: Bool
    let onProceed: () -> Void

    @State private var showSheet = false

    func body(content: Content) -> some View {
        guard AMENFeatureFlags.shared.mercyModeRepliesEnabled else {
            return AnyView(content)
        }
        return AnyView(
            content
                .onChange(of: isFlagged) { flagged in
                    if flagged { showSheet = true }
                }
                .sheet(isPresented: $showSheet) {
                    MercyModeSheet(
                        onSoften: { showSheet = false },
                        onPost: {
                            showSheet = false
                            onProceed()
                        }
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
        )
    }
}

// MARK: - Sheet

private struct MercyModeSheet: View {
    let onSoften: () -> Void
    let onPost: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
                .padding(.top, 28)

            VStack(spacing: 8) {
                Text("Be Kind First")
                    .font(.title3.bold())

                Text("This reply might come across as harsh. Consider softening your words to build up rather than tear down.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            VStack(spacing: 12) {
                Button(action: onSoften) {
                    Text("Soften my reply")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                Button(action: onPost) {
                    Text("Post as written")
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

// MARK: - View Extension

extension View {
    func mercyModeGuard(isFlagged: Bool, onProceed: @escaping () -> Void) -> some View {
        modifier(MercyModeRepliesModifier(isFlagged: isFlagged, onProceed: onProceed))
    }
}
