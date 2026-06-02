// ONEWorldFeedView.swift
// ONE — World Zone: five feed modes, session budget, matte cells, context gate, witness model.
// P3-D | Glass on chrome (header, mode chips) only — feed cells are strictly matte.
// Requires iOS 26 for glassEffect on mode switcher.

import SwiftUI

@available(iOS 26.0, *)
struct ONEWorldFeedView: View {
    @StateObject private var service = ONEFeedModeService()
    @State private var witnessTargetUID: String? = nil
    @State private var contextGateItemID: String? = nil
    @State private var relayError: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                feedContent
                chromeHeader
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
        .sheet(isPresented: Binding(
            get: { witnessTargetUID != nil },
            set: { if !$0 { witnessTargetUID = nil } }
        )) {
            if let uid = witnessTargetUID {
                ONEWitnessRequestView(targetUID: uid) { _ in witnessTargetUID = nil }
            }
        }
        .sheet(isPresented: Binding(
            get: { contextGateItemID != nil },
            set: { if !$0 { contextGateItemID = nil } }
        )) {
            if let itemID = contextGateItemID,
               let item = service.items.first(where: { $0.id == itemID }) {
                ONEContextGateView(
                    item: item,
                    gateStatus: service.gateStatus(for: itemID),
                    onSourceRead: { service.markSourceRead(for: itemID) },
                    onWatchProgress: { service.markWatchProgress($0, for: itemID) },
                    onProvenanceAcknowledged: { service.markProvenanceAcknowledged(for: itemID) },
                    onDismiss: { contextGateItemID = nil }
                )
            }
        }
        .alert("Relay failed", isPresented: Binding(
            get: { relayError != nil },
            set: { if !$0 { relayError = nil } }
        )) {
            Button("OK") { relayError = nil }
        } message: {
            Text(relayError ?? "")
        }
        .onAppear { service.loadStub(for: .close) }
    }

    // MARK: - Chrome header (glass)

    private var chromeHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Text("World")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Spacer()
                relayBudgetBadge
            }
            .padding(.horizontal, ONE.Spacing.md)
            .padding(.top, 56)
            .padding(.bottom, ONE.Spacing.xs)

            modeSwitcherRow

            budgetBar
                .padding(.horizontal, ONE.Spacing.md)
                .padding(.bottom, ONE.Spacing.sm)
        }
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.3) }
    }

    private var relayBudgetBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11))
            Text("\(service.userRelayBudget)")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(service.userRelayBudget <= 5 ? ONE.Colors.ephemeralRed : .secondary)
        .padding(.horizontal, ONE.Spacing.sm)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .accessibilityLabel("\(service.userRelayBudget) relay\(service.userRelayBudget == 1 ? "" : "s") remaining this week")
    }

    private var modeSwitcherRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ONE.Spacing.sm) {
                ForEach(ONEFeedModeKind.allCases, id: \.self) { mode in
                    modeChip(mode)
                }
            }
            .padding(.horizontal, ONE.Spacing.md)
            .padding(.vertical, ONE.Spacing.xs)
        }
    }

    private func modeChip(_ mode: ONEFeedModeKind) -> some View {
        let isSelected = service.session.mode == mode
        return Button {
            guard !isSelected else { return }
            withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                service.switchMode(mode)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: modeIcon(mode)).font(.system(size: 11))
                Text(mode.displayLabel).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isSelected ? AmenTheme.Colors.amenGold : Color.secondary)
            .padding(.horizontal, ONE.Spacing.md)
            .padding(.vertical, 6)
            .glassEffect(
                isSelected
                    ? .regular.tint(ONE.Colors.glassWarm).interactive()
                    : .regular.interactive(),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.displayLabel) feed\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var budgetBar: some View {
        let fraction = service.session.sessionBudget > 0
            ? Double(service.session.itemsSeen) / Double(service.session.sessionBudget)
            : 1.0
        return HStack(spacing: ONE.Spacing.sm) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(service.session.isExhausted
                              ? Color.secondary.opacity(0.4)
                              : AmenTheme.Colors.amenGold.opacity(0.7))
                        .frame(width: geo.size.width * fraction)
                        .animation(ONE.Motion.adaptive(reduceMotion: reduceMotion), value: fraction)
                }
            }
            .frame(height: 3)

            Text(service.session.isExhausted
                 ? "Session done"
                 : "\(service.session.remaining) left")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize()
        }
        .accessibilityLabel(
            service.session.isExhausted
            ? "Session complete. \(service.session.sessionBudget) items seen."
            : "\(service.session.remaining) of \(service.session.sessionBudget) items remaining this session."
        )
    }

    // MARK: - Feed content

    @ViewBuilder
    private var feedContent: some View {
        if service.session.isExhausted {
            sessionExhaustedView
        } else if service.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading \(service.session.mode.displayLabel) feed")
        } else if service.items.isEmpty {
            emptyStateView
        } else {
            ScrollView {
                LazyVStack(spacing: ONE.Spacing.sm) {
                    Color.clear.frame(height: 156)
                    ForEach(service.items) { item in
                        feedCell(item)
                            .onAppear { service.markItemSeen() }
                    }
                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, ONE.Spacing.md)
            }
        }
    }

    // MARK: - Feed cell (MATTE — never glass)

    private func feedCell(_ item: ONEFeedItemViewModel) -> some View {
        VStack(alignment: .leading, spacing: ONE.Spacing.sm) {
            authorRow(item)
            Text(item.textBody)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .lineLimit(5)
            metaRow(item)
            actionBar(item)
        }
        .padding(ONE.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: ONE.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(0.04))   // MATTE: no glassEffect on feed cells
        )
        .accessibilityElement(children: .contain)
    }

    private func authorRow(_ item: ONEFeedItemViewModel) -> some View {
        HStack(spacing: ONE.Spacing.sm) {
            Circle()
                .fill(AmenTheme.Colors.amenGold.opacity(0.18))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(String(item.authorDisplayName.prefix(1)))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                        .accessibilityHidden(true)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(item.authorDisplayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(item.createdAt, style: .relative)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                witnessTargetUID = item.authorDisplayName   // stub: would be item.authorUID
            } label: {
                Text("Witness")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ONE.Colors.witnessGold)
                    .padding(.horizontal, ONE.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().stroke(ONE.Colors.witnessGold.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Witness \(item.authorDisplayName)")
        }
    }

    private func metaRow(_ item: ONEFeedItemViewModel) -> some View {
        HStack(spacing: ONE.Spacing.sm) {
            let cls = item.provenance.displayClassification
            HStack(spacing: 4) {
                Image(systemName: cls.icon).font(.system(size: 10))
                Text(cls.displayLabel).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, ONE.Spacing.sm)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .accessibilityLabel(cls.accessibilityLabel)

            if !item.permissions.forwardAllowed {
                Image(systemName: "arrow.turn.up.right.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("No forwarding")
            }
            if !item.permissions.saveAllowed {
                Image(systemName: "square.and.arrow.down.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("No saving")
            }

            Spacer()

            ONEReachBudgetPill(budget: item.reachBudget)
        }
    }

    private func actionBar(_ item: ONEFeedItemViewModel) -> some View {
        HStack(spacing: ONE.Spacing.lg) {
            if item.permissions.reactAllowed {
                Button {
                    // React action (P4 scope: reaction picker)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "heart").font(.system(size: 14))
                        Text("React").font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("React to this moment")
            }

            Button {
                if service.isGatePassed(for: item.id) {
                    // comment sheet would open here (P4 scope)
                } else {
                    contextGateItemID = item.id
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left").font(.system(size: 14))
                    Text("Comment").font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                service.isGatePassed(for: item.id)
                ? "Add comment"
                : "Comment — complete context check first"
            )

            if item.reachBudget.hasReachRemaining && service.userRelayBudget > 0 {
                Button {
                    Task {
                        do {
                            _ = try await service.relay(itemID: item.id)
                        } catch {
                            relayError = error.localizedDescription
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 14))
                        Text("Relay").font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Relay this moment. \(item.reachBudget.sharesRemaining) relays remaining.")
            }

            Spacer()
        }
    }

    // MARK: - Session exhausted

    private var sessionExhaustedView: some View {
        VStack(spacing: ONE.Spacing.lg) {
            Color.clear.frame(height: 156)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AmenTheme.Colors.amenGold.opacity(0.5))
            Text("Session complete")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
            Text("You've seen all \(service.session.sessionBudget) items for this \(service.session.mode.displayLabel) session.\nSwitch modes or come back fresh.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            FlowLayout(spacing: ONE.Spacing.sm) {
                ForEach(ONEFeedModeKind.allCases.filter { $0 != service.session.mode }, id: \.self) { mode in
                    Button(mode.displayLabel) {
                        withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                            service.switchMode(mode)
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                    .padding(.horizontal, ONE.Spacing.md)
                    .padding(.vertical, ONE.Spacing.sm)
                    .background(Capsule().fill(AmenTheme.Colors.amenGold.opacity(0.10)))
                    .accessibilityLabel("Switch to \(mode.displayLabel) mode")
                }
            }
        }
        .padding(ONE.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session complete. \(service.session.sessionBudget) items seen. Switch mode to continue.")
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: ONE.Spacing.lg) {
            Color.clear.frame(height: 156)
            Image(systemName: modeIcon(service.session.mode))
                .font(.system(size: 48))
                .foregroundStyle(AmenTheme.Colors.amenGold.opacity(0.4))
            Text("Nothing here yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            Text(modeDescription(service.session.mode))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(ONE.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Mode metadata

    private func modeIcon(_ mode: ONEFeedModeKind) -> String {
        switch mode {
        case .close:  return "person.2.fill"
        case .create: return "star.fill"
        case .learn:  return "book.fill"
        case .local:  return "location.fill"
        case .quiet:  return "leaf.fill"
        }
    }

    private func modeDescription(_ mode: ONEFeedModeKind) -> String {
        switch mode {
        case .close:  return "Content from your close friends and witnesses only."
        case .create: return "Creator drops and collaborative moments."
        case .learn:  return "Long-form articles, reflections, and scripture study."
        case .local:  return "Content from your local community."
        case .quiet:  return "A slow, curated feed. No video. Low motion."
        }
    }
}

// MARK: - FlowLayout (simple horizontal wrapping)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
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

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 26.0, *)
#Preview("World Feed") {
    ONEWorldFeedView()
}
#endif
