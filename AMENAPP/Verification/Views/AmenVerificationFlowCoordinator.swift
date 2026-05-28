// AmenVerificationFlowCoordinator.swift
// AMENAPP — Verification & Trust System
//
// Coordinator that routes to the appropriate verification sub-flow.
// All sub-flow views are co-located in this file for cohesion.
//
// Sub-flows:
//   - Email: delegates to EmailVerificationGateView
//   - Phone: OTP-based phone verification
//   - Identity: external provider via SFSafariViewController
//   - Organization: form-based org verification request
//   - Role: form-based role verification request
//   - Creator: eligibility + consent flow
//   - Reverify: explains reverification requirement

import SwiftUI
import SafariServices

// MARK: - AmenVerificationFlowCoordinator

struct AmenVerificationFlowCoordinator: View {

    enum VerificationType: String, CaseIterable {
        case email
        case phone
        case identity
        case organization
        case role
        case creator
        case reverify
    }

    let type: VerificationType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch type {
        case .email:
            EmailVerificationGateView()

        case .phone:
            AmenPhoneVerificationView()

        case .identity:
            AmenIdentityVerificationView()

        case .organization:
            AmenOrganizationVerificationView()

        case .role:
            AmenRoleVerificationView()

        case .creator:
            AmenCreatorVerificationRequestView()

        case .reverify:
            AmenReverifyView()
        }
    }
}

// MARK: - AmenPhoneVerificationView

struct AmenPhoneVerificationView: View {

    @EnvironmentObject private var authViewModel: AuthenticationViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var countryCode: String = "+1"
    @State private var phoneNumber: String = ""
    @State private var isSending = false
    @State private var showOTPEntry = false
    @State private var otpCode: String = ""
    @State private var errorMessage: String? = nil
    @State private var isVerifying = false

    private let supportedCountryCodes = ["+1", "+44", "+61", "+64", "+27", "+234", "+254"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Info banner
                    HStack(spacing: 12) {
                        Image(systemName: "iphone.badge.play")
                            .font(.system(size: 28))
                            .foregroundStyle(.blue)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Phone Verification")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                            Text("We'll send a verification code to confirm this number.")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(infoBannerBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if !showOTPEntry {
                        // Phone number input
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Phone Number")
                                .font(.custom("OpenSans-SemiBold", size: 14))

                            HStack(spacing: 8) {
                                Picker("Country code", selection: $countryCode) {
                                    ForEach(supportedCountryCodes, id: \.self) { code in
                                        Text(code).tag(code)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 80)
                                .accessibilityLabel("Country code: \(countryCode)")

                                TextField("Phone number", text: $phoneNumber)
                                    .keyboardType(.phonePad)
                                    .textContentType(.telephoneNumber)
                                    .font(.custom("OpenSans-Regular", size: 16))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(.systemGray6))
                                    )
                                    .accessibilityLabel("Phone number")
                            }
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            sendVerificationCode()
                        } label: {
                            Group {
                                if isSending {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                } else {
                                    Text("Send Code")
                                        .font(.custom("OpenSans-SemiBold", size: 16))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(phoneNumber.isEmpty ? Color(.systemGray3) : Color.blue)
                            )
                        }
                        .disabled(phoneNumber.isEmpty || isSending)
                        .accessibilityLabel("Send verification code")
                    } else {
                        // OTP entry
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Enter the 6-digit code sent to \(countryCode)\(phoneNumber)")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)

                            TextField("123456", text: $otpCode)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .font(.custom("OpenSans-SemiBold", size: 24))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.systemGray6))
                                )
                                .accessibilityLabel("One-time code")
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            verifyOTP()
                        } label: {
                            Group {
                                if isVerifying {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                } else {
                                    Text("Verify")
                                        .font(.custom("OpenSans-SemiBold", size: 16))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(otpCode.count < 6 ? Color(.systemGray3) : Color.blue)
                            )
                        }
                        .disabled(otpCode.count < 6 || isVerifying)

                        Button("Use a different number") {
                            showOTPEntry = false
                            otpCode = ""
                            errorMessage = nil
                        }
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.blue)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Phone Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func sendVerificationCode() {
        isSending = true
        errorMessage = nil
        let fullPhone = "\(countryCode)\(phoneNumber)"
        Task {
            await authViewModel.sendPhoneVerificationCode(phoneNumber: fullPhone)
            await MainActor.run {
                isSending = false
                // If a verificationId was set, the code was sent successfully.
                if authViewModel.phoneVerificationId != nil {
                    showOTPEntry = true
                } else {
                    errorMessage = "Failed to send verification code. Please try again."
                }
            }
        }
    }

    private func verifyOTP() {
        isVerifying = true
        errorMessage = nil
        Task {
            await authViewModel.verifyPhoneCode(otpCode, displayName: "", username: "", isSignUp: false)
            await MainActor.run {
                isVerifying = false
                // On success the phoneVerificationId is cleared
                if authViewModel.phoneVerificationId == nil {
                    dismiss()
                } else {
                    errorMessage = "Verification failed. Please check your code and try again."
                }
            }
        }
    }

    @ViewBuilder
    private var infoBannerBackground: some View {
        if reduceTransparency {
            Color(.secondarySystemBackground)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.06))
                )
        }
    }
}

