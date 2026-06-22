// SmartPresenceLayer.swift
// AMENAPP
//
// Privacy-safe presence pills for the chat header.
// Shows approximate status only — no exact behavioral surveillance.
// Gated by smartPresenceEnabled.

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class SmartPresenceService: ObservableObject {
    static let shared = SmartPresenceService()

    @Published var ownStatus: SmartPresenceStatus = .activeNow
    @Published var isFocusMode: Bool = false
    @Published var isQuietMode: Bool = false

    private var presenceListener: ListenerRegistration?

    func setOwnStatus(_ status: SmartPresenceStatus) {
        guard AMENFeatureFlags.shared.smartPresenceEnabled else { return }
        ownStatus = status
        if status == .focusMode { isFocusMode = true; isQuietMode = false }
        else if status == .quietMode { isQuietMode = true; isFocusMode = false }
        else { isFocusMode = false; isQuietMode = false }
        AmenMessagingAnalytics.track(.presenceStatusChanged, parameters: ["status": status.rawValue])
        if status == .focusMode { AmenMessagingAnalytics.track(.focusModeEnabled) }
        if status == .quietMode { AmenMessagingAnalytics.track(.quietModeEnabled) }
        persistOwnStatus(status)
    }

    private func persistOwnStatus(_ status: SmartPresenceStatus) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        Task {
            try? await db.collection("users").document(uid)
                .collection("presence").document("main")
                .setData([
                    "status": status.rawValue,
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
        }
    }

    func observePresence(for uid: String, onChange: @escaping (SmartPresenceStatus) -> Void) {
        presenceListener?.remove()
        guard AMENFeatureFlags.shared.smartPresenceEnabled else { return }
        let db = Firestore.firestore()
        presenceListener = db.collection("users").document(uid)
            .collection("presence").document("main")
            .addSnapshotListener { snapshot, _ in
                guard let data = snapshot?.data(),
                      let raw = data["status"] as? String,
                      let status = SmartPresenceStatus(rawValue: raw) else { return }
                Task { @MainActor in onChange(status) }
            }
    }

    func stopObserving() {
        presenceListener?.remove()
        presenceListener = nil
    }
}

// MARK: - Presence Pill View

struct SmartPresencePill: View {
    let status: SmartPresenceStatus

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(status.rawValue)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(pillBackground, in: Capsule())
        .accessibilityLabel("Presence: \(status.rawValue)")
    }

    private var dotColor: Color {
        switch status {
        case .activeNow:      return .green
        case .recentlyActive: return .yellow
        case .focusMode:      return .blue
        case .quietMode:      return .purple
        case .mayReplyLater:  return .orange
        case .mobile:         return .teal
        }
    }

    private var pillBackground: some ShapeStyle {
        if reduceTransparency { return AnyShapeStyle(Color(.tertiarySystemBackground)) }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}

// MARK: - Presence Mode Picker Sheet

struct PresenceModePickerSheet: View {
    @ObservedObject var presenceService = SmartPresenceService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SmartPresenceStatus.allCases, id: \.self) { status in
                        Button {
                            presenceService.setOwnStatus(status)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: status.icon)
                                    .foregroundStyle(status == presenceService.ownStatus ? .blue : .primary)
                                    .frame(width: 28)
                                Text(status.rawValue)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if status == presenceService.ownStatus {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                        .font(.caption.weight(.bold))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Your Status")
                } footer: {
                    Text("Your status is approximate. Others see a safe label — not exact activity.")
                        .font(.caption)
                }
            }
            .navigationTitle("Set Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
