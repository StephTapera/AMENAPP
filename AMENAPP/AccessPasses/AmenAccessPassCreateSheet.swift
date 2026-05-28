// AmenAccessPassCreateSheet.swift
// AMENAPP — Create Access Pass Sheet
//
// Creator/admin creates a new access pass for a target surface.
// Safety: sensitive targets default to Request; warns before enabling direct Join.

import SwiftUI

struct AmenAccessPassCreateSheet: View {
    let targetType: AmenAccessTargetType
    let targetId: String
    let targetTitle: String
    var orgId: String?
    var churchId: String?
    var spaceId: String?
    var onCreated: ((AmenCreateAccessPassResponse) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var input: AmenCreateAccessPassInput
    @State private var isCreating = false
    @State private var createError: String?
    @State private var showSensitiveDirectJoinWarning = false
    @State private var expirationOption: ExpirationOption = .none
    @State private var customExpirationDate = Date().addingTimeInterval(86400 * 7)
    @State private var maxUsesOption: MaxUsesOption = .unlimited

    init(
        targetType: AmenAccessTargetType,
        targetId: String,
        targetTitle: String,
        orgId: String? = nil,
        churchId: String? = nil,
        spaceId: String? = nil,
        onCreated: ((AmenCreateAccessPassResponse) -> Void)? = nil
    ) {
        self.targetType = targetType
        self.targetId = targetId
        self.targetTitle = targetTitle
        self.orgId = orgId
        self.churchId = churchId
        self.spaceId = spaceId
        self.onCreated = onCreated
        _input = State(initialValue: AmenCreateAccessPassInput.defaultInput(
            for: targetType, targetId: targetId, title: targetTitle
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                targetSection
                modeSection
                expirationSection
                usesSection
                safetySection
                landingSection
                actionsSection
            }
            .navigationTitle("Create Access Pass")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createPass() }
                        .fontWeight(.semibold)
                        .disabled(isCreating || input.title.isEmpty)
                }
            }
            .alert("Allow Direct Join?", isPresented: $showSensitiveDirectJoinWarning) {
                Button("Yes, Allow Direct Join", role: .destructive) {
                    input.mode = .join
                    input.requiresApproval = false
                }
                Button("Keep Request Mode", role: .cancel) {
                    input.mode = .request
                }
            } message: {
                Text("This is a sensitive space (prayer room, private group, or youth space). Direct join is not recommended. Hosts typically prefer Request mode so they can approve members individually.")
            }
            .disabled(isCreating)
        }
    }

    // MARK: - Sections

    private var targetSection: some View {
        Section("Target") {
            LabeledContent("Type", value: targetType.displayName)
            LabeledContent("Name", value: targetTitle)
        }
    }

    private var modeSection: some View {
        Section {
            Picker("Access Mode", selection: $input.mode) {
                ForEach(AmenAccessMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .onChange(of: input.mode) { _, newMode in
                if newMode == .join && input.isSensitive {
                    showSensitiveDirectJoinWarning = true
                }
                input.requiresApproval = newMode == .request || newMode == .roleGated
            }

            if input.mode == .checkIn {
                Stepper(
                    "Duration: \(input.checkInDurationMinutes ?? 120) min",
                    value: Binding(
                        get: { input.checkInDurationMinutes ?? 120 },
                        set: { input.checkInDurationMinutes = $0 }
                    ),
                    in: 15...480,
                    step: 15
                )
            }

            Toggle("Requires Approval", isOn: $input.requiresApproval)
                .disabled(input.mode == .request || input.mode == .roleGated)
        } header: {
            Text("Access Mode")
        } footer: {
            Text(input.mode.footerDescription)
                .font(.footnote)
        }
    }

    private var expirationSection: some View {
        Section("Expiration") {
            Picker("Expiration", selection: $expirationOption) {
                ForEach(ExpirationOption.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            .onChange(of: expirationOption) { _, opt in
                switch opt {
                case .none:     input.expiresAt = nil
                case .endOfDay: input.expiresAt = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
                case .sevenDays: input.expiresAt = Date().addingTimeInterval(86400 * 7)
                case .custom:   input.expiresAt = customExpirationDate
                }
            }

            if expirationOption == .custom {
                DatePicker("Date", selection: $customExpirationDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .onChange(of: customExpirationDate) { _, v in
                        input.expiresAt = v
                    }
            }
        }
    }

    private var usesSection: some View {
        Section("Usage Limits") {
            Picker("Max Uses", selection: $maxUsesOption) {
                ForEach(MaxUsesOption.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            .onChange(of: maxUsesOption) { _, opt in
                switch opt {
                case .unlimited: input.maxUses = nil
                case .ten:       input.maxUses = 10
                case .fifty:     input.maxUses = 50
                case .oneHundred: input.maxUses = 100
                case .custom:    input.maxUses = input.maxUses ?? 25
                }
            }

            if maxUsesOption == .custom {
                Stepper("Max: \(input.maxUses ?? 25)", value: Binding(
                    get: { input.maxUses ?? 25 },
                    set: { input.maxUses = $0 }
                ), in: 1...10000)
            }

            Stepper("Per-User Limit: \(input.maxUsesPerUser)", value: $input.maxUsesPerUser, in: 1...10)
        }
    }

    private var safetySection: some View {
        Section {
            Toggle("Sensitive Space", isOn: $input.isSensitive)
            Toggle("Guest Preview Allowed", isOn: $input.allowGuestPreview)
            Toggle("Show Member Visibility Warning", isOn: $input.showMemberVisibilityWarning)
            if targetType == .prayerRoom || input.isSensitive {
                Toggle("Show Prayer Privacy Warning", isOn: $input.showPrayerPrivacyWarning)
            }
            Toggle("Require Moderator Approval", isOn: $input.requiresModeratorApproval)
        } header: {
            Text("Safety")
        } footer: {
            if input.isSensitive {
                Text("Sensitive spaces show additional privacy context to users and default to Request mode.")
                    .font(.footnote)
            }
        }
    }

    private var landingSection: some View {
        Section("Landing Screen") {
            TextField("Headline", text: $input.landingHeadline)
            TextField("Body text", text: $input.landingBody, axis: .vertical)
                .lineLimit(2...4)
            TextField("Primary button label", text: $input.primaryActionLabel)
        }
    }

    private var actionsSection: some View {
        Section {
            if let err = createError {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        }
    }

    // MARK: - Create

    private func createPass() {
        var finalInput = input
        finalInput.orgId = orgId
        finalInput.churchId = churchId
        finalInput.spaceId = spaceId

        isCreating = true
        createError = nil

        Task {
            do {
                let response = try await AmenAccessPassService.shared.createAccessPass(finalInput)
                AmenAccessPassAnalytics.shared.logCreated(
                    passId: response.accessPassId,
                    targetType: targetType,
                    mode: input.mode,
                    verifiedHostBadge: false
                )
                isCreating = false
                onCreated?(response)
                dismiss()
            } catch {
                createError = error.localizedDescription
                isCreating = false
            }
        }
    }

    // MARK: - Supporting Enums

    enum ExpirationOption: String, CaseIterable {
        case none = "none"
        case endOfDay = "endOfDay"
        case sevenDays = "sevenDays"
        case custom = "custom"

        var displayName: String {
            switch self {
            case .none:       return "No Expiration"
            case .endOfDay:   return "End of Day"
            case .sevenDays:  return "7 Days"
            case .custom:     return "Custom"
            }
        }
    }

    enum MaxUsesOption: String, CaseIterable {
        case unlimited  = "unlimited"
        case ten        = "ten"
        case fifty      = "fifty"
        case oneHundred = "oneHundred"
        case custom     = "custom"

        var displayName: String {
            switch self {
            case .unlimited:  return "Unlimited"
            case .ten:        return "10"
            case .fifty:      return "50"
            case .oneHundred: return "100"
            case .custom:     return "Custom"
            }
        }
    }
}

private extension AmenAccessMode {
    var footerDescription: String {
        switch self {
        case .preview:   return "Users can view without becoming a member."
        case .join:      return "Users join directly after seeing the landing screen."
        case .request:   return "Users submit a request; you approve or deny."
        case .checkIn:   return "Users get temporary timed access for an event."
        case .roleGated: return "Access is granted only to approved roles or email domains."
        }
    }
}
