import SwiftUI
import FirebaseFunctions

@MainActor
final class AmbientOSViewModel: ObservableObject {
    @Published private(set) var context: AmbientContext?
    @Published private(set) var summary: AmbientSummary?
    @Published private(set) var composerIntent: SmartComposerIntent?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var mode: AmbientMode = .default

    private let service: AmbientOSService

    init(service: AmbientOSService = AmbientOSService()) {
        self.service = service
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snapshot = try await service.fetchAmbientContext(mode: mode)
            context = snapshot.context
            summary = try await service.summarize(snapshot.context, fallback: snapshot.summary)
        } catch {
            errorMessage = error.localizedDescription
            if let fallback = try? await service.loadMockSnapshot() {
                context = fallback.context
                summary = fallback.summary
            }
        }
    }

    func setMode(_ newMode: AmbientMode) {
        guard mode != newMode else { return }
        mode = newMode
        Task { await load() }
    }

    func classifyComposerText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            composerIntent = nil
            return
        }

        composerIntent = try? await service.classifyComposerText(trimmed)
    }
}

struct AmbientOSService {
    struct Snapshot {
        let context: AmbientContext
        let summary: AmbientSummary?
    }

    private struct MockEnvelope: Decodable {
        let context: AmbientContext
        let summary: AmbientSummary?

        enum CodingKeys: String, CodingKey {
            case generatedAt
            case user
            case prayer
            case notes
            case messages
            case calendar
            case church
            case selah
            case arise
            case bereanSuggestion
            case mode
            case summary = "_summary"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let generatedAt = try container.decode(String.self, forKey: .generatedAt)
            let user = try container.decode(AmbientUser.self, forKey: .user)
            let prayer = try container.decode(AmbientPrayer.self, forKey: .prayer)
            let notes = try container.decode(AmbientNotes.self, forKey: .notes)
            let messages = try container.decode(AmbientMessages.self, forKey: .messages)
            let calendar = try container.decode(AmbientCalendar.self, forKey: .calendar)
            let church = try container.decode(AmbientChurch.self, forKey: .church)
            let selah = try container.decode(AmbientSelah.self, forKey: .selah)
            let arise = try container.decode(AmbientArise.self, forKey: .arise)
            let bereanSuggestion = try container.decodeIfPresent(AmbientBereanSuggestion.self, forKey: .bereanSuggestion)
            let mode = try container.decode(AmbientMode.self, forKey: .mode)

            context = AmbientContext(
                generatedAt: generatedAt,
                user: user,
                prayer: prayer,
                notes: notes,
                messages: messages,
                calendar: calendar,
                church: church,
                selah: selah,
                arise: arise,
                bereanSuggestion: bereanSuggestion,
                mode: mode
            )
            summary = try container.decodeIfPresent(AmbientSummary.self, forKey: .summary)
        }
    }

    private let functions = Functions.functions(region: "us-central1")
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func fetchAmbientContext(mode: AmbientMode) async throws -> Snapshot {
        let result = try await functions.httpsCallable("getAmbientContext").call(["mode": mode.rawValue])
        let context = try decode(AmbientContext.self, from: result.data)
        return Snapshot(context: context, summary: nil)
    }

    func summarize(_ context: AmbientContext, fallback: AmbientSummary?) async throws -> AmbientSummary {
        do {
            let contextData = try encoder.encode(context)
            let contextObject = try JSONSerialization.jsonObject(with: contextData)
            let result = try await functions.httpsCallable("summarizeAmbientContext").call(["context": contextObject])
            return try decode(AmbientSummary.self, from: result.data)
        } catch {
            if let fallback {
                return fallback
            }
            throw error
        }
    }

    func classifyComposerText(_ text: String) async throws -> SmartComposerIntent {
        let result = try await functions.httpsCallable("classifyComposerIntent").call(["text": text])
        return try decode(SmartComposerIntent.self, from: result.data)
    }

