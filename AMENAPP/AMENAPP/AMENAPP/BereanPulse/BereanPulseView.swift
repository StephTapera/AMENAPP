import SwiftUI
import UIKit

@MainActor
struct BereanPulseView: View {
    @StateObject private var viewModel: BereanPulseViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollOffset: CGFloat = 0

    init(viewModel: BereanPulseViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? BereanPulseViewModel())
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                background

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: BereanPulseScrollOffsetKey.self, value: proxy.frame(in: .named("bereanPulse")).minY)
                        }
                        .frame(height: 0)

                        topBar
                            .padding(.horizontal, 18)
                            .padding(.top, 14)

                        BereanPulseHeaderView(
                            titleDate: Self.dateFormatter.string(from: Date()),
                            intro: String(localized: "Continue the work Berean already understands, inspect the context being used, and turn the next best step into action."),
                            collapseProgress: collapseProgress
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 28)

                        BereanPulseModePillRow(selectedMode: $viewModel.selectedMode)
                            .padding(.top, 18)

                        workspaceContent
                            .padding(.horizontal, 18)
                            .padding(.top, 18)
                            .padding(.bottom, 132)
                    }
                }
                .coordinateSpace(name: "bereanPulse")
                .onPreferenceChange(BereanPulseScrollOffsetKey.self) { scrollOffset = $0 }

                topFade

                BereanPulseSmartComposerDock(
                    prompt: topCard == nil ? String(localized: "Ask Berean") : String(localized: "Continue with Berean"),
                    canAskBerean: topCard != nil,
                    disabledReason: String(localized: "Select a card to ask Berean"),
                    onAskBerean: askTopCard,
                    onCurate: {
                        softHaptic()
                        viewModel.openCurate()
                    },
                    onRefresh: {
                        softHaptic()
                        Task { await viewModel.refresh() }
                    }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.82), value: collapseProgress)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await viewModel.load() }
            .sheet(item: Binding(
                get: { viewModel.actionRouter.destination },
                set: { _ in viewModel.clearDestination() }
            )) { destination in
                BereanPulseDestinationView(destination: destination)
            }
            .sheet(isPresented: $viewModel.showCurateSheet) {
                BereanPulseCurateSheet(
                    preference: viewModel.preferences,
                    permissionManager: viewModel.permissionManager,
                    onSave: { updated in
                        Task { await viewModel.updatePreferences(updated) }
                    },
                    onReset: {
                        Task { await viewModel.updatePreferences(.default) }
                    }
                )
            }
            .sheet(item: $viewModel.permissionPromptContext) { context in
                BereanPulsePermissionSheet(
                    context: context,
                    onAllow: {
                        Task { await viewModel.requestPermissionFromPrompt() }
                    },
                    onNotNow: viewModel.dismissPermissionPrompt
                )
            }
            .sheet(
                isPresented: Binding(
                    get: { viewModel.actionRouter.shareText != nil },
                    set: { if !$0 { viewModel.clearShareText() } }
                )
            ) {
                if let text = viewModel.actionRouter.shareText {
                    ActivityView(activityItems: [text])
                }
            }
            .alert(
                String(localized: "Action unavailable"),
                isPresented: Binding(
                    get: { viewModel.actionRouter.unsupportedMessage != nil },
                    set: { if !$0 { viewModel.clearUnsupportedMessage() } }
                ),
                actions: {
                    Button(String(localized: "OK"), role: .cancel) {}
                },
                message: {
                    Text(viewModel.actionRouter.unsupportedMessage ?? "")
                }
            )
            .alert(
                String(localized: "Action unavailable"),
                isPresented: Binding(
                    get: { viewModel.actionUnavailableMessage != nil },
                    set: { if !$0 { viewModel.clearActionUnavailableMessage() } }
                ),
                actions: {
                    Button(String(localized: "OK"), role: .cancel) {}
                },
                message: {
                    Text(viewModel.actionUnavailableMessage ?? "")
                }
            )
        }
        .bereanGlass(.contextual)
    }

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(BereanPulseGlassIconButtonStyle())
            .accessibilityLabel(Text("Back"))

            Spacer()

            Text(String(localized: "Berean"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button(action: { viewModel.openCurate() }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(BereanPulseGlassIconButtonStyle())
            .accessibilityLabel(Text("Curate Berean Pulse"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .liquidGlassPanel(glassBehavior, cornerRadius: 28, elevated: false)
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch viewModel.feedState {
        case .loading:
            BereanPulseLoadingView()
                .liquidGlassPanel(glassBehavior, cornerRadius: 26, elevated: false)
        case .error(let message):
            BereanPulseErrorStateView(message: message) {
                Task { await viewModel.refresh() }
            }
            .liquidGlassPanel(glassBehavior, cornerRadius: 26, elevated: false)
        case .empty, .cardHidden:
            BereanPulseEmptyStateView {
                Task { await viewModel.refresh() }
            }
            .liquidGlassPanel(glassBehavior, cornerRadius: 26, elevated: false)
        case .loaded, .offlineCached, .limitedPermissions, .refreshing, .permissionRequired, .permissionDenied:
            VStack(alignment: .leading, spacing: 24) {
                contextTrustSection
                continueWorkingSection
                draftSection
                artifactSection
                suggestedActionSection
                BereanPulseSignalPanel(signals: viewModel.signals, isCollapsed: $viewModel.signalsCollapsed)
                allCardsSection
            }
        }
    }

    private var contextTrustSection: some View {
        BereanPulseWorkspaceSection(
            title: String(localized: "Context in use"),
            subtitle: String(localized: "Berean only shows visible signals and asks before using protected sources."),
            actionTitle: String(localized: "Curate"),
            action: { viewModel.openCurate() }
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    BereanPulseTrustPill(icon: "sparkles", title: String(localized: "Signals"), value: "\(visibleSignalCount) visible", isEmphasized: true)
                    BereanPulseTrustPill(icon: "checkmark.shield", title: String(localized: "Permissions"), value: permissionSummary)
                    BereanPulseTrustPill(icon: "folder", title: String(localized: "Work mode"), value: viewModel.preferences.workModeEnabled ? String(localized: "On") : String(localized: "Off"))
                    BereanPulseTrustPill(icon: "text.bubble", title: String(localized: "Tone"), value: viewModel.preferences.preferredTone.rawValue.capitalized)
                }
            }
        }
    }

    @ViewBuilder
    private var continueWorkingSection: some View {
        let cards = Array(viewModel.filteredCards.prefix(3))
        if !cards.isEmpty {
            BereanPulseWorkspaceSection(
                title: String(localized: "Continue working"),
                subtitle: String(localized: "Resume the highest-signal items without digging through history."),
                actionTitle: nil,
                action: nil
            ) {
                VStack(spacing: 10) {
                    ForEach(cards) { card in
                        BereanPulseMiniWorkCard(
                            title: card.title,
                            subtitle: card.whyNow,
                            systemImage: card.mode.systemImage,
                            actionTitle: card.recommendedActionTitle,
                            action: { Task { await viewModel.handlePrimaryAction(for: card) } }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var draftSection: some View {
        let drafts = viewModel.filteredCards.filter { $0.actionType == .draftMessage }
        if !drafts.isEmpty {
            BereanPulseWorkspaceSection(
                title: String(localized: "Drafts waiting"),
                subtitle: String(localized: "Message follow-ups Berean can prepare from real conversation context."),
                actionTitle: nil,
                action: nil
            ) {
                VStack(spacing: 10) {
                    ForEach(drafts.prefix(2)) { card in
                        BereanPulseMiniWorkCard(
                            title: card.title,
                            subtitle: card.subtitle,
                            systemImage: "square.and.pencil",
                            actionTitle: card.recommendedActionTitle,
                            action: { Task { await viewModel.handlePrimaryAction(for: card) } }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var artifactSection: some View {
        let artifacts = viewModel.filteredCards.filter { $0.actionType == .openProjectBrief }
        if !artifacts.isEmpty {
            BereanPulseWorkspaceSection(
                title: String(localized: "Project artifacts"),
                subtitle: String(localized: "Project briefs and work objects already connected to Berean routing."),
                actionTitle: nil,
                action: nil
            ) {
                VStack(spacing: 10) {
                    ForEach(artifacts.prefix(2)) { card in
                        BereanPulseMiniWorkCard(
                            title: card.title,
                            subtitle: card.subtitle,
                            systemImage: "doc.text.magnifyingglass",
                            actionTitle: card.recommendedActionTitle,
                            action: { Task { await viewModel.handlePrimaryAction(for: card) } }
                        )
                    }
                }
            }
        }
    }

    private var suggestedActionSection: some View {
        BereanPulseWorkspaceSection(
            title: String(localized: "Suggested next actions"),
            subtitle: String(localized: "Ranked by relevance, urgency, freshness, permissions, and your curation settings."),
            actionTitle: nil,
            action: nil
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.filteredCards.prefix(4)) { card in
                        BereanPulseActionChip(
                            title: card.recommendedActionTitle,
                            systemImage: card.mode.systemImage,
                            action: { Task { await viewModel.handlePrimaryAction(for: card) } },
                            isPrimary: card.id == topCard?.id,
                            isDisabled: !card.primaryActionIsAvailable
                        )
                    }
                }
            }
        }
    }

    private var allCardsSection: some View {
        BereanPulseWorkspaceSection(
            title: String(localized: "Pulse cards"),
            subtitle: String(localized: "Inspectable reasons, sources, permissions, feedback, and routed actions."),
            actionTitle: nil,
            action: nil
        ) {
            VStack(spacing: 14) {
                ForEach(viewModel.filteredCards) { card in
                    BereanPulseCardView(
                        card: card,
                        isExpanded: viewModel.isExpanded(card.id),
                        permissionManager: viewModel.permissionManager,
                        onExpand: {
                            if !reduceMotion { softHaptic() }
                            viewModel.toggleExpanded(card.id)
                        },
                        onPrimaryAction: {
                            Task { await viewModel.handlePrimaryAction(for: card) }
                        },
                        onLike: {
                            softHaptic()
                            viewModel.sendFeedback(.liked, for: card)
                        },
                        onDislike: {
                            softHaptic()
                            viewModel.sendFeedback(.disliked, for: card)
                        },
                        onSave: {
                            softHaptic()
                            viewModel.toggleSaved(card)
                        },
                        onShare: {
                            let action = BereanPulseAction(id: "\(card.id)_share", title: String(localized: "Share"), type: .shareCard, payload: [:], requiresPermission: false, permissionType: nil)
                            Task { await viewModel.perform(action, for: card) }
                        },
                        onHide: {
                            softHaptic()
                            viewModel.hide(card)
                        },
                        onAskBerean: {
                            let action = BereanPulseAction(id: "\(card.id)_ask", title: String(localized: "Ask Berean"), type: .askBerean, payload: ["prompt": card.expandedBody], requiresPermission: false, permissionType: nil)
                            Task { await viewModel.perform(action, for: card) }
                        },
                        onWhyNow: {
                            viewModel.toggleExpanded(card.id)
                        }
                    )
                }
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.985, green: 0.985, blue: 0.975),
                Color(red: 0.955, green: 0.972, blue: 0.965)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var topFade: some View {
        LinearGradient(
            colors: [Color.white.opacity(0.92), Color.white.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 110)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    private var topCard: BereanPulseCard? {
        viewModel.filteredCards.first
    }

    private var visibleSignalCount: Int {
        viewModel.signals.filter(\.isUserVisible).count
    }

    private var permissionSummary: String {
        let blocked = BereanPulsePermissionSource.allCases.filter { source in
            viewModel.permissionManager.status(for: source) == .denied
        }.count
        return blocked == 0 ? String(localized: "Inspectable") : "\(blocked) blocked"
    }

    private var collapseProgress: CGFloat {
        min(max(-scrollOffset / 120, 0), 1)
    }

    private var glassBehavior: LiquidGlassScrollBehavior {
        LiquidGlassScrollBehavior(offset: scrollOffset, velocityHint: scrollOffset * 0.4)
    }

    private func askTopCard() {
        guard let card = topCard else { return }
        softHaptic()
        let action = BereanPulseAction(id: "\(card.id)_dock_ask", title: String(localized: "Ask Berean"), type: .askBerean, payload: ["prompt": card.expandedBody], requiresPermission: false, permissionType: nil)
        Task { await viewModel.perform(action, for: card) }
    }

    private func softHaptic() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter
    }()
}

private struct BereanPulseScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> Void) {}
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    BereanPulseView(viewModel: BereanPulseViewModel(service: BereanPulseService(provider: MockBereanPulseProvider())))
}
