// HealthProviderAdapter.swift — AMEN IntegrationOS
// HealthKit adapter conforming to ProviderAdapter.

import Foundation
import HealthKit

final class HealthKitAdapter: ProviderAdapter {
    let providerId = "healthkit"
    let capabilities: ProviderCapabilitySet = [.health]
    let costClass: ProviderCostClass = .free

    private let store = HKHealthStore()
    private var authorizedTypes: Set<HKSampleType> = []

    var hkStore: HKHealthStore { store }

    func authorize(scopes: [ConsentScope]) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw IntegrationOSError.providerUnavailable(providerId)
        }
        let readTypes = scopesToHKTypes(scopes)
        guard !readTypes.isEmpty else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        authorizedTypes = readTypes
    }

    func refresh() async throws {
        // HealthKit doesn't provide a way to bulk-check; re-request is idempotent.
    }

    func revoke() async throws {
        authorizedTypes = []
    }

    func fetch(request: ProviderRequest) async throws -> ProviderResponse {
        return ProviderResponse(providerId: providerId, payload: [:], statusCode: 200)
    }

    func normalize(payload: ProviderResponse) throws -> ExternalUniversalObject {
        ExternalUniversalObject(
            id: UUID().uuidString,
            sourceProviderId: providerId,
            type: .healthMetric,
            title: "Health Metric",
            subtitle: nil,
            metadata: [:],
            fetchedAt: Date()
        )
    }

    func health() async -> ProviderHealthStatus {
        HKHealthStore.isHealthDataAvailable() ? .healthy : .unavailable
    }

    // MARK: - Helpers

    private func scopesToHKTypes(_ scopes: [ConsentScope]) -> Set<HKSampleType> {
        var types: Set<HKSampleType> = []
        for scope in scopes {
            switch scope {
            case .healthWalkingSteps:
                if let t = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(t) }
            case .healthSleepData:
                if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(t) }
            case .healthWorkouts:
                types.insert(HKObjectType.workoutType())
            default: break
            }
        }
        return types
    }

    // MARK: - Typed Queries

    func fetchSteps(for date: Date) async -> Double {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                let count = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: count)
            }
            store.execute(query)
        }
    }
}
