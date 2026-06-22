// ServiceModeOverlay.swift
// Minimal in-service focused tool layer
// Subtle, one-handed, dismissible
// AMENAPP

import SwiftUI

// MARK: - ServiceModeAction

enum ServiceModeAction: String, CaseIterable {
    case captureVerse  = "captureVerse"
    case startNote     = "startNote"
    case prayerThought = "prayerThought"
    case saveTakeaway  = "saveTakeaway"

    var label: String {
        switch self {
        case .captureVerse:  return "Verse"
        case .startNote:     return "Note"
        case .prayerThought: return "Prayer"
        case .saveTakeaway:  return "Takeaway"
        }
    }

    var icon: String {
        switch self {
        case .captureVerse:  return "text.quote"
        case .startNote:     return "note.text"
        case .prayerThought: return "hands.sparkles"
        case .saveTakeaway:  return "bookmark.fill"
        }
    }
}

// MARK: - ServiceModeOverlay

struct ServiceModeOverlay: View {

    let churchName: String
    let onCapture: (ServiceModeAction) -> Void
    let onDismiss: () -> Void

    @State private var isMinimized = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if isMinimized {
                // Minimized pill
                minimizedPill
            } else {
                // Full action card
                fullCard
            }

            // Dismiss link
            if !isMinimized {
                Button("Dismiss") {
                    onDismiss()
                }
                .font(AMENFont.regular(13))
                .foregroundStyle(.secondary)
                .padding(.trailing, 4)
            }
        }
        .padding(.trailing, 16)
        .transition(
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        )
    }

    // MARK: - Minimized Pill

    private var minimizedPill: some View {
        Button {
            withAnimation(Motion.adaptive(Animation.spring(response: 0.3, dampingFraction: 0.75))) {
                isMinimized = false
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Service Mode")
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
                            .strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5)
                    )
            }
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Full Card

    private var fullCard: some View {
        VStack(alignment: .trailing, spacing: 10) {
            // Minimize button
            Button {
                withAnimation(Motion.adaptive(Animation.spring(response: 0.3, dampingFraction: 0.75))) {
                    isMinimized = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Service Mode")
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.systemScaled(10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            // Action buttons row
            HStack(spacing: 8) {
                ForEach(ServiceModeAction.allCases, id: \.rawValue) { action in
                    Button {
                        onCapture(action)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: action.icon)
                                .font(.systemScaled(13, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(action.label)
                                .font(AMENFont.semiBold(12))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                )
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ZStack(alignment: .bottomTrailing) {
        Color.white.ignoresSafeArea()
        ServiceModeOverlay(
            churchName: "Antioch Church",
            onCapture: { _ in },
            onDismiss: {}
        )
        .padding(.bottom, 60)
    }
}
#endif
