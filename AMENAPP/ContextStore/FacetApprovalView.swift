// FacetApprovalView.swift
// AMEN Context Intelligence OS - Approval UI

import SwiftUI

struct FacetApprovalView: View {
    @Binding var candidates: [ContextFacet]
    
    var body: some View {
        List(candidates) { candidate in
            VStack(alignment: .leading) {
                Text(candidate.label)
                Text(candidate.value.displaySummary)
                    .foregroundStyle(.secondary)
            }
            .swipeActions {
                Button("Approve") {
                    // Approve facet
                }
                .tint(.green)
                
                Button("Reject") {
                    // Reject facet
                }
                .tint(.red)
            }
        }
    }
}
