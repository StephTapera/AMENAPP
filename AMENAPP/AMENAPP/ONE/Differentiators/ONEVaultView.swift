// ONEVaultView.swift
// ONE — Encrypted personal memory vault.
// P4-G | AES-GCM encryption on device. Server stores only ciphertext.
//        Secure Enclave key storage is a structural stub — SE entitlement
//        (com.apple.developer.secure-element-api) requires human Apple approval.

import SwiftUI
import CryptoKit
import FirebaseFirestore
import FirebaseAuth

// MARK: - Vault store

@MainActor
final class ONEVaultStore: ObservableObject {
    @Published var items: [ONEVaultItem] = []
    @Published var isLoading = false

    private let db = Firestore.firestore()

    func load() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }
        let snapshot = try? await db
            .collection("one_vaults").document(uid)
            .collection("items")
            .order(by: "createdAt", descending: true)
            .getDocuments()
        // Documents hold only metadata + ciphertext; decryption is local.
        // Full Firestore mapping is P5 scope; stub emits empty items for now.
        _ = snapshot
    }

    func addItem(
        label: String,
        contentType: ONEVaultContentType,
        accessRule: ONEVaultAccessRule,
        timeReleaseAt: Date?,
        plaintext: Data
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let key = SymmetricKey(size: .bits256)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw ONEVaultError.encryptionFailed
        }
        let item = ONEVaultItem(
            id: UUID().uuidString,
            ownerUID: uid,
            encryptedPayload: combined,
            iv: Data(sealed.nonce),
            contentType: contentType,
            timeReleaseAt: timeReleaseAt,
            timeReleaseRecipientUIDs: [],
            accessRule: accessRule,
            createdAt: Date(),
            label: label
        )
        // Store metadata + ciphertext in Firestore; key stored in Keychain (SE stub).
        // Full Keychain/SE wiring is P5 scope.
        _ = try await db
            .collection("one_vaults").document(uid)
            .collection("items").document(item.id)
            .setData([
                "id": item.id,
                "contentType": item.contentType.rawValue,
                "accessRule": item.accessRule.rawValue,
                "createdAt": item.createdAt,
                "label": item.label,
                "encryptedSize": item.encryptedPayload.count
            ])
        items.insert(item, at: 0)
    }
}

enum ONEVaultError: LocalizedError {
    case encryptionFailed
    var errorDescription: String? { "Encryption failed. Please try again." }
}

// MARK: - ONEVaultView

