//
//  TrustedCircleView.swift
//  AMENAPP
//
//  Trusted Circle setup and management
//  Opt-in escalation that respects privacy
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseDatabase
import Combine

struct TrustedCircleView: View {
    @StateObject private var viewModel = TrustedCircleViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // MARK: Header
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.2.circle.fill")
                                .font(.systemScaled(32))
                                .foregroundStyle(.purple)

                            Text("Trusted Circle")
                                .font(AMENFont.bold(24))
                        }

                        Text("Add 1-5 people who can be notified if AMEN detects you might need support. You're always in control.")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)

                    // MARK: Enable Toggle Card
                    Text("SETTINGS")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        Toggle(isOn: $viewModel.isEnabled) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enable Trusted Circle")
                                    .font(AMENFont.semiBold(17))

                                Text("Allow AMEN to notify your trusted contacts")
                                    .font(AMENFont.regular(14))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(.purple)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    if viewModel.isEnabled {

                        // MARK: Notification Rule Section
                        Text("NOTIFICATION RULE")
                            .font(AMENFont.bold(11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ForEach(Array([
                                TrustedCircle.EscalationRule.askFirst,
                                TrustedCircle.EscalationRule.autoHigh,
                                TrustedCircle.EscalationRule.autoCritical,
                                TrustedCircle.EscalationRule.manual
                            ].enumerated()), id: \.offset) { index, rule in
                                EscalationRuleCard(
                                    rule: rule,
                                    isSelected: viewModel.escalationRule == rule,
                                    onSelect: { viewModel.escalationRule = rule }
                                )
                                if index < 3 {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                        .padding(.horizontal, 16)

                        // MARK: Trusted Contacts Section
                        HStack {
                            Text("TRUSTED CONTACTS")
                                .font(AMENFont.bold(11))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("\(viewModel.contacts.count)/50")
                                .font(AMENFont.regular(11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            if viewModel.contacts.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.systemScaled(48))
                                        .foregroundStyle(.secondary)

                                    Text("No contacts added yet")
                                        .font(AMENFont.regular(15))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            } else {
                                ForEach(Array(viewModel.contacts.enumerated()), id: \.element.id) { index, contact in
                                    TrustedContactRow(
                                        contact: contact,
                                        onDelete: { viewModel.removeContact(contact) }
                                    )
                                    if index < viewModel.contacts.count - 1 {
                                        Divider().padding(.leading, 16)
                                    }
                                }
                            }

                            if viewModel.contacts.count < 50 {
                                if !viewModel.contacts.isEmpty {
                                    Divider().padding(.leading, 16)
                                }
                                Button {
                                    viewModel.showAddContact = true
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.systemScaled(20))
                                        Text("Add Trusted Contact")
                                            .font(AMENFont.semiBold(16))
                                    }
                                    .foregroundStyle(.purple)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Divider().padding(.leading, 16)
                                Text("You've reached the maximum of 50 trusted contacts.")
                                    .font(AMENFont.regular(13))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                            }
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                        .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 32)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Trusted Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        Task { await viewModel.save() }
                        dismiss()
                    }
                    .font(AMENFont.semiBold(16))
                }
            }
            .sheet(isPresented: $viewModel.showAddContact) {
                AddTrustedContactSheet(onAdd: { contact in
                    viewModel.addContact(contact)
                })
            }
        }
        .task {
            await viewModel.load()
        }
    }
}

// MARK: - Escalation Rule Card

struct EscalationRuleCard: View {
    let rule: TrustedCircle.EscalationRule
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.systemScaled(20))
                    .foregroundStyle(isSelected ? .purple : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.displayName)
                        .font(AMENFont.semiBold(16))
                        .foregroundStyle(.primary)

                    Text(rule.description)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Trusted Contact Row

struct TrustedContactRow: View {
    let contact: TrustedCircle.TrustedContact
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.circle.fill")
                .font(.systemScaled(40))
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 4) {
                Text(contact.name)
                    .font(AMENFont.semiBold(16))

                Text(contact.relationship)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)

                if let phone = contact.phoneNumber {
                    Text(phone)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.systemScaled(16))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Add Trusted Contact Sheet

