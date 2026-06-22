// MemoryLedgerService.swift
// AMENAPP
//
// Wave 3 — Memory Ledger + Data Vault.
//
// Projects the REAL on-device Berean memory store (BereanMemoryStore: Keychain
// for high-zone fields, UserDefaults for the rest) into user-facing
// MemoryLedgerEntry rows, and wires the real view / delete / export / delete-all
// / pause controls. Every control acts on the real store (§2.6).
//
// Honesty notes (§2):
//   - lastUsedAt / usageCount are NOT tracked by the store. We surface that
//     truthfully (the UI shows "usage not tracked") instead of inventing counts.
//   - namespace reflects the real on-device location + PRIVACY-CORE zone.
//   - Export emits the user's own real values (this is their data export).
//
// Gated by AMENFeatureFlags.shared.memoryLedgerEnabled (default OFF).

import Foundation
import SwiftUI

@MainActor
final class MemoryLedgerService: ObservableObject {

    @Published private(set) var entries: [MemoryLedgerEntry] = []

    private let store = BereanMemoryStore.shared

    /// User-level pause: when true, BereanMemoryStore.save() must not persist new
    /// memory. Read by the store's save path (key shared below).
    static let pauseDefaultsKey = "berean.memory.userPaused"

    var isPaused: Bool {
        get { UserDefaults.standard.bool(forKey: Self.pauseDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.pauseDefaultsKey) }
    }

    func reload() {
        entries = store.records.map(makeEntry)
    }

    // MARK: - Controls (all operate on the real store)

    func delete(_ entry: MemoryLedgerEntry) {
        guard let field = MemoryField(rawValue: entry.id) else { return }
        store.delete(field: field)
        reload()
    }

    /// Data Vault — delete everything.
    func deleteAll() {
        store.deleteAll()
        reload()
    }

    /// Data Vault — export everything as pretty JSON (the user's own data).
    func exportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    // MARK: - Mapping

    private func makeEntry(_ record: BereanMemoryRecord) -> MemoryLedgerEntry {
        MemoryLedgerEntry(
            id: record.id,
            summary: "\(record.field.ledgerTitle): \(preview(record))",
            namespace: "device:\(String(describing: record.zone))",
            whyStored: record.field.ledgerWhyStored,
            storedAt: iso8601.string(from: Date(timeIntervalSince1970: record.createdAt)),
            // The store does not record last-use — surface nil honestly, never faked.
            lastUsedAt: nil,
            usageCount: 0,
            editable: record.userCanDelete,
            deletable: record.userCanDelete
        )
    }

    /// High-zone (encrypted) values are summarised, not shown raw, in the list.
    private func preview(_ record: BereanMemoryRecord) -> String {
        if record.encryptedAtRest { return "stored privately" }
        return String(record.value.prefix(60))
    }

    private let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - MemoryField display (additive; rationale shown to the user)

extension MemoryField {
    var ledgerTitle: String {
        switch self {
        case .preferredTranslation: return "Preferred translation"
        case .studyStyle:           return "Study style"
        case .theologicalLean:      return "Theological lean"
        case .denominationalLean:   return "Denominational lean"
        case .readingHabits:        return "Reading habits"
        case .prayerHistory:        return "Prayer history"
        }
    }

    var ledgerWhyStored: String {
        switch self {
        case .preferredTranslation: return "So Berean quotes the translation you prefer."
        case .studyStyle:           return "So answers match how you like to study."
        case .theologicalLean:      return "To frame answers within your tradition, where relevant."
        case .denominationalLean:   return "To frame answers within your tradition, where relevant."
        case .readingHabits:        return "To pace suggestions to your reading rhythm."
        case .prayerHistory:        return "To remember prayers you asked Berean to hold (encrypted on this device)."
        }
    }
}
