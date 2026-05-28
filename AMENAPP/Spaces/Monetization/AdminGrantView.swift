// AdminGrantView.swift
// AMENAPP — Spaces Monetization (Agent E)
//
// Admin UI for comping / granting entitlement to a member without payment.
// Caller MUST verify the current user is owner/admin before presenting.
//
// Usage:
//   AdminGrantView(spaceId: "abc123", targetUserId: "uid456", isPresented: $showGrant)
//
// On success: entitlement written server-side with source:"grant"; sheet dismisses.
// On error:   inline error text shown.
//
// The grant path is the ONLY way external/linked members receive paid access.
// Money never crosses a community Link in v1.

import SwiftUI
import FirebaseFunctions

// MARK: - Admin Grant View

struct AdminGrantView: View {

    let spaceId: String
    let targetUserId: String
    @Binding var isPresented: Bool

    // MARK: State

    @State private var isLifetime: Bool = true
    @State private var expirationDate: Date = Calendar.current.date(
        byAdding: .month, value: 1, to: Date()
    ) ?? Date()
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    private let functions = Functions.functions()

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                AmenTheme.Colors.backgroundGrouped.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        memberSection
                        accessDurationSection
                        if let message = errorMessage {
                            errorView(message: message)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Grant Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                        .accessibilityLabel("Cancel grant")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    confirmButton
                }
            }
        }
    }

    // MARK: - Member Section

    private var memberSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Member")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            HStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(targetUserId)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(1)

                    // Production TODO: fetch and display displayName from users/{userId}
                    Text("Member ID")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .fill(AmenTheme.Colors.backgroundGroupedRow)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Granting access to member \(targetUserId)")
    }

    // MARK: - Access Duration Section

    private var accessDurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Access Duration")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            Toggle(isOn: $isLifetime) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lifetime access")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text("No expiration date")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
            }
            .tint(AmenTheme.Colors.amenGold)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .fill(AmenTheme.Colors.backgroundGroupedRow)
            }
            .accessibilityLabel("Lifetime access")
            .accessibilityHint("Toggle to set or remove expiration date")

            if !isLifetime {
                DatePicker(
                    "Expires on",
                    selection: $expirationDate,
                    in: Date()...,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.compact)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                        .fill(AmenTheme.Colors.backgroundGroupedRow)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(Motion.liquidSpring, value: isLifetime)
                .accessibilityLabel("Expiration date picker")
                .accessibilityHint("Select when access expires")
            }
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.leading)
        }
        .accessibilityLabel("Error: \(message)")
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: - Confirm Button

    private var confirmButton: some View {
        Button {
            Task { await submitGrant() }
        } label: {
            if isLoading {
                ProgressView()
                    .tint(AmenTheme.Colors.amenGold)
            } else {
                Text("Grant")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
            }
        }
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? "Granting access, please wait" : "Confirm access grant")
        .accessibilityHint("Double-tap to confirm granting access")
    }

    // MARK: - Submit

    private func submitGrant() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var payload: [String: Any] = [
            "spaceId": spaceId,
            "targetUserId": targetUserId,
        ]

        if !isLifetime {
            // ISO 8601 string -- matches entitlementService.ts Timestamp.fromDate(new Date(expiresAt))
            let formatter = ISO8601DateFormatter()
            payload["expiresAt"] = formatter.string(from: expirationDate)
        }

        do {
            let result = try await functions
                .httpsCallable(SpacesCallable.grantAccess.rawValue)
                .call(payload)

            guard
                let data = result.data as? [String: Any],
                let success = data["success"] as? Bool,
                success
            else {
                errorMessage = "Unexpected server response. Please try again."
                return
            }

            isPresented = false

        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
