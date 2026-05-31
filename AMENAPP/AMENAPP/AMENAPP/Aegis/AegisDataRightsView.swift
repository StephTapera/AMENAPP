// AegisDataRightsView.swift
// Aegis — Data Rights (C51–C58)
// Covers: noSellGuarantee, trackingMinimization, shadowProfilePrevention,
//         crossPlatformLinking, trueRightToBeForgotten, reverseImageTraceability,
//         digitalLegacy, dataPortability

import SwiftUI
import FirebaseAuth

// MARK: - ViewModel

@MainActor
final class AegisDataRightsViewModel: ObservableObject {
    @Published var summary: AegisDataRightsSummary? = nil
    @Published var isLoadingExport = false
    @Published var isLoadingDelete = false
    @Published var showDeleteConfirm = false
    @Published var exportUrl: URL? = nil
    @Published var deletionManifest: AegisDeletionManifest? = nil
    @Published var error: String? = nil
    @Published var legacyContactUID: String = ""
    @Published var showLegacyContactEntry = false

    private var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    func loadSummary() async {
        let uid = currentUserId
        guard !uid.isEmpty else { return }
        do {
            let result = try await AegisDataRightsService.shared.getDataRightsSummary(userId: uid)
            summary = result
        } catch {
            self.error = error.localizedDescription
        }
    }

    func requestExport() async {
        let uid = currentUserId
        guard !uid.isEmpty else { return }
        isLoadingExport = true
        error = nil
        do {
            let url = try await AegisDataRightsService.shared.requestDataExport(userId: uid)
            exportUrl = url
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingExport = false
    }

    func requestDeletion() async {
        let uid = currentUserId
        guard !uid.isEmpty else { return }
        isLoadingDelete = true
        error = nil
        do {
            let manifest = try await AegisDataRightsService.shared.requestTrueDeletion(userId: uid)
            deletionManifest = manifest
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingDelete = false
    }
}

// MARK: - View

struct AegisDataRightsView: View {
    @StateObject private var vm = AegisDataRightsViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let flags = AegisFeatureFlags.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ourPromiseCard
                    yourDataCard
                    trackingDisclosureCard
                    if flags.isEnabled(.digitalLegacy) { digitalLegacyCard }
                    if flags.isEnabled(.reverseImageTraceability) { reverseImageCard }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Your Data")
            .navigationBarTitleDisplayMode(.large)
            .task { await vm.loadSummary() }
            .confirmationDialog(
                "Delete My Account and Data",
                isPresented: $vm.showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {
                    Task { await vm.requestDeletion() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deletionWarningText)
            }
            .alert("Error", isPresented: Binding(
                get: { vm.error != nil },
                set: { _ in vm.error = nil }
            )) {
                Button("OK", role: .cancel) { vm.error = nil }
            } message: {
                Text(vm.error ?? "")
            }
        }
    }

    // MARK: - Our Promise Card (C51/C52/C53/C54)

    private var ourPromiseCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                cardHeader(icon: "hand.raised.fill", title: "Our Promise", color: .amenGold)

                Text("AMEN will never sell your data. We collect only what's needed to serve you. We do not build profiles of people who haven't joined AMEN.")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if flags.isEnabled(.crossPlatformLinking) {
                    Divider()
                    HStack(spacing: 10) {
                        Image(systemName: "link.badge.plus")
                            .foregroundStyle(Color.amenBlue)
                            .accessibilityHidden(true)
                        Text("We don't link your identity across platforms.")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - Your Data Card (C58 export + C55 deletion)

    private var yourDataCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 16) {
                cardHeader(icon: "externaldrive.fill", title: "Your Data", color: .amenBlue)

                // Export (C58)
                if flags.isEnabled(.dataPortability) {
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            Task { await vm.requestExport() }
                        } label: {
                            HStack(spacing: 10) {
                                if vm.isLoadingExport {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "square.and.arrow.down")
                                        .foregroundStyle(Color.amenBlue)
                                        .accessibilityHidden(true)
                                }
                                Text("Download your data")
                                    .font(AMENFont.semiBold(15))
                                    .foregroundStyle(Color.amenBlue)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .disabled(vm.isLoadingExport)
                        .accessibilityLabel(vm.isLoadingExport ? "Preparing your data export" : "Download your data")

                        if let url = vm.exportUrl {
                            Link("Open Export", destination: url)
                                .font(AMENFont.regular(13))
                                .foregroundStyle(Color.amenGold)
                                .accessibilityLabel("Open your data export")
                        }
                    }
                } else {
                    comingSoonRow(label: "Download your data", capability: .dataPortability)
                }

                Divider()

                // Deletion (C55)
                if flags.isEnabled(.trueRightToBeForgotten) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.8)) {
                                vm.showDeleteConfirm = true
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if vm.isLoadingDelete {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "trash.fill")
                                        .foregroundStyle(Color.red)
                                        .accessibilityHidden(true)
                                }
                                Text("Delete my account and data")
                                    .font(AMENFont.semiBold(15))
                                    .foregroundStyle(Color.red)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .disabled(vm.isLoadingDelete)
                        .accessibilityLabel(vm.isLoadingDelete ? "Processing account deletion" : "Delete my account and data — destructive, cannot be undone")

