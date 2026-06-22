//
//  NotificationActivityTabs.swift
//  AMENAPP
//
//  Primary activity category tabs for the Notifications screen.
//  Provides a top-level segmented control that groups notifications
//  by activity type, sitting above the existing filter pills.
//

import SwiftUI

// MARK: - Activity Tab Enum

enum NotificationActivityTab: String, CaseIterable {
    case all       = "All"
    case follows   = "Follows"
    case mentions  = "Mentions"
    case replies   = "Replies"

    var icon: String {
        switch self {
        case .all:       return "bell.fill"
        case .follows:   return "person.2.fill"
        case .mentions:  return "at"
        case .replies:   return "bubble.left.and.bubble.right.fill"
        }
    }
}

// MARK: - Activity Tabs View

struct NotificationActivityTabs: View {
    @Binding var selectedTab: NotificationActivityTab
    @Namespace private var tabAnimation

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NotificationActivityTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func tabButton(_ tab: NotificationActivityTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(Motion.adaptive(.spring(response: 0.30, dampingFraction: 0.78))) {
                selectedTab = tab
            }
            HapticManager.impact(style: .light)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.systemScaled(12, weight: .semibold))

                Text(tab.rawValue)
                    .font(AMENFont.semiBold(13))
            }
            .foregroundStyle(isSelected ? .black : .black.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.90))
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                        .matchedGeometryEffect(id: "activityTab", in: tabAnimation)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
