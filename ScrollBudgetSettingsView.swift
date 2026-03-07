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
        List {
            // Enable/Disable Toggle
            Section {
                Toggle(isOn: Binding(
                    get: { budgetManager.isEnabled },
                    set: { _ in budgetManager.toggleEnabled() }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Scroll Budget")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                        Text("Manage your daily feed time with gentle reminders")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
            }
            
            if budgetManager.isEnabled {
                // Current Usage Section
                Section {
                    UsageProgressRow(budgetManager: budgetManager)
                } header: {
                    Text("TODAY'S USAGE")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
                
                // Budget Configuration
                Section {
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
                    
                    Picker("Enforcement", selection: Binding(
                        get: { budgetManager.enforcementMode },
                        set: { budgetManager.updateEnforcement(mode: $0) }
                    )) {
                        ForEach(ScrollBudgetManager.EnforcementMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("BUDGET SETTINGS")
                        .font(.custom("OpenSans-Bold", size: 12))
                } footer: {
                    if budgetManager.enforcementMode == .softStop {
                        Text("Soft stop allows 2 five-minute extensions before locking the feed.")
                            .font(.custom("OpenSans-Regular", size: 12))
                    } else {
                        Text("Hard stop locks the feed immediately when budget is reached.")
                            .font(.custom("OpenSans-Regular", size: 12))
                    }
                }
                
                // Exempt Sections
                Section {
                    ForEach(ScrollBudgetManager.ExemptSection.allCases, id: \.self) { section in
                        Toggle(isOn: Binding(
                            get: { budgetManager.exemptSections.contains(section) },
                            set: { _ in budgetManager.toggleExemptSection(section) }
                        )) {
                            Text(section.rawValue)
                                .font(.custom("OpenSans-Regular", size: 15))
                        }
                        .tint(.blue)
                    }
                } header: {
                    Text("EXEMPT SECTIONS")
                        .font(.custom("OpenSans-Bold", size: 12))
                } footer: {
                    Text("These sections won't count toward your daily budget. Prayer, Bible study, and messages remain accessible.")
                        .font(.custom("OpenSans-Regular", size: 12))
                }
                
                // How It Works
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(icon: "clock", text: "Only active scrolling counts, not idle time")
                        InfoRow(icon: "bell", text: "Gentle nudges at 50% and 80% usage")
                        InfoRow(icon: "moon.stars", text: "Supportive redirects when budget reached")
                        InfoRow(icon: "hand.raised", text: "Prayer and Bible study always accessible")
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("HOW IT WORKS")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
            }
        }
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
                        .font(.custom("OpenSans-Bold", size: 24))
                    Text("Feed time today")
                        .font(.custom("OpenSans-Regular", size: 13))
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
                        .font(.custom("OpenSans-Bold", size: 14))
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
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.red)
                }
            } else if budgetManager.usagePercentage >= 80 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("\(budgetManager.remainingMinutes) minutes remaining")
                        .font(.custom("OpenSans-SemiBold", size: 13))
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
