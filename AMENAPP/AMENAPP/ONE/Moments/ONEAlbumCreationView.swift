// ONEAlbumCreationView.swift
// ONE — Collaborative album creation sheet.
// P2-H | Uses PhotosPicker for multi-image selection. Collaborator invite is a stub.

import SwiftUI
import PhotosUI

struct ONEAlbumCreationView: View {
    var onCreate: ([PhotosPickerItem], String, ONEPrivacyContract) -> Void = { _, _, _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var contract = ONEPrivacyContract(
        audience: .closeFriends,
        lifetime: .permanent,
        permissions: ONEMomentPermissions(
            forwardAllowed: false, saveAllowed: true, quoteAllowed: false,
            reactAllowed: true, translateAllowed: true,
            summarizeAllowed: false, aiTrainingAllowed: false
        ),
        safety: .init(), metricsPrivate: true, reshareAllowed: false
    )
    @State private var showPrivacyOverride = false
    @State private var selectedAudience: ONEAudienceScope = .closeFriends

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selectedItems.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                photosSection
                titleSection
                privacySection
            }
            .navigationTitle("New Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(selectedItems, title.trimmingCharacters(in: .whitespacesAndNewlines), contract)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canCreate)
                }
            }
        }
        .sheet(isPresented: $showPrivacyOverride) { privacyOverrideSheet }
    }

    // MARK: - Sections

    private var photosSection: some View {
        Section {
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 50,
                matching: .images
            ) {
                HStack {
                    Image(systemName: "photo.badge.plus")
                        .foregroundStyle(ONE.Colors.privateIndigo)
                    Text(selectedItems.isEmpty ? "Add Photos" : "\(selectedItems.count) photos selected")
                        .foregroundStyle(selectedItems.isEmpty ? .secondary : .primary)
                    Spacer()
                    if !selectedItems.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ONE.Colors.repairGreen)
                    }
                }
            }
            .accessibilityLabel(selectedItems.isEmpty ? "Add photos to album" : "\(selectedItems.count) photos selected, tap to change")
        } header: {
            Text("Photos")
        } footer: {
            Text("Up to 50 photos. All members can add more after creation.")
                .font(.caption)
        }
    }

    private var titleSection: some View {
        Section("Album Title") {
            TextField("Give your album a name", text: $title)
                .accessibilityLabel("Album title")
        }
    }

    private var privacySection: some View {
        Section {
            Button { showPrivacyOverride = true } label: {
                HStack(spacing: ONE.Spacing.sm) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(ONE.Colors.privateIndigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contract.audience.displayLabel)
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("\(contract.lifetime.displayLabel) · \(contract.permissions.saveAllowed ? "Saving allowed" : "No saving")")
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.systemScaled(12))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Privacy: \(contract.audience.displayLabel), \(contract.lifetime.displayLabel). Tap to change.")
        } header: {
            Text("Privacy")
        } footer: {
            Text("Everyone invited will see the privacy settings before joining the album.")
                .font(.caption)
        }
    }

    // MARK: - Privacy override sheet

    private var privacyOverrideSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ONE.Spacing.lg) {
                VStack(alignment: .leading, spacing: ONE.Spacing.sm) {
                    Text("Who can see this album?")
                        .font(.systemScaled(17, weight: .semibold))
                    audienceChipRow
                }

                VStack(alignment: .leading, spacing: ONE.Spacing.sm) {
                    Text("Can members save photos?")
                        .font(.systemScaled(17, weight: .semibold))
                    Toggle("Allow saving", isOn: Binding(
                        get: { contract.permissions.saveAllowed },
                        set: { contract.permissions.saveAllowed = $0 }
                    ))
                    .tint(ONE.Colors.repairGreen)
                }
                Spacer()
            }
            .padding(ONE.Spacing.lg)
            .navigationTitle("Album Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showPrivacyOverride = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var audienceChipRow: some View {
        HStack(spacing: ONE.Spacing.sm) {
            ForEach([ONEAudienceScope.selfOnly, .closeFriends, .witnesses], id: \.kind) { scope in
                let isSelected = contract.audience.kind == scope.kind
                Button {
                    contract = ONEPrivacyContract(
                        audience: scope,
                        lifetime: contract.lifetime,
                        permissions: contract.permissions,
                        safety: contract.safety,
                        metricsPrivate: contract.metricsPrivate,
                        reshareAllowed: contract.reshareAllowed
                    )
                } label: {
                    Text(scope.displayLabel)
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(isSelected ? ONE.Colors.privateIndigo : .secondary)
                        .padding(.horizontal, ONE.Spacing.md)
                        .padding(.vertical, ONE.Spacing.sm)
                        .background(
                            Capsule()
                                .fill(isSelected ? ONE.Colors.privateIndigo.opacity(0.12) : Color.primary.opacity(0.06))
                                .stroke(isSelected ? ONE.Colors.privateIndigo.opacity(0.30) : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(scope.displayLabel)\(isSelected ? ", selected" : "")")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}
