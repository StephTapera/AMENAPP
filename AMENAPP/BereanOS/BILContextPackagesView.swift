// BILContextPackagesView.swift
// AMENAPP — BI-05 Context Packages

import SwiftUI

struct BILContextPackagesView: View {
    var body: some View {
        List {
            Section("Packages") {
                ForEach(BILWaveOneSamples.packages) { package in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(package.name)
                                .font(.headline)
                            Spacer()
                            Text("v\(package.version)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(package.mode)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Label("\(package.sourceCount) sources", systemImage: "doc.text")
                            Label("\(package.ledgerCount) ledger", systemImage: "list.bullet.rectangle")
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Version rule") {
                Text("Package edits create a new immutable version. Active sessions keep their original version.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Context Packages")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        BILContextPackagesView()
    }
}
