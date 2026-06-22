//
//  HeyFeedActivePillsBar.swift
//  AMENAPP
//
//  Horizontal scrollable strip showing active NL feed preferences.
//  Appears in the OpenTable header when the user has tuned their feed.
//  Each pill shows the active action, its target, and time remaining.
//  Tapping X on a pill removes that preference immediately.
//

import SwiftUI

// MARK: - Active Pills Bar

struct HeyFeedActivePillsBar: View {
    @ObservedObject private var nlService = HeyFeedNLPreferencesService.shared

    var body: some View {
        let active = nlService.activePreferences.filter { !$0.isExpired }
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Feed state label
                        Text("Feed tuned:")
                            .font(AMENFont.regular(11))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 2)

                        ForEach(active) { pref in
                            HeyFeedActivePillChip(preference: pref) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                Task { try? await nlService.removePreference(id: pref.id) }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.78)), value: active.map(\.id))
        }
    }
}

// MARK: - Individual Pill Chip

private struct HeyFeedActivePillChip: View {
    let preference: HeyFeedNLPreference
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: actionIcon)
                .font(.systemScaled(10, weight: .semibold))
                .foregroundStyle(actionColor)

            Text(preference.targetLabel)
                .font(AMENFont.semiBold(11))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(preference.timeRemainingLabel)
                .font(.systemScaled(9))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.systemScaled(9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.thinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(actionColor.opacity(0.18), lineWidth: 0.5)
                )
        )
    }

    private var actionIcon: String {
        switch preference.action {
        case .increase: return "arrow.up"
        case .decrease: return "arrow.down"
        case .mute:     return "eye.slash"
        case .explore:  return "sparkles"
        case .balance:  return "arrow.2.circlepath"
        }
    }

    private var actionColor: Color {
        switch preference.action {
        case .increase: return .green
        case .decrease: return .orange
        case .mute:     return .red
        case .explore:  return .blue
        case .balance:  return .secondary
        }
    }
}
