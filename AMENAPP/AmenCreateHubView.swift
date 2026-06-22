// AmenCreateHubView.swift
// AMENAPP
// Universal Create Hub (Phase 2).

import SwiftUI

struct AmenCreateHubView: View {
    private let intents = AmenCreationIntent.allCases

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Create")
                        .font(AMENFont.bold(24))
                        .padding(.horizontal)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(intents) { intent in
                            NavigationLink(value: intent) {
                                AmenCreateIntentCard(intent: intent)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                AMENAnalyticsService.shared.track(.creationIntentSelected(intent: intent.rawValue))
                            })
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
            }
            .navigationDestination(for: AmenCreationIntent.self) { intent in
                AmenAdaptiveComposerView(intent: intent)
            }
            .onAppear {
                AMENAnalyticsService.shared.track(.createHubOpened)
            }
        }
    }
}

private struct AmenCreateIntentCard: View {
    let intent: AmenCreationIntent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(intent.displayName)
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.primary)

            Text(intent.contentType.displayName)
                .font(.systemScaled(12, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(intent.displayName)
    }
}
