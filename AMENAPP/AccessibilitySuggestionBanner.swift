// AccessibilitySuggestionBanner.swift
// AMEN App — Accessibility Intelligence Layer (Phase 5)
//
// Compact glass banner at top of feed. Shows suggestion text + "Try it" + "Not now".
// Auto-dismisses after 8 seconds. Motion.adaptive animation.

import SwiftUI

struct AccessibilitySuggestionBanner: View {

    @ObservedObject private var engine = AccessibilitySuggestionEngine.shared
    @State private var autoDismissTask: Task<Void, Never>?

    var body: some View {
        if let suggestion = engine.pendingSuggestion {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(Color(.label))
                        Text(suggestion.message)
                            .font(AMENFont.regular(12))
                            .foregroundStyle(Color(.secondaryLabel))
                            .lineLimit(2)
                    }

                    Spacer()
                }

                HStack(spacing: 12) {
                    Spacer()

                    Button {
                        engine.dismissSuggestion()
                    } label: {
                        Text("Not now")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }

                    Button {
                        HapticManager.impact(style: .light)
                        engine.acceptSuggestion()
                    } label: {
                        Text(suggestion.actionLabel)
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.85)), value: engine.pendingSuggestion == nil)
            .onAppear {
                // Auto-dismiss after 8 seconds
                autoDismissTask = Task {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    if !Task.isCancelled {
                        engine.dismissSuggestion()
                    }
                }
            }
            .onDisappear {
                autoDismissTask?.cancel()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(suggestion.title). \(suggestion.message)")
            .accessibilityAction(named: suggestion.actionLabel) {
                engine.acceptSuggestion()
            }
            .accessibilityAction(named: "Dismiss") {
                engine.dismissSuggestion()
            }
        }
    }
}
