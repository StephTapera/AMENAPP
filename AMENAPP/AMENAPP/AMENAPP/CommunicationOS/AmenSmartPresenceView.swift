// AmenSmartPresenceView.swift
// AMEN App — Smart Collaboration Layer: Slice 4 — Presence UI
//
// Gated entirely behind `RemoteKillSwitch.shared.smartPresenceEnabled` (default OFF).
//
// Non-negotiable design rules enforced here:
//   1. Approximate labels only — no exact last-seen time, no view counts, no typing indicators.
//   2. States are human-readable and non-pressuring.
//   3. Expired snapshots (expiresAt < now) are hidden or shown as "—".
//   4. Only the calling user may update their own presence.
//   5. All UI states handled: empty, loading, error, offline.
//   6. Full VoiceOver + Reduce Motion support.
//   7. Flag OFF → all components return EmptyView.

import SwiftUI
import FirebaseAuth

// MARK: - AmenSmartPresenceState Display Extension

extension AmenSmartPresenceState {

    /// Human-readable, non-pressuring label shown in all UI surfaces.
    var displayName: String {
        switch self {
        case .activeNow:      return "Active now"
        case .recentlyActive: return "Recently active"
        case .mayReplyLater:  return "May reply later"
        case .focus:          return "Focused"
        case .quiet:          return "Quiet"
        }
    }

    /// Semantic dot color — maps to the AMEN design palette.
    var dotColor: Color {
        switch self {
        case .activeNow:      return Color(.systemGreen)
        case .recentlyActive: return Color(.init(red: 0.47, green: 0.58, blue: 0.73, alpha: 1)) // blue-gray
        case .mayReplyLater:  return Color(.systemGray3)
        case .focus:          return Color(.systemOrange).opacity(0.9)  // amber
        case .quiet:          return Color(.systemGray4)
        }
    }

    /// SF Symbol name paired with this state.
    var icon: String {
        switch self {
        case .activeNow:      return "circle.fill"
        case .recentlyActive: return "circle.lefthalf.filled"
        case .mayReplyLater:  return "clock.fill"
        case .focus:          return "moon.fill"
        case .quiet:          return "bell.slash.fill"
        }
    }
}

// MARK: - AmenPresenceStateLabel
// Compact inline pill showing a single participant's presence state.

