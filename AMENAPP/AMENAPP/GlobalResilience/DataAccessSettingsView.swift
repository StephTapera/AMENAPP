// DataAccessSettingsView.swift
// AMEN — Global Resilience System
//
// Settings screen for Data & Access preferences: data mode, language, shared-device
// privacy, and an about section.
//
// Deep-link entry point:
//   NotificationCenter.default.post(name: .openDataAccessSettings, object: nil)
//
// Onboarding use:
//   DataAccessSettingsView.asOnboardingStep(onContinue: { ... })

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import LocalAuthentication

// MARK: - DataAccessSettingsView

struct DataAccessSettingsView: View {

    // MARK: Environment / bindings

    @StateObject private var lowDataManager = LowDataModeManager.shared
    @State private var showSheet: Bool = false

    // MARK: Language state

    @State private var languageProfile: LanguageProfile = Self.loadLanguageProfile()
    @State private var primaryLanguageInput: String = ""
    @State private var autoTranslate: Bool = false
    @State private var showOriginal: Bool = false

    // MARK: Shared device privacy state

    @State private var sharedDeviceMode: Bool = false
    @State private var isBiometricPromptShown: Bool = false
    @State private var sharedDeviceSaveInFlight: Bool = false
    @State private var sharedDeviceError: String? = nil

    // MARK: Notification listener

    private let openSettingsPublisher = NotificationCenter.default
        .publisher(for: .openDataAccessSettings)

    // MARK: Body

