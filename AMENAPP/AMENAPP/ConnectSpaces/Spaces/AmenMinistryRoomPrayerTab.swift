// AMENAPP/AMENAPP/ConnectSpaces/Spaces/AmenMinistryRoomPrayerTab.swift
// AMEN Connect + Spaces — Ministry Room Prayer Board
// Built 2026-06-02

import SwiftUI
import FirebaseAnalytics
import FirebaseAuth

// MARK: - ViewModel

@MainActor
final class AmenMinistryRoomPrayerViewModel: ObservableObject {
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
        // filtered by kind == .prayer from Firestore.
        do {
            // Intentional stub: no network call yet; returns empty array.
            let fetched: [AmenConnectSpacesDerivedItem] = []
            items = fetched
        }
        isLoading = false
    }

    func markAnswered(item: AmenConnectSpacesDerivedItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items[idx]
        updated.status = .done
        items[idx] = updated
    }
}

// MARK: - Prayer Card

private struct AmenPrayerCard: View {
    let item: AmenConnectSpacesDerivedItem
    let onMarkAnswered: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var statusColor: Color {
        switch item.status {
        case .done:       return Color(hex: "D9A441")
        case .open:       return Color(hex: "6E4BB5")
        case .inProgress: return Color(hex: "245B8F")
        case .waiting:    return Color.white.opacity(0.55)
        case .archived:   return Color.white.opacity(0.30)
        }
    }

    private var statusLabel: String {
        switch item.status {
        case .done:       return "Answered"
        case .open:       return "Active"
        case .inProgress: return "In Prayer"
        case .waiting:    return "Waiting"
        case .archived:   return "Archived"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title row
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "hands.sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .fixedSize(horizontal: false, vertical: true)

                    if let owner = item.owner {
                        Text(owner)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }

                Spacer()

                // Status badge
                Text(statusLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(statusColor.opacity(0.15))
                            .overlay(
                                Capsule()
                                    .strokeBorder(statusColor.opacity(0.35), lineWidth: 1)
                            )
                    )
                    .accessibilityLabel("Status: \(statusLabel)")
            }

            // Gold private praying count — no public vanity metric
            HStack(spacing: 5) {
                Image(systemName: "flame")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .accessibilityHidden(true)
                Text("3 praying")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
            }
            .accessibilityLabel("3 people are praying for this request")

            // Mark as answered button (only shown for non-done items)
            if item.status != .done {
                Button {
                    let anim: Animation = reduceMotion
                        ? .easeInOut(duration: 0.01)
                        : .easeInOut(duration: 0.22)
                    withAnimation(anim) {
                        onMarkAnswered()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Mark as answered")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "6E4BB5"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color(hex: "6E4BB5").opacity(0.12))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color(hex: "6E4BB5").opacity(0.30), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark \(item.title) as answered")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prayer request: \(item.title). Status: \(statusLabel).")
    }
}

// MARK: - Empty State

private struct AmenPrayerEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "candle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color(hex: "D9A441").opacity(0.7))
                .accessibilityHidden(true)
            Text("No prayer requests yet.\nShare one in Chat.")
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No prayer requests yet. Share one in Chat.")
    }
}

// MARK: - Main View

struct AmenMinistryRoomPrayerTab: View {
    let spaceId: String

    @StateObject private var vm: AmenMinistryRoomPrayerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(spaceId: String) {
        self.spaceId = spaceId
        _vm = StateObject(wrappedValue: AmenMinistryRoomPrayerViewModel(spaceId: spaceId))
    }

    var body: some View {
        VStack(spacing: 0) {
            if vm.isLoading {
                loadingView
            } else if vm.items.isEmpty {
                AmenPrayerEmptyState()
                    .background(Color(hex: "070607"))
            } else {
                itemList
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
            Analytics.logEvent("ministry_room_prayer_viewed", parameters: [
                "space_id": spaceId
            ])
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color(hex: "D9A441"))
            Text("Loading prayer board…")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "070607"))
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(vm.items) { item in
                    AmenPrayerCard(item: item) {
                        vm.markAnswered(item: item)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(hex: "070607"))
    }
}
