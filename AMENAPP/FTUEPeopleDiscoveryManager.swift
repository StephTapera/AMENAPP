//
//  FTUEPeopleDiscoveryManager.swift
//  AMENAPP
//
//  Manages the "Find Your People" first-time user experience.
//  Persists completion state and the church/interests data collected
//  during the flow so PeopleDiscoveryView can surface personalized sections.
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - FTUE State Keys

private enum FTUEPeopleKeys {
    static let completed  = "ftue_people_discovery_completed_v1"
    static let churchName = "ftue_people_discovery_churchName"
    static let churchId   = "ftue_people_discovery_churchId"
    static let interests  = "ftue_people_discovery_interests"
}

// MARK: - Manager

@MainActor
final class FTUEPeopleDiscoveryManager: ObservableObject {

    static let shared = FTUEPeopleDiscoveryManager()

    // MARK: - State

    /// Whether the user has already been through the "Find Your People" FTUE.
    @Published private(set) var hasCompleted: Bool = false

    /// Church name typed/selected during the FTUE (cached locally for fast reads).
    @Published private(set) var churchName: String = ""

    /// Matched Firestore church document ID (empty if no match).
    @Published private(set) var churchId: String = ""

    /// Interests selected during the FTUE (superset of onboarding interests).
    @Published private(set) var interests: [String] = []

    // MARK: - Init

    private init() { loadLocalState() }

    // MARK: - Public API

    /// Call when the user finishes the FTUE sheet.
    /// Saves data both locally (UserDefaults) and to Firestore.
    func complete(churchName: String, churchId: String, interests: [String]) async {
        self.churchName = churchName
        self.churchId   = churchId
        self.interests  = interests
        self.hasCompleted = true
        persistLocally()
        await persistToFirestore(churchName: churchName, churchId: churchId, interests: interests)
    }

    /// Mark completed without saving new data (for users who skip).
    func markCompleted() {
        hasCompleted = true
        UserDefaults.standard.set(true, forKey: FTUEPeopleKeys.completed)
    }

    /// Reset — for testing only.
    func reset() {
        hasCompleted = false
        churchName   = ""
        churchId     = ""
        interests    = []
        UserDefaults.standard.removeObject(forKey: FTUEPeopleKeys.completed)
        UserDefaults.standard.removeObject(forKey: FTUEPeopleKeys.churchName)
        UserDefaults.standard.removeObject(forKey: FTUEPeopleKeys.churchId)
        UserDefaults.standard.removeObject(forKey: FTUEPeopleKeys.interests)
    }

    // MARK: - Private

    private func loadLocalState() {
        hasCompleted = UserDefaults.standard.bool(forKey: FTUEPeopleKeys.completed)
        churchName   = UserDefaults.standard.string(forKey: FTUEPeopleKeys.churchName) ?? ""
        churchId     = UserDefaults.standard.string(forKey: FTUEPeopleKeys.churchId)   ?? ""
        interests    = UserDefaults.standard.stringArray(forKey: FTUEPeopleKeys.interests) ?? []
    }

    private func persistLocally() {
        UserDefaults.standard.set(true,       forKey: FTUEPeopleKeys.completed)
        UserDefaults.standard.set(churchName, forKey: FTUEPeopleKeys.churchName)
        UserDefaults.standard.set(churchId,   forKey: FTUEPeopleKeys.churchId)
        UserDefaults.standard.set(interests,  forKey: FTUEPeopleKeys.interests)
    }

    private func persistToFirestore(churchName: String, churchId: String, interests: [String]) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var data: [String: Any] = ["ftue_people_completed": true]
        if !churchName.isEmpty { data["onboardingChurchName"] = churchName }
        if !churchId.isEmpty   { data["onboardingChurchId"]   = churchId  }
        if !interests.isEmpty  { data["discoveryInterests"]   = interests }
        // Merge so we never overwrite other profile fields.
        try? await Firestore.firestore()
            .collection("users").document(uid)
            .setData(data, merge: true)
    }
}