    func loadMockSnapshot() async throws -> Snapshot {
        guard let url = Bundle.main.url(forResource: "mock_ambient_context", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        let envelope = try decoder.decode(MockEnvelope.self, from: data)
        return Snapshot(context: envelope.context, summary: envelope.summary)
    }

    private func decode<T: Decodable>(_ type: T.Type, from object: Any) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        return try decoder.decode(T.self, from: data)
    }
}

struct AmbientOSSurfaceView: View {
    @StateObject private var viewModel = AmbientOSViewModel()
    @ObservedObject private var flags = AMENFeatureFlags.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                if flags.ambientOSEnabled {
                    ScrollView {
                        VStack(spacing: 18) {
                            if let context = viewModel.context, let summary = viewModel.summary {
                                AmbientHomeHeaderView(context: context, summary: summary) { mode in
                                    withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.82))) {
                                        viewModel.setMode(mode)
                                    }
                                }
                                AmbientPriorityActionsView(actions: summary.actions)
                                AmbientSmartComposerView(intent: viewModel.composerIntent) { text in
                                    await viewModel.classifyComposerText(text)
                                }
                                AmbientWorkspaceCardsView(context: context)
                                AmbientNLPlannerView()
                                AmbientDestinationCardsView(events: context.church.upcomingEvents)
                                AmbientOperatingModeGateView(mode: context.mode)
                            } else if viewModel.isLoading {
                                AmbientLoadingView()
                            } else {
                                AmbientEmptyStateView(errorMessage: viewModel.errorMessage) {
                                    Task { await viewModel.load() }
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                    }
                    .task { await viewModel.load() }
                    .refreshable { await viewModel.load() }
                } else {
                    AmbientFeatureDisabledView()
                }
            }
            .background(AmenTheme.Colors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Ambient")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct AmbientHomeHeaderView: View {
    let context: AmbientContext
    let summary: AmbientSummary
    let onModeSelected: (AmbientMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Label(modeLabel, systemImage: modeIcon)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGoldText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .ambientGlassChrome(tint: AmenTheme.Colors.amenGold, radius: 18)

                Spacer()

                Menu {
                    ForEach(AmbientMode.allCases, id: \.rawValue) { mode in
                        Button {
                            onModeSelected(mode)
                        } label: {
                            Label(mode.menuTitle, systemImage: mode.symbol)
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.systemScaled(16, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .ambientGlassChrome(tint: AmenTheme.Colors.amenGold, radius: 20)
                }
                .accessibilityLabel("Ambient mode")
            }

            Text(summary.greetingProse)
                .font(.systemScaled(28, weight: .bold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if let nextEvent = context.calendar.nextEvent {
                    AmbientSignalPill(symbol: "calendar", title: nextEvent.title, subtitle: nextEvent.startsAt.ambientTimeLabel)
                }
                if let suggestion = context.bereanSuggestion {
                    AmbientSignalPill(symbol: suggestion.kind.symbol, title: suggestion.label, subtitle: "Berean")
                }
            }
        }
        .padding(18)
        .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AmenTheme.Colors.borderSoft, lineWidth: 0.75))
    }

    private var modeLabel: String { context.mode.menuTitle }
    private var modeIcon: String { context.mode.symbol }
}

struct AmbientPriorityActionsView: View {
    let actions: [PriorityAction]

    private var scheduledActions: [PriorityAction] { actions.filter { $0.scheduledAt != nil } }
    private var unscheduledActions: [PriorityAction] { actions.filter { $0.scheduledAt == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AmbientSectionHeader(title: "Priority Actions", symbol: "checklist")

            if actions.isEmpty {
                Text("Nothing needs review right now.")
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    ForEach(scheduledActions) { action in
                        PriorityActionRow(action: action, showsRail: true)
                    }

                    if !unscheduledActions.isEmpty {
                        Text("Unscheduled")
                            .font(.systemScaled(12, weight: .bold))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, scheduledActions.isEmpty ? 0 : 4)

                        ForEach(unscheduledActions) { action in
                            PriorityActionRow(action: action, showsRail: false)
                        }
                    }
                }
            }
        }
    }
}