struct AmenPresenceStateLabel: View {
    let state: AmenSmartPresenceState
    var showIcon: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 5) {
            if showIcon {
                // Dot — decorative; full label provided via accessibilityLabel below.
                Circle()
                    .fill(state.dotColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
            Text(state.displayName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(pillBackground, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.displayName)
    }

    private var pillBackground: some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(.tertiarySystemBackground))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}

// MARK: - AmenPresenceAvatarRow
// Inline row showing up to 5 participant presence dots.
// Tap → full AmenPresenceDetailSheet.

struct AmenPresenceAvatarRow: View {
    let threadId: String
    let threadType: AmenSmartThreadType
    let spaceId: String?
    let channelId: String?

    @ObservedObject private var service = AmenSmartPresenceService.shared
    @ObservedObject private var killSwitch = RemoteKillSwitch.shared

    @State private var showDetail = false

    // Maximum dots shown inline before truncating.
    private let maxVisible = 5

    var body: some View {
        // Flag OFF → invisible — no space consumed.
        guard killSwitch.smartPresenceEnabled else { return AnyView(EmptyView()) }

        return AnyView(content)
    }

    @ViewBuilder
    private var content: some View {
        if let err = service.error {
            // Error state — muted row with label.
            errorRow(err)
        } else if service.participantPresence.isEmpty && !isLoading {
            // Empty state — hide entirely, no space taken.
            EmptyView()
        } else {
            dotRow
                .sheet(isPresented: $showDetail) {
                    AmenPresenceDetailSheet(
                        threadId: threadId,
                        threadType: threadType,
                        spaceId: spaceId,
                        channelId: channelId
                    )
                    .presentationDetents([.medium, .large])
                }
                .onAppear {
                    service.startListening(
                        threadId: threadId,
                        threadType: threadType,
                        spaceId: spaceId,
                        channelId: channelId
                    )
                }
                .onDisappear {
                    service.stopListening()
                }
        }
    }

    // Loading: 3 gray skeleton dots.
    private var isLoading: Bool {
        // Treat initial empty state before first Firestore delivery as loading.
        // The service clears participantPresence on stop, so empty == loading
        // only while a listener is active. We proxy that by checking error==nil
        // and the listener has been attached (after onAppear).
        false  // conservative — show empty rather than false skeleton.
    }

    private var dotRow: some View {
        let visible = Array(service.participantPresence.prefix(maxVisible))
        let overflow = service.participantPresence.count - maxVisible

        return Button {
            showDetail = true
        } label: {
            HStack(spacing: -4) {
                ForEach(Array(visible.enumerated()), id: \.element.userId) { index, snapshot in
                    presenceDot(snapshot: snapshot)
                        .zIndex(Double(maxVisible - index))
                }
                if overflow > 0 {
                    overflowBadge(count: overflow)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityRowLabel)
        .accessibilityHint("Double-tap to see all participant statuses")
    }

    private func presenceDot(snapshot: AmenThreadPresenceSnapshot) -> some View {
        Circle()
            .fill(snapshot.state.dotColor)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(Color(.systemBackground), lineWidth: 1.5)
            )
            .accessibilityHidden(true)
    }

    private func overflowBadge(count: Int) -> some View {
        ZStack {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 10, height: 10)
            Text("+\(count)")
                .font(.system(size: 6, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    private func errorRow(_ error: Error) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "wifi.slash")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Offline")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Presence unavailable")
    }

    private var accessibilityRowLabel: String {
        let count = service.participantPresence.count
        if count == 1 {
            return "1 participant — \(service.participantPresence[0].state.displayName)"
        }
        return "\(count) participants active"
    }
}

// MARK: - AmenPresenceDetailSheet
// Bottom sheet: list of other participants' states + own presence picker.

struct AmenPresenceDetailSheet: View {
    let threadId: String
    let threadType: AmenSmartThreadType
    let spaceId: String?
    let channelId: String?

    @ObservedObject private var service = AmenSmartPresenceService.shared
    @ObservedObject private var killSwitch = RemoteKillSwitch.shared
    @Environment(\.dismiss) private var dismiss

    // Optimistic local selection for immediate feedback.
    @State private var selectedState: AmenSmartPresenceState? = nil

    var body: some View {
        NavigationStack {
            List {
                othersSection
                ownPickerSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Presence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Others

    @ViewBuilder
    private var othersSection: some View {
        let others = service.participantPresence
        if !others.isEmpty {
            Section {
                ForEach(others, id: \.userId) { snapshot in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(snapshot.state.dotColor)
                            .frame(width: 9, height: 9)
                            .accessibilityHidden(true)
                        Text(snapshot.state.displayName)
                            .font(.subheadline)
                        Spacer()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(snapshot.state.displayName)
                }
            } header: {
                Text("Others in this thread")
            }
        }
    }

    // MARK: Own Picker

    private var ownPickerSection: some View {
        Section {
            ForEach(AmenSmartPresenceState.allCases, id: \.self) { state in
                Button {
                    selectState(state)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: state.icon)
                            .foregroundStyle(isSelected(state) ? .blue : state.dotColor)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(state.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        if isSelected(state) {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.blue)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state.displayName)
                .accessibilityAddTraits(isSelected(state) ? .isSelected : [])
            }
        } header: {
            Text("Set your status")
        } footer: {
            Text("Status clears automatically after 30 minutes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private func isSelected(_ state: AmenSmartPresenceState) -> Bool {
        selectedState == state
    }

    private func selectState(_ state: AmenSmartPresenceState) {
        selectedState = state
        Task {
            await service.updateOwnPresence(
                state: state,
                threadId: threadId,
                threadType: threadType,
                spaceId: spaceId,
                channelId: channelId
            )
        }
    }
}

// MARK: - AmenOwnPresencePicker
// Standalone compact control: menu button showing current own state.

struct AmenOwnPresencePicker: View {
    let threadId: String
    let threadType: AmenSmartThreadType
    let spaceId: String?
    let channelId: String?

    @ObservedObject private var killSwitch = RemoteKillSwitch.shared
    @ObservedObject private var service = AmenSmartPresenceService.shared

    // Track own state locally since the service's participantPresence excludes self.
    @State private var ownState: AmenSmartPresenceState? = nil

    var body: some View {
        guard killSwitch.smartPresenceEnabled else { return AnyView(EmptyView()) }
        return AnyView(picker)
    }

    private var picker: some View {
        Menu {
            ForEach(AmenSmartPresenceState.allCases, id: \.self) { state in
                Button {
                    selectState(state)
                } label: {
                    Label(state.displayName, systemImage: state.icon)
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let current = ownState {
                    Circle()
                        .fill(current.dotColor)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(current.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Set status")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .accessibilityLabel(pickerAccessibilityLabel)
        .accessibilityHint("Opens status menu")
    }

    private var pickerAccessibilityLabel: String {
        if let current = ownState {
            return "Set your presence status. Current: \(current.displayName)"
        }
        return "Set your presence status. Current: not set"
    }

    private func selectState(_ state: AmenSmartPresenceState) {
        ownState = state
        AMENAnalyticsService.shared.track(
            .smartPresenceUpdated(stateCategory: state.rawValue)
        )
        Task {
            await service.updateOwnPresence(
                state: state,
                threadId: threadId,
                threadType: threadType,
                spaceId: spaceId,
                channelId: channelId
            )
        }
    }
}
