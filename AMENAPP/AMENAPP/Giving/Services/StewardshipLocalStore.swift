// StewardshipLocalStore.swift
// AMENAPP
//
// Privacy-first on-device stewardship storage.
// Income data is NEVER sent to any server. Stored encrypted using Keychain.
// All financial reflection stays local. Only giving session metadata lives in Firestore.

import Foundation
import Security

// MARK: - Stewardship Snapshot (on-device only)

struct StewardshipSnapshot: Codable {
    var monthlyIncomeEstimate: Int?      // cents, Keychain-only, never synced
    var tithingTargetPercent: Double?    // e.g. 0.10 = 10%, Keychain-only
    var notes: String?
    var updatedAt: Date

    var tithingTargetAmount: Int? {
        guard let income = monthlyIncomeEstimate, let pct = tithingTargetPercent else { return nil }
        return Int(Double(income) * pct)
    }

    var tithingTargetFormatted: String? {
        guard let amount = tithingTargetAmount else { return nil }
        let dollars = amount / 100
        return "$\(dollars)/month"
    }

    static var empty: StewardshipSnapshot {
        StewardshipSnapshot(updatedAt: Date())
    }
}

// MARK: - Store

@MainActor
final class StewardshipLocalStore: ObservableObject {

    @Published private(set) var snapshot: StewardshipSnapshot = .empty
    @Published private(set) var journalEntries: [GivingJournalEntry] = []
    @Published private(set) var receipts: [GivingReceipt] = []

    private let keychainKey = "amen.stewardship.snapshot.v1"
    private let journalKey = "amen.giving.journal.v1"
    private let receiptsKey = "amen.giving.receipts.v1"

    init() {
        loadSnapshot()
        loadJournal()
        loadReceipts()
    }

    // MARK: - Stewardship Snapshot (Keychain)

    func saveIncomeEstimate(_ cents: Int?) {
        snapshot.monthlyIncomeEstimate = cents
        snapshot.updatedAt = Date()
        persistSnapshot()
    }

    func saveTithingTarget(_ percent: Double?) {
        snapshot.tithingTargetPercent = percent
        snapshot.updatedAt = Date()
        persistSnapshot()
    }

    func saveNotes(_ notes: String?) {
        snapshot.notes = notes
        snapshot.updatedAt = Date()
        persistSnapshot()
    }

    private func persistSnapshot() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        saveToKeychain(key: keychainKey, data: data)
    }

    private func loadSnapshot() {
        guard let data = loadFromKeychain(key: keychainKey),
              let saved = try? JSONDecoder().decode(StewardshipSnapshot.self, from: data) else { return }
        snapshot = saved
    }

    // MARK: - Journal (UserDefaults — no PII)

    func addJournalEntry(_ entry: GivingJournalEntry) {
        journalEntries.insert(entry, at: 0)
        persistJournal()
    }

    func updateJournalEntry(_ entry: GivingJournalEntry) {
        guard let idx = journalEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        journalEntries[idx] = entry
        persistJournal()
    }

    func deleteJournalEntry(id: String) {
        journalEntries.removeAll { $0.id == id }
        persistJournal()
    }

    private func persistJournal() {
        guard let data = try? JSONEncoder().encode(journalEntries) else { return }
        UserDefaults.standard.set(data, forKey: journalKey)
    }

    private func loadJournal() {
        guard let data = UserDefaults.standard.data(forKey: journalKey),
              let saved = try? JSONDecoder().decode([GivingJournalEntry].self, from: data) else { return }
        journalEntries = saved
    }

    // MARK: - Receipts (UserDefaults — no income data)

    func addReceipt(_ receipt: GivingReceipt) {
        receipts.insert(receipt, at: 0)
        persistReceipts()
    }

    func receipts(forYear year: Int) -> [GivingReceipt] {
        receipts.filter { $0.taxYear == year }
    }

    private func persistReceipts() {
        guard let data = try? JSONEncoder().encode(receipts) else { return }
        UserDefaults.standard.set(data, forKey: receiptsKey)
    }

    private func loadReceipts() {
        guard let data = UserDefaults.standard.data(forKey: receiptsKey),
              let saved = try? JSONDecoder().decode([GivingReceipt].self, from: data) else { return }
        receipts = saved
    }

    // MARK: - Computed Aggregates (local only)

    func totalGiving(forYear year: Int) -> Int {
        receipts(forYear: year).reduce(0) { $0 + $1.amount }
    }

    // MARK: - Keychain Helpers

    private func saveToKeychain(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
}