                        if let manifest = vm.deletionManifest {
                            deletionManifestSummary(manifest)
                        }
                    }
                } else {
                    comingSoonRow(label: "Delete my account and data", capability: .trueRightToBeForgotten)
                }
            }
        }
    }

    @ViewBuilder
    private func deletionManifestSummary(_ manifest: AegisDeletionManifest) -> some View {
        let totalPaths = manifest.firestorePaths.count
            + manifest.storagePaths.count
            + manifest.pineconeNamespaces.count
            + manifest.derivedDataPaths.count

        VStack(alignment: .leading, spacing: 4) {
            Label(
                manifest.isComplete ? "Deletion complete." : "Deletion in progress…",
                systemImage: manifest.isComplete ? "checkmark.circle.fill" : "clock.fill"
            )
            .font(AMENFont.semiBold(13))
            .foregroundStyle(manifest.isComplete ? Color.green : Color.amenGold)

            Text("\(totalPaths) data paths queued for removal.")
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemFill))
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tracking Disclosure Card (C52)

    private var trackingDisclosureCard: some View {
        glassCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What we collect:")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    ForEach(["Posts and reactions", "Church activity", "Prayer interactions"], id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle.fill")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.primary)
                    }

                    Text("What we do NOT collect:")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    ForEach(
                        ["Location (unless you share)", "Contacts", "Browsing history outside AMEN"],
                        id: \.self
                    ) { item in
                        Label(item, systemImage: "xmark.circle.fill")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(Color.red.opacity(0.8))
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "eye.slash.fill")
                        .foregroundStyle(Color.amenPurple)
                        .accessibilityHidden(true)
                    Text("What we collect")
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.primary)
                }
            }
            .tint(Color.amenPurple)
        }
    }

    // MARK: - Digital Legacy Card (C57)

    private var digitalLegacyCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                cardHeader(icon: "heart.text.square.fill", title: "Digital Legacy", color: .amenGold)

                Button {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.8)) {
                        vm.showLegacyContactEntry.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .foregroundStyle(Color.amenGold)
                            .accessibilityHidden(true)
                        Text("Set a Legacy Contact")
                            .font(AMENFont.semiBold(15))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("Set a Legacy Contact for your account")

                if vm.showLegacyContactEntry {
                    TextField("Enter user ID or username", text: $vm.legacyContactUID)
                        .font(AMENFont.regular(14))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Legacy contact username or user ID")
                }

                Divider()

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "moon.stars.fill")
                        .foregroundStyle(Color.amenPurple)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Memorialize my account")
                            .font(AMENFont.semiBold(14))
                            .foregroundStyle(.primary)
                        Text("Your legacy contact can request memorialization after your passing.")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Reverse Image Card (C56)

    private var reverseImageCard: some View {
        glassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "photo.badge.magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.amenBlue)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Profile Photo Traceability")
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.primary)
                    Text("Your profile photo may be searchable via reverse image tools. Consider using a photo that isn't widely indexed.")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Helpers

    private var deletionWarningText: String {
        "This permanently deletes your posts, messages, notes, prayer requests, and all AI-derived data including search indexes. This cannot be undone."
    }

    @ViewBuilder
    private func cardHeader(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(title)
                .font(AMENFont.semiBold(15))
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func comingSoonRow(label: String, capability: AegisCapability) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
            Spacer()
            Text("Coming soon")
                .font(AMENFont.regular(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(.systemFill))
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label). Coming soon.")
    }

    @ViewBuilder
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}

#if DEBUG
#Preview {
    AegisDataRightsView()
}
#endif
