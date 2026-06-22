//
//  AmenProfileFieldPrivacySection.swift
//  AMENAPP — CommunityOS/Privacy
//
//  Trust & Safety Remediation item 21 follow-on — per-field profile visibility.
//
//  A drop-in settings Section letting the user individually show/hide their
//  email, phone, and birthday on their profile. Backed by
//  PrivacySettings.customOverrides (no Codable migration).
//
//  POSTURE:
//    - Gated by AMENFeatureFlags.profileFieldPrivacyEnabled — renders NOTHING when
//      OFF (zero regression).
//    - Fields default to HIDDEN. [MINOR] Toggles are disabled and forced hidden
//      for minor accounts.
//
//  Usage (inside a Form/List):
//      AmenProfileFieldPrivacySection(userId: currentUserId)
//

import SwiftUI

struct AmenProfileFieldPrivacySection: View {
    let userId: String

    @ObservedObject private var engine = AmenPrivacyEngine.shared
    @ObservedObject private var flags = AMENFeatureFlags.shared
    @State private var working: Set<String> = []

    private var isMinor: Bool { engine.settings?.isMinor ?? true }

    var body: some View {
        if flags.profileFieldPrivacyEnabled {
            Section {
                ForEach(ProfileContactField.allCases) { field in
                    Toggle(isOn: binding(for: field)) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(field.displayName)
                                Text(field.privacyHint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } icon: {
                            Image(systemName: field.systemImage)
                        }
                    }
                    .disabled(isMinor || working.contains(field.overrideKey))
                }
            } header: {
                Text("Profile Fields")
            } footer: {
                if isMinor {
                    Text("For your safety, contact details are always hidden on younger accounts.")
                } else {
                    Text("Choose which contact details appear on your profile. Hidden by default.")
                }
            }
            .task {
                if engine.settings?.userId != userId {
                    try? await engine.loadSettings(for: userId)
                }
            }
        }
    }

    private func binding(for field: ProfileContactField) -> Binding<Bool> {
        Binding(
            get: { engine.settings?.showsProfileField(field) ?? false },
            set: { newValue in
                Task {
                    working.insert(field.overrideKey)
                    defer { working.remove(field.overrideKey) }
                    try? await engine.setProfileField(field, visible: newValue, for: userId)
                }
            }
        )
    }
}
