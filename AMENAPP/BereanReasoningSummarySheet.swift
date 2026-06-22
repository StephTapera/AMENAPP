//
//  BereanReasoningSummarySheet.swift
//  AMENAPP
//
//  Safe summary sheet for Study Mode categories.
//

import SwiftUI

struct BereanReasoningSummarySheet: View {
    let node: BereanReasoningNode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: node.category.icon)
                        .font(.systemScaled(18, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.7))
                    Text(node.category.title)
                        .font(.systemScaled(18, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Text(node.summary ?? "Berean is preparing this surface.")
                    .font(.systemScaled(14, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .lineSpacing(3)

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color(red: 0.98, green: 0.98, blue: 0.98))
            .navigationTitle("Study Surface")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.systemScaled(15, weight: .semibold))
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }
}
