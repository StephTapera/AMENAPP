// BILBranchingView.swift
// AMENAPP — BI-03 Conversation Branching

import SwiftUI

struct BILBranchingView: View {
    var body: some View {
        List {
            Section("Branches") {
                ForEach(BILWaveOneSamples.branches) { branch in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(branch.name)
                                .font(.headline)
                            Spacer()
                            Text(branch.forkTurn)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(branch.divergenceSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Merge rule") {
                Text("Merging creates a synthesis episode on the destination branch. Source branches are never rewritten.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Branches")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        BILBranchingView()
    }
}
