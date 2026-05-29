//
//  ActiveSessionsView.swift
//  AMENAPP
//
//  View and manage active login sessions across devices
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

struct ActiveSessionsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var devices: [DeviceSession] = []
    @State private var isLoading = true
    @State private var showSignOutConfirmation = false
    @State private var deviceToSignOut: DeviceSession?
    @State private var currentDeviceId: String = ""
    @State private var showRevokeAllConfirmation = false
    @State private var isRevokingAll = false
    @State private var revokeAllError: String?
    @State private var showRevokeAllError = false
    @State private var revokeAllSuccess = false

    var body: some View {
        NavigationStack {
            ZStack {
                if isLoading {
                    ProgressView("Loading sessions...")
                } else if devices.isEmpty {
                    emptyState
                } else {
                    devicesList
                }
            }
            .navigationTitle("Active Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadDevices()
                currentDeviceId = await getDeviceIdentifier()
            }
            .refreshable {
                await loadDevices()
            }
            .confirmationDialog(
                "Sign out all devices?",
                isPresented: $showRevokeAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out All Devices", role: .destructive) {
                    Task { await revokeAllSessions() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will immediately sign you out on every device, including this one. You'll need to sign in again.")
            }
            .alert("Error", isPresented: $showRevokeAllError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(revokeAllError ?? "Failed to sign out all devices. Please try again.")
            }
            .alert("Sign Out Device?", isPresented: $showSignOutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    if let device = deviceToSignOut {
                        Task {
                            await removeDevice(device)
                        }
                    }
                }
            } message: {
                if let device = deviceToSignOut {
                    Text("This will sign out \(device.deviceName). You'll need to sign in again on that device.")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.systemScaled(48))
                .foregroundStyle(.secondary)

            Text("No Active Sessions")
                .font(.systemScaled(18, weight: .semibold))

            Text("You're not signed in on any devices")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var devicesList: some View {
        ScrollView {
            VStack(spacing: 0) {

                // MARK: Signed In Devices Section
                Text("SIGNED IN DEVICES")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                        DeviceSessionRow(
                            device: device,
                            isCurrentDevice: device.deviceId == currentDeviceId,
                            onSignOut: {
                                deviceToSignOut = device
                                showSignOutConfirmation = true
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        if index < devices.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                // Footer
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your account is currently signed in on \(devices.count) device\(devices.count == 1 ? "" : "s").")
                    if devices.count > 1 {
                        Text("You can sign out from any device remotely for security.")
                    }
                }
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // MARK: Security Info Section
                Text("SECURITY")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Secure Sessions")
                                .font(.systemScaled(14, weight: .semibold))

                            Text("All sessions are encrypted and protected by Firebase Authentication")
                                .font(.systemScaled(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Auto Refresh")
                                .font(.systemScaled(14, weight: .semibold))

                            Text("Sessions automatically refresh every 7 days for security")
                                .font(.systemScaled(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Button {
                        showRevokeAllConfirmation = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isRevokingAll ? "ellipsis.circle.fill" : "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(isRevokingAll ? "Signing out all devices…" : "Sign Out All Devices")
                                    .font(.systemScaled(14, weight: .semibold))
                                    .foregroundStyle(.red)
                                Text("Immediately revokes all active sessions")
                                    .font(.systemScaled(13))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isRevokingAll { ProgressView().tint(.red) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRevokingAll)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                if revokeAllSuccess {
                    Label("All other sessions have been signed out.", systemImage: "checkmark.circle.fill")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                Spacer(minLength: 40)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - Data Loading

    private func loadDevices() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }

        do {
            lazy var db = Firestore.firestore()
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("devices")
                .whereField("isActive", isEqualTo: true)
                .order(by: "lastRefreshed", descending: true)
                .getDocuments()

            devices = snapshot.documents.compactMap { doc in
                try? doc.data(as: DeviceSession.self)
            }

            dlog("✅ Loaded \(devices.count) active device sessions")

        } catch {
            dlog("❌ Failed to load devices: \(error.localizedDescription)")
        }

        isLoading = false
    }

    private func removeDevice(_ device: DeviceSession) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        do {
            lazy var db = Firestore.firestore()

            // If signing out current device, sign out locally
            if device.deviceId == currentDeviceId {
                try Auth.auth().signOut()
                return
            }

            // Otherwise, just mark as inactive (soft delete)
            try await db.collection("users")
                .document(userId)
                .collection("devices")
                .document(device.deviceId)
                .updateData([
                    "isActive": false,
                    "signedOutAt": Timestamp(date: Date())
                ])

            // Remove from local list
            devices.removeAll { $0.id == device.id }

            dlog("✅ Device signed out: \(device.deviceName)")

            // Success haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)

        } catch {
            dlog("❌ Failed to sign out device: \(error.localizedDescription)")

            // Error haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }

    private func getDeviceIdentifier() async -> String {
        if let identifier = UIDevice.current.identifierForVendor?.uuidString {
            return identifier
        }
        return "unknown-device"
    }

    private func revokeAllSessions() async {
        isRevokingAll = true
        revokeAllSuccess = false
        defer { isRevokingAll = false }
        do {
            let functions = Functions.functions(region: "us-central1")
            _ = try await functions.httpsCallable("revokeAllSessions").call()
            await MainActor.run {
                revokeAllSuccess = true
                devices.removeAll()
            }
        } catch {
            await MainActor.run {
                revokeAllError = error.localizedDescription
                showRevokeAllError = true
            }
        }
    }
}

// MARK: - Device Session Row

struct DeviceSessionRow: View {
    let device: DeviceSession
    let isCurrentDevice: Bool
    let onSignOut: () -> Void

    // Remember Me state — only relevant for the current device row.
    private var isRemembered: Bool {
        isCurrentDevice && SessionTimeoutManager.shared.isRememberMeEnabled()
    }

    /// The hard-cap expiry date for a "Remembered" session (session start + 30 days).
    private var sessionExpiry: Date? {
        guard isRemembered, let start = SessionTimeoutManager.shared.sessionStartDate() else { return nil }
        return Calendar.current.date(byAdding: .day, value: 30, to: start)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Device icon
            ZStack {
                Circle()
                    .fill(isCurrentDevice ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: deviceIcon)
                    .font(.systemScaled(20))
                    .foregroundStyle(isCurrentDevice ? .green : .gray)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Device name + chips
                HStack(spacing: 6) {
                    Text(device.deviceName)
                        .font(.systemScaled(16, weight: .semibold))

                    if isCurrentDevice {
                        Text("This Device")
                            .font(.systemScaled(11, weight: .medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    // Remember Me / Standard chip
                    if isCurrentDevice {
                        Text(isRemembered ? "Remembered" : "Standard")
                            .font(.systemScaled(11, weight: .medium))
                            .foregroundStyle(isRemembered ? .blue : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(isRemembered ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }

                Text("\(device.deviceModel) · iOS \(device.osVersion)")
                    .font(.systemScaled(13))
                    .foregroundStyle(.secondary)

                Text("Last active: \(formattedDate(device.lastRefreshed))")
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)

                // Show max expiry date for Remembered sessions
                if let expiry = sessionExpiry {
                    Text("Session expires: \(formattedAbsoluteDate(expiry))")
                        .font(.systemScaled(11))
                        .foregroundStyle(.blue.opacity(0.8))
                }
            }

            Spacer()

            if !isCurrentDevice {
                Button {
                    onSignOut()
                } label: {
                    Text("Sign Out")
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var deviceIcon: String {
        if device.deviceModel.contains("iPad") {
            return "ipad"
        } else {
            return "iphone"
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formattedAbsoluteDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Device Session Model

struct DeviceSession: Identifiable, Codable {
    var id: String? // Document ID from Firestore
    let deviceId: String
    let deviceName: String
    let deviceModel: String
    let osVersion: String
    let appVersion: String
    let token: String
    let createdAt: Date
    let lastRefreshed: Date
    let isActive: Bool
    let userId: String

    enum CodingKeys: String, CodingKey {
        case id
        case deviceId
        case deviceName
        case deviceModel
        case osVersion
        case appVersion
        case token
        case createdAt
        case lastRefreshed
        case isActive
        case userId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id)
        deviceId = try container.decode(String.self, forKey: .deviceId)
        deviceName = try container.decode(String.self, forKey: .deviceName)
        deviceModel = try container.decode(String.self, forKey: .deviceModel)
        osVersion = try container.decode(String.self, forKey: .osVersion)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        token = try container.decode(String.self, forKey: .token)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        userId = try container.decode(String.self, forKey: .userId)

        // Handle Timestamp conversion
        if let timestamp = try? container.decode(Timestamp.self, forKey: .createdAt) {
            createdAt = timestamp.dateValue()
        } else {
            createdAt = Date()
        }

        if let timestamp = try? container.decode(Timestamp.self, forKey: .lastRefreshed) {
            lastRefreshed = timestamp.dateValue()
        } else {
            lastRefreshed = Date()
        }
    }
}

// MARK: - Preview

#Preview {
    ActiveSessionsView()
}
