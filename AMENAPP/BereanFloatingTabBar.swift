// BereanFloatingTabBar.swift
// AMEN App — Floating Liquid Glass sub-navigation dock for the Berean surface.
// Sits below the composer and provides four spiritual surface tabs:
// Chat, Notes, Selah, and Explore. Selah mode intentionally slows the UI
// to support contemplation, prayer, and reflection.

import SwiftUI

// MARK: - Surface Tab

enum BereanSurfaceTab: String, CaseIterable, Identifiable {
    case chat    = "Chat"
    case notes   = "Notes"
    case selah   = "Selah"
    case explore = "Explore"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chat:    return "bubble.left.and.bubble.right.fill"
        case .notes:   return "note.text"
        case .selah:   return "moon.stars.fill"
        case .explore: return "books.vertical.fill"
        }
    }

    /// When true, the Berean surface adopts Selah mode: slower transitions,
    /// reduced suggestion density, and scripture-centered layout.
    var isSelahMode: Bool { self == .selah }
}

// MARK: - BereanFloatingTabBar

struct BereanFloatingTabBar: View {
    @Binding var selectedTab: BereanSurfaceTab
    @Namespace private var tabNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BereanSurfaceTab.allCases) { tab in
                tabItem(tab)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(dockBackground)
    }

    // MARK: - Tab item

    @ViewBuilder
    private func tabItem(_ tab: BereanSurfaceTab) -> some View {
        let isSelected = selectedTab == tab
        let springAnimation: Animation = reduceMotion
            ? .linear(duration: 0.1)
            : .spring(response: 0.36, dampingFraction: 0.76)

        Button {
            withAnimation(springAnimation) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.82))
                            .frame(width: 46, height: 28)
                            .shadow(color: Color.black.opacity(0.07), radius: 4, x: 0, y: 1)
                            .matchedGeometryEffect(id: "tabHighlight", in: tabNamespace)
                    }

                    Image(systemName: tab.icon)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .frame(height: 28)
                        .symbolEffect(.bounce, value: isSelected)
                }

                Text(tab.rawValue)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tab.rawValue) tab")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Background

    private var dockBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(.regularMaterial)
            .shadow(color: Color.black.opacity(0.09), radius: 13, x: 0, y: 3)
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.60), lineWidth: 0.5)
            }
    }
}

// MARK: - Selah Mode Modifier

/// Apply to any view inside Berean to adopt Selah's contemplative pacing.
struct BereanSelahModifier: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .animation(
                isActive && !reduceMotion
                    ? .easeInOut(duration: 0.65)
                    : nil,
                value: isActive
            )
            .environment(\.bereanSelahActive, isActive)
    }
}

// MARK: - Environment Key for Selah Mode

struct BereanSelahActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var bereanSelahActive: Bool {
        get { self[BereanSelahActiveKey.self] }
        set { self[BereanSelahActiveKey.self] = newValue }
    }
}

extension View {
    func bereanSelahMode(_ active: Bool) -> some View {
        modifier(BereanSelahModifier(isActive: active))
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var tab: BereanSurfaceTab = .chat

    VStack(spacing: 40) {
        BereanFloatingTabBar(selectedTab: $tab)
            .padding(.horizontal, 16)

        Text("Selected: \(tab.rawValue)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding(.vertical, 40)
    .background(Color(red: 0.96, green: 0.96, blue: 0.94))
}
