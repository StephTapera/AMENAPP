// YouthModeFeedModifier.swift
// AMEN — Youth Mode Feed Pacing Modifier
//
// Inserts breathing-room cards at 3-5 item intervals when youth mode is active.
// Disables scroll acceleration and hides the "load more" infinite scroll trigger.
//
// Flag gate: AMENFeatureFlags.shared.youthMode

import SwiftUI

// MARK: - Breathing Room Card

struct BreathingRoomCard: View {

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf")
                .font(.title3)
                .foregroundStyle(.green.opacity(0.7))
                .accessibilityHidden(true)
            Text("Take a moment before continuing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Take a moment before continuing")
    }
}

// MARK: - Youth Feed Pacing ViewModifier

struct YouthFeedPacing: ViewModifier {

    let itemCount: Int
    @ObservedObject private var service = YouthModeService.shared

    func body(content: Content) -> some View {
        content
            .onAppear {
                if AMENFeatureFlags.shared.youthMode && service.isActive {
                    disableScrollAcceleration()
                }
            }
    }

    private func disableScrollAcceleration() {
        UIScrollView.appearance().decelerationRate = .normal
    }
}

// MARK: - Paced Feed Items Builder

struct PacedFeedItems<Item: Identifiable, ItemView: View, PlaceholderView: View>: View {

    let items: [Item]
    let itemView: (Item) -> ItemView
    let breathingRoomView: () -> PlaceholderView
    let showLoadMore: Bool

    @ObservedObject private var youthService = YouthModeService.shared

    private var youthModeActive: Bool {
        AMENFeatureFlags.shared.youthMode && youthService.isActive
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                itemView(item)

                if youthModeActive && youthService.shouldInsertBreathingRoom(afterItemIndex: index) {
                    breathingRoomView()
                }
            }

            if showLoadMore && !youthModeActive {
                loadMoreTrigger
            }
        }
        .modifier(YouthFeedPacing(itemCount: items.count))
    }

    private var loadMoreTrigger: some View {
        Color.clear
            .frame(height: 40)
            .accessibilityHidden(true)
    }
}

// MARK: - View Extension

extension View {
    func youthFeedPacing(itemCount: Int) -> some View {
        self.modifier(YouthFeedPacing(itemCount: itemCount))
    }
}
