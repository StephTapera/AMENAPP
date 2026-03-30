// StudioCommissionsView.swift
// AMEN Studio — Commissions Module

import SwiftUI

struct StudioCommissionsView: View {
    let commissionProfile: StudioCommissionProfile?
    let creatorId: String
    let isOwnProfile: Bool

    @StateObject private var service = StudioDataService.shared
    @State private var showRequestForm = false
    @State private var isTogglingOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let commission = commissionProfile {
                // Status banner
                commissionsStatusBanner(commission)

                // Examples
                if !commission.exampleWorkIds.isEmpty {
                    sectionHeader("Example Work")
                    Text("Examples loaded from portfolio.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }

                // Commission types
                if !commission.commissionTypes.isEmpty {
                    sectionHeader("What I Create")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(commission.commissionTypes, id: \.self) { type in
                                commissionTypeChip(type)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                // Pricing
                pricingSection(commission)

                // Queue info
                queueSection(commission)

                // Terms
                if !commission.termsAndConditions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("Terms")
                        Text(commission.termsAndConditions)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }
                }

                // CTA or toggle
                if isOwnProfile {
                    ownerToggleSection(commission)
                } else if commission.isOpen {
                    requestCTA
                } else {
                    closedNotice
                }
            } else {
                emptyState
            }

            Spacer(minLength: 32)
        }
        .padding(.top, 16)
        .sheet(isPresented: $showRequestForm) {
            StudioCommissionRequestView(
                creatorId: creatorId,
                creatorName: service.myProfile?.displayName ?? ""
            )
        }
    }

    // MARK: - Status Banner

