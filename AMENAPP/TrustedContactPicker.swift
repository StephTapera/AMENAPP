//
//  TrustedContactPicker.swift
//  AMENAPP
//
//  UIViewControllerRepresentable wrapping CNContactPickerViewController
//  for selecting trusted contacts from the phone's address book.
//  Stores up to 3 contacts locally in UserDefaults (never sent to server).
//

import SwiftUI
import Combine
import ContactsUI

// MARK: - Data Model

struct TrustedContact: Codable, Identifiable {
    var id = UUID()
    var name: String
    var phone: String
    var relationship: String // e.g. "Parent", "Friend", "Pastor"
}

// MARK: - Store

@MainActor
final class TrustedContactStore: ObservableObject {
    static let shared = TrustedContactStore()

    @Published var contacts: [TrustedContact] {
        didSet { save() }
    }

    private let key = "amen.trustedContacts"
    private let maxContacts = 3

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([TrustedContact].self, from: data) {
            contacts = decoded
        } else {
            contacts = []
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    var canAddMore: Bool { contacts.count < maxContacts }

    func add(_ contact: TrustedContact) {
        guard canAddMore else { return }
        contacts.append(contact)
    }

    func remove(at index: Int) {
        guard index < contacts.count else { return }
        contacts.remove(at: index)
    }
}

// MARK: - Contact Picker (UIKit wrapper)

struct ContactPickerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onSelect: (String, String) -> Void // (name, phone)

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, dismiss: dismiss)
    }

    class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: (String, String) -> Void
        let dismiss: DismissAction

        init(onSelect: @escaping (String, String) -> Void, dismiss: DismissAction) {
            self.onSelect = onSelect
            self.dismiss = dismiss
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
            let name = "\(contactProperty.contact.givenName) \(contactProperty.contact.familyName)".trimmingCharacters(in: .whitespaces)
            if let phone = contactProperty.value as? CNPhoneNumber {
                onSelect(name, phone.stringValue)
            }
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            // dismiss handled by UIKit automatically
        }
    }
}

// MARK: - Trusted Contacts Section (for CrisisResourcesDetailView)

struct TrustedContactsSection: View {
    @ObservedObject private var store = TrustedContactStore.shared
    @State private var showContactPicker = false

    private let accent = Color(red: 0.22, green: 0.52, blue: 0.50)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.2.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(accent)
                Text("Your Trusted People")
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.primary)
                Spacer()
            }

            if store.contacts.isEmpty {
                Text("Who can you call right now? Save up to 3 trusted contacts for one-tap access.")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }

            ForEach(Array(store.contacts.enumerated()), id: \.element.id) { index, contact in
                trustedContactRow(contact: contact, index: index)
            }

            if store.canAddMore {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showContactPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                        Text("Add a trusted person")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                    }
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(accent.opacity(0.08))
                    )
                }
                .buttonStyle(SquishButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
        .sheet(isPresented: $showContactPicker) {
            ContactPickerView { name, phone in
                let contact = TrustedContact(name: name, phone: phone, relationship: "")
                store.add(contact)
            }
        }
    }

    private func trustedContactRow(contact: TrustedContact, index: Int) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(accent.opacity(0.14))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(contact.name.prefix(1)).uppercased())
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(accent)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.primary)
                Text(contact.phone)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // One-tap call
            Button {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                let clean = contact.phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
                if let url = URL(string: "tel:\(clean)") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(accent, in: Circle())
            }
            .buttonStyle(SquishButtonStyle())

            // Remove
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    store.remove(at: index)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(accent.opacity(0.05))
        )
    }
}
