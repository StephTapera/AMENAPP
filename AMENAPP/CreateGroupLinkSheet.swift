//
//  CreateGroupLinkSheet.swift
//  AMENAPP
//
//  Sheet for creating a new group with an invite link.
//  Uses AMEN Liquid Glass design: white base, black text, subtle translucency,
//  refined depth, smooth native iOS motion.
//

import SwiftUI

struct CreateGroupLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = GroupLinkViewModel()

    /// Called when group + link are created. Passes the GroupLink.
    var onCreated: ((GroupLink) -> Void)?

    /// Preset purpose from the compose menu (prayer, church, event, etc.)
    var presetPurpose: GroupPurpose?

    private let nameCharLimit = 50
    @State private var appeared = false

    var canCreate: Bool {
        let trimmed = viewModel.config.groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !viewModel.isCreating
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    groupNameSection
                    purposeSection
                    joinModeSection
                    safetyTierSection
                    optionsSection
                    smartDefaultsBanner
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            }
            .background(Color(.systemBackground))
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("OpenSans-Regular", size: 16))
                        .disabled(viewModel.isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await viewModel.createGroupWithLink()
                            if let link = viewModel.createdLink {
                                onCreated?(link)
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                    }
                    .disabled(!canCreate)
                }
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.createError != nil },
                set: { if !$0 { viewModel.createError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.createError ?? "")
            }
            .onAppear {
                // Apply preset purpose if launched from a shortcut
                if let preset = presetPurpose {
                    viewModel.config.purpose = preset
                    viewModel.config.applyPurposeDefaults()
                }
                withAnimation(.easeOut(duration: 0.35).delay(0.05)) {
                    appeared = true
                }
            }
        }
    }

    private var navigationTitle: String {
        switch presetPurpose {
        case .prayer: return "Prayer Group"
        case .church: return "Church Group"
        case .event: return "Event Group"
        case .bibleStudy: return "Bible Study"
        default: return "Create with Link"
        }
    }

    // MARK: - Sections

    private var groupNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Group Name")

            TextField("Enter group name", text: $viewModel.config.groupName)
                .font(.custom("OpenSans-Regular", size: 17))
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                        )
                )
                .onChange(of: viewModel.config.groupName) { _, newValue in
                    if newValue.count > nameCharLimit {
                        viewModel.config.groupName = String(newValue.prefix(nameCharLimit))
                    }
                }

            HStack {
                Spacer()
                Text("\(viewModel.config.groupName.count)/\(nameCharLimit)")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var purposeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Purpose")

            LazyVGrid(columns: [
                GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
            ], spacing: 10) {
                ForEach(GroupPurpose.allCases) { purpose in
                    let isSelected = viewModel.config.purpose == purpose
                    Button {
                        withAnimation(AmenMotion.micro) {
                            viewModel.config.purpose = purpose
                            viewModel.config.applyPurposeDefaults()
                        }
                        HapticManager.impact(style: .light)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: purpose.icon)
                                .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .black : .secondary)
                            Text(purpose.displayName)
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isSelected
                                      ? Color.black.opacity(0.06)
                                      : Color.black.opacity(0.02))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(
                                    isSelected
                                        ? Color.black.opacity(0.18)
                                        : Color.black.opacity(0.04),
                                    lineWidth: isSelected ? 1.5 : 0.5
                                )
                        )
                        .scaleEffect(isSelected ? 1.0 : 0.98)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var joinModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Join Mode")

            ForEach(GroupJoinMode.allCases) { mode in
                let isSelected = viewModel.config.joinMode == mode
                Button {
                    withAnimation(AmenMotion.micro) {
                        viewModel.config.joinMode = mode
                    }
                    HapticManager.impact(style: .light)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 17))
                            .frame(width: 28)
                            .foregroundStyle(isSelected ? .primary : .tertiary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.displayName)
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)
                            Text(mode.subtitle)
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: isSelected
                              ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(isSelected ? .black : Color.black.opacity(0.12))
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isSelected
                                  ? Color.black.opacity(0.04)
                                  : Color.black.opacity(0.015))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isSelected
                                    ? Color.black.opacity(0.12)
                                    : Color.black.opacity(0.04),
                                lineWidth: 0.5
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var safetyTierSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Safety Level")

            HStack(spacing: 10) {
                ForEach(GroupSafetyTier.allCases) { tier in
                    let isSelected = viewModel.config.safetyTier == tier
                    Button {
                        withAnimation(AmenMotion.micro) {
                            viewModel.config.safetyTier = tier
                        }
                        HapticManager.impact(style: .light)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: tier == .strict ? "shield.checkered" : "shield")
                                .font(.system(size: 18))
                                .foregroundStyle(isSelected ? .primary : .tertiary)
                            Text(tier.displayName)
                                .font(.custom("OpenSans-SemiBold", size: 13))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                            Text(tier.subtitle)
                                .font(.custom("OpenSans-Regular", size: 11))
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isSelected
                                      ? Color.black.opacity(0.05)
                                      : Color.black.opacity(0.02))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(
                                    isSelected
                                        ? Color.black.opacity(0.15)
                                        : Color.black.opacity(0.04),
                                    lineWidth: isSelected ? 1 : 0.5
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Options")

            // Member limit
            glassOptionRow(icon: "person.2.fill", label: "Member Limit") {
                Menu {
                    Button("No Limit") { viewModel.config.memberLimit = nil }
                    Button("10") { viewModel.config.memberLimit = 10 }
                    Button("25") { viewModel.config.memberLimit = 25 }
                    Button("50") { viewModel.config.memberLimit = 50 }
                    Button("100") { viewModel.config.memberLimit = 100 }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.config.memberLimit.map { "\($0)" } ?? "No Limit")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Expiration
            glassOptionRow(icon: "clock.fill", label: "Link Expires After") {
                Menu {
                    Button("Never") { viewModel.config.expirationDays = nil }
                    Button("1 Hour") { viewModel.config.expirationHours = 1 }
                    Button("24 Hours") { viewModel.config.expirationHours = 24 }
                    Button("3 Days") { viewModel.config.expirationDays = 3 }
                    Button("7 Days") { viewModel.config.expirationDays = 7 }
                    Button("30 Days") { viewModel.config.expirationDays = 30 }
                } label: {
                    HStack(spacing: 4) {
                        Text(expirationLabel)
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func glassOptionRow<Trailing: View>(
        icon: String, label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.tertiary)
                .frame(width: 24)
            Text(label)
                .font(.custom("OpenSans-Regular", size: 15))
            Spacer()
            trailing()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.black.opacity(0.04), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private var smartDefaultsBanner: some View {
        let purpose = viewModel.config.purpose
        if purpose != .general {
            let text = smartDefaultsText(for: purpose)
            if !text.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.black.opacity(0.5))
                    Text(text)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.025))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5)
                        )
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.custom("OpenSans-Bold", size: 12))
            .foregroundStyle(.tertiary)
            .kerning(0.8)
    }

    private func smartDefaultsText(for purpose: GroupPurpose) -> String {
        switch purpose {
        case .prayer: return "Prayer groups default to approval + strict safety for a safe space."
        case .bibleStudy: return "Bible study groups default to 7-day link expiration."
        case .event: return "Event groups default to 3-day link expiration."
        case .church: return "Church groups default to admin approval for trusted membership."
        case .fellowship, .general: return ""
        }
    }

    private var expirationLabel: String {
        if let hours = viewModel.config.expirationHours {
            if hours < 24 {
                return hours == 1 ? "1 Hour" : "\(hours) Hours"
            }
        }
        guard let days = viewModel.config.expirationDays else { return "Never" }
        return days == 1 ? "1 Day" : "\(days) Days"
    }
}