    @ViewBuilder
    private func commissionsStatusBanner(_ profile: StudioCommissionProfile) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(profile.isOpen
                          ? Color(red: 0.18, green: 0.62, blue: 0.36).opacity(0.15)
                          : Color(.systemGray5))
                    .frame(width: 40, height: 40)
                Image(systemName: profile.isOpen ? "pencil.line" : "lock.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(profile.isOpen ? Color(red: 0.18, green: 0.62, blue: 0.36) : .secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.isOpen ? "Commissions Open" : "Commissions Closed")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(profile.isOpen ? Color(red: 0.18, green: 0.62, blue: 0.36) : .secondary)
                if let note = profile.queueNote, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(
            profile.isOpen
                ? Color(red: 0.18, green: 0.62, blue: 0.36).opacity(0.08)
                : Color(.systemGray6),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Pricing

    @ViewBuilder
    private func pricingSection(_ profile: StudioCommissionProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Pricing")
            HStack(spacing: 14) {
                if let base = profile.basePrice {
                    pricingCell(label: "Starting at", value: base.formatted(.currency(code: "USD")))
                } else {
                    pricingCell(label: "Pricing", value: "Custom Quote")
                }
                pricingCell(label: "Turnaround", value: "\(profile.turnaroundWeeks) week\(profile.turnaroundWeeks == 1 ? "" : "s")")
                if profile.requiresDeposit {
                    pricingCell(label: "Deposit", value: "\(profile.depositPercent)%")
                }
            }
            .padding(.horizontal, 16)

            if let note = profile.priceNote, !note.isEmpty {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Queue

    @ViewBuilder
    private func queueSection(_ profile: StudioCommissionProfile) -> some View {
        if profile.maxQueueSize > 0 {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Queue Status")
                HStack(spacing: 0) {
                    ForEach(0..<profile.maxQueueSize, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index < profile.currentQueueSize
                                  ? Color(red: 0.55, green: 0.25, blue: 0.88)
                                  : Color(.systemGray5))
                            .frame(height: 8)
                            .padding(.horizontal, 1)
                    }
                }
                .padding(.horizontal, 16)
                Text("\(profile.currentQueueSize) of \(profile.maxQueueSize) slots filled")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Owner Toggle

    @ViewBuilder
    private func ownerToggleSection(_ profile: StudioCommissionProfile) -> some View {
        VStack(spacing: 10) {
            Button {
                toggleOpen(!profile.isOpen)
            } label: {
                HStack {
                    if isTogglingOpen {
                        ProgressView().tint(.white)
                    } else {
                        Label(
                            profile.isOpen ? "Close Commissions" : "Open Commissions",
                            systemImage: profile.isOpen ? "lock.fill" : "pencil.line"
                        )
                    }
                }
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    profile.isOpen
                        ? Color.red.opacity(0.8)
                        : Color(red: 0.18, green: 0.62, blue: 0.36),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
            .buttonStyle(.liquidGlass)
            .disabled(isTogglingOpen)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Request CTA

    @ViewBuilder
    private var requestCTA: some View {
        VStack(spacing: 8) {
            Button {
                showRequestForm = true
            } label: {
                Text("Request a Commission")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Color(red: 0.55, green: 0.25, blue: 0.88),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            .buttonStyle(.liquidGlass)
            .padding(.horizontal, 16)

            Text("You'll submit a request — the creator reviews and responds.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    @ViewBuilder
    private var closedNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.fill")
                .foregroundStyle(.secondary)
            Text("This creator isn't accepting commissions right now. Check back later.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "pencil.line")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(isOwnProfile ? "Set up commissions" : "No commissions")
                .font(.custom("OpenSans-SemiBold", size: 16))
            if isOwnProfile {
                Text("Accept custom work requests from the community.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(48)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func commissionTypeChip(_ type: CommissionType) -> some View {
        Text(type.label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(red: 0.55, green: 0.25, blue: 0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(red: 0.55, green: 0.25, blue: 0.88).opacity(0.10), in: Capsule())
    }

    @ViewBuilder
    private func pricingCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
        }
        .padding(10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.custom("OpenSans-Bold", size: 16))
            .padding(.horizontal, 16)
    }

    private func toggleOpen(_ open: Bool) {
        isTogglingOpen = true
        Task {
            try? await service.toggleCommissionsOpen(open)
            isTogglingOpen = false
        }
    }
}

// MARK: - Commission Request Form

struct StudioCommissionRequestView: View {
    let creatorId: String
    let creatorName: String

    @StateObject private var service = StudioDataService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var commissionType: CommissionType = .artwork
    @State private var description = ""
    @State private var budgetMin = ""
    @State private var budgetMax = ""
    @State private var hasDeadline = false
    @State private var deadline = Date().addingTimeInterval(60 * 60 * 24 * 30)
    @State private var isSubmitting = false
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            if submitted {
                submittedState
            } else {
                Form {
                    Section("Request Details") {
                        Picker("Type of Work", selection: $commissionType) {
                            ForEach(CommissionType.allCases, id: \.self) { type in
                                Text(type.label).tag(type)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Describe your project")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $description)
                                .frame(minHeight: 100)
                        }
                    }

                    Section("Budget (Optional)") {
                        TextField("Min (USD)", text: $budgetMin).keyboardType(.decimalPad)
                        TextField("Max (USD)", text: $budgetMax).keyboardType(.decimalPad)
                    }

                    Section("Timeline") {
                        Toggle("I have a deadline", isOn: $hasDeadline)
                        if hasDeadline {
                            DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                        }
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "shield.fill")
                                    .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.36))
                                    .font(.system(size: 12))
                                Text("Your inquiry is safe and moderated.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Text("The creator will review your request and respond. No payment is required until they accept.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Request Commission")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Submit") { submit() }
                            .disabled(description.isEmpty || isSubmitting)
                            .font(.custom("OpenSans-SemiBold", size: 15))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var submittedState: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.36))

            Text("Request Sent")
                .font(.custom("OpenSans-Bold", size: 22))

            Text("Your commission request has been sent to \(creatorName). They'll review it and respond via your messages.")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Done") { dismiss() }
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(Color(red: 0.15, green: 0.45, blue: 0.90), in: RoundedRectangle(cornerRadius: 14))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submit() {
        guard let requesterId = service.myProfile?.userId else { return }
        isSubmitting = true
        let request = StudioCommissionRequest(
            creatorId: creatorId,
            requesterId: requesterId,
            requesterName: service.myProfile?.displayName ?? "Anonymous",
            commissionType: commissionType,
            description: description,
            referenceURLs: [],
            budgetMin: Double(budgetMin),
            budgetMax: Double(budgetMax),
            deadlineDate: hasDeadline ? deadline : nil,
            status: .pending,
            requiresDeposit: false,
            depositPaid: false,
            moderationFlag: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        Task {
            try? await service.submitCommissionRequest(request)
            isSubmitting = false
            submitted = true
        }
    }
}
