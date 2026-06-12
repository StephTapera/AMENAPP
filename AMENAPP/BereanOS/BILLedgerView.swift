// BILLedgerView.swift
// AMENAPP — BI-02 Context Ledger

import SwiftUI

struct BILLedgerView: View {
    var body: some View {
        List {
            Section("Ledger entries") {
                ForEach(BILWaveOneSamples.ledger) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.state)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(entry.provenance)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Text(entry.belief)
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Conflict policy") {
                Text("Contradictions create review cards. They never silently overwrite active, pinned, or locked beliefs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Context Ledger")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        BILLedgerView()
    }
}