struct PriorityActionRow: View {
    let action: PriorityAction
    let showsRail: Bool

    var body: some View {
        Button {
            action.openDeepLink()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    Circle()
                        .fill(action.tier.tint)
                        .frame(width: 10, height: 10)
                    if showsRail {
                        Rectangle()
                            .fill(AmenTheme.Colors.borderSoft)
                            .frame(width: 1, height: 42)
                    }
                }
                .padding(.top, 6)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Image(systemName: action.source.symbol)
                            .foregroundStyle(action.tier.tint)
                        Text(action.source.label)
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                        if let scheduledAt = action.scheduledAt {
                            Text(scheduledAt.ambientTimeLabel)
                                .font(.systemScaled(12, weight: .semibold))
                                .foregroundStyle(AmenTheme.Colors.amenGoldText)
                        }
                    }

                    Text(action.title)
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.systemScaled(12, weight: .bold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .padding(.top, 6)
            }
            .padding(14)
            .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AmenTheme.Colors.borderSoft, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }
}

struct GlassToolRailView: View {
    let items: [GlassToolRailItem]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items) { item in
                Button(action: item.action) {
                    Image(systemName: item.sfSymbol)
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(item.isDestructive ? AmenTheme.Colors.statusError : AmenTheme.Colors.textPrimary)
                        .frame(width: 42, height: 42)
                        .ambientGlassChrome(tint: item.isDestructive ? AmenTheme.Colors.statusError : AmenTheme.Colors.amenGold, radius: 21)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
            }
        }
        .padding(8)
        .ambientGlassChrome(tint: AmenTheme.Colors.amenGold, radius: 28)
    }
}

struct AmbientSmartComposerView: View {
    let intent: SmartComposerIntent?
    let classify: (String) async -> Void

    @State private var text = ""
    @State private var classifyTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AmbientSectionHeader(title: "Composer", symbol: "square.and.pencil")

            VStack(alignment: .leading, spacing: 12) {
                TextField("Share a prayer, testimony, note, or plan", text: $text, axis: .vertical)
                    .font(.systemScaled(16, weight: .regular))
                    .lineLimit(3...6)
                    .padding(12)
                    .background(AmenTheme.Colors.surfaceInput, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onChange(of: text) { _, newValue in
                        classifyTask?.cancel()
                        classifyTask = Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            guard !Task.isCancelled else { return }
                            await classify(newValue)
                        }
                    }

                if let intent, !intent.chips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(intent.chips, id: \.rawValue) { chip in
                                Label(chip.label, systemImage: chip.symbol)
                                    .font(.systemScaled(13, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .ambientGlassChrome(tint: AmenTheme.Colors.amenGold, radius: 16)
                            }
                        }
                    }
                }

                HStack {
                    if let postType = intent?.postType {
                        Text(postType.rawValue)
                            .font(.systemScaled(12, weight: .bold))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }

                    Spacer()

                    Button {
                    } label: {
                        Label("Review", systemImage: "checkmark.seal")
                            .font(.systemScaled(15, weight: .bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .ambientGlassChrome(tint: AmenTheme.Colors.amenGold, radius: 18)
                    }
                    .buttonStyle(.plain)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(14)
            .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AmenTheme.Colors.borderSoft, lineWidth: 0.75))
        }
    }
}

struct AmbientWorkspaceCardsView: View {
    let context: AmbientContext

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AmbientSectionHeader(title: "Workspaces", symbol: "rectangle.3.group")

