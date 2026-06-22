// GlassTabBar.swift
// AMENAPP — Shared/DesignSystem
//
// Root-level glass navigation bar. Used as control chrome only — never on reading surfaces.

import SwiftUI

// MARK: - Tab Definition

enum AmenTab: Int, CaseIterable {
    case home, messages, spaces, churchNotes, profile

    var label: String {
        switch self {
        case .home:        return "Home"
        case .messages:    return "Messages"
        case .spaces:      return "Spaces"
        case .churchNotes: return "Notes"
        case .profile:     return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home:        return "house"
        case .messages:    return "bubble.left.and.bubble.right"
        case .spaces:      return "rectangle.3.group"
        case .churchNotes: return "note.text"
        case .profile:     return "person.circle"
        }
    }

    var selectedIcon: String { "\(icon).fill" }
}

// MARK: - Glass Tab Bar

struct GlassTabBar: View {
    @Binding var selectedTab: AmenTab
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AmenTab.allCases, id: \.rawValue) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .background {
            Group {
                if reduceTransparency {
                    Color(.systemBackground).opacity(0.97)
                } else {
                    Rectangle().fill(.regularMaterial)
                }
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(contrast == .increased ? 0.0 : 0.12))
                    .frame(height: 0.5)
            }
        }
        .overlay(alignment: .top) {
            Divider().opacity(contrast == .increased ? 1.0 : 0.25)
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: AmenTab) -> some View {
        let isSelected = selectedTab == tab
        Button {
            guard selectedTab != tab else { return }
            if reduceMotion {
                selectedTab = tab
            } else {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                    selectedTab = tab
                }
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.systemScaled(22, weight: isSelected ? .semibold : .regular))
                    // PURGED: Color.amenGold → Color.accentColor per C3 design contract
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .scaleEffect(reduceMotion ? 1 : (isSelected ? 1.08 : 1.0))
                    .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7), value: isSelected)

                Text(tab.label)
                    .font(.systemScaled(10, weight: isSelected ? .semibold : .regular))
                    // PURGED: Color.amenGold → Color.accentColor per C3 design contract
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var tab: AmenTab = .home
    VStack {
        Spacer()
        GlassTabBar(selectedTab: $tab)
    }
    .ignoresSafeArea(edges: .bottom)
}
