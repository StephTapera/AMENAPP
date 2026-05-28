// GivingHomeViewModel.swift
// AMENAPP
//
// Orchestrates the main giving surface: feed, intent profile, disaster events, requests.

import Foundation
import SwiftUI
import FirebaseAuth

@MainActor
final class GivingHomeViewModel: ObservableObject {

    // MARK: - Published State

    @Published var organizations: [GivingOrganization] = []
    @Published var rankedOrganizations: [GivingOrganization] = []
    @Published var causeBriefs: [CauseBrief] = []
    @Published var activeDisasterEvents: [DisasterEvent] = []
    @Published var benevolenceRequests: [BenevolenceRequest] = []

    @Published var givingProfile: GivingProfile = .empty
    @Published var selectedTab: GivingFeedTab = .vetted

    @Published var isLoading = false
    @Published var hasCompletedIntentFlow = false
    @Published var showIntentFlow = false
    @Published var showOrgDetail: GivingOrganization? = nil
    @Published var showBereanCounsel = false
    @Published var showStewardshipDashboard = false
    @Published var showTaxCenter = false
    @Published var showWhyShownSheet: GivingOrganization? = nil
    @Published var errorMessage: String? = nil

    // MARK: - Dependencies

    private let dataService = NonprofitDataService()
    private let rankingService = GivingRankingService()
    let stewardshipStore: StewardshipLocalStore

    init(stewardshipStore: StewardshipLocalStore? = nil) {
        self.stewardshipStore = stewardshipStore ?? StewardshipLocalStore()
    }

    // MARK: - Lifecycle

    func onAppear() {
        Task { await loadAll() }
    }

    func onIntentFlowCompleted(_ profile: GivingProfile) {
        givingProfile = profile
        hasCompletedIntentFlow = true
        showIntentFlow = false
        Task {
            if let userId = Auth.auth().currentUser?.uid {
                try? await dataService.saveGivingProfile(profile, userId: userId)
            }
            rerank()
        }
    }

    // MARK: - Load

    private func loadAll() async {
        isLoading = true
        errorMessage = nil

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadProfile() }
            group.addTask { await self.loadOrganizations() }
            group.addTask { await self.loadCauseBriefs() }
            group.addTask { await self.loadDisasterEvents() }
            group.addTask { await self.loadRequests() }
        }

        isLoading = false

        if !givingProfile.isComplete {
            showIntentFlow = true
        }
    }

    private func loadProfile() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        if let profile = try? await dataService.fetchGivingProfile(userId: userId) {
            givingProfile = profile
            hasCompletedIntentFlow = profile.isComplete
        }
    }

    private func loadOrganizations() async {
        do {
            let orgs = try await dataService.fetchOrganizations(limit: 60)
            organizations = orgs
            rerank()
        } catch {
            errorMessage = "Unable to load organizations. Please try again."
        }
    }

    private func loadCauseBriefs() async {
        causeBriefs = (try? await dataService.fetchCauseBriefs()) ?? []
    }

    private func loadDisasterEvents() async {
        activeDisasterEvents = (try? await dataService.fetchActiveDisasterEvents()) ?? []
    }

    private func loadRequests() async {
        benevolenceRequests = (try? await dataService.fetchApprovedRequests(limit: 15)) ?? []
    }

    // MARK: - Re-ranking

    func rerank() {
        let disaster = activeDisasterEvents.first
        rankedOrganizations = rankingService.rank(
            organizations: organizations,
            profile: givingProfile,
            disasterEvent: disaster
        )
    }

    // MARK: - Feed Helpers

    var filteredOrgs: [GivingOrganization] {
        rankingService.filter(organizations: rankedOrganizations, for: selectedTab)
    }

    var hasActiveDisaster: Bool {
        !activeDisasterEvents.isEmpty
    }

    var primaryDisaster: DisasterEvent? {
        activeDisasterEvents.first
    }

    var heroScriptureQuote: String {
        guard let cause = givingProfile.causePreferences.first else {
            return "\"Each one should give what he has decided in his heart to give.\" — 2 Cor 9:7"
        }
        switch cause {
        case .fosterCare, .pregnancyWomen:
            return "\"Defend the weak and the fatherless.\" — Psalm 82:3"
        case .persecutedChurch:
            return "\"Remember those in prison as if you were with them.\" — Hebrews 13:3"
        case .homelessness:
            return "\"Share your food with the hungry.\" — Isaiah 58:7"
        case .disasterRelief:
            return "\"He saw him and had compassion.\" — Luke 10:33"
        case .antiTrafficking:
            return "\"Speak up for those who cannot speak.\" — Proverbs 31:8"
        case .prisonMinistry:
            return "\"I was in prison and you came to visit me.\" — Matthew 25:36"
        default:
            return "\"Each one should give what he has decided in his heart to give.\" — 2 Cor 9:7"
        }
    }

    // MARK: - Profile Update

    func updateProfile(_ profile: GivingProfile) {
        givingProfile = profile
        rerank()
        Task {
            if let userId = Auth.auth().currentUser?.uid {
                try? await dataService.saveGivingProfile(profile, userId: userId)
            }
        }
    }
}
