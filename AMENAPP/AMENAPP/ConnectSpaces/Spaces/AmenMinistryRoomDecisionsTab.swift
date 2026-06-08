// AMENAPP/AMENAPP/ConnectSpaces/Spaces/AmenMinistryRoomDecisionsTab.swift
// AMEN Connect + Spaces — Ministry Room Decisions Log
// Built 2026-06-02

import SwiftUI
import FirebaseAnalytics
import FirebaseAuth

// MARK: - ViewModel

@MainActor
final class AmenMinistryRoomDecisionsViewModel: ObservableObject {
    @Published var items: [AmenConnectSpacesDerivedItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let spaceId: String

    init(spaceId: String) {
        self.spaceId = spaceId
    }

    func load() async {
        guard !spaceId.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        // Stub: callable returns empty — real implementation would call
        // AmenConnectSpacesCallableProxy.shared to fetch derived items
        // filtered by kind == .decision from Firestore.
        let fetched: [AmenConnectSpacesDerivedItem] = []
        items = fetched
        isLoading = false
    }
}

// MARK: - Date Formatter

private let decisionDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f
}()

// MARK: - Decision Card

private struct AmenDecisionCard: View {
    let item: AmenConnectSpacesDerivedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: title + badge
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .fixedSize(horizontal: false, vertical: true)

                    if let owner = item.owner {
                        Text(owner)
                            .font(.systemScaled(12))
                            .foregroundStyle(Color.white.opacity(0.50))
                    }
                }

                Spacer()

                // Purple "Decision made" badge
                Text("Decision made")
                    .font(.systemScaled(11, weight: .bold))
                    .foregroundStyle(Color(hex: "6E4BB5"))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(hex: "6E4BB5").opacity(0.15))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color(hex: "6E4BB5").opacity(0.35), lineWidth: 1)
                            )
                    )
                    .accessibilityLabel("Decision made")
            }

            Divider()
                .background(Color.white.opacity(0.08))

            // Date made
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.systemScaled(11))
                    .foregroundStyle(Color(hex: "D9A441").opacity(0.70))
                    .accessibilityHidden(true)
                Text("Made \(decisionDateFormatter.string(from: item.createdAt))")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(Color(hex: "D9A441").opacity(0.80))
            }
            .accessibilityLabel("Made on \(decisionDateFormatter.string(from: item.createdAt))")

            // Source message snippet
            HStack(spacing: 6) {
                Image(systemName: "quote.opening")
                    .font(.systemScaled(11))
                    .foregroundStyle(Color.white.opacity(0.30))
                    .accessibilityHidden(true)
                Text("From conversation thread")
                    .font(.systemScaled(12))
                    .foregroundStyle(Color.white.opacity(0.40))
                    .italic()
            }
            .accessibilityLabel("Source: From conversation thread")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(hex: "6E4BB5").opacity(0.18), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Decision: \(item.title). \(item.owner.map { "Owner: \($0)." } ?? "") Made \(decisionDateFormatter.string(from: item.createdAt)).")
    }
}

// MARK: - Empty State

private struct AmenDecisionsEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "scale.3d")
                .font(.systemScaled(36, weight: .light))
                .foregroundStyle(Color(hex: "D9A441").opacity(0.7))
                .accessibilityHidden(true)
            Text("No decisions logged yet.")
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No decisions logged yet.")
    }
}

// MARK: - Main View

struct AmenMinistryRoomDecisionsTab: View {
    let spaceId: String

    @StateObject private var vm: AmenMinistryRoomDecisionsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(spaceId: String) {
        self.spaceId = spaceId
        _vm = StateObject(wrappedValue: AmenMinistryRoomDecisionsViewModel(spaceId: spaceId))
    }

    var body: some View {
        VStack(spacing: 0) {
            if vm.isLoading {
                loadingView
            } else if vm.items.isEmpty {
                AmenDecisionsEmptyState()
                    .background(Color(hex: "070607"))
            } else {
                decisionList
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .accessibilityLabel("Error: \(error)")
            }
        }
        .background(Color(hex: "070607"))
        .task { await vm.load() }
        .onAppear {
            Analytics.logEvent("ministry_room_decisions_tab_viewed", parameters: nil)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color(hex: "D9A441"))
            Text("Loading decisions…")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "070607"))
    }

    private var decisionList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(vm.items) { item in
                    AmenDecisionCard(item: item)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(hex: "070607"))
    }
}
