// TrustLedgerSettingsView.swift
// AMENAPP — Trust OS
//
// Settings surface showing the user's Trust Passport badge
// and a chronological log of safety ledger events.

import SwiftUI
import FirebaseAuth

struct TrustLedgerSettingsView: View {

    @StateObject private var ledgerService  = TrustLedgerService.shared
    @StateObject private var passportService = TrustPassportService.shared

    var body: some View {
        List {
            // MARK: Passport Badge
            Section {
                HStack(spacing: 12) {
                    Image(systemName: passportService.verificationBadge)
                        .font(.title2)
                        .foregroundStyle(.blue)
                    Text("Trust Level: \(passportService.currentLevel.rawValue.capitalized)")
                        .font(.headline)
                }
                .padding(.vertical, 4)
            }

            // MARK: Safety History
            Section("Safety History") {
                if ledgerService.recentEntries.isEmpty {
                    Text("No safety events recorded yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(ledgerService.recentEntries, id: \.createdAt) { entry in
                        LedgerEntryRow(entry: entry)
                    }
                }
            }
        }
        .navigationTitle("Your Safety History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            await ledgerService.fetchRecentEntries(uid: uid, limit: 50)
            await passportService.fetchCurrentLevel(uid: uid)
        }
    }
}

// MARK: - Row

private struct LedgerEntryRow: View {
    let entry: TrustLedgerEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.action)
                    .font(.headline)
                Text(entry.whatChanged)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: entry.reversible ? "checkmark.shield" : "shield.slash")
                .foregroundStyle(entry.reversible ? .green : .red)
                .accessibilityLabel(entry.reversible ? "Reversible action" : "Permanent action")
        }
        .padding(.vertical, 2)
    }
}
