//
//  ScrollBudgetSettingsView.swift
//  AMENAPP
//
//  Settings view for configuring scroll budget and wellbeing controls
//

import SwiftUI

struct ScrollBudgetSettingsView: View {
    @ObservedObject private var budgetManager = ScrollBudgetManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // MARK: - Enable/Disable
                VStack(spacing: 0) {
                    Toggle(isOn: Binding(
                        get: { budgetManager.isEnabled },
                        set: { _ in budgetManager.toggleEnabled() }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Scroll Budget")
                                .font(AMENFont.semiBold(16))
                            Text("Manage your daily feed time with gentle reminders")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)
                .padding(.top, 24)

                if budgetManager.isEnabled {

                    // MARK: - TODAY'S USAGE
                    Text("TODAY'S USAGE")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        UsageProgressRow(budgetManager: budgetManager)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    // MARK: - BUDGET SETTINGS
                    Text("BUDGET SETTINGS")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        Picker("Daily Budget", selection: Binding(
                            get: { budgetManager.dailyBudgetMinutes },
                            set: { budgetManager.updateBudget(minutes: $0) }
                        )) {
                            Text("15 minutes").tag(15)
                            Text("30 minutes").tag(30)
                            Text("45 minutes").tag(45)
                            Text("60 minutes").tag(60)
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider().padding(.leading, 16)

                        Picker("Enforcement", selection: Binding(
                            get: { budgetManager.enforcementMode },
                            set: { budgetManager.updateEnforcement(mode: $0) }
                        )) {
                            ForEach(ScrollBudgetManager.EnforcementMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    if budgetManager.enforcementMode == .softStop {
                        Text("Soft stop allows 2 five-minute extensions before locking the feed.")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    } else {
                        Text("Hard stop locks the feed immediately when budget is reached.")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }

                    // MARK: - EXEMPT SECTIONS
                    Text("EXEMPT SECTIONS")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        let sections = ScrollBudgetManager.ExemptSection.allCases
                        ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                            Toggle(isOn: Binding(
                                get: { budgetManager.exemptSections.contains(section) },
                                set: { _ in budgetManager.toggleExemptSection(section) }
                            )) {
                                Text(section.rawValue)
                                    .font(AMENFont.regular(15))
                            }
                            .tint(.blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            if index < sections.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Text("These sections won't count toward your daily budget. Prayer, Bible study, and messages remain accessible.")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // MARK: - HOW IT WORKS
                    Text("HOW IT WORKS")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 12) {
                            InfoRow(icon: "clock", text: "Only active scrolling counts, not idle time")
                            InfoRow(icon: "bell", text: "Gentle nudges at 50% and 80% usage")
                            InfoRow(icon: "moon.stars", text: "Supportive redirects when budget reached")
                            InfoRow(icon: "hand.raised", text: "Prayer and Bible study always accessible")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Scroll Budget")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Usage Progress Row

struct UsageProgressRow: View {
    @ObservedObject var budgetManager: ScrollBudgetManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Time display
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(budgetManager.todayScrollMinutes)) / \(budgetManager.dailyBudgetMinutes) min")
                        .font(AMENFont.bold(24))
                    Text("Feed time today")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Percentage circle
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: budgetManager.usagePercentage / 100)
                        .stroke(
                            budgetManager.usagePercentage >= 100 ? Color.red :
                            budgetManager.usagePercentage >= 80 ? Color.orange :
                            Color.blue,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(budgetManager.usagePercentage))%")
                        .font(AMENFont.bold(14))
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [
                                    budgetManager.usagePercentage >= 100 ? .red :
                                    budgetManager.usagePercentage >= 80 ? .orange :
                                    .blue,
                                    budgetManager.usagePercentage >= 100 ? .red.opacity(0.7) :
                                    budgetManager.usagePercentage >= 80 ? .orange.opacity(0.7) :
                                    .blue.opacity(0.7)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * min(1.0, budgetManager.usagePercentage / 100), height: 8)
                }
            }
            .frame(height: 8)

            // Status message
            if budgetManager.isLocked {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.red)
                    Text("Feed locked • \(budgetManager.remainingMinutes) min until tomorrow")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.red)
                }
            } else if budgetManager.usagePercentage >= 80 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("\(budgetManager.remainingMinutes) minutes remaining")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ScrollBudgetSettingsView()
    }
}