            VStack(spacing: 10) {
                WorkspaceRow(symbol: "building.2", title: "Church", subtitle: context.church.nextService?.title ?? "No service scheduled", status: context.church.nextService?.startsAt.ambientDateLabel ?? "Quiet")
                WorkspaceRow(symbol: "person.2", title: "Family", subtitle: context.prayer.awaitingResponse.first?.title ?? "Prayer queue clear", status: "Private")
                WorkspaceRow(symbol: "bubble.left.and.bubble.right", title: "Groups", subtitle: context.messages.needingFollowUp.first?.title ?? "No follow-up flagged", status: "Review only")
            }
        }
    }
}

struct WorkspaceRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let status: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.systemScaled(18, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenGoldText)
                .frame(width: 38, height: 38)
                .ambientGlassChrome(tint: AmenTheme.Colors.amenGold, radius: 19)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.systemScaled(16, weight: .bold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text(subtitle)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(status)
                .font(.systemScaled(12, weight: .bold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .padding(14)
        .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AmenTheme.Colors.borderSoft, lineWidth: 0.75))
    }
}

struct AmbientNLPlannerView: View {
    @State private var planText = ""
    @State private var draftItems: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AmbientSectionHeader(title: "Planner", symbol: "wand.and.stars")

            VStack(alignment: .leading, spacing: 12) {
                TextField("Describe plans to structure for review", text: $planText, axis: .vertical)
                    .font(.systemScaled(15, weight: .regular))
                    .lineLimit(2...5)
                    .padding(12)
                    .background(AmenTheme.Colors.surfaceInput, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                if !draftItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(draftItems, id: \.self) { item in
                            Label(item, systemImage: "circle")
                                .font(.systemScaled(14, weight: .medium))
                                .foregroundStyle(AmenTheme.Colors.textPrimary)
                        }
                    }
                }

                Button {
                    draftItems = makeDraftItems(from: planText)
                } label: {
                    Label("Create Draft", systemImage: "list.bullet.clipboard")
                        .font(.systemScaled(15, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .ambientGlassChrome(tint: AmenTheme.Colors.amenGold, radius: 18)
                }
                .buttonStyle(.plain)
                .disabled(planText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
            .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AmenTheme.Colors.borderSoft, lineWidth: 0.75))
        }
    }

    private func makeDraftItems(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return [
            "Clarify purpose: \(trimmed)",
            "Choose date and owner",
            "Review before creating tasks"
        ]
    }
}

