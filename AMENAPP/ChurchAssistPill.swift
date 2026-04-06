// ChurchAssistPill.swift
// Floating Liquid Glass assist pill — context-aware, dismissible
// AMENAPP

import SwiftUI

// MARK: - ChurchAssistPill

struct ChurchAssistPill: View {

    let state: ChurchVisitState
    let churchName: String
    let onTap: (ChurchAssistPromptType) -> Void
    let onDismiss: () -> Void

    @State private var isExpanded = false
    @State private var isVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Computed Properties

    private var pillIcon: String {
        switch state {
        case .planning:         return "location.fill"
        case .arrived:          return "checkmark.circle.fill"
        case .inService:        return "book.fill"
        case .postVisit:        return "heart.fill"
        case .revisitSuggested: return "arrow.counterclockwise.circle.fill"
        default:                return "building.columns.fill"
        }
    }

    private var pillLabel: String {
        switch state {
        case .planning:         return "Planning to attend \(churchName)?"
        case .arrived:          return "Need Church Notes?"
        case .inService:        return "Capture a verse or takeaway"
        case .postVisit:        return "What did you learn today?"
        case .revisitSuggested: return "Plan your return?"
        default:                return churchName
        }
    }

    private var actionChips: [(label: String, prompt: ChurchAssistPromptType)] {
        switch state {
        case .arrived:
            return [
                ("Start Notes",   .arrivedNeedsNotes),
                ("Checklist",     .arrivedChecklist),
                ("Add Prayer",    .inServicePrayerThought)
            ]
        case .inService:
            return [
                ("Capture Verse",   .inServiceCaptureVerse),
                ("Prayer Thought",  .inServicePrayerThought),
                ("Save Takeaway",   .postVisitReflection)
            ]
        case .postVisit:
            return [
                ("Write Reflection",    .postVisitReflection),
                ("Save Privately",      .postVisitReflection),
                ("Share to #OpenTable", .postVisitShare)
            ]
        case .planning:
            return [
                ("See What to Expect", .firstVisitCompanion),
                ("Compare Services",   .compareServices),
                ("Save Church",        .planningToAttend)
            ]
        case .revisitSuggested:
            return [
                ("Plan Return",        .revisitSuggestion),
                ("Compare Services",   .compareServices),
                ("Save Church",        .planningToAttend)
            ]
        default:
            return []
        }
    }

    // MARK: - Body

    var body: some View {
        if isVisible {
            VStack(alignment: .trailing, spacing: 8) {
                // Main pill
                HStack(spacing: 10) {
                    Image(systemName: pillIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(pillLabel)
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    // Dismiss button
                    Button {
                        dismissPill()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5)
                        )
                }
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                .onTapGesture {
                    withAnimation(Motion.adaptive(Animation.spring(response: 0.3, dampingFraction: 0.72))) {
                        isExpanded.toggle()
                    }
                }

                // Expanded action chips
                if isExpanded {
                    VStack(alignment: .trailing, spacing: 6) {
                        ForEach(actionChips, id: \.label) { chip in
                            Button {
                                onTap(chip.prompt)
                                withAnimation(Motion.adaptive(Motion.springRelease)) {
                                    isExpanded = false
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(chip.label)
                                        .font(AMENFont.semiBold(12))
                                        .foregroundStyle(.primary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background {
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        )
                    )
                }
            }
            .padding(.horizontal, 16)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                )
            )
        }
    }

    // MARK: - Actions

    private func dismissPill() {
        withAnimation(Motion.adaptive(Animation.spring(response: 0.4, dampingFraction: 0.8))) {
            isVisible = false
            isExpanded = false
        }
        onDismiss()
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ZStack(alignment: .bottom) {
        Color.white.ignoresSafeArea()
        ChurchAssistPill(
            state: .arrived,
            churchName: "Antioch Church",
            onTap: { _ in },
            onDismiss: {}
        )
        .padding(.bottom, 40)
    }
}
#endif