// MARK: - SFSafariView UIViewControllerRepresentable

private struct SFSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - AmenIdentityVerificationView

struct AmenIdentityVerificationView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var isLoading = true
    @State private var sessionUrl: URL? = nil
    @State private var sessionToken: String? = nil
    @State private var errorMessage: String? = nil
    @State private var showSafari = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(message: error)
                } else if sessionUrl != nil {
                    readyView
                }
            }
            .padding(24)
            .navigationTitle("Identity Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await startIdentityVerification()
            }
            .sheet(isPresented: $showSafari) {
                if let url = sessionUrl {
                    SFSafariView(url: url)
                        .onDisappear {
                            // After returning from provider, trigger a status refresh
                            Task { await AmenVerificationService.shared.refreshStatus() }
                        }
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
            Text("Preparing identity verification…")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
        }
    }

    private var readyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.text.rectangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)

            Text("Identity Verification")
                .font(.custom("OpenSans-SemiBold", size: 20))

            Text("Identity verification in progress. You'll be taken to our secure identity provider. Amen does not store your ID documents — only the verification result is returned.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showSafari = true
            } label: {
                Text("Open Verification")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(Color.indigo)
                    )
            }
            .accessibilityLabel("Open identity verification")
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Something went wrong")
                .font(.custom("OpenSans-SemiBold", size: 18))
            Text(message)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                isLoading = true
                errorMessage = nil
                Task { await startIdentityVerification() }
            }
            .font(.custom("OpenSans-SemiBold", size: 15))
        }
    }

    private func startIdentityVerification() async {
        do {
            let result = try await AmenVerificationService.shared.startIdentityVerification()
            if let url = URL(string: result.sessionUrl) {
                sessionUrl = url
                sessionToken = result.sessionToken
            } else {
                errorMessage = "Invalid session URL returned. Please try again."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - AmenOrganizationVerificationView

struct AmenOrganizationVerificationView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var orgId: String = ""
    @State private var domainEmail: String = ""
    @State private var orgName: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil
    @State private var didSubmit = false

    private var canSubmit: Bool {
        !orgId.isEmpty && !domainEmail.isEmpty && !orgName.isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if didSubmit {
                        successView
                    } else {
                        formContent
                    }
                }
                .padding(20)
            }
            .navigationTitle("Organization Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "building.2.crop.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            Text("Request Submitted")
                .font(.custom("OpenSans-SemiBold", size: 20))

            Text("We'll verify your organization using the information you provided. This usually takes 1–3 business days. You'll receive a notification when the review is complete.")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Done") { dismiss() }
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue))
        }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Informational note
            Text("We'll verify your organization using the information you provide. This usually takes 1–3 business days.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6))
                )

            formField(label: "Organization Name", placeholder: "e.g., First Baptist Church", text: $orgName)
                .textContentType(.organizationName)

            formField(label: "Organization ID", placeholder: "Your Amen org ID", text: $orgId)
                .autocorrectionDisabled()

            formField(label: "Domain Email", placeholder: "you@yourchurch.org", text: $domainEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if let error = errorMessage {
                Text(error)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.red)
            }

            Button {
                submitRequest()
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView().progressViewStyle(.circular).tint(.white)
                    } else {
                        Text("Submit Request")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canSubmit ? Color.blue : Color(.systemGray3))
                )
            }
            .disabled(!canSubmit)
        }
    }

    private func formField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .font(.custom("OpenSans-Regular", size: 15))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6))
                )
                .accessibilityLabel(label)
        }
    }

    private func submitRequest() {
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await AmenVerificationService.shared.requestOrganizationVerification(
                    orgId: orgId,
                    domainEmail: domainEmail
                )
                await MainActor.run { didSubmit = true }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}

// MARK: - AmenRoleVerificationView

struct AmenRoleVerificationView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var orgName: String = ""
    @State private var selectedRole: AmenRoleType = .pastor
    @State private var scope: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil
    @State private var didSubmit = false

    private var canSubmit: Bool {
        !orgName.isEmpty && !scope.isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if didSubmit {
                        successView
                    } else {
                        formContent
                    }
                }
                .padding(20)
            }
            .navigationTitle("Role Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.badge.shield.checkmark.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("Role Request Submitted")
                .font(.custom("OpenSans-SemiBold", size: 20))

            Text("Your role request will be reviewed by the organization admin. You'll be notified when it's approved.")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Done") { dismiss() }
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.green))
        }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your role request will be reviewed by the organization admin.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text("Organization Name")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.secondary)
                TextField("e.g., First Baptist Church", text: $orgName)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6))
                    )
                    .accessibilityLabel("Organization name")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Role")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.secondary)
                Picker("Select role", selection: $selectedRole) {
                    ForEach(AmenRoleType.allCases, id: \.self) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6))
                )
                .accessibilityLabel("Role: \(selectedRole.displayName)")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Scope")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.secondary)
                Text("Where does this role apply? (e.g., Youth Ministry, Main Campus, Online)")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.tertiary)
                TextField("e.g., Youth Ministry", text: $scope)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6))
                    )
                    .accessibilityLabel("Role scope")
            }

            if let error = errorMessage {
                Text(error)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.red)
            }

            Button {
                submitRoleRequest()
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView().progressViewStyle(.circular).tint(.white)
                    } else {
                        Text("Submit Request")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canSubmit ? Color.green : Color(.systemGray3))
                )
            }
            .disabled(!canSubmit)
        }
    }

    private func submitRoleRequest() {
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await AmenVerificationService.shared.requestRoleVerification(
                    orgId: orgName,
                    role: selectedRole.rawValue,
                    scope: scope
                )
                await MainActor.run { didSubmit = true }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}

