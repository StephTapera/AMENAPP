// ChurchJourneyPlanViewModel.swift
// AMENAPP
//
// Drives ChurchJourneyPlanView. Owns the draft state, timing recomputation,
// routine lookup, and saving the journey via the createChurchJourney CF.

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFunctions

// MARK: - Day mapping helpers

private let dayNameToWeekday: [String: Int] = [
    "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
    "thursday": 5, "friday": 6, "saturday": 7
]

@MainActor
final class ChurchJourneyPlanViewModel: ObservableObject {

    // MARK: - State

    @Published var draft: ChurchJourneyDraft
    @Published var computedTiming: ChurchJourneyTiming = ChurchJourneyTiming()
    @Published var isSaving = false
    @Published var savedJourneyId: String?
    @Published var error: String?

    // Service time picker — uses the existing ChurchServiceTime struct
    @Published var serviceTimes: [ChurchServiceTime] = []
    @Published var selectedServiceTime: ChurchServiceTime? {
        didSet { draft.selectedServiceTime = selectedServiceTime; recomputeTiming() }
    }

    // Route estimate
    @Published var routeEstimateMinutes: Int = 20 {
        didSet { draft.routeEstimateMinutes = routeEstimateMinutes; recomputeTiming() }
    }

    // Routine suggestion
    @Published var matchingRoutine: ChurchRoutine?
    @Published var showRoutineSuggestion = false

    // MARK: - Dependencies

    private let routineService = ChurchRoutineMemoryService.shared
    private let functions = Functions.functions()
    private var church: ChurchEntity { draft.church }

    // MARK: - Init

    init(church: ChurchEntity, preselectedServiceTimeId: String? = nil) {
        self.draft = ChurchJourneyDraft.empty(for: church)
        loadServiceTimes(from: church)
        loadMatchingRoutine(churchId: church.id, serviceTimeId: preselectedServiceTimeId)
    }

    // MARK: - Service times

    private func loadServiceTimes(from church: ChurchEntity) {
        // Map ChurchEntity.ServiceTime → existing ChurchServiceTime struct
        // ChurchServiceTime: dayOfWeek: String, startTime: String, label: String?
        serviceTimes = church.serviceTimes.map { st in
            let dayName = dayName(from: st.dayOfWeek) // Int → "Sunday"
            return ChurchServiceTime(
                dayOfWeek: dayName,
                startTime: st.time,
                label: st.serviceType
            )
        }
        // Pre-select first upcoming service for today's day of week
        let todayName = currentDayName()
        selectedServiceTime = serviceTimes.first(where: { $0.dayOfWeek.lowercased() == todayName })
            ?? serviceTimes.first
    }

    // MARK: - Timing recomputation (instant, local-first)

    func recomputeTiming() {
        guard let serviceTime = selectedServiceTime,
              let serviceDate = nextOccurrence(of: serviceTime) else { return }

        let serviceEnd = serviceDate.addingTimeInterval(75 * 60) // 75 min default
        let inputs = ChurchJourneyPlannerInputs(
            serviceStartAt: serviceDate,
            serviceEndAt: serviceEnd,
            options: draft.options,
            routeEstimateMinutes: routeEstimateMinutes,
            parkingComplexity: "medium",
            quietHoursStart: nil,
            quietHoursEnd: nil
        )
        computedTiming = ChurchJourneyPlanner.computeTiming(from: inputs)
    }

    var departureSummary: String {
        guard let serviceTime = selectedServiceTime,
              let serviceDate = nextOccurrence(of: serviceTime) else {
            return "Select a service time"
        }
        return ChurchJourneyPlanner.departureSummary(timing: computedTiming, serviceStart: serviceDate)
    }

    // MARK: - Options toggles

    func toggleCoffee() { draft.options.coffeeEnabled.toggle(); recomputeTiming() }
    func toggleWorshipPrep() { draft.options.worshipPrepEnabled.toggle(); recomputeTiming() }
    func toggleScripturePrep() { draft.options.scripturePrepEnabled.toggle(); recomputeTiming() }
    func toggleFamilyMode() { draft.options.familyModeEnabled.toggle(); recomputeTiming() }
    func toggleReflection() { draft.options.reflectionEnabled.toggle(); recomputeTiming() }

