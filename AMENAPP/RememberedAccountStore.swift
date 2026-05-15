// RememberedAccountStore.swift
// AMENAPP
//
// Persists remembered account display hints across app launches.
// Stores non-sensitive data only — no passwords, no raw Firebase tokens.
// Max 5 accounts. Sorted by most-recently active first.

import Foundation
import FirebaseAnalytics

@MainActor
final class RememberedAccountStore: ObservableObject {
    static let shared = RememberedAccountStore()

    private static let storageKey = "amen_remembered_accounts_v1"
    private static let maxAccounts = 5

    @Published private(set) var accounts: [RememberedAccount] = []

    var mostRecentAccount: RememberedAccount? { accounts.first }
    var hasAccounts: Bool { !accounts.isEmpty }

    private init() { load() }

    // MARK: - Write

    func addOrUpdate(_ account: RememberedAccount) {
        var updated = accounts.filter { $0.uid != account.uid }
        var fresh = account
        fresh.isLastActiveAccount = true
        updated.insert(fresh, at: 0)
        accounts = Array(updated.prefix(Self.maxAccounts)).enumerated().map { i, a in
            var m = a
            m.isLastActiveAccount = (i == 0)
            return m
        }
        persist()
        Analytics.logEvent("remembered_account_saved", parameters: nil)
    }

    func clearAccount(uid: String) {
        accounts.removeAll { $0.uid == uid }
        if !accounts.isEmpty {
            accounts[0].isLastActiveAccount = true
        }
        persist()
        Analytics.logEvent("account_card_removed", parameters: nil)
    }

    func clearAll() {
        accounts.removeAll()
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([RememberedAccount].self, from: data) else { return }
        accounts = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
