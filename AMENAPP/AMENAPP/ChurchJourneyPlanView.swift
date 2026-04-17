// ChurchJourneyPlanView.swift
// AMENAPP
//
// Premium planner UI — church visit planning.
// Feel: modular cards, inline toggles, smart defaults, floating summary capsule.
// Maintains strict visual consistency with AMEN's glass/capsule design language.

import SwiftUI

struct ChurchJourneyPlanView: View {

    @StateObject private var vm: ChurchJourneyPlanViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: ChurchJourneyRouter

    init(church: ChurchEntity, serviceTimeId: String? = nil) {
        _vm = StateObject(wrappedValue: ChurchJourneyPlanViewModel(
            church: church,
            preselectedServiceTimeId: serviceTimeId
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 16) {
                        churchHeaderCard
                        serviceTimePicker
                        if vm.showRoutineSuggestion, let routine = vm.matchingRoutine {
                            routineSuggestionBanner(routine: routine)
                        }
                        optionsCard
                        timingCard
                        saveAsRoutineToggle
                        Spacer(minLength: 120)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .background(Color(.systemBackground))

                floatingBottomCapsule
            }
            .navigationTitle("Plan Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.primary)
                }
            }
            .alert("Something went wrong", isPresented: .constant(vm.error != nil)) {
                Button("OK") { vm.error = nil }
            } message: {
                Text(vm.error ?? "")
            }
            .onChange(of: vm.savedJourneyId) { _, journeyId in
                guard let journeyId else { return }
                dismiss()
                router.navigate(to: .prep(journeyID: journeyId))
            }
        }
    }

    // MARK: - Church Header

    private var churchHeaderCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.columns")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.draft.church.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(vm.draft.church.city + (vm.draft.church.state.map { ", \($0)" } ?? ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Service Time Picker

    private var serviceTimePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Service Time")

            if vm.serviceTimes.isEmpty {
                Text("No service times listed — you can still plan manually.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.serviceTimes) { st in
                            serviceTimeChip(st)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func serviceTimeChip(_ serviceTime: ChurchServiceTime) -> some View {
        let selected = vm.selectedServiceTime?.id == serviceTime.id
        return Button {
            vm.selectedServiceTime = serviceTime
        } label: {
            VStack(spacing: 2) {
                Text(serviceTime.startTime)
                    .font(.subheadline.weight(.semibold))
                if let label = serviceTime.label {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(selected ? Color.primary : Color(.tertiarySystemFill))
            .foregroundStyle(selected ? Color(.systemBackground) : .primary)
            .clipShape(Capsule())
            .accessibilityLabel("\(serviceTime.startTime), \(serviceTime.label ?? "Service")")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
        }
        .buttonStyle(.plain)
    }

    // MARK: - Routine Suggestion Banner

    private func routineSuggestionBanner(routine: ChurchRoutine) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "star.circle.fill")
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
                Text("Your Sunday Routine")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    vm.showRoutineSuggestion = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss routine suggestion")
            }

            Text("You usually attend \(routine.churchNameSnapshot). Use your saved options?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                vm.applyMatchingRoutine()
            } label: {
                Text("Use my usual")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apply saved routine: \(routine.churchNameSnapshot)")
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Options Card

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Morning Plan")

            planOptionRow(
                icon: "cup.and.heat.waves",
                label: "Add a coffee stop",
                accessibilityLabel: "Coffee stop",
                isOn: vm.draft.options.coffeeEnabled
            ) { vm.toggleCoffee() }

            Divider().padding(.leading, 44)

            planOptionRow(
                icon: "music.note",
                label: "Worship prep",
                accessibilityLabel: "Worship preparation",
                isOn: vm.draft.options.worshipPrepEnabled
            ) { vm.toggleWorshipPrep() }

            Divider().padding(.leading, 44)

            planOptionRow(
                icon: "book",
                label: "Scripture prep",
                accessibilityLabel: "Scripture preparation",
                isOn: vm.draft.options.scripturePrepEnabled
            ) { vm.toggleScripturePrep() }

            Divider().padding(.leading, 44)

            planOptionRow(
                icon: "figure.2",
                label: "Going with family",
                accessibilityLabel: "Family mode",
                isOn: vm.draft.options.familyModeEnabled
            ) { vm.toggleFamilyMode() }

            Divider().padding(.leading, 44)

            planOptionRow(
                icon: "note.text",
                label: "Take notes during service",
                accessibilityLabel: "Note-taking mode",
                isOn: vm.draft.options.noteModeEnabled
            ) { vm.draft.options.noteModeEnabled.toggle() }

            Divider().padding(.leading, 44)

            planOptionRow(
                icon: "bubble.left.and.text.bubble.right",
                label: "Reflect after service",
                accessibilityLabel: "Post-service reflection",
                isOn: vm.draft.options.reflectionEnabled
            ) { vm.toggleReflection() }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func planOptionRow(
        icon: String,
        label: String,
        accessibilityLabel: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(isOn ? .primary : .secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? .primary : Color(.tertiaryLabel))
                    .font(.system(size: 20))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Timing Card

    private var timingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Leave Timing")

            Text(vm.departureSummary)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if let leaveIn = ChurchJourneyPlanner.leaveInSummary(timing: vm.computedTiming) {
                Text(leaveIn)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            timingRow(
                label: "Departure",
                date: vm.computedTiming.departureAt,
                icon: "car"
            )

            if vm.draft.options.coffeeEnabled {
                timingRow(
                    label: "Coffee window",
                    date: vm.computedTiming.coffeeWindowStartAt,
                    icon: "cup.and.heat.waves"
                )
            }

            if vm.draft.options.worshipPrepEnabled || vm.draft.options.scripturePrepEnabled {
                timingRow(
                    label: "Prep starts",
                    date: vm.computedTiming.prepStartAt,
                    icon: "book"
                )
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func timingRow(label: String, date: Date?, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let date {
                Text(date, style: .time)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Save as Routine Toggle

    private var saveAsRoutineToggle: some View {
        Toggle(isOn: $vm.draft.saveAsRoutine) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Save as Sunday Routine")
                    .font(.subheadline.weight(.medium))
                Text("AMEN will remember these options for this church.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(SwitchToggleStyle())
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("Save as Sunday Routine")
        .accessibilityHint("AMEN will remember these options for this church")
    }

    // MARK: - Floating Bottom Capsule

    private var floatingBottomCapsule: some View {
        VStack(spacing: 8) {
            Button {
                Task { await vm.saveJourney() }
            } label: {
                HStack {
                    if vm.isSaving {
                        ProgressView()
                            .tint(Color(.systemBackground))
                    } else {
                        Text("Save Plan")
                            .font(.body.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.primary)
                .foregroundStyle(Color(.systemBackground))
                .clipShape(Capsule())
            }
            .disabled(vm.isSaving || vm.selectedServiceTime == nil)
            .accessibilityLabel("Save church visit plan")

            Button {
                dismiss()
            } label: {
                Text("Just Go Without Saving")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Skip saving, close planner")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
        .padding(.top, 12)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.bottom, 2)
    }
}
