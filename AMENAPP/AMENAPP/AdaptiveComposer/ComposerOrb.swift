// ComposerOrb.swift
// AMEN — Floating circular glass button that blooms into a radial creation menu.
// Guard: only shown when featureFlags.composerOrbEnabled == true (caller responsibility).
import SwiftUI

// MARK: - FloatingComposerOrb

/// Floating circular glass button → radial bloom creation menu.
/// Guard: only shown when featureFlags.composerOrbEnabled == true (caller responsibility).
struct FloatingComposerOrb: View {
    let onToolSelected: (ToolID) -> Void
    @State private var isBloomOpen = false
    @State private var orbPosition: OrbEdge = .trailing
    @GestureState private var dragTranslation: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("composerOrbEdge") private var savedEdge: String = "trailing"

    private let orbSize: CGFloat = 52
    private let bloomRadius: CGFloat = 88
    private let orbTools: [(ToolID, String)] = [
        (.photo, "photo"), (.bible, "book.fill"), (.prayerRequest, "hands.sparkles"),
        (.event, "calendar"), (.poll, "chart.bar.fill"), (.churchNote, "building.columns"),
        (.music, "music.note"), (.voice, "mic.fill"), (.location, "mappin.and.ellipse"),
        (.file, "paperclip"),
    ]

    init(onToolSelected: @escaping (ToolID) -> Void) {
        self.onToolSelected = onToolSelected
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dim overlay when bloom is open
                if isBloomOpen {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .onTapGesture { closeBloom() }
                        .transition(.opacity)
                }

                // Bloom items
                if isBloomOpen {
                    bloomMenu(in: geo)
                }

                // Orb button
                orbButton(in: geo)
            }
            .onAppear {
                orbPosition = savedEdge == "leading" ? .leading : .trailing
            }
        }
        .animation(reduceMotion ? .linear(duration: 0) : .spring(response: 0.35, dampingFraction: 0.82),
                   value: isBloomOpen)
    }

    // MARK: - Orb Button

    private func orbButton(in geo: GeometryProxy) -> some View {
        let baseX: CGFloat = orbPosition == .trailing
            ? geo.size.width - orbSize - 16
            : 16
        let baseY: CGFloat = geo.size.height - orbSize - 32

        return Button(action: { withAnimation { isBloomOpen.toggle() } }) {
            Image(systemName: isBloomOpen ? "xmark" : "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: orbSize, height: orbSize)
                .amenInteractiveGlassEffect(in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        }
        .accessibilityLabel(isBloomOpen ? "Close creation menu" : "Open creation menu")
        .accessibilityHint(isBloomOpen ? "Closes the creation menu" : "Opens a menu of creation tools")
        .accessibilityAction(named: "Move to left edge") {
            orbPosition = .leading
            savedEdge = "leading"
        }
        .accessibilityAction(named: "Move to right edge") {
            orbPosition = .trailing
            savedEdge = "trailing"
        }
        .offset(x: baseX + dragTranslation.width, y: baseY + dragTranslation.height)
        .gesture(
            DragGesture()
                .updating($dragTranslation) { value, state, _ in state = value.translation }
                .onEnded { value in
                    let midX = geo.size.width / 2
                    let finalX = baseX + value.translation.width
                    orbPosition = finalX < midX ? .leading : .trailing
                    savedEdge = orbPosition == .leading ? "leading" : "trailing"
                }
        )
    }

    // MARK: - Bloom Menu

    @ViewBuilder
    private func bloomMenu(in geo: GeometryProxy) -> some View {
        let centerX: CGFloat = orbPosition == .trailing
            ? geo.size.width - orbSize / 2 - 16
            : orbSize / 2 + 16
        let centerY: CGFloat = geo.size.height - orbSize / 2 - 32

        if reduceMotion {
            // Reduce motion: simple grid instead of radial bloom
            VStack(spacing: 12) {
                ForEach(Array(orbTools.chunkedOrb(into: 5)), id: \.first?.0) { row in
                    HStack(spacing: 12) {
                        ForEach(row, id: \.0) { toolId, icon in
                            OrbActionButton(icon: icon, toolId: toolId) {
                                onToolSelected(toolId)
                                closeBloom()
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .position(x: centerX, y: centerY - 120)
            .transition(.opacity)
        } else {
            ForEach(Array(orbTools.enumerated()), id: \.element.0) { index, tool in
                let angle = angleForIndex(index, total: orbTools.count)
                let itemX = centerX + bloomRadius * cos(angle)
                let itemY = centerY + bloomRadius * sin(angle)

                OrbActionButton(icon: tool.1, toolId: tool.0) {
                    onToolSelected(tool.0)
                    closeBloom()
                }
                .position(x: itemX, y: itemY)
                .transition(.scale(scale: 0.1).combined(with: .opacity))
                .animation(
                    .spring(response: 0.35, dampingFraction: 0.82)
                        .delay(isBloomOpen
                               ? Double(index) * 0.03
                               : Double(orbTools.count - index - 1) * 0.02),
                    value: isBloomOpen
                )
            }
        }
    }

    // MARK: - Helpers

    private func angleForIndex(_ index: Int, total: Int) -> CGFloat {
        let startAngle: CGFloat = -.pi / 2 - .pi / 4
        let endAngle: CGFloat = .pi + .pi / 4
        let step = (endAngle - startAngle) / CGFloat(max(total - 1, 1))
        return startAngle + step * CGFloat(index)
    }

    private func closeBloom() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            isBloomOpen = false
        }
    }

    // MARK: - OrbEdge

    enum OrbEdge { case leading, trailing }
}

// MARK: - Array+chunkedOrb (fileprivate to avoid collision with existing extension)

private extension Array {
    func chunkedOrb(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

// MARK: - OrbActionButton

private struct OrbActionButton: View {
    let icon: String
    let toolId: ToolID
    let onTap: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: onTap) {
            Image(systemName: icon)
                .font(.body)
                .frame(width: 44, height: 44)
                .background(
                    Group {
                        if reduceTransparency {
                            Circle().fill(Color(.systemBackground).opacity(0.97))
                        } else {
                            Circle().fill(Color.white.opacity(0.18))
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
                        }
                    }
                )
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .accessibilityLabel(CreationTool.registry.first { $0.id == toolId }?.title ?? icon)
        .accessibilityHint("Creates a \(CreationTool.registry.first { $0.id == toolId }?.title ?? icon) attachment")
    }
}
