import SwiftUI

struct CreateGivingGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let service: GivingGoalService
    @State private var title = ""
    @State private var goalType: GoalType = .count
    @State private var targetCount = ""
    @State private var targetAmount = ""
    @State private var frequency: GoalFrequency = .monthly
    @State private var reminderFrequency: ReminderFrequency = .weekly
    @State private var selectedOrgs: [OrganizationStub] = []
    @State private var showOrgPicker = false
    @State private var isCreating = false

    enum GoalType: String, CaseIterable {
        case count = "Count", amount = "Amount", both = "Both"
    }

    private var canCreate: Bool { !title.isEmpty && !selectedOrgs.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal Details") {
                    TextField("Goal title", text: $title)
                        .font(.custom("OpenSans-Regular", size: 15))
                    Picker("Goal type", selection: $goalType) {
                        ForEach(GoalType.allCases, id: \.self) { t in Text(t.rawValue).tag(t) }
                    }
                    .pickerStyle(.segmented)
                }
                if goalType == .count || goalType == .both {
                    Section("Organizations Target") {
                        HStack {
                            Text("Number of organizations").font(.custom("OpenSans-Regular", size: 14))
                            Spacer()
                            TextField("3", text: $targetCount).keyboardType(.numberPad).frame(width: 60).multilineTextAlignment(.trailing)
                        }
                    }
                }
                if goalType == .amount || goalType == .both {
                    Section("Amount Target") {
                        HStack {
                            Text("$").foregroundStyle(AmenTheme.Colors.textSecondary)
                            TextField("500", text: $targetAmount).keyboardType(.numberPad)
                        }
                    }
                }
                Section("Schedule") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(GoalFrequency.allCases, id: \.self) { f in Text(f.displayName).tag(f) }
                    }
                    Picker("Reminders", selection: $reminderFrequency) {
                        ForEach(ReminderFrequency.allCases, id: \.self) { r in Text(r.displayName).tag(r) }
                    }
                }
                Section {
                    Button { showOrgPicker = true } label: {
                        HStack {
                            Text("Add organizations (\(selectedOrgs.count))")
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(Color(red: 0.10, green: 0.60, blue: 0.56))
                            Spacer()
                            Image(systemName: "plus.circle.fill").foregroundStyle(Color(red: 0.10, green: 0.60, blue: 0.56))
                        }
                    }
                    .accessibilityLabel("Add organizations, \(selectedOrgs.count) selected")
                }
            }
            .navigationTitle("New Giving Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.font(.custom("OpenSans-Regular", size: 16))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isCreating ? "Creating..." : "Create") {
                        Task { await createGoal() }
                    }
                    .font(.custom("OpenSans-Bold", size: 15))
                    .disabled(!canCreate || isCreating)
                }
            }
            .sheet(isPresented: $showOrgPicker) {
                OrganizationPickerView(selected: Binding(
                    get: { selectedOrgs.first },
                    set: { if let o = $0, !selectedOrgs.contains(where: { $0.id == o.id }) { selectedOrgs.append(o) } }
                ))
            }
        }
    }

    private func createGoal() async {
        isCreating = true
        defer { isCreating = false }
        try? await service.createGoal(
            title: title,
            targetAmount: (goalType == .amount || goalType == .both) ? (Int(targetAmount).map { $0 * 100 }) : nil,
            targetCount: (goalType == .count || goalType == .both) ? Int(targetCount) : nil,
            organizations: selectedOrgs.compactMap { $0.id },
            frequency: frequency,
            reminderFrequency: reminderFrequency
        )
        dismiss()
    }
}
