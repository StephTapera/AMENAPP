// MultiPaneCommunicationView.swift
// AMEN Comms OS — Multi-Pane Communication Shell (Agent 10)
//
// Adaptive layout: sidebar + thread list + optional detail panel on iPad/large-width.
// Falls back to BereanCommunicationHubView on compact (iPhone) and when flag is OFF.
// All new surfaces (command palette, group pulse, decisions) are wired here behind their flags.

import SwiftUI

// MARK: - Pane Selection

enum CommsPaneSelection: Hashable {
    case none
    case thread(String)     // conversationId
    case commandPalette
}

// MARK: - ViewModel

@MainActor
final class MultiPaneCommunicationViewModel: ObservableObject {
    @Published var selectedPane: CommsPaneSelection = .none
    @Published var showDetailPanel = false
    @Published var isCommandPaletteVisible = false

    func selectThread(_ id: String) {
        selectedPane = .thread(id)
        showDetailPanel = true
    }

    func openCommandPalette() {
        isCommandPaletteVisible = true
    }

    func dismissCommandPalette() {
        isCommandPaletteVisible = false
    }

    func closeDetail() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            selectedPane = .none
            showDetailPanel = false
        }
    }
}

// MARK: - Root View

struct MultiPaneCommunicationView: View {
    @StateObject private var viewModel = MultiPaneCommunicationViewModel()
    @Environment(\.horizontalSizeClass)             private var sizeClass
    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let flags = AMENFeatureFlags.shared

    var body: some View {
        if flags.commsMultiPaneEnabled {
            adaptiveLayout
        } else {
            BereanCommunicationHubView()
        }
    }

    // MARK: Layout Switching

    @ViewBuilder
    private var adaptiveLayout: some View {
        if sizeClass == .regular {
            regularLayout
        } else {
            compactLayout
        }
    }

    // iPad / large-width
    private var regularLayout: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 220)
            Divider()
            threadList.frame(minWidth: 300, maxWidth: 400)
            if viewModel.showDetailPanel {
                Divider()
                detailPanel
                    .frame(maxWidth: .infinity)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .opacity
                            )
                    )
            }
        }
        .animation(
            reduceMotion ? .none : .spring(response: 0.38, dampingFraction: 0.82),
            value: viewModel.showDetailPanel
        )
        .overlay(alignment: .top) {
            if viewModel.isCommandPaletteVisible {
                commandPaletteOverlay
                    .transition(
                        reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity)
                    )
                    .animation(
                        reduceMotion ? .linear(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.78),
                        value: viewModel.isCommandPaletteVisible
                    )
            }
        }
    }

    // iPhone: single-pane hub
    private var compactLayout: some View {
        BereanCommunicationHubView(
            onOpenThread: { id in viewModel.selectThread(id) }
        )
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            Divider()
            sidebarNav
            Spacer()
        }
        .frame(maxHeight: .infinity)
        .background {
            if reduceTransparency { Color(.secondarySystemBackground) }
            else { Rectangle().fill(.regularMaterial) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Communication sidebar")
    }

    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(.blue)
            Text("Communion").font(.headline.weight(.semibold))
            Spacer()
        }
        .padding(16)
    }

    private var sidebarNav: some View {
        VStack(alignment: .leading, spacing: 2) {
            sidebarNavRow("All Threads",  icon: "tray.2",             isSelected: viewModel.selectedPane == .none)
            if flags.commsDecisionsEnabled {
                sidebarNavRow("Decisions",    icon: "checkmark.seal",    isSelected: false)
            }
            if flags.commsPulseEnabled {
                sidebarNavRow("Group Pulse",  icon: "waveform",          isSelected: false)
            }
            if flags.commsCommandPaletteEnabled {
                Divider().padding(.vertical, 4)
                Button { viewModel.openCommandPalette() } label: {
                    Label("Search", systemImage: "magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open command palette")
            }
        }
        .padding(.top, 4)
    }

    private func sidebarNavRow(_ label: String, icon: String, isSelected: Bool) -> some View {
        Button {
            if isSelected { viewModel.closeDetail() }
        } label: {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(isSelected ? .blue : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isSelected ? Color.blue.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Thread List

    private var threadList: some View {
        BereanCommunicationHubView(
            onOpenThread: { id in
                withAnimation(reduceMotion ? .none : .spring(response: 0.38, dampingFraction: 0.82)) {
                    viewModel.selectThread(id)
                }
            }
        )
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private var detailPanel: some View {
        switch viewModel.selectedPane {
        case .thread(let id):
            threadDetailPanel(id: id)
        default:
            EmptyView()
        }
    }

    private func threadDetailPanel(id: String) -> some View {
        VStack(spacing: 0) {
            // Panel header
            HStack {
                Text("Thread")
                    .font(.headline.weight(.semibold))
                Spacer()
                Button(action: viewModel.closeDetail) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close detail panel")
            }
            .padding(16)
            .background {
                if reduceTransparency { Color(.systemBackground) }
                else { Rectangle().fill(.regularMaterial) }
            }
            Divider()

            // Smart context surfaces (flag-gated)
            ScrollView {
                VStack(spacing: 16) {
                    if flags.commsPulseEnabled {
                        GroupPulseCard(conversationId: id, isGroup: true)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Command Palette Overlay

    private var commandPaletteOverlay: some View {
        ZStack(alignment: .top) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { viewModel.dismissCommandPalette() }

            UniversalCommandPalette(
                threadId: currentThreadId,
                onSelectResult: { _ in viewModel.dismissCommandPalette() },
                onDismiss: { viewModel.dismissCommandPalette() }
            )
            .padding(.horizontal, 40)
            .padding(.top, 80)
            .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityLabel("Command palette overlay")
    }

    private var currentThreadId: String {
        if case .thread(let id) = viewModel.selectedPane { return id }
        return ""
    }
}
