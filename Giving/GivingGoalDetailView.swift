import SwiftUI

struct GivingGoalDetailView: View {
    let goal: GivingGoal
    let service: GivingGoalService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusHeader
                    progressSection
                    organizationsSection
                    reminderSection
                }
                .padding(16)
                .padding(.bottom, 32)
            }
            .navigationTitle(goal.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }.font(.custom("OpenSans-Regular", size: 16))
                }
            }
        }
    }

    private var statusHeader: some View {
        HStack {
            Text(goal.status.displayName)
                .font(.custom("OpenSans-Bold", size: 13))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(goal.status == .active ? Color.green : goal.status == .paused ? Color.orange : Color.blue)
                .cornerRadius(10)
            Spacer()
            if let deadline = goal.deadline?.dateValue() {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Deadline").font(.custom("OpenSans-Regular", size: 11)).foregroundStyle(AmenTheme.Colors.textTertiary)
                    Text(deadline.formatted(date: .abbreviated, time: .omitted)).font(.custom("OpenSans-Bold", size: 13)).foregroundStyle(AmenTheme.Colors.textPrimary)
                }
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Progress").font(.custom("OpenSans-Bold", size: 16)).foregroundStyle(AmenTheme.Colors.textPrimary)
            if let targetCount = goal.targetCount {
                progressBar(label: "\(goal.currentCount) of \(targetCount) organizations", value: goal.countProgressFraction, color: Color(red: 0.10, green: 0.60, blue: 0.56))
            }
            if let targetAmount = goal.targetAmount {
                progressBar(label: "$\(goal.currentAmount / 100) of $\(targetAmount / 100)", value: goal.amountProgressFraction, color: Color(red: 0.83, green: 0.69, blue: 0.22))
            }
        }
        .padding(14)
        .background(AmenTheme.Colors.surfaceCard)
        .cornerRadius(14)
    }

    private func progressBar(label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.custom("OpenSans-Bold", size: 14)).foregroundStyle(AmenTheme.Colors.textPrimary)
            ProgressView(value: value).tint(color)
            Text("\(Int(value * 100))% complete").font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textTertiary)
        }
        .accessibilityLabel("\(label), \(Int(value * 100)) percent")
    }

    private var organizationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Organizations (\(goal.organizations.count))")
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            ForEach(goal.organizations) { org in
                HStack {
                    Image(systemName: "building.columns.fill").foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
                    Text(org.orgName).font(.custom("OpenSans-Regular", size: 14)).foregroundStyle(AmenTheme.Colors.textPrimary)
                    Spacer()
                    if let target = org.targetAmount {
                        Text("$\(org.currentAmount / 100)/$\(target / 100)").font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                }
                .padding(10).background(AmenTheme.Colors.backgroundPrimary).cornerRadius(8)
                .accessibilityLabel(org.orgName)
            }
        }
        .padding(14).background(AmenTheme.Colors.surfaceCard).cornerRadius(14)
    }

    private var reminderSection: some View {
        HStack {
            Image(systemName: "bell.fill").foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
            VStack(alignment: .leading, spacing: 2) {
                Text("Reminders").font(.custom("OpenSans-Bold", size: 14)).foregroundStyle(AmenTheme.Colors.textPrimary)
                Text(goal.reminderFrequency.displayName).font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(14).background(AmenTheme.Colors.surfaceCard).cornerRadius(14)
    }
}