struct AmbientDestinationCardsView: View {
    let events: [EventRef]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AmbientSectionHeader(title: "Destinations", symbol: "mappin.and.ellipse")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(events) { event in
                        DestinationCard(event: event)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct DestinationCard: View {
    let event: EventRef

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.systemScaled(20, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(event.startsAt.ambientDateLabel)
                    .font(.systemScaled(13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
            }

            HStack(spacing: 8) {
                Label("Service", systemImage: "clock")
                Label("Ministry", systemImage: "hands.sparkles")
            }
            .font(.systemScaled(12, weight: .bold))
            .foregroundStyle(.white)
        }
        .padding(16)
        .frame(width: 250, height: 170)
        .background(
            LinearGradient(
                colors: [AmenTheme.Colors.amenGold.opacity(0.72), AmenTheme.Colors.textPrimary.opacity(0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.24), lineWidth: 0.75))
    }
}

struct AmbientOperatingModeGateView: View {
    let mode: AmbientMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionHeader(title: "Operating Mode", symbol: "shield.lefthalf.filled")

            HStack(spacing: 12) {
                Image(systemName: mode.symbol)
                    .font(.systemScaled(18, weight: .bold))
                    .foregroundStyle(AmenTheme.Colors.amenGoldText)
                    .frame(width: 38, height: 38)
                    .ambientGlassChrome(tint: AmenTheme.Colors.amenGold, radius: 19)

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.menuTitle)
                        .font(.systemScaled(16, weight: .bold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text("Self-administration only. Every suggested action stays a draft until reviewed.")
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AmenTheme.Colors.borderSoft, lineWidth: 0.75))
        }
    }
}

struct AmbientSignalPill: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.systemScaled(12, weight: .bold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(AmenTheme.Colors.amenGoldText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AmenTheme.Colors.surfaceChip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct AmbientSectionHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(AmenTheme.Colors.amenGoldText)
            Text(title)
                .font(.systemScaled(18, weight: .bold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Spacer()
        }
    }
}

struct AmbientLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading Ambient context")
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

struct AmbientFeatureDisabledView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenGoldText)
            Text("Ambient OS is off")
                .font(.systemScaled(18, weight: .bold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("Enable Remote Config key ambient_os_enabled only after privacy review, Aegis review, and fleet verification are complete.")
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(18)
    }
}

struct AmbientEmptyStateView: View {
    let errorMessage: String?
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenGoldText)
            Text(errorMessage ?? "Ambient context is not available yet.")
                .font(.systemScaled(15, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.systemScaled(15, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .ambientGlassChrome(tint: AmenTheme.Colors.amenGold, radius: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AmbientGlassChromeModifier: ViewModifier {
    let tint: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(Glass.regular.tint(tint).interactive(), in: .rect(cornerRadius: radius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(tint.opacity(0.28), lineWidth: 0.75))
        }
    }
}

private extension View {
    func ambientGlassChrome(tint: Color, radius: CGFloat) -> some View {
        modifier(AmbientGlassChromeModifier(tint: tint, radius: radius))
    }
}

extension AmbientMode: CaseIterable {
    static var allCases: [AmbientMode] { [.default, .driving, .atChurch] }

    var menuTitle: String {
        switch self {
        case .default: return "Default"
        case .driving: return "Driving"
        case .atChurch: return "At Church"
        }
    }

    var symbol: String {
        switch self {
        case .default: return "sun.max"
        case .driving: return "car"
        case .atChurch: return "building.columns"
        }
    }
}

private extension BereanSuggestionKind {
    var symbol: String {
        switch self {
        case .study: return "book"
        case .pray: return "hands.sparkles"
        case .reflect: return "text.bubble"
        }
    }
}

private extension ComposerChip {
    var label: String {
        switch self {
        case .photo: return "Photo"
        case .churchNote: return "Church Note"
        case .event: return "Event"
        case .prayerRequest: return "Prayer"
        case .sermon: return "Sermon"
        case .scripture: return "Scripture"
        }
    }

    var symbol: String {
        switch self {
        case .photo: return "photo"
        case .churchNote: return "note.text"
        case .event: return "calendar"
        case .prayerRequest: return "hands.sparkles"
        case .sermon: return "mic"
        case .scripture: return "book"
        }
    }
}

private extension ActionTier {
    var tint: Color {
        switch self {
        case .high: return AmenTheme.Colors.statusError
        case .medium: return AmenTheme.Colors.amenGold
        case .low: return AmenTheme.Colors.textSecondary
        }
    }
}

private extension ActionSource {
    var label: String {
        switch self {
        case .prayer: return "Prayer"
        case .note: return "Note"
        case .message: return "Message"
        case .church: return "Church"
        case .selah: return "Selah"
        case .berean: return "Berean"
        }
    }

    var symbol: String {
        switch self {
        case .prayer: return "hands.sparkles"
        case .note: return "note.text"
        case .message: return "message"
        case .church: return "building.columns"
        case .selah: return "book.closed"
        case .berean: return "sparkles"
        }
    }
}

private extension PriorityAction {
    func openDeepLink() {
        guard let url = URL(string: deepLink) else { return }
        UIApplication.shared.open(url)
    }
}

private extension String {
    var ambientTimeLabel: String {
        guard let date = ISO8601DateFormatter.ambient.date(from: self) else { return self }
        return date.formatted(date: .omitted, time: .shortened)
    }

    var ambientDateLabel: String {
        guard let date = ISO8601DateFormatter.ambient.date(from: self) else { return self }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private extension ISO8601DateFormatter {
    static let ambient: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

#Preview {
    AmbientOSSurfaceView()
}
