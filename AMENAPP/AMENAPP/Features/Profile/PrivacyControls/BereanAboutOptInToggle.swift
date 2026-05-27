// BereanAboutOptInToggle.swift
// AMEN App — Profile settings toggle for the Berean "About This Person" opt-in.
//
// Shows a disclosure sheet the FIRST time the user enables the feature, then
// commits immediately on subsequent toggles.  State is persisted in UserDefaults.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Constants

private enum BereanOptInDefaults {
    static let disclosureSeenKey = "profile.v2.bereanAboutDisclosureSeen"
}

// MARK: - Toggle View

public struct BereanAboutOptInToggle: View {
    @Binding public var isOptedIn: Bool
    public let onToggle: (Bool) async throws -> Void

    @State private var showDisclosure = false
    @State private var isSaving = false
    @State private var saveError: String? = nil
    /// Tracks the value the toggle is *attempting* to move to so we can
    /// revert it if the user cancels the disclosure sheet.
    @State private var pendingValue: Bool? = nil

    public init(isOptedIn: Binding<Bool>, onToggle: @escaping (Bool) async throws -> Void) {
        self._isOptedIn = isOptedIn
        self.onToggle = onToggle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Allow Berean conversations about me")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text("Visitors can ask Berean about your faith journey")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    Toggle("", isOn: toggleBinding)
                        .labelsHidden()
                        .disabled(isSaving)
                        .tint(Color("amenGold", bundle: .main))
                        .accessibilityLabel("Allow Berean conversations about me")
                        .accessibilityHint(
                            isOptedIn
                                ? "Currently enabled. Toggle to disable."
                                : "Currently disabled. Toggle to enable and see disclosure."
                        )

                    if isSaving {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.75)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )

            if let error = saveError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: saveError)
        .sheet(isPresented: $showDisclosure) {
            disclosureSheet
        }
    }

    // MARK: - Toggle binding

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { isOptedIn },
            set: { newValue in
                guard newValue != isOptedIn else { return }
                if newValue {
                    let alreadySeen = UserDefaults.standard.bool(forKey: BereanOptInDefaults.disclosureSeenKey)
                    if alreadySeen {
                        commitToggle(newValue)
                    } else {
                        // Hold the toggle visually in the ON position while disclosure is shown
                        isOptedIn = true
                        pendingValue = true
                        showDisclosure = true
                    }
                } else {
                    commitToggle(newValue)
                }
            }
        )
    }

    // MARK: - Disclosure sheet

    private var disclosureSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Label("About Berean Conversations", systemImage: "person.text.rectangle")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("When enabled, visitors to your profile can ask Berean questions about you. Here's exactly what Berean can and cannot access.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Included section
                    DisclosureSection(
                        title: "What's included",
                        icon: "checkmark.circle.fill",
                        iconColor: .green,
                        items: [
                            "Your public testimony and bio",
                            "Your pinned posts (public only)",
                            "Your last 10 public posts",
                            "Your role (creator, mentor, ministry leader)",
                            "Your church name and city (if set)",
                        ]
                    )

                    // Excluded section
                    DisclosureSection(
                        title: "What's never included",
                        icon: "xmark.circle.fill",
                        iconColor: .red,
                        items: [
                            "Direct messages or private conversations",
                            "Private prayer requests",
                            "Posts marked as private or followers-only",
                            "Your email, phone, or sensitive account data",
                            "Any content you haven't made public",
                        ]
                    )

                    // Footer note
                    Text("You can turn this off at any time from your profile settings.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .background(.ultraThinMaterial)
            .navigationTitle("Berean About Me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        // User cancelled — revert the optimistic toggle-ON
                        isOptedIn = false
                        pendingValue = nil
                        showDisclosure = false
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        UserDefaults.standard.set(true, forKey: BereanOptInDefaults.disclosureSeenKey)
                        showDisclosure = false
                        commitToggle(true)
                    } label: {
                        Text("I understand, enable")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color("amenGold", bundle: .main), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .accessibilityLabel("I understand, enable Berean conversations about me")

                    Button {
                        isOptedIn = false
                        pendingValue = nil
                        showDisclosure = false
                    } label: {
                        Text("Cancel")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Cancel, do not enable Berean conversations")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(24)
    }

    // MARK: - Helpers

    private func commitToggle(_ newValue: Bool) {
        isSaving = true
        saveError = nil
        Task {
            do {
                try await onToggle(newValue)
                await MainActor.run {
                    isOptedIn = newValue
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    // Revert to prior value on failure
                    isOptedIn = !newValue
                    isSaving = false
                    saveError = "Couldn't save. Please try again."
                }
            }
        }
    }
}

// MARK: - Disclosure section helper

private struct DisclosureSection: View {
    let title: String
    let icon: String
    let iconColor: Color
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(iconColor.opacity(0.7))
                            .padding(.top, 2)
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(14)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
    }
}

// MARK: - Default onToggle implementation (for use by the profile settings host)
// This extension makes it easy for the host view to wire up the Firestore write
// without duplicating the logic.

public extension BereanAboutOptInToggle {
    /// Convenience factory that bakes in the standard Firestore persistence logic.
    static func withFirestorePersistence(isOptedIn: Binding<Bool>) -> BereanAboutOptInToggle {
        BereanAboutOptInToggle(isOptedIn: isOptedIn) { newValue in
            let db = Firestore.firestore()
            guard let uid = Auth.auth().currentUser?.uid else {
                throw URLError(.userAuthenticationRequired)
            }
            try await db.collection("users").document(uid).updateData([
                "profile.bereanAboutOptIn": newValue,
            ])
        }
    }
}
