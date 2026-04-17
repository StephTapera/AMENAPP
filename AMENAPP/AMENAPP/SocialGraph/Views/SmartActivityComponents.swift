// SmartActivityComponents.swift
// AMENAPP
//
// Shared UI components for the Smart Activity Layer:
// SmartActivityFilterBar, SmartSearchBar, SmartUserRowSkeleton,
// SmartActivityDigestView (summary banner at top of list).

import SwiftUI

// MARK: - SmartActivityFilterBar

struct SmartActivityFilterBar: View {
    @Binding var activeFilter: SocialGraphFilter
    @Binding var sortMode: SocialGraphSortMode
    var showSortMenu: Bool = true

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SocialGraphFilter.allCases) { filter in
                    SmartActivityFilterChip(
                        label: filter.rawValue,
                        systemImage: filter.systemImage,
                        isSelected: activeFilter == filter
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            activeFilter = filter
                        }
                    }
                }

                if showSortMenu {
                    Divider()
                        .frame(height: 20)
                        .padding(.horizontal, 2)

                    Menu {
                        ForEach(SocialGraphSortMode.allCases) { mode in
                            Button {
                                sortMode = mode
                            } label: {
                                Label(mode.rawValue, systemImage: sortMode == mode ? "checkmark" : "")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 11, weight: .semibold))
                            Text(sortMode.rawValue)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.secondary.opacity(0.1)))
                    }
                    .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - FilterChip

private struct SmartActivityFilterChip: View {
    let label: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.blue : Color.secondary.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - SmartSearchBar

struct SmartSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search"

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 15))

            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .focused($isFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - SmartUserRowSkeleton

struct SmartUserRowSkeleton: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(shimmerGradient)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(shimmerGradient)
                    .frame(width: 120, height: 14)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(shimmerGradient)
                    .frame(width: 80, height: 12)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(shimmerGradient)
                    .frame(width: 140, height: 11)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onAppear { startAnimation() }
    }

    private var shimmerGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.secondary.opacity(0.08),
                Color.secondary.opacity(0.18),
                Color.secondary.opacity(0.08),
            ]),
            startPoint: UnitPoint(x: phase - 1, y: 0.5),
            endPoint: UnitPoint(x: phase, y: 0.5)
        )
    }

    private func startAnimation() {
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            phase = 2
        }
    }
}

// MARK: - SmartActivityDigestView

/// Top-of-list banner summarizing unseen activity counts across the list.
struct SmartActivityDigestView: View {
    let rows: [SmartUserRowViewModel]

    private var unseenCount: Int {
        rows.filter { $0.activityState.hasUnseen }.count
    }
    private var activeCount: Int {
        rows.filter { $0.activityState.isActive }.count
    }

    var body: some View {
        if unseenCount > 0 || activeCount > 0 {
            HStack(spacing: 16) {
                if unseenCount > 0 {
                    digestStat(
                        value: "\(unseenCount)",
                        label: unseenCount == 1 ? "new update" : "new updates",
                        systemImage: "circle.badge.fill",
                        color: .blue
                    )
                }

                if activeCount > 0 {
                    digestStat(
                        value: "\(activeCount)",
                        label: activeCount == 1 ? "active recently" : "active recently",
                        systemImage: "bolt.fill",
                        color: .orange
                    )
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.blue.opacity(0.05))
        }
    }

    private func digestStat(value: String, label: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text("\(value) \(label)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}
