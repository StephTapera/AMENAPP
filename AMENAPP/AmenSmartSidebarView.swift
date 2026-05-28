// AmenSmartSidebarView.swift
// AMEN App — Smart Sidebar with live intelligence panels.
//
// Panels: Continue Reflection, Active Prayer Threads, Unresolved Discussions,
// Important Mentions, Spiritual Growth Themes, Organization Memory, AI Insights,
// Related Scripture. Calm Liquid Glass design — white backgrounds, minimal chrome.

import SwiftUI

struct AmenSmartSidebarView: View {
    let spaceId: String
    var onOpenBerean: ((String) -> Void)? = nil
    var onOpenThread: ((String) -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    @StateObject private var memoryService = AmenPersistentMemoryGraphService.shared
    @StateObject private var pinService = AmenSemanticPinService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    continueReflectionPanel
                    activePrayerPanel
                    unresolvedPanel
                    spiritualThemesPanel
                    orgMemoryPanel
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onDismiss?() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.5))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.black.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task { await loadSidebarData() }
    }

    // MARK: - Continue Reflection

    private var continueReflectionPanel: some View {
        AmenSidebarPanel(title: "Continue Reflection", icon: "moon.stars.fill") {
            if let continuity = memoryService.spiritualContinuity,
               !continuity.unfinishedReflections.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(continuity.unfinishedReflections.prefix(2), id: \.self) { ref in
                        Button {
                            onOpenBerean?(ref)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.45))
                                Text(ref)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.black.opacity(0.72))
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("No unfinished reflections.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.38))
            }
        }
    }

    // MARK: - Active Prayer Panel

    private var activePrayerPanel: some View {
        AmenSidebarPanel(title: "Active Prayer Threads", icon: "hands.sparkles.fill") {
            let prayers = pinService.prayerPins
            if prayers.isEmpty {
                Text("No active prayer pins.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.38))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(prayers.prefix(3)) { pin in
                        Button {
                            if let tid = pin.threadId { onOpenThread?(tid) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "hands.sparkles.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color(red: 0.62, green: 0.49, blue: 0.79))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pin.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.black.opacity(0.78))
                                        .lineLimit(1)
                                    Text(pin.preview)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.black.opacity(0.42))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Unresolved Discussions Panel

    private var unresolvedPanel: some View {
        AmenSidebarPanel(title: "Unresolved Items", icon: "questionmark.circle.fill") {
            let unresolved = pinService.unresolvedPins
            if unresolved.isEmpty {
                Text("All caught up.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.38))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(unresolved.prefix(3)) { pin in
                        Button {
                            if let tid = pin.threadId { onOpenThread?(tid) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: pin.pinType.icon)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color(red: 0.79, green: 0.63, blue: 0.27))
                                Text(pin.title)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.black.opacity(0.72))
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Spiritual Themes Panel

    private var spiritualThemesPanel: some View {
        AmenSidebarPanel(title: "Spiritual Themes", icon: "sparkles") {
            let themes = memoryService.recurringScriptureThemes
            if themes.isEmpty {
                Text("No recurring themes yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.38))
            } else {
                SidebarChipFlowLayout(spacing: 6) {
                    ForEach(themes, id: \.self) { theme in
                        Text(theme)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.65))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.97, green: 0.97, blue: 0.94))
                                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5))
                            )
                    }
                }
            }
        }
    }

    // MARK: - Org Memory Panel

    private var orgMemoryPanel: some View {
        AmenSidebarPanel(title: "Organization Memory", icon: "building.2.fill") {
            let nodes = memoryService.nodes(for: .organizational, spaceId: spaceId)
            if nodes.isEmpty {
                Text("No organizational memory yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.38))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(nodes.prefix(3)) { node in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(node.humblePrefix + node.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.78))
                            Text(node.body)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.black.opacity(0.48))
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadSidebarData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await AmenPersistentMemoryGraphService.shared.loadSpaceMemory(spaceId: self.spaceId) }
            group.addTask { await AmenPersistentMemoryGraphService.shared.loadUserSpaceMemory(spaceId: self.spaceId) }
            group.addTask { await AmenPersistentMemoryGraphService.shared.loadSpiritualContinuity(spaceId: self.spaceId) }
        }
        AmenSemanticPinService.shared.subscribeToSpacePins(spaceId: spaceId)
    }
}

// MARK: - Panel Component

private struct AmenSidebarPanel<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.55))
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.78))
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.35))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Flow Layout (tag wrapping)

private struct SidebarChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
