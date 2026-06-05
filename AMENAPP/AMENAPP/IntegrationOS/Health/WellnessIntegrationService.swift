// WellnessIntegrationService.swift — AMEN IntegrationOS
// Actor that wraps HKHealthStore via HealthKitAdapter for wellness data.

import Foundation
import HealthKit
import FirebaseRemoteConfig

actor WellnessIntegrationService {
    static let shared = WellnessIntegrationService()
    private init() {}

    private let adapter = HealthKitAdapter()
    private let remoteConfig = RemoteConfig.remoteConfig()
    private var isEnabled: Bool { remoteConfig.configValue(forKey: "integration_health_enabled").booleanValue }

    struct WellnessSummary {
        let date: Date
        let steps: Double
        let activeCalories: Double
        let sleepHours: Double
        let workoutMinutes: Double
    }

    // MARK: - Authorization

    func requestAccess(scopes: [ConsentScope]) async throws {
        guard isEnabled else { return }
        try await adapter.authorize(scopes: scopes)
    }

    // MARK: - Steps

    func steps(for date: Date = Date()) async -> Double {
        guard isEnabled else { return 0 }
        return await adapter.fetchSteps(for: date)
    }

    // MARK: - Summary

    func dailySummary(for date: Date = Date()) async -> WellnessSummary {
        guard isEnabled else {
            return WellnessSummary(date: date, steps: 0, activeCalories: 0, sleepHours: 0, workoutMinutes: 0)
        }
        let steps = await adapter.fetchSteps(for: date)
        let calories = await fetchActiveCalories(for: date)
        let sleep = await fetchSleepHours(for: date)
        let workout = await fetchWorkoutMinutes(for: date)
        return WellnessSummary(
            date: date,
            steps: steps,
            activeCalories: calories,
            sleepHours: sleep,
            workoutMinutes: workout
        )
    }

    // MARK: - Private Fetches

    private func fetchActiveCalories(for date: Date) async -> Double {
        guard let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
        return await fetchSum(type: type, date: date, unit: .kilocalorie())
    }

    private func fetchWorkoutMinutes(for date: Date) async -> Double {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let total = (samples as? [HKWorkout])?.reduce(0) { $0 + $1.duration / 60 } ?? 0
                continuation.resume(returning: total)
            }
            adapter.hkStore.execute(query)
        }
    }

    private func fetchSleepHours(for date: Date) async -> Double {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return 0 }
        let start = Calendar.current.date(byAdding: .hour, value: -10, to: Calendar.current.startOfDay(for: date)) ?? date
        let end = Calendar.current.startOfDay(for: date).addingTimeInterval(3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let total = (samples as? [HKCategorySample])?.reduce(0.0) { acc, s in
                    (s.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                     s.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue) ?
                    acc + s.endDate.timeIntervalSince(s.startDate) / 3600 : acc
                } ?? 0
                continuation.resume(returning: total)
            }
            adapter.hkStore.execute(query)
        }
    }

    private func fetchSum(type: HKQuantityType, date: Date, unit: HKUnit) async -> Double {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                let value = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            adapter.hkStore.execute(query)
        }
    }
}
