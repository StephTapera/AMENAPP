// BereanMemoryScope.swift
// AMEN Berean — Memory scope controls.
// Users choose how much context Berean retains:
// Off / This Chat / This Project / All Berean
//
// BereanMemoryScopeStore — @ObservableObject singleton, persisted via UserDefaults.
// BereanMemoryScopeSheet — full settings sheet (present as .sheet).
// BereanMemoryScopeChip  — compact pill for the chat composer toolbar.

import SwiftUI
import Combine

// MARK: - Scope Model

enum BereanMemoryScope: String, CaseIterable, Codable {
    case off          = "off"
    case thisChat     = "this_chat"
    case thisProject  = "this_project"
    case allBerean    = "all_berean"

    var label: String {
        switch self {
        case .off:          return "Off"
        case .thisChat:     return "This Chat"
        case .thisProject:  return "This Project"
        case .allBerean:    return "All Berean"
        }
    }

    var icon: String {
        switch self {
        case .off:          return "xmark.circle"
        case .thisChat:     return "bubble.left.and.bubble.right"
        case .thisProject:  return "folder"
        case .allBerean:    return "brain"
        }
    }

    var description: String {
        switch self {
        case .off:          return "Berean won't remember anything from this session"
        case .thisChat:     return "Context limited to the current conversation only"
        case .thisProject:  return "Uses memory from this project's chats and notes"
        case .allBerean:    return "Full context from all your Berean history and projects"
        }
    }

    var accent: Color {
        switch self {
        case .off:          return Color(white: 0.55)
        case .thisChat:     return Color(red: 0.30, green: 0.45, blue: 0.75)
        case .thisProject:  return Color(red: 0.25, green: 0.55, blue: 0.40)
        case .allBerean:    return Color(red: 0.45, green: 0.25, blue: 0.85)
        }
    }
}

// MARK: - Store

final class BereanMemoryScopeStore: ObservableObject {
    static let shared = BereanMemoryScopeStore()

    @Published var scope: BereanMemoryScope = .thisChat {
        didSet { UserDefaults.standard.set(scope.rawValue, forKey: "berean_memory_scope_v1") }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "berean_memory_scope_v1") ?? BereanMemoryScope.thisChat.rawValue
        scope = BereanMemoryScope(rawValue: saved) ?? .thisChat
    }
}

// MARK: - BereanMemoryScopeSheet

struct BereanMemoryScopeSheet: View {
    @ObservedObject private var store = BereanMemoryScopeStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.975, green: 0.975, blue: 0.975).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Blurb
                    Text("Control how much Berean remembers about you and your conversations.")
                        .font(.systemScaled(14))
                        .foregroundStyle(Color(white: 0.52))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 14).padding(.bottom, 22)

                    VStack(spacing: 0) {
                        ForEach(Array(BereanMemoryScope.allCases.enumerated()), id: \.element.rawValue) { idx, scopeOption in
                            scopeRow(scopeOption)
                            if idx < BereanMemoryScope.allCases.count - 1 {
                                Divider().padding(.leading, 62)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color(white: 0, opacity: 0.06), lineWidth: 0.5))
                    )
                    .padding(.horizontal, 16)

                    Spacer()
                }
            }
            .navigationTitle("Memory Scope")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.font(.systemScaled(15, weight: .semibold))
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    @ViewBuilder
    private func scopeRow(_ scopeOption: BereanMemoryScope) -> some View {
        let isSelected = store.scope == scopeOption
        let accent = scopeOption.accent

        Button {
            withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.80))) {
                store.scope = scopeOption
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: scopeOption.icon)
                    .font(.systemScaled(16, weight: .medium))
                    .foregroundStyle(isSelected ? accent : Color(white: 0.52))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(scopeOption.label)
                        .font(.systemScaled(15, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(Color(white: 0.10))
                    Text(scopeOption.description)
                        .font(.systemScaled(12))
                        .foregroundStyle(Color(white: 0.50))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(isSelected ? accent.opacity(0.04) : Color.clear)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - BereanMemoryScopeChip

/// Compact inline chip showing active scope. Taps open BereanMemoryScopeSheet.
struct BereanMemoryScopeChip: View {
    @ObservedObject private var store = BereanMemoryScopeStore.shared
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            HStack(spacing: 4) {
                Image(systemName: store.scope.icon)
                    .font(.systemScaled(10, weight: .medium))
                Text(store.scope.label)
                    .font(.systemScaled(12, weight: .medium))
            }
            .foregroundStyle(store.scope.accent)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(store.scope.accent.opacity(0.10))
                    .overlay(Capsule().strokeBorder(store.scope.accent.opacity(0.18), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) { BereanMemoryScopeSheet() }
    }
}
