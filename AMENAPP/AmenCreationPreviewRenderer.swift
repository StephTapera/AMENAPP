// AmenCreationPreviewRenderer.swift
// AMENAPP
// Preview renderer for Universal Create drafts.

import SwiftUI

struct AmenCreationPreviewRenderer: View {
    let draft: AmenCreationDraft

    var body: some View {
        let node = draft.toContentNode()
        ScrollView {
            AmenContentRenderer(node: node)
                .padding(.horizontal)
                .padding(.top, 12)
        }
        .navigationTitle("Preview")
    }
}
