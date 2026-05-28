import SwiftUI

struct GivingGoalView: View {
    @StateObject private var service = GivingGoalService()
    @State private var selectedTab: GoalTab = .active
    @State private var showCreate = false
    @State private var selectedGoal: GivingGoal? = nil

    enum GoalTab: String, CaseIterable {
        case active = "Active", calendar = "Calendar", completed = "Completed"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker
                tabContent
            }
            .navigationTitle("Giving Goals")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
                    }
                    .accessibilityLabel("Create giving goal")
                }
            }
            .onAppear { service.startListening() }
            .sheet(isPresented: $showCreate) { CreateGivingGoalSheet(service: service) }
            .sheet(item: $selectedGoal) { goal in GivingGoalDetailView(goal: goal, service: service) }
        }
    }

    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(GoalTab.allCases, id: \.self) { t in Text(t.rawValue).tag(t) }
        }
        .pickerStyle(.segmented)
        .padding()
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .active:
            ScrollView {
                LazyVStack(spacing: 12) {
                    if service.goals.isEmpty {
                        emptyState
                    } else {
                        ForEach(service.goals) { goal in
                            GivingGoalCard(goal: goal).onTapGesture { selectedGoal = goal }
                        }
                    }
                }
                .padding(16)
            }
        case .calendar:
            GivingCalendarView()
        case .completed:
            CompletedGoalsView(service: service)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "target").font(.system(size: 48)).foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("No active goals").font(.custom("OpenSans-Bold", size: 17)).foregroundStyle(AmenTheme.Colors.textSecondary)
            Text("Set a giving goal and track your progress toward supporting organizations you care about.")
                .font(.custom("OpenSans-Regular", size: 14)).foregroundStyle(AmenTheme.Colors.textTertiary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            AmenLiquidGlassPillButton(
                title: "Create Goal",
                systemImage: "plus.circle",
                isLoading: false,
                isDisabled: false
            ) { showCreate = true }
        }
        .padding(.top, 60)
    }
}

struct GivingGoalCard: View {
    let goal: GivingGoal
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(goal.title).font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(AmenTheme.Colors.textPrimary).lineLimit(1)
                Spacer()
                Text(goal.status.displayName)
                    .font(.custom("OpenSans-Regular", size: 11)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(goal.status == .active ? Color.green : Color.orange).cornerRadius(8)
            }
            if let target = goal.targetCount {
                ProgressView("\(goal.currentCount) of \(target) organizations", value: goal.countProgressFraction)
                    .font(.custom("OpenSans-Regular", size: 12)).tint(Color(red: 0.10, green: 0.60, blue: 0.56))
            }
            if let target = goal.targetAmount {
                ProgressView("$\(goal.currentAmount / 100) of $\(target / 100)", value: goal.amountProgressFraction)
                    .font(.custom("OpenSans-Regular", size: 12)).tint(Color(red: 0.83, green: 0.69, blue: 0.22))
            }
        }
        .padding(14).background(AmenTheme.Colors.surfaceCard).cornerRadius(14)
        .accessibilityLabel(goal.title)
    }
}

struct CompletedGoalsView: View {
    let service: GivingGoalService
    @State private var completedGoals: [GivingGoal] = []
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(completedGoals) { goal in
                    GivingGoalCard(goal: goal)
                }
                if completedGoals.isEmpty {
                    Text("No completed goals yet").font(.custom("OpenSans-Regular", size: 15)).foregroundStyle(AmenTheme.Colors.textTertiary).padding(.top, 60)
                }
            }
            .padding(16)
        }
        .task { completedGoals = await service.completedGoals() }
    }
}