struct AddTrustedContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    // Manual entry fields
    @State private var name = ""
    @State private var relationship = ""
    @State private var phoneNumber = ""
    @State private var email = ""
    // Followers picker
    @State private var followers: [FollowerPickerUser] = []
    @State private var isLoadingFollowers = false
    @State private var followerSearch = ""

    let onAdd: (TrustedCircle.TrustedContact) -> Void

    /// Simple model for displaying a follower in the picker.
    struct FollowerPickerUser: Identifiable {
        let id: String
        let displayName: String
        let username: String
    }

    var canSave: Bool {
        !name.isEmpty && !relationship.isEmpty && (!phoneNumber.isEmpty || !email.isEmpty)
    }

    var filteredFollowers: [FollowerPickerUser] {
        if followerSearch.isEmpty { return followers }
        return followers.filter {
            $0.displayName.localizedCaseInsensitiveContains(followerSearch) ||
            $0.username.localizedCaseInsensitiveContains(followerSearch)
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    Picker("Add method", selection: $selectedTab) {
                        Text("From Followers").tag(0)
                        Text("Manual Entry").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if selectedTab == 0 {
                        followersPickerContent
                    } else {
                        manualEntryContent
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Add Trusted Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await loadFollowers()
            }
        }
    }

    @ViewBuilder
    private var followersPickerContent: some View {
        if isLoadingFollowers {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
        } else if followers.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.2.slash")
                    .font(.systemScaled(40))
                    .foregroundStyle(.secondary)
                Text("No followers to add")
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            VStack(spacing: 0) {
                // Search bar
                SearchBar(text: $followerSearch, placeholder: "Search followers")
                    .padding(.bottom, 4)

                Divider().padding(.leading, 16)

                ForEach(Array(filteredFollowers.enumerated()), id: \.element.id) { index, user in
                    Button {
                        let contact = TrustedCircle.TrustedContact(
                            id: UUID().uuidString,
                            userId: user.id,
                            name: user.displayName,
                            phoneNumber: nil,
                            email: nil,
                            relationship: "Follower",
                            addedAt: Date(),
                            isVerified: false
                        )
                        onAdd(contact)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.systemScaled(32))
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                    .font(AMENFont.semiBold(15))
                                    .foregroundStyle(.primary)
                                Text("@\(user.username)")
                                    .font(AMENFont.regular(13))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.purple)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    if index < filteredFollowers.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var manualEntryContent: some View {
        VStack(spacing: 0) {

            // MARK: Contact Info
            Text("CONTACT INFO")
                .font(AMENFont.bold(11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                TextField("Name", text: $name)
                    .font(AMENFont.regular(16))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                Divider().padding(.leading, 16)

                TextField("Relationship (Friend, Family, etc.)", text: $relationship)
                    .font(AMENFont.regular(16))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)

            // MARK: Contact Method
            Text("CONTACT METHOD")
                .font(AMENFont.bold(11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                TextField("Phone Number", text: $phoneNumber)
                    .font(AMENFont.regular(16))
                    .keyboardType(.phonePad)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                Divider().padding(.leading, 16)

                TextField("Email (optional)", text: $email)
                    .font(AMENFont.regular(16))
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)

            Text("Provide at least one way to reach this person")
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            // MARK: Submit
            Button("Add Contact") {
                let contact = TrustedCircle.TrustedContact(
                    id: UUID().uuidString,
                    userId: nil,
                    name: name,
                    phoneNumber: phoneNumber.isEmpty ? nil : phoneNumber,
                    email: email.isEmpty ? nil : email,
                    relationship: relationship,
                    addedAt: Date(),
                    isVerified: false
                )
                onAdd(contact)
                dismiss()
            }
            .disabled(!canSave)
            .font(AMENFont.semiBold(16))
            .foregroundStyle(canSave ? .purple : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)
            .padding(.top, 24)

            Spacer(minLength: 32)
        }
    }

    /// Load the current user's followers from RTDB + Firestore for the picker.
    /// Reads follower IDs from RTDB `user-followers/{userId}` then fetches display
    /// names from Firestore `users/{followerId}` (up to 50 followers).
    private func loadFollowers() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isLoadingFollowers = true
        defer { isLoadingFollowers = false }
        do {
            // 1. Get follower IDs from RTDB
            let rtdbRef = Database.database().reference()
                .child("user-followers").child(userId)
            let snapshot = try await rtdbRef.getData()
            guard snapshot.exists(), let dict = snapshot.value as? [String: Any] else { return }
            let followerIds = Array(dict.keys.prefix(50))

            // 2. Fetch display names from Firestore in parallel
            let db = Firestore.firestore()
            var result: [FollowerPickerUser] = []
            try await withThrowingTaskGroup(of: FollowerPickerUser?.self) { group in
                for fid in followerIds {
                    group.addTask {
                        let doc = try await db.collection("users").document(fid).getDocument()
                        guard let data = doc.data(),
                              let displayName = data["displayName"] as? String else { return nil }
                        let username = data["username"] as? String ?? displayName.lowercased()
                        return FollowerPickerUser(id: fid, displayName: displayName, username: username)
                    }
                }
                for try await user in group {
                    if let user = user { result.append(user) }
                }
            }
            followers = result.sorted { $0.displayName < $1.displayName }
        } catch {
            dlog("⚠️ TrustedCircle: failed to load followers: \(error.localizedDescription)")
        }
    }
}

// Lightweight inline search bar used in TrustedCircle followers picker
private struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - View Model

@MainActor
class TrustedCircleViewModel: ObservableObject {
    @Published var isEnabled = false
    @Published var escalationRule: TrustedCircle.EscalationRule = .askFirst
    @Published var contacts: [TrustedCircle.TrustedContact] = []
    @Published var showAddContact = false

    private let service = EnhancedCrisisSupportService.shared
    private var circle: TrustedCircle?

    func load() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        do {
            if let existingCircle = try await service.loadTrustedCircle(userId: userId) {
                circle = existingCircle
                isEnabled = existingCircle.isEnabled
                escalationRule = existingCircle.escalationRule
                contacts = existingCircle.contacts
            }
        } catch {
            dlog("⚠️ Failed to load trusted circle: \(error)")
        }
    }

    func save() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let updatedCircle = TrustedCircle(
            userId: userId,
            contacts: contacts,
            escalationRule: escalationRule,
            isEnabled: isEnabled,
            createdAt: circle?.createdAt ?? Date(),
            updatedAt: Date()
        )

        do {
            try await service.saveTrustedCircle(updatedCircle)
            dlog("✅ Trusted circle saved")
        } catch {
            dlog("⚠️ Failed to save trusted circle: \(error)")
        }
    }

    func addContact(_ contact: TrustedCircle.TrustedContact) {
        contacts.append(contact)
    }

    func removeContact(_ contact: TrustedCircle.TrustedContact) {
        contacts.removeAll { $0.id == contact.id }
    }
}

// MARK: - Preview

#Preview {
    TrustedCircleView()
}
