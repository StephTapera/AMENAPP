// ChildSafetyControlsView.swift
// AMENAPP
//
// Wave 6 — guardian-facing child-safety controls. Teen-safe defaults are ON.
// Honest about the §6 human gate: NCMEC filing is handled by the safety team
// after registration; this surface escalates internally, it does not file.
//
// Gated by AMENFeatureFlags.shared.childSafetySurfaceEnabled (default OFF).

import SwiftUI

struct ChildSafetyControlsView: View {
    @StateObject private var controller = ChildSafetyController()

    var body: some View {
        List {
            Section {
                Toggle(isOn: $controller.dmAdultsBlocked) {
                    Label("Block DMs from adults", systemImage: "envelope.badge.shield.half.filled")
                }
                .tint(.blue)
                Toggle(isOn: $controller.slowFeed) {
                    Label("Slower, calmer feed", systemImage: "tortoise")
                }
                .tint(.blue)
                Toggle(isOn: $controller.guardianCategoriesOnly) {
                    Label("Guardian sees categories only", systemImage: "eye.trianglebadge.exclamationmark")
                }
                .tint(.blue)
            } header: {
                Text("Teen-safe defaults")
            } footer: {
                Text("These are on by default for younger accounts. Guardians see categories of activity, never private message content.")
            }

            Section {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                    Text("Grooming signals are held for human review automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Protection")
            }

            Section {
                Text("To report child sexual abuse material, contact the in-app safety team — it is escalated immediately for human review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Reporting CSAM")
            } footer: {
                Text("Formal reporting to NCMEC requires legal registration handled by the AMEN safety team. This app escalates internally; it does not file reports directly.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Child Safety")
    }
}

#if DEBUG
#Preview("Child safety") {
    NavigationStack { ChildSafetyControlsView() }
}
#endif
