//
//  AgeGateView.swift
//  AMENAPP
//
//  COPPA compliance age gate — shown once on first launch.
//  Per COPPA, we block users under 13.
//
//  Age data storage:
//  - This view only collects a year-of-birth to compute the current age.
//    The raw year is NOT persisted by this view.
//  - After account creation, AgeAssuranceService stores the full date of birth
//    in Firestore at users/{uid}/private/age_assurance (a private subcollection
//    inaccessible to other users per Firestore rules). This is required for
//    ongoing age-tier enforcement and COPPA audit purposes.
//  - AgeAssuranceService.loadTier() defaults to .teen (fail-closed) when no
//    profile exists, preventing accidental adult-tier access.
//
//  CHILD-001 FIX: hasCompletedAgeVerification is now stored in the iOS Keychain
//  (kSecClassGenericPassword) instead of UserDefaults (@AppStorage). This prevents
//  a reinstall-bypass attack where a malicious user could clear UserDefaults by
//  deleting and reinstalling the app. Keychain items survive reinstall under
//  kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, preserving the COPPA gate
//  across reinstalls on the same device. The gate is intentionally fail-closed:
//  if the Keychain read fails for any reason, the gate is shown.
//

import SwiftUI
import Security

// MARK: - Keychain helper for age gate flag (CHILD-001)

/// A simple Keychain-backed Boolean that replaces @AppStorage for the COPPA age
/// gate flag. Survives app reinstall on the same device, preventing the
/// uninstall-reinstall bypass documented in audit finding CHILD-001.
enum AgeGateKeychain {
    private static let service  = (Bundle.main.bundleIdentifier ?? "com.amenapp") + ".agegate"
    private static let account  = "hasCompletedAgeVerification"
    private static let trueData = Data([0x01])

    /// Returns true only when the Keychain item is present and equals the sentinel byte.
    /// Fails closed: returns false on any read error so the gate is always shown on doubt.
    static var hasCompleted: Bool {
        get {
            let query: [CFString: Any] = [
                kSecClass:            kSecClassGenericPassword,
                kSecAttrService:      service,
                kSecAttrAccount:      account,
                kSecReturnData:       true,
                kSecMatchLimit:       kSecMatchLimitOne
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess,
                  let data = result as? Data,
                  data == trueData else {
                return false  // fail-closed: gate shows on any read failure
            }
            return true
        }
        set {
            if newValue {
                // Write or update the sentinel byte
                let query: [CFString: Any] = [
                    kSecClass:       kSecClassGenericPassword,
                    kSecAttrService: service,
                    kSecAttrAccount: account
                ]
                // Try update first; if item doesn't exist, add it
                let updateAttrs: [CFString: Any] = [
                    kSecValueData:      trueData,
                    kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                ]
                let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
                if updateStatus == errSecItemNotFound {
                    var addQuery = query
                    addQuery[kSecValueData] = trueData
                    addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                    _ = SecItemAdd(addQuery as CFDictionary, nil)
                }
            } else {
                // Delete the item so the gate reappears
                let query: [CFString: Any] = [
                    kSecClass:       kSecClassGenericPassword,
                    kSecAttrService: service,
                    kSecAttrAccount: account
                ]
                _ = SecItemDelete(query as CFDictionary)
            }
        }
    }
}

// MARK: - View

struct AgeGateView: View {
    @Binding var isEligible: Bool

    // CHILD-001: Backing store moved from @AppStorage (UserDefaults) to Keychain.
    // The computed getter/setter on AgeGateKeychain wraps SecItemCopyMatching /
    // SecItemAdd / SecItemUpdate / SecItemDelete.  Reads fail-closed: if the Keychain
    // item is absent the gate shows, preventing a reinstall bypass.
    @State private var _keychainVerified: Bool = AgeGateKeychain.hasCompleted

    @State private var birthDate = Calendar.current.date(
        byAdding: .year, value: -16, to: Date()
    ) ?? Date()
    @State private var showUnderAgeMessage = false
    @State private var appeared = false

    var age: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.systemScaled(52))
                    .foregroundStyle(.indigo)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.8)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: appeared)

                Text("How old are you?")
                    .font(.title2.bold())
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1), value: appeared)

                Text("You must be \(AppConfig.Legal.minimumAge) or older to use AMEN")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.15), value: appeared)
            }

            DatePicker(
                "Date of birth",
                selection: $birthDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .onChange(of: birthDate) { _, _ in
                showUnderAgeMessage = age < AppConfig.Legal.minimumAge
            }

            if showUnderAgeMessage {
                Text("Sorry, you must be \(AppConfig.Legal.minimumAge) or older to create an account.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button("Continue") {
                if age >= AppConfig.Legal.minimumAge {
                    // CHILD-001: Write to Keychain (not UserDefaults) so this flag
                    // survives reinstall and cannot be cleared by deleting the app.
                    AgeGateKeychain.hasCompleted = true
                    _keychainVerified = true
                    isEligible = true
                } else {
                    showUnderAgeMessage = true
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(age >= AppConfig.Legal.minimumAge ? Color.indigo : Color.indigo.opacity(0.35))
            )
            .padding(.horizontal, 24)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: age >= AppConfig.Legal.minimumAge)

            Spacer()
        }
        .onAppear {
            withAnimation { appeared = true }
        }
    }
}
