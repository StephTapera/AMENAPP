// StewardshipDashboardView.swift
// AMENAPP
//
// Private monthly stewardship planner — formative, not addictive.
// Income data stays on-device (Keychain). Never sent to server.
// No social surfaces. No comparison. Pure faithful resource management.

import SwiftUI

struct StewardshipDashboardView: View {
    @StateObject private var vm: StewardshipViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: StewardshipLocalStore) {
        _vm = StateObject(wrappedValue: StewardshipViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Privacy banner
                        privacyBanner

                        // Planner card
                        plannerCard
                            .id(StewardshipViewModel.StewardshiSection.planner)

                        // Allocation
                        if let review = vm.annualReview {
                            allocationCard(review: review)
                                .id(StewardshipViewModel.StewardshiSection.allocation)
                        }

                        // Annual review
                        annualReviewCard
                            .id(StewardshipViewModel.StewardshiSection.annualReview)

                        // Quick actions
                        quickActions

                        // Disclaimer
                        disclaimer
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
                .navigationTitle("Stewardship")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .onChange(of: vm.activeSection) { _, section in
                    guard let section else { return }
                    switch section {
                    case .planner, .allocation, .annualReview:
                        withAnimation(.amenSnappy) {
                            proxy.scrollTo(section, anchor: .top)
                        }
                        vm.activeSection = nil
                    case .recurring, .taxCenter, .journal:
                        break // handled by sheet below
                    }
                }
            }
        }
        .onAppear { vm.onAppear() }
        .sheet(isPresented: $vm.showIncomeInput) {
            incomeInputSheet
        }
        .sheet(item: $vm.activeSection) { section in
            switch section {
            case .taxCenter:
                TaxCenterView(store: vm.store)
            case .journal:
                GivingJournalView(store: vm.store)
            case .recurring:
                recurringPlaceholderSheet
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Privacy Banner

    private var privacyBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AmenTheme.Colors.backgroundSecondary)
                Image(systemName: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Stays on your device")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text("Income and tithe targets are stored locally using Keychain encryption. Never sent to any server.")
                    .font(.system(size: 12))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
        )
    }

    // MARK: - Planner Card

    private var plannerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Monthly planner", icon: "chart.pie.fill")

            if vm.hasIncomeSet {
                // Show tithe target
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tithe target")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                            .textCase(.uppercase)
                            .tracking(1.2)
                        if let target = vm.monthlyTithingTarget {
                            Text(target)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(AmenTheme.Colors.textPrimary)
                        }
                    }
                    Spacer()
                    Button("Edit") {
                        vm.showIncomeInput = true
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AmenTheme.Colors.backgroundSecondary, in: Capsule())
                }

                // Tithe percentage stepper
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Target percentage")
                            .font(.system(size: 12))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                        Spacer()
                        HStack(spacing: 2) {
                            Button {
                                let current = Double(vm.tithingPercentText) ?? 10
                                vm.tithingPercentText = "\(max(1, Int(current) - 1))"
                                vm.saveTithing()
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 32, height: 32)
                                    .background(AmenTheme.Colors.backgroundSecondary, in: Circle())
                            }
                            .buttonStyle(.plain)

                            Text("\(vm.tithingPercentText)%")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AmenTheme.Colors.textPrimary)
                                .frame(minWidth: 44)
                                .multilineTextAlignment(.center)

                            Button {
                                let current = Double(vm.tithingPercentText) ?? 10
                                vm.tithingPercentText = "\(min(100, Int(current) + 1))"
                                vm.saveTithing()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 32, height: 32)
                                    .background(AmenTheme.Colors.backgroundSecondary, in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                // Prompt to set income
                VStack(alignment: .leading, spacing: 10) {
                    Text("Set a monthly income estimate to calculate tithe targets and giving allocations.")
                        .font(.system(size: 14))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineSpacing(2)

                    Button {
                        vm.showIncomeInput = true
                    } label: {
                        Label("Set monthly estimate", systemImage: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AmenTheme.Colors.backgroundSecondary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
        )
        .amenShadow(radius: 8, y: 3)
    }

    // MARK: - Allocation Card

    private func allocationCard(review: GivingAnnualReview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("This year's allocation", icon: "chart.bar.fill")

            HStack(spacing: 0) {
                allocationBar(
                    label: "Church",
                    percent: review.churchPercent,
                    color: Color.accentColor,
                    value: "$\(review.churchGivingTotal / 100)"
                )

                Divider().frame(height: 50)

                allocationBar(
                    label: "Nonprofits",
                    percent: review.nonprofitPercent,
                    color: AmenTheme.Colors.statusSuccess,
                    value: "$\(review.nonprofitGivingTotal / 100)"
                )

                Divider().frame(height: 50)

                allocationBar(
                    label: "Orgs",
                    percent: 100,
                    color: AmenTheme.Colors.textTertiary,
                    value: "\(review.destinationCount)"
                )
            }
            .frame(maxWidth: .infinity)

            // Progress bar
            GeometryReader { g in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor)
                        .frame(width: g.size.width * CGFloat(review.churchPercent) / 100)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AmenTheme.Colors.statusSuccess)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 8)

            HStack {
                Text("Local giving: $\(review.localGivingTotal / 100)")
                    .font(.system(size: 12))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                Spacer()
                Text("Global: $\(review.globalGivingTotal / 100)")
                    .font(.system(size: 12))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
        }
        .padding(16)
        .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
        )
        .amenShadow(radius: 8, y: 3)
    }

    private func allocationBar(label: String, percent: Int, color: Color, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Annual Review Card

    private var annualReviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionHeader("Annual review", icon: "calendar.badge.checkmark")
                Spacer()
                let year = Calendar.current.component(.year, from: Date())
                Text(String(year))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }

            if vm.isLoadingReview {
                HStack {
                    ProgressView()
                    Text("Generating review...")
                        .font(.system(size: 14))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            } else if let review = vm.annualReview {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This year you gave to \(review.destinationCount) organizations totaling \(review.totalFormatted).")
                        .font(.system(size: 15))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineSpacing(2)

                    if review.churchPercent > 70 {
                        Text("Your giving is weighted toward your local church. You may want to consider adding a nonprofit cause next year.")
                            .font(.system(size: 13))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .lineSpacing(2)
                    }
                }
            } else {
                Text("Your annual review will generate once you have giving activity this year.")
                    .font(.system(size: 14))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineSpacing(2)
            }
        }
        .padding(16)
        .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
        )
        .amenShadow(radius: 8, y: 3)
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(StewardshipViewModel.StewardshiSection.allCases.filter { $0 != .planner }, id: \.id) { section in
                Button {
                    vm.activeSection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .font(.system(size: 15))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                        Text(section.rawValue)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(12)
                    .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Recurring Placeholder Sheet

    private var recurringPlaceholderSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                Text("Recurring Gifts")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text("Manage your recurring giving commitments here.")
                    .font(.system(size: 14))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                // TODO: Wire to recurring gifts list once AmenGiveActionHandler exposes scheduled gifts
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Recurring Gifts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { vm.activeSection = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Disclaimer

    private var disclaimer: some View {
        Text("Stewardship data is private and stored locally on this device. AMEN does not report or store your income information.")
            .font(.system(size: 11))
            .foregroundStyle(AmenTheme.Colors.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    // MARK: - Income Input Sheet

    private var incomeInputSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                        Text("Stored locally only. Never shared.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                    Text("This estimate helps calculate tithe targets. It stays on your device.")
                        .font(.system(size: 14))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineSpacing(2)
                }
                .padding(14)
                .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Monthly income estimate")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)

                    HStack {
                        Text("$")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                        TextField("0", text: $vm.incomeInputText)
                            .font(.system(size: 28, weight: .semibold))
                            .keyboardType(.numberPad)
                    }
                    .padding(14)
                    .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Spacer()

                Button(action: vm.saveIncome) {
                    Text("Save estimate")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textInverse)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AmenTheme.Colors.buttonPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    vm.store.saveIncomeEstimate(nil)
                    vm.showIncomeInput = false
                } label: {
                    Text("Clear income data")
                        .font(.system(size: 13))
                        .foregroundStyle(AmenTheme.Colors.statusError)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            .padding(20)
            .navigationTitle("Monthly estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.showIncomeInput = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
    }
}

// MARK: - Local Animation Tokens
// amenSnappy is not globally exported from the kit; redeclare privately here
// following the pattern in AmenActionTray.swift and AmenMinistryRoomPrayerTab.swift.

private extension Animation {
    static var amenSnappy: Animation {
        .spring(response: 0.22, dampingFraction: 0.70)
    }
}