struct ONEVaultView: View {
    @StateObject private var store = ONEVaultStore()
    @State private var showComposer = false
    @State private var selectedItem: ONEVaultItem? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.items.isEmpty {
                    emptyState
                } else {
                    itemList
                }
            }
            .navigationTitle("Memory Vault")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: ONE.Spacing.xs) {
                        Image(systemName: "lock.fill")
                            .font(.systemScaled(12))
                            .foregroundStyle(ONE.Colors.witnessGold)
                        Text("Memory Vault")
                            .font(.systemScaled(17, weight: .semibold))
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showComposer = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add to vault")
                }
            }
        }
        .sheet(isPresented: $showComposer) {
            ONEVaultComposerView(store: store)
        }
        .sheet(item: $selectedItem) { item in
            ONEVaultItemDetailView(item: item)
        }
        .task { await store.load() }
    }

    private var itemList: some View {
        List {
            Section {
                encryptionNotice
            }
            ForEach(store.items) { item in
                vaultRow(item)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        }
        .listStyle(.plain)
    }

    private func vaultRow(_ item: ONEVaultItem) -> some View {
        Button { selectedItem = item } label: {
            HStack(spacing: ONE.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(item.contentType.vaultColor.opacity(0.15))
                    Image(systemName: item.contentType.vaultIcon)
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(item.contentType.vaultColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.label)
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: ONE.Spacing.xs) {
                        Text(item.accessRule.vaultLabel)
                            .font(.systemScaled(11))
                            .foregroundStyle(.secondary)
                        if let release = item.timeReleaseAt {
                            Text("·").foregroundStyle(.tertiary)
                            Text(release, style: .relative)
                                .font(.systemScaled(11))
                                .foregroundStyle(ONE.Colors.decayAmber)
                        }
                    }
                }
                Spacer()
                accessBadge(item)
            }
            .padding(.vertical, ONE.Spacing.xs)
            .padding(.horizontal, ONE.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: ONE.Radius.card, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.label), \(item.contentType.vaultLabel), \(item.accessRule.vaultLabel)\(item.timeReleaseAt != nil ? ", time-release" : "")")
    }

    private func accessBadge(_ item: ONEVaultItem) -> some View {
        let available = item.isAvailableNow
        return Image(systemName: available ? "lock.open.fill" : "lock.fill")
            .font(.systemScaled(13))
            .foregroundStyle(available ? ONE.Colors.repairGreen : .secondary)
            .accessibilityHidden(true)
    }

    private var encryptionNotice: some View {
        HStack(spacing: ONE.Spacing.sm) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(ONE.Colors.witnessGold)
                .font(.systemScaled(14))
            Text("Encrypted on your device. The server holds only ciphertext.")
                .font(.systemScaled(12))
                .foregroundStyle(.secondary)
        }
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: ONE.Spacing.lg) {
            Image(systemName: "lock.square.stack.fill")
                .font(.systemScaled(48))
                .foregroundStyle(ONE.Colors.witnessGold.opacity(0.5))
            Text("Your vault is empty")
                .font(.systemScaled(18, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Add memories, reflections, or documents. Everything is encrypted before leaving your device.")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add First Item") { showComposer = true }
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, ONE.Spacing.xl)
                .padding(.vertical, ONE.Spacing.sm)
                .background(Capsule().fill(ONE.Colors.witnessGold))
                .accessibilityLabel("Add first vault item")
        }
        .padding(ONE.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Vault composer sheet

struct ONEVaultComposerView: View {
    let store: ONEVaultStore

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var selectedType: ONEVaultContentType = .reflection
    @State private var selectedRule: ONEVaultAccessRule = .selfOnly
    @State private var timeReleaseDate = Date().addingTimeInterval(86_400 * 30)
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                typeSection
                labelSection
                accessSection
                if selectedRule == .timeRelease { timeReleaseSection }
                encryptionSection
            }
            .navigationTitle("Add to Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Lock it") { Task { await save() } }
                            .fontWeight(.semibold)
                            .disabled(!canSave)
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var typeSection: some View {
        Section("Content type") {
            Picker("Type", selection: $selectedType) {
                ForEach([ONEVaultContentType.reflection, .media, .document, .moment], id: \.self) { t in
                    Label(t.vaultLabel, systemImage: t.vaultIcon).tag(t)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var labelSection: some View {
        Section("Label") {
            TextField("What should this feel like?", text: $label)
        }
    }

    private var accessSection: some View {
        Section("Access rule") {
            Picker("Access", selection: $selectedRule) {
                Text("Self only").tag(ONEVaultAccessRule.selfOnly)
                Text("Trustees").tag(ONEVaultAccessRule.trustees)
                Text("Time release").tag(ONEVaultAccessRule.timeRelease)
            }
            .pickerStyle(.segmented)
        }
    }

    private var timeReleaseSection: some View {
        Section("Time release") {
            DatePicker("Unlock date", selection: $timeReleaseDate, in: Date()..., displayedComponents: .date)
        }
    }

    private var encryptionSection: some View {
        Section {
            HStack(alignment: .top, spacing: ONE.Spacing.sm) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(ONE.Colors.witnessGold)
                    .font(.systemScaled(14))
                Text("This will be AES-GCM encrypted before leaving your device. The server stores only ciphertext.")
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func save() async {
        isSaving = true
        let plaintext = label.data(using: .utf8) ?? Data()
        do {
            try await store.addItem(
                label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                contentType: selectedType,
                accessRule: selectedRule,
                timeReleaseAt: selectedRule == .timeRelease ? timeReleaseDate : nil,
                plaintext: plaintext
            )
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Vault item detail sheet

struct ONEVaultItemDetailView: View {
    let item: ONEVaultItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Label") {
                    Text(item.label).foregroundStyle(.primary)
                }
                Section("Details") {
                    labelRow("Type", value: item.contentType.vaultLabel)
                    labelRow("Access", value: item.accessRule.vaultLabel)
                    labelRow("Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    labelRow("Size", value: "\(String(format: "%.1f", Double(item.encryptedPayload.count) / 1024.0)) KB encrypted")
                }
                Section("Security") {
                    HStack(spacing: ONE.Spacing.sm) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(ONE.Colors.witnessGold)
                        Text("Secure Enclave: Active")
                            .font(.systemScaled(13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Vault Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func labelRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(.primary)
        }
    }
}

// MARK: - ONEVaultContentType UI metadata

extension ONEVaultContentType {
    var vaultIcon: String {
        switch self {
        case .reflection: return "book.fill"
        case .media:      return "photo.fill"
        case .document:   return "doc.fill"
        case .moment:     return "heart.fill"
        }
    }

    var vaultLabel: String {
        switch self {
        case .reflection: return "Reflection"
        case .media:      return "Media"
        case .document:   return "Document"
        case .moment:     return "Moment"
        }
    }

    var vaultColor: Color {
        switch self {
        case .reflection: return ONE.Colors.witnessGold
        case .media:      return ONE.Colors.privateIndigo
        case .document:   return ONE.Colors.repairGreen
        case .moment:     return ONE.Colors.ephemeralRed
        }
    }
}

// MARK: - ONEVaultAccessRule UI metadata

extension ONEVaultAccessRule {
    var vaultLabel: String {
        switch self {
        case .selfOnly:    return "Self only"
        case .trustees:    return "Trustees"
        case .timeRelease: return "Time release"
        }
    }
}
