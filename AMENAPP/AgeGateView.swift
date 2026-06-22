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

    // Honor the user's transparency setting: Liquid Glass and materials are
    // swapped for an opaque surface when Reduce Transparency is enabled.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var age: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
    }

    private var meetsMinimumAge: Bool { age >= AppConfig.Legal.minimumAge }

    var body: some View {
        ZStack {
            // Ambient indigo wash behind the glass surfaces. Purely decorative,
            // dropped entirely under Reduce Transparency for a flat backdrop.
            if !reduceTransparency {
                Circle()
                    .fill(Color.indigo.opacity(0.16))
                    .frame(width: 300, height: 300)
                    .blur(radius: 100)
                    .offset(y: -200)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 28) {
                Spacer()

                header

                // The wheel picker now sits on its own Liquid Glass card so the
                // selection reads as a focused, tactile surface rather than a
                // floating control.
                DatePicker(
                    "Date of birth",
                    selection: $birthDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .modifier(AgeGateGlassCard(cornerRadius: 28, reduceTransparency: reduceTransparency))
                .padding(.horizontal, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.2), value: appeared)
                .onChange(of: birthDate) { _, _ in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showUnderAgeMessage = !meetsMinimumAge
                    }
                }

                if showUnderAgeMessage {
                    Text("Sorry, you must be \(AppConfig.Legal.minimumAge) or older to create an account.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                continueButton

                Spacer()
            }
        }
        .onAppear {
            withAnimation { appeared = true }
        }
    }

    // MARK: - Header (icon + title + subtitle)

    private var header: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.systemScaled(46))
                .foregroundStyle(.indigo)
                .frame(width: 96, height: 96)
                .modifier(AgeGateGlassCircle(reduceTransparency: reduceTransparency))
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.8)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: appeared)

            VStack(spacing: 8) {
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
        }
    }

    // MARK: - Continue button (Liquid Glass prominent)

    private var continueButton: some View {
        Button(action: handleContinue) {
            Text("Continue")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .controlSize(.large)
        .modifier(AgeGateProminentGlassButton())
        .tint(.indigo)
        .opacity(meetsMinimumAge ? 1 : 0.55)
        .padding(.horizontal, 24)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: meetsMinimumAge)
        .accessibilityHint(meetsMinimumAge
            ? Text("Confirms your age and continues")
            : Text("You must be \(AppConfig.Legal.minimumAge) or older to continue"))
    }

    private func handleContinue() {
        if meetsMinimumAge {
            // CHILD-001: Write to Keychain (not UserDefaults) so this flag
            // survives reinstall and cannot be cleared by deleting the app.
            AgeGateKeychain.hasCompleted = true
            _keychainVerified = true
            isEligible = true
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showUnderAgeMessage = true
            }
        }
    }
}

// MARK: - Adaptive Liquid Glass helpers
//
// Deployment target is iOS 17, but the app builds against a newer SDK that
// ships Liquid Glass (`glassEffect`, `.glassProminent`). These modifiers use
// the real material on iOS 26+ and fall back to translucent materials (or an
// opaque fill under Reduce Transparency) on earlier systems. No glass surface
// is nested inside another, per the project's no-glass-on-glass rule.

/// Rounded Liquid Glass card used behind the date wheel.
private struct AgeGateGlassCard: ViewModifier {
    let cornerRadius: CGFloat
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(Glass.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(reduceTransparency
                            ? AnyShapeStyle(Color(.secondarySystemBackground))
                            : AnyShapeStyle(.ultraThinMaterial))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

/// Circular Liquid Glass chip used behind the header icon.
private struct AgeGateGlassCircle: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(Glass.regular, in: .circle)
        } else {
            content
                .background(
                    Circle().fill(reduceTransparency
                        ? AnyShapeStyle(Color(.secondarySystemBackground))
                        : AnyShapeStyle(.ultraThinMaterial))
                )
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                .clipShape(Circle())
        }
    }
}

/// Prominent Liquid Glass button style with a capsule fallback for older systems.
private struct AgeGateProminentGlassButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
        } else {
            content
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
    }
}

// MARK: - Preview
//
// Styling-only canvas for the Liquid Glass pass. Uses a constant binding so the
// enforcement path is never exercised: no app launch, no FirebaseApp.configure(),
// and no way to advance past the gate. This is intentionally NOT a re-show or
// skip control — it only renders the presentational layer. A constant `false`
// binding means "Continue" cannot dismiss anything here.
#if DEBUG
#Preview("Age Gate · Glass") {
    AgeGateView(isEligible: .constant(false))
}
#endif
