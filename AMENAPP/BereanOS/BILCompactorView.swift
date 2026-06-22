// BILCompactorView.swift
// AMENAPP — BI-01 Compactor

import SwiftUI

struct BILCompactorView: View {
    @State private var approvalState: BILApprovalState = .autoApproved

    var body: some View {
        List {
            Section("Episode") {
                LabeledContent("Turn range", value: "14-28")
                LabeledContent("Tier ceiling", value: BILTier.tierC.rawValue)
                LabeledContent("Approval", value: approvalState.rawValue)
            }

            Section("Summary structure") {
                ForEach(BILWaveOneSamples.facts) { fact in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(fact.title)
                                .font(.headline)
                            Spacer()
                            Text("\(Int(fact.confidence * 100))%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(fact.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Controls") {
                Button("Approve episode") {
                    approvalState = .approved
                }
                Button("Undo compaction", role: .destructive) {
                    approvalState = .undone
                }
            }
        }
        .navigationTitle("Compactor")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        BILCompactorView()
    }
}
