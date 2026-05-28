// BereanModesSheet.swift
// AMEN Berean — AI mode selector.
// Adapts Berean's response personality, format, and tone.
// Persisted across sessions via UserDefaults.

import SwiftUI
import Combine

// MARK: - Mode Model

struct BereanModeOption: Identifiable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let chipColor: Color
}

extension BereanModeOption {
    static let catalog: [BereanModeOption] = [
        BereanModeOption(id: "standard",   name: "Standard",           icon: "sparkles",
                   description: "Balanced, clear, helpful answers",
                   chipColor: Color(white: 0.22)),
        BereanModeOption(id: "scripture",  name: "Scripture-Aware",    icon: "book.pages",
                   description: "Grounds every response in scripture",
                   chipColor: Color(red: 0.30, green: 0.30, blue: 0.82)),
        BereanModeOption(id: "prayer",     name: "Prayer Mode",         icon: "hands.sparkles",
                   description: "Reverent, comforting, prayer-first",
                   chipColor: Color(red: 0.55, green: 0.20, blue: 0.85)),
        BereanModeOption(id: "study",      name: "Study Mode",          icon: "graduationcap",
                   description: "Structured, detailed, educational",
                   chipColor: Color(red: 0.12, green: 0.40, blue: 0.75)),
        BereanModeOption(id: "deep",       name: "Deep Thought",        icon: "brain",
                   description: "Slower, nuanced, multi-angle analysis",
                   chipColor: Color(red: 0.20, green: 0.45, blue: 0.65)),
        BereanModeOption(id: "social",     name: "Social Coach",        icon: "person.2",
                   description: "Tactful, practical for social replies",
                   chipColor: Color(red: 0.15, green: 0.55, blue: 0.45)),
        BereanModeOption(id: "rewrite",    name: "Gentle Rewrite",      icon: "pencil.and.sparkles",
                   description: "Softer, kinder rewrites with grace",
                   chipColor: Color(red: 0.65, green: 0.38, blue: 0.18)),
        BereanModeOption(id: "creator",    name: "Creator Mode",        icon: "wand.and.stars",
                   description: "Sharp, creative, post-ready output",
                   chipColor: Color(red: 0.70, green: 0.25, blue: 0.55)),
        BereanModeOption(id: "church",     name: "Church Companion",    icon: "building.columns",
                   description: "Church planning, notes, community",
                   chipColor: Color(red: 0.18, green: 0.50, blue: 0.30)),
        BereanModeOption(id: "safety",     name: "Safety Review",       icon: "shield.lefthalf.filled",
                   description: "Tone analysis and civility checks",
                   chipColor: Color(red: 0.80, green: 0.35, blue: 0.25)),
    ]

    static var standard: BereanModeOption { catalog[0] }
}

// MARK: - Mode Store

final class BereanModeStore: ObservableObject {
    static let shared = BereanModeStore()

    @Published var selectedMode: BereanModeOption = BereanModeOption.catalog[0] {
        didSet { UserDefaults.standard.set(selectedMode.id, forKey: "berean_active_mode_id") }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "berean_active_mode_id") ?? "standard"
        selectedMode = BereanModeOption.catalog.first { $0.id == saved } ?? BereanModeOption.catalog[0]
    }
}

// MARK: - BereanModesSheet

/// Present this as a `.sheet` from the chat header or composer mode button.
struct BereanModesSheet: View {
    @ObservedObject private var modeStore = BereanModeStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.975, green: 0.975, blue: 0.975).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        Text("Choose how Berean responds to you")
                            .font(.systemScaled(14))
                            .foregroundStyle(Color(white: 0.52))
                            .padding(.top, 6).padding(.bottom, 20)

                        VStack(spacing: 0) {
                            ForEach(Array(BereanModeOption.catalog.enumerated()), id: \.element.id) { idx, mode in
                                modeRow(mode)
                                if idx < BereanModeOption.catalog.count - 1 {
                                    Divider().padding(.leading, 64)
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

                        Spacer().frame(height: 40)
                    }
                    .padding(.top, 4)
                }
            }
            .navigationTitle("Berean Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.font(.systemScaled(15, weight: .semibold))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    @ViewBuilder
    private func modeRow(_ mode: BereanModeOption) -> some View {
        let isSelected = modeStore.selectedMode.id == mode.id

        Button {
            withAnimation(Motion.adaptive(.spring(response: 0.30, dampingFraction: 0.80))) {
                modeStore.selectedMode = mode
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(260))
                dismiss()
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(mode.chipColor.opacity(isSelected ? 0.15 : 0.07))
                        .frame(width: 40, height: 40)
                    Image(systemName: mode.icon)
                        .font(.systemScaled(16, weight: .medium))
                        .foregroundStyle(mode.chipColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.name)
                        .font(.systemScaled(15, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(Color(white: 0.10))
                    Text(mode.description)
                        .font(.systemScaled(12))
                        .foregroundStyle(Color(white: 0.50))
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(mode.chipColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(isSelected ? mode.chipColor.opacity(0.04) : Color.clear)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - BereanActiveModeChip

/// Compact pill showing the active mode. Tap to open BereanModesSheet.
/// Drop into the chat composer toolbar or nav header.
struct BereanActiveModeChip: View {
    @ObservedObject private var modeStore = BereanModeStore.shared
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            HStack(spacing: 4) {
                Image(systemName: modeStore.selectedMode.icon)
                    .font(.systemScaled(10, weight: .semibold))
                Text(modeStore.selectedMode.name)
                    .font(.systemScaled(12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.systemScaled(9, weight: .semibold))
            }
            .foregroundStyle(modeStore.selectedMode.chipColor)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(modeStore.selectedMode.chipColor.opacity(0.10))
                    .overlay(Capsule().strokeBorder(modeStore.selectedMode.chipColor.opacity(0.20), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) { BereanModesSheet() }
    }
}