    // MARK: - Apply saved routine

    func applyMatchingRoutine() {
        guard let routine = matchingRoutine else { return }
        routineService.applyRoutine(routine, to: &draft)
        if let stId = routine.preferredServiceTimeId,
           let match = serviceTimes.first(where: { $0.id == stId }) {
            selectedServiceTime = match
        }
        showRoutineSuggestion = false
        recomputeTiming()
    }

    // MARK: - Save journey

    func saveJourney() async {
        guard let serviceTime = selectedServiceTime,
              let serviceDate = nextOccurrence(of: serviceTime) else {
            error = "Please select a service time."
            return
        }

        isSaving = true
        error = nil

        let serviceEnd = serviceDate.addingTimeInterval(75 * 60)
        let serviceLabel = [serviceTime.label, serviceTime.startTime]
            .compactMap { $0 }.joined(separator: " • ")

        let payload: [String: Any] = [
            "churchId": church.id,
            "serviceTimeId": serviceTime.id,
            "serviceLabelSnapshot": serviceLabel,
            "serviceStartAt": Int(serviceDate.timeIntervalSince1970 * 1000),
            "serviceEndAt": Int(serviceEnd.timeIntervalSince1970 * 1000),
            "options": [
                "coffeeEnabled": draft.options.coffeeEnabled,
                "worshipPrepEnabled": draft.options.worshipPrepEnabled,
                "scripturePrepEnabled": draft.options.scripturePrepEnabled,
                "familyModeEnabled": draft.options.familyModeEnabled,
                "noteModeEnabled": draft.options.noteModeEnabled,
                "reflectionEnabled": draft.options.reflectionEnabled,
            ],
            "usedRoutineId": draft.useRoutineId as Any,
            "routeEstimateMinutes": routeEstimateMinutes,
            "planSource": draft.useRoutineId != nil ? "routine" : "manual",
        ]

        do {
            let result = try await functions.httpsCallable("createChurchJourney").call(payload)
            if let data = result.data as? [String: Any],
               let journeyId = data["journeyId"] as? String {
                savedJourneyId = journeyId
                ChurchJourneyStore.shared.loadJourney(id: journeyId)

                if draft.saveAsRoutine {
                    try? await routineService.saveRoutine(from: draft)
                }
            }
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }

    // MARK: - Helpers

    private func nextOccurrence(of serviceTime: ChurchServiceTime) -> Date? {
        let calendar = Calendar.current
        // Convert "Sunday" → weekday component 1
        guard let targetWeekday = dayNameToWeekday[serviceTime.dayOfWeek.lowercased()] else { return nil }

        // Parse time from e.g. "9:00 AM"
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let timeDate = formatter.date(from: serviceTime.startTime) else { return nil }

        let hour = calendar.component(.hour, from: timeDate)
        let minute = calendar.component(.minute, from: timeDate)
        let today = calendar.component(.weekday, from: Date())

        var daysAhead = (targetWeekday - today + 7) % 7
        if daysAhead == 0 {
            let nowHour = calendar.component(.hour, from: Date())
            let nowMin = calendar.component(.minute, from: Date())
            if hour < nowHour || (hour == nowHour && minute <= nowMin) {
                daysAhead = 7
            }
        }

        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.day = (components.day ?? 0) + daysAhead
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    private func dayName(from weekday: Int) -> String {
        // 1=Sun, 7=Sat  →  "Sunday", "Monday", ...
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let idx = max(0, (weekday - 1) % 7)
        return days[idx]
    }

    private func currentDayName() -> String {
        let weekday = Calendar.current.component(.weekday, from: Date()) // 1=Sun
        return dayName(from: weekday).lowercased()
    }

    private func loadMatchingRoutine(churchId: String, serviceTimeId: String?) {
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let routine = routineService.routine(for: churchId, serviceTimeId: serviceTimeId) {
                self.matchingRoutine = routine
                self.showRoutineSuggestion = true
            }
        }
    }
}
