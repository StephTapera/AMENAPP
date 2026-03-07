//
//  TrustedCircleView.swift
//  AMENAPP
//
//  Trusted Circle setup and management
//  Opt-in escalation that respects privacy
//

import SwiftUI
import FirebaseAuth
import Combine

struct TrustedCircleView: View {
    @StateObject private var viewModel = TrustedCircleViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header explanation
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.2.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.purple)
                            
                            Text("Trusted Circle")
                                .font(.custom("OpenSans-Bold", size: 24))
                        }
                        
                        Text("Add 1-5 people who can be notified if AMEN detects you might need support. You're always in control.")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    
                    // Enable toggle
                    Toggle(isOn: $viewModel.isEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Trusted Circle")
                                .font(.custom("OpenSans-SemiBold", size: 17))
                            
                            Text("Allow AMEN to notify your trusted contacts")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.purple)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    
                    if viewModel.isEnabled {
                        // Escalation rule
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Notification Rule")
                                .font(.custom("OpenSans-SemiBold", size: 17))
                                .padding(.horizontal, 20)
                            
                            ForEach([
                                TrustedCircle.EscalationRule.askFirst,
                                TrustedCircle.EscalationRule.autoHigh,
                                TrustedCircle.EscalationRule.autoCritical,
                                TrustedCircle.EscalationRule.manual
                            ], id: \.self) { rule in
                                EscalationRuleCard(
                                    rule: rule,
                                    isSelected: viewModel.escalationRule == rule,
                                    onSelect: {
                                        viewModel.escalationRule = rule
                                    }
                                )
                            }
                        }
                        
                        Divider()
                            .padding(.horizontal, 20)
                        
                        // Trusted contacts
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Trusted Contacts")
                                    .font(.custom("OpenSans-SemiBold", size: 17))
                                
                                Spacer()
                                
                                Text("\(viewModel.contacts.count)/5")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 20)
                            
                            if viewModel.contacts.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.secondary)
                                    
                                    Text("No contacts added yet")
                                        .font(.custom("OpenSans-Regular", size: 15))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            } else {
                                ForEach(viewModel.contacts) { contact in
                                    TrustedContactRow(
                                        contact: contact,
                                        onDelete: {
                                            viewModel.removeContact(contact)
                                        }
                                    )
                                }
                            }
                            
                            if viewModel.contacts.count < 5 {
                                Button {
                                    viewModel.showAddContact = true
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 20))
                                        
                                        Text("Add Trusted Contact")
                                            .font(.custom("OpenSans-SemiBold", size: 16))
                                    }
                                    .foregroundStyle(.purple)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color(.tertiarySystemBackground))
                                    .cornerRadius(12)
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                }
                .padding(.vertical, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Trusted Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        Task {
                            await viewModel.save()
                        }
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
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
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .purple : .secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.displayName)
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Text(rule.description)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.purple.opacity(0.1) : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}

// MARK: - Trusted Contact Row

struct TrustedContactRow: View {
    let contact: TrustedCircle.TrustedContact
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.purple)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(contact.name)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                
                Text(contact.relationship)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                
                if let phone = contact.phoneNumber {
                    Text(phone)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal, 20)
    }
}

// MARK: - Add Trusted Contact Sheet

struct AddTrustedContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var relationship = ""
    @State private var phoneNumber = ""
    @State private var email = ""
    
    let onAdd: (TrustedCircle.TrustedContact) -> Void
    
    var canSave: Bool {
        !name.isEmpty && !relationship.isEmpty && (!phoneNumber.isEmpty || !email.isEmpty)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .font(.custom("OpenSans-Regular", size: 16))
                    
                    TextField("Relationship (Friend, Family, etc.)", text: $relationship)
                        .font(.custom("OpenSans-Regular", size: 16))
                } header: {
                    Text("Contact Info")
                }
                
                Section {
                    TextField("Phone Number", text: $phoneNumber)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .keyboardType(.phonePad)
                    
                    TextField("Email (optional)", text: $email)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Contact Method")
                } footer: {
                    Text("Provide at least one way to reach this person")
                }
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
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
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
        }
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
            print("⚠️ Failed to load trusted circle: \(error)")
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
            print("✅ Trusted circle saved")
        } catch {
            print("⚠️ Failed to save trusted circle: \(error)")
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
