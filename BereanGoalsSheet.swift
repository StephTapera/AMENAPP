//
//  BereanGoalsSheet.swift
//  AMENAPP
//
//  Sheet accessible from the Berean landing screen showing:
//  - List of current goals with category icons
//  - Add goal button (title + category picker)
//  - Mark complete toggle
//  - Empty state: "Set your first goal"
//  - Uses BereanGoalsService
//

import SwiftUI

// MARK: - BereanGoalsSheet

struct BereanGoalsSheet: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = BereanGoalsService.shared

    @State private var showAddGoal = false
    @State private var deletionGoalId: UUID? = nil
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.97, green: 0.97, blue: 0.97).ignoresSafeArea()

                if service.goals.isEmpty {
                    emptyState
                } else {
                    goalList
                }
            }
            .navigationTitle("My Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showAddGoal = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .sheet(isPresented: $showAddGoal) {
                BereanAddGoalSheet()
            }
            .confirmationDialog("Delete Goal?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let id = deletionGoalId {
                        withAnimation(.easeOut(duration: 0.25)) {
                            BereanGoalsService.shared.deleteGoal(id)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Goal List

    private var goalList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Active goals section
                if !service.activeGoals.isEmpty {
                    sectionHeader("Active", count: service.activeGoals.count)
                    ForEach(service.activeGoals) { goal in
                        goalRow(goal)
                    }
                }

                // Completed goals section
                if !service.completedGoals.isEmpty {
                    sectionHeader("Completed", count: service.completedGoals.count)
                        .padding(.top, 8)
                    ForEach(service.completedGoals) { goal in
                        goalRow(goal)
                    }
                }

                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(white: 0.55))
                .kerning(0.6)
                .textCase(.uppercase)
            Text("(\(count))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(white: 0.65))
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func goalRow(_ goal: BereanGoal) -> some View {
        HStack(spacing: 14) {
            // Completion toggle
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    BereanGoalsService.shared.toggleComplete(goal.id)
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(
                            goal.isCompleted
                                ? goal.goalCategory.swiftUIAccentColor
                                : Color(white: 0.78),
                            lineWidth: 1.5
                        )
                        .frame(width: 24, height: 24)

                    if goal.isCompleted {
                        Circle()
                            .fill(goal.goalCategory.swiftUIAccentColor)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            // Category icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(goal.goalCategory.swiftUIAccentColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: goal.goalCategory.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(goal.goalCategory.swiftUIAccentColor)
            }

            // Title + meta
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(
                        goal.isCompleted
                            ? Color(white: 0.60)
                            : Color(white: 0.12)
                    )
                    .strikethrough(goal.isCompleted, color: Color(white: 0.60))
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(goal.goalCategory.displayName)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(goal.goalCategory.swiftUIAccentColor)

                    if let completedAt = goal.completedAt {
                        Text("· Completed \(completedAt.bereanRelativeDate)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color(white: 0.55))
                    } else {
                        Text("· Added \(goal.createdAt.bereanRelativeDate)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color(white: 0.62))
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
        )
        .padding(.bottom, 8)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deletionGoalId = goal.id
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.48, green: 0.36, blue: 0.75).opacity(0.10))
                    .frame(width: 72, height: 72)
                Image(systemName: "target")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Color(red: 0.48, green: 0.36, blue: 0.75))
            }

            VStack(spacing: 6) {
                Text("Set your first goal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(white: 0.12))
                Text("Track spiritual, health, work, and\nrelationship goals with Berean's help.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(white: 0.50))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showAddGoal = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Add Goal")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.48, green: 0.36, blue: 0.75),
                                    Color(red: 0.35, green: 0.25, blue: 0.62)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(red: 0.48, green: 0.36, blue: 0.75).opacity(0.30), radius: 8, y: 3)
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showAddGoal) {
                BereanAddGoalSheet()
            }
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - BereanAddGoalSheet

struct BereanAddGoalSheet: View {

    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var category: BereanGoalCategory = .spiritual
    @FocusState private var isTitleFocused: Bool

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.97, green: 0.97, blue: 0.97).ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    // Title field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Goal")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(white: 0.55))
                            .kerning(0.5)
                            .textCase(.uppercase)

                        TextField("e.g. Read the Bible in a year", text: $title)
                            .font(.system(size: 16, weight: .regular))
                            .focused($isTitleFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                if canSave { saveAndDismiss() }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
                            )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 28)

                    // Category picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Category")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(white: 0.55))
                            .kerning(0.5)
                            .textCase(.uppercase)
                            .padding(.horizontal, 20)

                        HStack(spacing: 10) {
                            ForEach(BereanGoalCategory.allCases, id: \.rawValue) { cat in
                                categoryChip(cat)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    Spacer()
                }
            }
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") { saveAndDismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .disabled(!canSave)
                }
            }
            .onAppear { isTitleFocused = true }
        }
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func categoryChip(_ cat: BereanGoalCategory) -> some View {
        let isSelected = category == cat
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeOut(duration: 0.2)) { category = cat }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected
                            ? cat.swiftUIAccentColor.opacity(0.18)
                            : Color.white)
                        .frame(width: 48, height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    isSelected ? cat.swiftUIAccentColor.opacity(0.45) : Color.black.opacity(0.07),
                                    lineWidth: 1.0
                                )
                        )
                    Image(systemName: cat.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isSelected ? cat.swiftUIAccentColor : Color(white: 0.50))
                }
                Text(cat.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? cat.swiftUIAccentColor : Color(white: 0.50))
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isSelected)
        .frame(maxWidth: .infinity)
    }

    private func saveAndDismiss() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let goal = BereanGoal(title: trimmed, category: category.rawValue)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        BereanGoalsService.shared.addOrUpdate(goal)
        dismiss()
    }
}

// MARK: - BereanGoalCategory + SwiftUI Color Helper

private extension BereanGoalCategory {
    var swiftUIAccentColor: Color {
        switch self {
        case .spiritual:     return Color(red: 0.48, green: 0.36, blue: 0.75)
        case .health:        return Color(red: 0.88, green: 0.36, blue: 0.36)
        case .work:          return Color(red: 0.23, green: 0.51, blue: 0.96)
        case .relationships: return Color(red: 0.15, green: 0.68, blue: 0.38)
        }
    }
}

// MARK: - Date Formatting Helper

private extension Date {
    var bereanRelativeDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "today" }
        if calendar.isDateInYesterday(self) { return "yesterday" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Goals Sheet") {
    BereanGoalsSheet()
}

#Preview("Add Goal Sheet") {
    BereanAddGoalSheet()
}
#endif