    var body: some View {
        List {
            dataModeSection
            languageSection
            sharedDevicePrivacySection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Data & Access")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            syncLocalStateFromProfile()
        }
        .onReceive(openSettingsPublisher) { _ in
            showSheet = true
        }
        .sheet(isPresented: $showSheet) {
            NavigationStack {
                DataAccessSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSheet = false }
                        }
                    }
            }
        }
    }

    // MARK: - Data Mode Section

    @ViewBuilder
    private var dataModeSection: some View {
        Section {
            glassRow {
                Picker("Mode", selection: $lowDataManager.userOverride) {
                    Text("Automatic").tag(DataMode.automatic)
                    Text("Low Data").tag(DataMode.lowData)
                    Text("WiFi Only for Media").tag(DataMode.wifiOnlyMedia)
                    Text("Standard").tag(DataMode.standard)
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Data mode picker")
            }
        } header: {
            Text("DATA MODE")
        } footer: {
            Text("Controls how AMEN loads media and content on constrained connections.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Language Section

    @ViewBuilder
    private var languageSection: some View {
        Section {
            glassRow {
                HStack {
                    Text("Primary Language")
                        .foregroundStyle(.primary)
                    Spacer()
                    TextField("e.g. en, es, fr", text: $primaryLanguageInput)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Primary language code")
                        .onChange(of: primaryLanguageInput) { _, newValue in
                            saveLanguageProfile()
                        }
                }
            }

            glassRow {
                Toggle("Auto-Translate", isOn: $autoTranslate)
                    .accessibilityLabel("Auto-translate content")
                    .onChange(of: autoTranslate) { _, _ in
                        saveLanguageProfile()
                    }
            }

            glassRow {
                Toggle("Show Original Text", isOn: $showOriginal)
                    .accessibilityLabel("Show original text alongside translation")
                    .onChange(of: showOriginal) { _, _ in
                        saveLanguageProfile()
                    }
            }
        } header: {
            Text("LANGUAGE")
        } footer: {
            Text("Use BCP-47 language codes (e.g. \"en\", \"fr\", \"pt-BR\"). Auto-Translate uses your primary language as the target.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Shared Device Privacy Section

    @ViewBuilder
    private var sharedDevicePrivacySection: some View {
        Section {
            glassRow {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Shared Device Mode", isOn: Binding(
                        get: { sharedDeviceMode },
                        set: { newValue in
                            handleSharedDeviceToggle(newValue)
                        }
                    ))
                    .accessibilityLabel("Shared device privacy mode")
                    .disabled(sharedDeviceSaveInFlight)

                    Text("When enabled, AMEN limits personalized content and clears session data on each launch — suitable for family or shared devices.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let errorText = sharedDeviceError {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if sharedDeviceSaveInFlight {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("SHARED DEVICE PRIVACY")
        } footer: {
            Text("Biometric authentication is required to change this setting.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - About Section

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            glassRow {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About Data & Access")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("Data & Access controls how AMEN behaves across different network conditions, languages, and device contexts. These settings help ensure AMEN works for everyone — from fast connections in major cities to constrained networks and shared devices in community settings around the world.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Glass Row Helper

    /// Wraps content in a `.glassEffect()` capsule-shaped row with iOS 26 guard.
    @ViewBuilder
    private func glassRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 26, *) {
            content()
                .listRowBackground(Color.clear)
        } else {
            content()
        }
    }

    // MARK: - Shared Device Logic

    private func handleSharedDeviceToggle(_ newValue: Bool) {
        sharedDeviceError = nil
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Device has no biometrics — fall back to device passcode.
            authenticateWithPasscode(newValue: newValue)
            return
        }

        isBiometricPromptShown = true
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Verify your identity to change shared device settings."
        ) { success, authError in
            Task { @MainActor in
                isBiometricPromptShown = false
                if success {
                    await persistSharedDeviceMode(newValue)
                } else {
                    sharedDeviceError = authError?.localizedDescription ?? "Authentication failed."
                }
            }
        }
    }

    private func authenticateWithPasscode(newValue: Bool) {
        let context = LAContext()
        isBiometricPromptShown = true
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Verify your identity to change shared device settings."
        ) { success, authError in
            Task { @MainActor in
                isBiometricPromptShown = false
                if success {
                    await persistSharedDeviceMode(newValue)
                } else {
                    sharedDeviceError = authError?.localizedDescription ?? "Authentication failed."
                }
            }
        }
    }

    private func persistSharedDeviceMode(_ enabled: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            sharedDeviceError = "You must be signed in to change this setting."
            return
        }

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        sharedDeviceSaveInFlight = true
        sharedDeviceError = nil

        do {
            try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .collection("devices")
                .document(deviceId)
                .setData(["sharedDeviceMode": enabled, "updatedAt": FieldValue.serverTimestamp()],
                         merge: true)
            sharedDeviceMode = enabled
        } catch {
            sharedDeviceError = "Could not save preference. Please try again."
        }

        sharedDeviceSaveInFlight = false
    }

    // MARK: - Language Profile Persistence

    private static let languageProfileUDKey = "gr_languageProfile"

    private static func loadLanguageProfile() -> LanguageProfile {
        guard
            let data = UserDefaults.standard.data(forKey: languageProfileUDKey),
            let profile = try? JSONDecoder().decode(LanguageProfile.self, from: data)
        else {
            return LanguageProfile(
                primary: Locale.preferredLanguages.first ?? "en",
                secondaries: [],
                autoTranslate: false,
                showOriginal: false
            )
        }
        return profile
    }

    private func syncLocalStateFromProfile() {
        primaryLanguageInput = languageProfile.primary
        autoTranslate = languageProfile.autoTranslate
        showOriginal = languageProfile.showOriginal
    }

    private func saveLanguageProfile() {
        let updated = LanguageProfile(
            primary: primaryLanguageInput.trimmingCharacters(in: .whitespaces),
            secondaries: languageProfile.secondaries,
            autoTranslate: autoTranslate,
            showOriginal: showOriginal
        )
        languageProfile = updated
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: Self.languageProfileUDKey)
        }
    }

    // MARK: - Onboarding Step Factory

    /// Wraps DataAccessSettingsView in a VStack with a "Continue" button for use
    /// within first-run onboarding flows.
    @MainActor
    static func asOnboardingStep(onContinue: @escaping () -> Void) -> some View {
        DataAccessSettingsOnboardingWrapper(onContinue: onContinue)
    }
}

// MARK: - DataAccessSettingsOnboardingWrapper

/// Private wrapper used by `asOnboardingStep(onContinue:)`.
private struct DataAccessSettingsOnboardingWrapper: View {

    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DataAccessSettingsView()

            Divider()

            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .accessibilityLabel("Continue to next onboarding step")
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}