// MARK: - AmenRoleType (local enum for picker)

private enum AmenRoleType: String, CaseIterable {
    case pastor          = "pastor"
    case churchAdmin     = "church_admin"
    case youthLeader     = "youth_leader"
    case ministryStaff   = "ministry_staff"
    case teacher         = "teacher"
    case mentor          = "mentor"
    case worshipLeader   = "worship_leader"
    case eventHost       = "event_host"
    case groupModerator  = "group_moderator"
    case other           = "other"

    var displayName: String {
        switch self {
        case .pastor:         return "Pastor"
        case .churchAdmin:    return "Church Admin"
        case .youthLeader:    return "Youth Leader"
        case .ministryStaff:  return "Ministry Staff"
        case .teacher:        return "Teacher"
        case .mentor:         return "Mentor"
        case .worshipLeader:  return "Worship Leader"
        case .eventHost:      return "Event Host"
        case .groupModerator: return "Group Moderator"
        case .other:          return "Other"
        }
    }
}

// MARK: - AmenCreatorVerificationRequestView

struct AmenCreatorVerificationRequestView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil
    @State private var didSubmit = false

    private let eligibilityRequirements: [(icon: String, text: String)] = [
        ("person.text.rectangle.fill", "Identity must be verified"),
        ("calendar.badge.checkmark", "Account must be at least 30 days old"),
        ("shield.lefthalf.filled.badge.checkmark", "Account must be in good safety standing"),
        ("doc.text.magnifyingglass", "Content must comply with community content policy"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if didSubmit {
                        pendingView
                    } else {
                        eligibilityContent
                    }
                }
                .padding(20)
            }
            .navigationTitle("Creator Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var eligibilityContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "star.bubble.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Creator Verification")
                        .font(.custom("OpenSans-SemiBold", size: 18))
                    Text("Become a verified creator on Amen")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
            }

            Text("Eligibility Requirements")
                .font(.custom("OpenSans-SemiBold", size: 15))

            VStack(alignment: .leading, spacing: 12) {
                ForEach(eligibilityRequirements, id: \.text) { req in
                    HStack(spacing: 12) {
                        Image(systemName: req.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        Text(req.text)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray6))
            )

            Text("By applying, you confirm that your content aligns with Amen's community covenant and content policy.")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)

            if let error = errorMessage {
                Text(error)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.red)
            }

            Button {
                applyForCreatorVerification()
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView().progressViewStyle(.circular).tint(.white)
                    } else {
                        Text("Apply for Creator Verification")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12).fill(Color.orange)
                )
            }
            .disabled(isSubmitting)
        }
    }

    private var pendingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.badge.checkmark.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Application Submitted")
                .font(.custom("OpenSans-SemiBold", size: 20))

            Text("Your creator verification application is under review. We'll notify you when the decision is made. This usually takes 3–5 business days.")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Done") { dismiss() }
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange))
        }
    }

    private func applyForCreatorVerification() {
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await AmenVerificationService.shared.requestCreatorVerification()
                await MainActor.run { didSubmit = true }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}

// MARK: - AmenReverifyView

struct AmenReverifyView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var showingIdentityFlow = false

    private let reasons: [(icon: String, text: String)] = [
        ("calendar.badge.exclamationmark", "Your verification has expired"),
        ("person.badge.key.fill", "Account information has changed"),
        ("shield.slash.fill", "Policy update requires re-verification"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.indigo)
                        .accessibilityHidden(true)

                    VStack(spacing: 8) {
                        Text("Reverification Required")
                            .font(.custom("OpenSans-SemiBold", size: 20))

                        Text("Your verification needs to be renewed. This may be due to:")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(reasons, id: \.text) { reason in
                            HStack(spacing: 12) {
                                Image(systemName: reason.icon)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.indigo)
                                    .frame(width: 24)
                                    .accessibilityHidden(true)
                                Text(reason.text)
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6))
                    )

                    Text("Reverification follows the same process as the original verification. Your existing badges will remain visible while the review is in progress.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        showingIdentityFlow = true
                    } label: {
                        Text("Start Reverification")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12).fill(Color.indigo)
                            )
                    }
                    .accessibilityLabel("Start reverification")

                    Button("Cancel") { dismiss() }
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .navigationTitle("Reverification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingIdentityFlow) {
                AmenIdentityVerificationView()
            }
        }
    }
}
