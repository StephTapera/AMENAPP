// FloatingComposerPill.swift
// AMEN — Apple Mail-style floating glass pill, right-aligned above keyboard.
// Used for Messages, Group Chats, Comments surfaces.
// Guard: only shown when featureFlags.composerFloatingPillEnabled == true (caller responsibility).
import SwiftUI

/// Apple Mail-style floating glass pill, right-aligned above keyboard.
/// Used for Messages, Group Chats, Comments surfaces.
/// Guard: only shown when featureFlags.composerFloatingPillEnabled == true (caller responsibility).
public struct FloatingComposerPill: View {
    @StateObject private var vm: CreationRailViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let surface: ComposerSurface
    let onToolSelected: (ToolID) -> Void
    @Binding var isTyping: Bool
    @State private var showExpandedSheet = false

    // Default icon set for messages/comments
    private let defaultIcons: [(ToolID, String)] = [
        (.photo, "photo"),
        (.bible, "book.fill"),
        (.prayerRequest, "hands.sparkles"),
        (.voice, "mic.fill"),
    ]

    public init(surface: ComposerSurface,
                isTyping: Binding<Bool>,
                onToolSelected: @escaping (ToolID) -> Void) {
        self._vm = StateObject(wrappedValue: CreationRailViewModel.makeForSurface(surface))
        self.surface = surface
        self._isTyping = isTyping
        self.onToolSelected = onToolSelected
    }

    public var body: some View {
        HStack {
            Spacer()
            pillContent
                .animation(reduceMotion ? .linear(duration: 0)
                           : .spring(response: 0.3, dampingFraction: 0.82),
                           value: isTyping)
        }
        .padding(.trailing, 16)
        .sheet(isPresented: $showExpandedSheet) {
            PillExpandedSheet(vm: vm, onToolSelected: { id in
                onToolSelected(id)
                showExpandedSheet = false
            })
            .presentationDetents([.medium])
        }
        .onChange(of: isTyping) { typing in
            if !typing {
                // Small delay before expanding back
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    // expanded state handled by pill display
                }
            }
        }
    }

    @ViewBuilder
    private var pillContent: some View {
        if isTyping {
            // Lone "+" while typing
            Button(action: { showExpandedSheet = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .background(pillBackground(for: Capsule()))
            .clipShape(Capsule())
            .accessibilityLabel("More creation tools")
            .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
        } else {
            // Full pill
            HStack(spacing: 2) {
                ForEach(defaultIcons, id: \.0) { (id, icon) in
                    PillIconButton(icon: icon, toolId: id) { onToolSelected(id) }
                }
                Button(action: { showExpandedSheet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("More tools")
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(pillBackground(for: Capsule()))
            .clipShape(Capsule())
            .transition(reduceMotion ? .opacity : .scale(scale: 0.97).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Message tools")
        }
    }

    @ViewBuilder
    private func pillBackground<S: Shape>(for shape: S) -> some View {
        if reduceTransparency {
            AnyView(shape.fill(Color(.systemBackground).opacity(0.95))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 2))
        } else {
            AnyView(shape.fill(Color.white.opacity(0.15))
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.1), radius: 10, y: 3))
        }
    }
}

// MARK: - PillIconButton
private struct PillIconButton: View {
    let icon: String
    let toolId: ToolID
    let onTap: () -> Void
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .frame(width: 36, height: 36)
        }
        .scaleEffect(isPressed && !reduceMotion ? 0.9 : 1.0)
        .animation(reduceMotion ? .linear(duration: 0) : .spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in isPressed = true }
            .onEnded { _ in isPressed = false })
        .accessibilityLabel(CreationTool.registry.first { $0.id == toolId }?.title ?? icon)
    }
}

// MARK: - PillExpandedSheet
private struct PillExpandedSheet: View {
    let vm: CreationRailViewModel
    let onToolSelected: (ToolID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create").font(.headline).padding(.horizontal)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 16) {
                ForEach(vm.orderedTools) { tool in
                    Button(action: { onToolSelected(tool.id) }) {
                        VStack(spacing: 6) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 22))
                                .frame(width: 44, height: 44)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
                            Text(tool.title)
                                .font(.caption2).lineLimit(1)
                        }
                    }
                    .accessibilityLabel(tool.title)
                    .accessibilityHint("Adds a \(tool.title) attachment")
                }
            }
            .padding(.horizontal)
        }
        .padding(.top)
    }
}
