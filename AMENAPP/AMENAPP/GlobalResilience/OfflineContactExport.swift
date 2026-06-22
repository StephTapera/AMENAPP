import SwiftUI
import Contacts

// MARK: - ContactExportService

final class ContactExportService {
    static let shared = ContactExportService()

    private let store = CNContactStore()

    private init() {}

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestAccess(for: .contacts)
            return granted
        } catch {
            return false
        }
    }

    func exportContact(displayName: String, phone: String?, email: String?) async throws {
        let contact = CNMutableContact()

        let parts = displayName.split(separator: " ", maxSplits: 1)
        if parts.count >= 2 {
            contact.givenName = String(parts[0])
            contact.familyName = String(parts[1])
        } else {
            contact.givenName = displayName
        }

        if let phone = phone, !phone.isEmpty {
            let phoneValue = CNPhoneNumber(stringValue: phone)
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: phoneValue)]
        }

        if let email = email, !email.isEmpty {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: email as NSString)]
        }

        let saveRequest = CNSaveRequest()
        saveRequest.add(contact, toContainerWithIdentifier: nil)

        do {
            try store.execute(saveRequest)
        } catch let error as CNError {
            if error.code == .authorizationDenied {
                throw ContactExportError.authorizationDenied
            }
            throw error
        }
    }
}

// MARK: - ContactExportError

enum ContactExportError: LocalizedError {
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Contacts access was denied. Please enable it in Settings to export contacts."
        }
    }
}

// MARK: - OfflineContactExportView

struct OfflineContactExportView: View {
    let contacts: [(id: String, displayName: String, phone: String?, email: String?)]

    @State private var exportedIds: Set<String> = []
    @State private var isAuthorized: Bool = false
    @State private var hasCheckedPermission: Bool = false
    @State private var isRequestingPermission: Bool = false
    @State private var errorMessage: String? = nil
    @State private var isExportingAll: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear

                VStack(spacing: 0) {
                    headerView
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    if !hasCheckedPermission {
                        permissionCheckView
                    } else if !isAuthorized {
                        permissionDeniedView
                    } else {
                        contactListView
                    }
                }
            }
            .amenGlassEffect()
            .navigationTitle("Save Contacts Offline")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await checkPermission()
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save contacts locally to stay in touch if there are connectivity issues")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var permissionCheckView: some View {
        VStack {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
            Spacer()
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Contacts Access Required")
                    .font(.headline)

                Text("AMEN needs access to your Contacts to save people locally on your device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if isRequestingPermission {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                Button {
                    Task { await requestPermission() }
                } label: {
                    Text("Allow Contacts Access")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                }

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
            }

            Spacer()
        }
    }

    private var contactListView: some View {
        VStack(spacing: 0) {
            List {
                ForEach(contacts, id: \.id) { contact in
                    contactRow(contact: contact)
                }
            }
            .listStyle(.plain)

            exportAllButton
                .padding(16)
        }
    }

    private func contactRow(contact: (id: String, displayName: String, phone: String?, email: String?)) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(.body.weight(.medium))

                if let phone = contact.phone {
                    Label(phone, systemImage: "phone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let email = contact.email {
                    Label(email, systemImage: "envelope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if exportedIds.contains(contact.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button {
                    Task { await exportSingle(contact: contact) }
                } label: {
                    Text("Save")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .animation(.spring(duration: 0.3), value: exportedIds)
    }

    private var exportAllButton: some View {
        let remaining = contacts.filter { !exportedIds.contains($0.id) }
        let allDone = remaining.isEmpty

        return Button {
            Task { await exportAll() }
        } label: {
            HStack(spacing: 8) {
                if isExportingAll {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.8)
                } else if allDone {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(allDone ? "All Contacts Saved" : "Export All (\(remaining.count))")
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(allDone ? Color.green : Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
        }
        .disabled(allDone || isExportingAll)
        .animation(.spring(duration: 0.3), value: allDone)
    }

    // MARK: - Actions

    private func checkPermission() async {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = false
        case .denied, .restricted:
            isAuthorized = false
        case .limited:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }
        hasCheckedPermission = true
    }

    private func requestPermission() async {
        isRequestingPermission = true
        let granted = await ContactExportService.shared.requestAccess()
        isAuthorized = granted
        isRequestingPermission = false
        hasCheckedPermission = true
    }

    private func exportSingle(contact: (id: String, displayName: String, phone: String?, email: String?)) async {
        errorMessage = nil
        do {
            try await ContactExportService.shared.exportContact(
                displayName: contact.displayName,
                phone: contact.phone,
                email: contact.email
            )
            withAnimation {
                _ = exportedIds.insert(contact.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportAll() async {
        errorMessage = nil
        isExportingAll = true
        let remaining = contacts.filter { !exportedIds.contains($0.id) }
        for contact in remaining {
            do {
                try await ContactExportService.shared.exportContact(
                    displayName: contact.displayName,
                    phone: contact.phone,
                    email: contact.email
                )
                withAnimation {
                    _ = exportedIds.insert(contact.id)
                }
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }
        isExportingAll = false
    }
}

// MARK: - Preview

#Preview {
    OfflineContactExportView(contacts: [
        (id: "1", displayName: "Sarah Johnson", phone: "+1 555 123 4567", email: "sarah@example.com"),
        (id: "2", displayName: "Pastor Marcus Williams", phone: "+1 555 987 6543", email: nil),
        (id: "3", displayName: "Grace Chen", phone: nil, email: "grace@church.org"),
        (id: "4", displayName: "David Okonkwo", phone: "+1 555 246 8101", email: "david@example.com")
    ])
}
