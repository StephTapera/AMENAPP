//
//  UnusualLoginDetector.swift
//  AMENAPP
//
//  Detects sign-ins from new/unrecognized devices and writes a login alert
//  to users/{uid}/loginAlerts. InAppNotificationBanner or ActiveSessionsView
//  can surface this to the user.
//

import Foundation
import UIKit
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class UnusualLoginDetector {

    static let shared = UnusualLoginDetector()
    private init() {}

    private let db = Firestore.firestore()

    // MARK: - Check Login Device

    /// Called on every auth state change when a user signs in.
    /// If the current device identifier has never been seen before, writes a loginAlert.
    func checkLoginDevice(userId: String) async {
        let deviceId = currentDeviceId()

        do {
            // Check known devices
            let knownDevicesSnap = try await db.collection("users").document(userId)
                .collection("devices").whereField("deviceId", isEqualTo: deviceId)
                .limit(to: 1)
                .getDocuments()

            if knownDevicesSnap.documents.isEmpty {
                // New device — write an alert
                let alertId = UUID().uuidString
                try await db.collection("users").document(userId)
                    .collection("loginAlerts").document(alertId)
                    .setData([
                        "deviceId": deviceId,
                        "deviceName": currentDeviceName(),
                        "systemVersion": UIDevice.current.systemVersion,
                        "createdAt": FieldValue.serverTimestamp(),
                        "dismissed": false,
                    ])

                // Register the device as known going forward
                try await db.collection("users").document(userId)
                    .collection("devices").document(deviceId)
                    .setData([
                        "deviceId": deviceId,
                        "deviceName": currentDeviceName(),
                        "systemVersion": UIDevice.current.systemVersion,
                        "firstSeenAt": FieldValue.serverTimestamp(),
                        "lastSeenAt": FieldValue.serverTimestamp(),
                    ], merge: true)

                // Post local in-app warning banner
                await MainActor.run {
                    ToastManager.shared.showWarning(
                        "New sign-in on \(self.currentDeviceName()). If this wasn't you, check Settings → Account Status."
                    )
                }

                print("⚠️ [UnusualLogin] New device detected — alert written for user \(userId)")
            } else {
                // Known device — update last seen
                try await db.collection("users").document(userId)
                    .collection("devices").document(deviceId)
                    .updateData(["lastSeenAt": FieldValue.serverTimestamp()])
            }
        } catch {
            print("⚠️ [UnusualLogin] Error checking device: \(error)")
        }
    }

    // MARK: - Device Helpers

    private func currentDeviceId() -> String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    private func currentDeviceName() -> String {
        UIDevice.current.name
    }
}
