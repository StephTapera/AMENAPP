// BILWaveOneHubView.swift
// AMENAPP — Berean Intelligence Layer Wave 1

import SwiftUI

struct BILWaveOneHubView: View {
    var body: some View {
        List {
            if BILWaveOneFeatureGate.compactorEnabled {
                NavigationLink {
                    BILCompactorView()
                } label: {
                    row(title: "Compactor", subtitle: "Review memory episodes before they shape Berean.", icon: "rectangle.stack.badge.person.crop")
                }
            }
            if BILWaveOneFeatureGate.ledgerEnabled {
                NavigationLink {
                    BILLedgerView()
                } label: {
                    row(title: "Context Ledger", subtitle: "Inspect beliefs, locks, and provenance.", icon: "list.bullet.rectangle")
                }
            }
            if BILWaveOneFeatureGate.branchingEnabled {
                NavigationLink {
                    BILBranchingView()
                } label: {
                    row(title: "Branches", subtitle: "Fork a thread without rewriting its source path.", icon: "arrow.triangle.branch")
                }
            }
            if BILWaveOneFeatureGate.sourceCardsEnabled {
                NavigationLink {
                    BILSourceCardsView()
                } label: {
                    row(title: "Source Cards", subtitle: "Ground answers in summarized sources and citations.", icon: "doc.text.magnifyingglass")
                }
            }
            if BILWaveOneFeatureGate.contextPackagesEnabled {
                NavigationLink {
                    BILContextPackagesView()
                } label: {
                    row(title: "Context Packages", subtitle: "Launch reusable Berean context bundles.", icon: "shippingbox")
                }
            }
        }
        .navigationTitle("Berean Intelligence")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(title: String, subtitle: String, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack {
        BILWaveOneHubView()
    }
}
