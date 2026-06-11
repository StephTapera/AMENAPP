// SpacesCreationRail.swift
// AMEN — Docked rail variant for Spaces with Liquid Glass backdrop.
// Default tools: [Bible, Prayer, Event, Poll, File, Task, Video, More].
// Church-mode adds Announcement and Donation to the + menu.
import SwiftUI

// MARK: - SpacesCreationRail

/// Docked rail variant for Spaces.
/// Default tools: [Bible, Prayer, Event, Poll, File, Task, Video, More].
/// Church-mode adds Announcement and Donation to the + sheet.
struct SpacesCreationRail: View {
    @StateObject private var vm: CreationRailViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let onToolSelected: (ToolID) -> Void
    let onAttachmentReady: (ComposerAttachment) -> Void
    @Binding var currentText: String

    private let spacesTools: [ToolID] = [.bible, .prayerRequest, .event, .poll, .file, .task, .video]

    init(currentText: Binding<String>,
                churchContext: ChurchComposerContext? = nil,
                spaceContext: SpaceComposerContext? = nil,
                onToolSelected: @escaping (ToolID) -> Void,
                onAttachmentReady: @escaping (ComposerAttachment) -> Void) {
        self._vm = StateObject(wrappedValue: CreationRailViewModel.makeForSurface(
            .space, churchContext: churchContext, spaceContext: spaceContext))
        self._currentText = currentText
        self.onToolSelected = onToolSelected
        self.onAttachmentReady = onAttachmentReady
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(spacesTools, id: \.self) { toolId in
                    if let tool = CreationTool.registry.first(where: { $0.id == toolId }) {
                        SpacesRailButton(tool: tool) {
                            onToolSelected(toolId)
                        }
                    }
                }

                // More button
                Button(action: { /* TODO: show expanded sheet */ }) {
                    VStack(spacing: 2) {
                        Image(systemName: "ellipsis")
                            .font(.body)
                            .frame(width: 28, height: 28)
                        Text("More")
                            .font(.caption2)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("More tools")
                .accessibilityHint("Show additional creation tools for this space")
            }
            .padding(.horizontal, 12)
        }
        .frame(minHeight: 56)
        .background(railBackground)
        .onChange(of: currentText) { _, text in
            vm.textDidChange(text, reduceMotion: reduceMotion)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Space creation tools")
    }

    // MARK: - Rail Background

    @ViewBuilder
    private var railBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground).opacity(0.95))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.10))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - SpacesRailButton

private struct SpacesRailButton: View {
    let tool: CreationTool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Image(systemName: tool.icon)
                    .font(.body)
                    .frame(width: 28, height: 28)
                Text(tool.title)
                    .font(.caption2)
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(tool.title)
        .accessibilityHint("Add \(tool.title) to the space")
    }
}
