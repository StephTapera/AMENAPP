//
//  ActiveSessionsView.swift
//  AMENAPP
//
//  View and manage active login sessions across devices
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ActiveSessionsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var devices: [DeviceSession] = []
    @State private var isLoading = true
    @State private var showSignOutConfirmation = false
    @State private var deviceToSignOut: DeviceSession?
    @State private var currentDeviceId: String = ""
    
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
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No Active Sessions")
                .font(.system(size: 18, weight: .semibold))
            
            Text("You're not signed in on any devices")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var devicesList: some View {
        List {
            Section {
                ForEach(devices) { device in
                    DeviceSessionRow(
                        device: device,
                        isCurrentDevice: device.deviceId == currentDeviceId,
                        onSignOut: {
                            deviceToSignOut = device
                            showSignOutConfirmation = true
                        }
                    )
                }
            } header: {
                Text("SIGNED IN DEVICES")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your account is currently signed in on \(devices.count) device\(devices.count == 1 ? "" : "s").")
                    
                    if devices.count > 1 {
                        Text("You can sign out from any device remotely for security.")
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Secure Sessions")
                                .font(.system(size: 14, weight: .semibold))
                            
                            Text("All sessions are encrypted and protected by Firebase Authentication")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Auto Refresh")
                                .font(.system(size: 14, weight: .semibold))
                            
                            Text("Sessions automatically refresh every 7 days for security")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadDevices() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }
        
        do {
            let db = Firestore.firestore()
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("devices")
                .whereField("isActive", isEqualTo: true)
                .order(by: "lastRefreshed", descending: true)
                .getDocuments()
            
            devices = snapshot.documents.compactMap { doc in
                try? doc.data(as: DeviceSession.self)
            }
            
            print("✅ Loaded \(devices.count) active device sessions")
            
        } catch {
            print("❌ Failed to load devices: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    private func removeDevice(_ device: DeviceSession) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let db = Firestore.firestore()
            
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
            
            print("✅ Device signed out: \(device.deviceName)")
            
            // Success haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
        } catch {
            print("❌ Failed to sign out device: \(error.localizedDescription)")
            
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
                    .font(.system(size: 20))
                    .foregroundStyle(isCurrentDevice ? .green : .gray)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Device name + chips
                HStack(spacing: 6) {
                    Text(device.deviceName)
                        .font(.system(size: 16, weight: .semibold))

                    if isCurrentDevice {
                        Text("This Device")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    // Remember Me / Standard chip
                    if isCurrentDevice {
                        Text(isRemembered ? "Remembered" : "Standard")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isRemembered ? .blue : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(isRemembered ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }

                Text("\(device.deviceModel) · iOS \(device.osVersion)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Text("Last active: \(formattedDate(device.lastRefreshed))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                // Show max expiry date for Remembered sessions
                if let expiry = sessionExpiry {
                    Text("Session expires: \(formattedAbsoluteDate(expiry))")
                        .font(.system(size: 11))
                        .foregroundStyle(.blue.opacity(0.8))
                }
            }

            Spacer()

            if !isCurrentDevice {
                Button {
                    onSignOut()
                } label: {
                    Text("Sign Out")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 8)
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
