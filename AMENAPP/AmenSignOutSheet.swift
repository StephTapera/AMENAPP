// AmenSignOutSheet.swift
// AMENAPP
//
// Liquid Glass sign-out confirmation sheet.
// Three options: Sign Out (keep hint) / Sign Out and Remove / Cancel.
// Presented from SettingsView as a .sheet so it respects system appearance.

import SwiftUI
import FirebaseAnalytics

struct AmenSignOutSheet: View {
    let displayName: String
    let onSignOut: () -> Void
    let onSignOutAndRemove: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 20)

            // Title
            VStack(spacing: 6) {
                Text("Sign out of Amen?")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text("You can continue as \(firstName) next time unless you remove this account from this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer().frame(height: 28)

            // Action buttons
            VStack(spacing: 10) {
                // Sign Out (keep hint)
                Button {
                    Analytics.logEvent("sign_out_confirmed", parameters: ["removed_from_device": "false"])
                    dismiss()
                    onSignOut()
                } label: {
                    Text("Sign Out")
                        .font(.body.bold())
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            Capsule().fill(
                                reduceTransparency
                                    ? Color(.secondarySystemBackground)
                                    : .regularMaterial
                            )
                        )
                }

                // Sign Out and Remove
                Button {
                    Analytics.logEvent("sign_out_removed_from_device", parameters: nil)
                    dismiss()
                    onSignOutAndRemove()
                } label: {
                    Text("Sign Out and Remove From This Device")
                        .font(.body)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            Capsule().fill(
                                reduceTransparency
                                    ? Color(.secondarySystemBackground)
                                    : .regularMaterial
                            )
                        )
                }

                // Cancel
                Button {
                    Analytics.logEvent("sign_out_cancelled", parameters: nil)
                    dismiss()
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
            }
            .padding(.horizontal, 20)

            Spacer().frame(height: 20)
        }
        .background(Color(.systemBackground))
        .presentationDetents([.height(310)])
        .presentationDragIndicator(.hidden)
        .onAppear {
            Analytics.logEvent("sign_out_sheet_shown", parameters: nil)
        }
    }
}
