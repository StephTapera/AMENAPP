import SwiftUI
import UIKit

protocol SupportSignalProducing {
    var supportSurface: SupportSurface { get }
    var supportContentText: String { get }
    var supportSourceId: String? { get }
    var supportMetadata: [String: String] { get }
}

enum SupportPresentationMode: Equatable {
    case none
    case chips([SupportActionChip])
    case inlineCard(SupportInlineCardModel)
    case sheet(SupportInterventionSheetModel)
}

struct SupportActionChip: Identifiable, Equatable {
    let id: String
    let title: String
    let action: SupportAction

    init(action: SupportAction) {
        self.id = action.id
        self.title = action.title
        self.action = action
    }
}

struct SupportInlineCardModel: Equatable {
    let title: String
    let message: String
}

struct SupportInterventionSheetModel: Equatable {
    let title: String
    let message: String
    let allowContinue: Bool
}

struct SupportInterventionPayload: Identifiable {
    let id = UUID()
    let surface: SupportSurface
    let sourceId: String?
    let analyzedText: String
    let metadata: [String: String]
    let decision: SupportRouteDecision
    let presentationMode: SupportPresentationMode

    var actions: [SupportAction] { decision.actions }
    var riskTier: SupportRiskTier {
        switch decision.routingLevel {
        case .none:
            return .none
        case .gentleSupport:
            return .low
        case .guidedSupport:
            return .moderate
        case .immediateHelp:
            return .elevated
        }
    }
}

struct SupportDestination: Identifiable {
    enum Kind {
        case resources
        case berean
        case findChurch
        case mentalHealth
        case nonprofits
        case trustedCircle
        case churchNotes
        case helpingSomeoneElse
        case prayerSupport
    }

    let id = UUID()
    let kind: Kind
    let title: String?
    let detail: String?
}

@MainActor
final class SupportDetectionService: ObservableObject {
    static let shared = SupportDetectionService()

    private let coordinator = SupportIntelligenceCoordinator.shared

    func analyzeSupport(
        surface: SupportSurface,
        text: String,
        sourceId: String? = nil,
        metadata: [String: String] = [:]
    ) async -> SupportInterventionPayload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumCharacterThreshold(for: surface) else { return nil }

        let decision = await coordinator.analyze(text: trimmed, surface: surface, sourceId: sourceId)
        let presentationMode = presentationMode(for: decision, surface: surface)

        guard presentationMode != .none else { return nil }

        return SupportInterventionPayload(
            surface: surface,
            sourceId: sourceId,
            analyzedText: trimmed,
            metadata: metadata,
            decision: decision,
            presentationMode: presentationMode
        )
    }

    func record(payload: SupportInterventionPayload, outcome: InterventionOutcome) {
        Task {
            await coordinator.recordIntervention(
                surface: payload.surface,
                decision: payload.decision,
                outcome: outcome
            )
        }
    }

    private func minimumCharacterThreshold(for surface: SupportSurface) -> Int {
        switch surface {
        case .dmDraft:
            return 18
        case .churchNote:
            return 24
        case .prayerRequest, .prayerComposer, .postDraft:
            return 12
        default:
            return 10
        }
    }

    private func presentationMode(for decision: SupportRouteDecision, surface: SupportSurface) -> SupportPresentationMode {
        switch surface {
        case .postDraft:
            switch decision.routingLevel {
            case .none:
                return .none
            case .gentleSupport:
                return .chips(chips(from: decision))
            case .guidedSupport:
                return .inlineCard(
                    SupportInlineCardModel(
                        title: "Support Before You Post",
                        message: "You can keep this private, turn it into prayer, or take a smaller next step first."
                    )
                )
            case .immediateHelp:
                return .sheet(
                    SupportInterventionSheetModel(
                        title: "Pause Before Posting",
                        message: "This sounds heavy. You can still continue, but support options are ready first.",
                        allowContinue: true
                    )
                )
            }
        case .dmDraft:
            switch decision.routingLevel {
            case .none, .gentleSupport:
                return .none
            case .guidedSupport:
                return .inlineCard(
                    SupportInlineCardModel(
                        title: "Pause Before Sending",
                        message: "A calmer next step, support option, or trusted contact may help before this message goes out."
                    )
                )
            case .immediateHelp:
                return .sheet(
                    SupportInterventionSheetModel(
                        title: "Support Before Sending",
                        message: "This message may need immediate support or a safer pause before it is sent.",
                        allowContinue: true
                    )
                )
            }
        case .prayerRequest, .prayerComposer:
            switch decision.routingLevel {
            case .none:
                return .none
            case .gentleSupport:
                return .chips(chips(from: decision))
            case .guidedSupport:
                return .inlineCard(
                    SupportInlineCardModel(
                        title: "Turn Prayer Into Care",
                        message: "Prayer can stay central while support, church, or practical next steps stay close."
                    )
                )
            case .immediateHelp:
                return .sheet(
                    SupportInterventionSheetModel(
                        title: "Immediate Support Is Available",
                        message: "We can keep this prayer private and still place urgent support options right here.",
                        allowContinue: true
                    )
                )
            }
        case .churchNote:
            switch decision.routingLevel {
            case .none:
                return .none
            case .gentleSupport, .guidedSupport:
                return .inlineCard(
                    SupportInlineCardModel(
                        title: "Care & Action",
                        message: "Your notes suggest a few next steps you may want to keep with this reflection."
                    )
                )
            case .immediateHelp:
                return .sheet(
                    SupportInterventionSheetModel(
                        title: "Care Summary Ready",
                        message: "Your notes point to support options worth reviewing before you move on.",
                        allowContinue: true
                    )
                )
            }
        default:
            return .none
        }
    }

    private func chips(from decision: SupportRouteDecision) -> [SupportActionChip] {
        Array(decision.actions.prefix(3)).map(SupportActionChip.init(action:))
    }
}

@MainActor
final class SupportActionExecutor: ObservableObject {
    static let shared = SupportActionExecutor()

    @Published var activeDestination: SupportDestination?

    func execute(_ action: SupportAction, from surface: SupportSurface) {
        switch action.type {
        case .openGroundingExercise, .openBreathingTool, .openCounselingResources, .openSupportGroups:
            activeDestination = SupportDestination(kind: .mentalHealth, title: action.title, detail: nil)
        case .openPrayerFlow, .convertToPrivatePrayer:
            activeDestination = SupportDestination(kind: .prayerSupport, title: action.title, detail: action.promptTemplate)
        case .openBerean:
            activeDestination = SupportDestination(kind: .berean, title: action.title, detail: action.promptTemplate)
        case .openFindChurch, .shareWithPastorOrCareTeam:
            activeDestination = SupportDestination(kind: .findChurch, title: action.title, detail: action.filters["supportTag"])
        case .openNonprofitResources:
            activeDestination = SupportDestination(kind: .nonprofits, title: action.title, detail: action.filters["need"])
        case .openHelpingSomeoneElse:
            activeDestination = SupportDestination(kind: .helpingSomeoneElse, title: action.title, detail: nil)
        case .messageTrustedContact:
            activeDestination = SupportDestination(kind: .trustedCircle, title: action.title, detail: nil)
        case .saveToPrivateNotes, .viewResourcePlan:
            activeDestination = SupportDestination(kind: .churchNotes, title: action.title, detail: nil)
        case .call988:
            openURL("tel://988")
        case .text988:
            openURL("sms:988")
        case .textCrisisLine:
            openURL("sms:741741")
        case .call911:
            openURL("tel://911")
        }
    }

    func clearDestination() {
        activeDestination = nil
    }

    private func openURL(_ rawValue: String) {
        guard let url = URL(string: rawValue) else { return }
        UIApplication.shared.open(url)
    }
}

struct SupportChipsRowView: View {
    let chips: [SupportActionChip]
    let onTap: (SupportAction) -> Void
    let onDismiss: (() -> Void)?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    Button {
                        onTap(chip.action)
                    } label: {
                        Text(chip.title)
                            .font(AMENFont.semiBold(12))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(reduceTransparency
                                        ? AnyShapeStyle(AmenTheme.Colors.backgroundElevated)
                                        : AnyShapeStyle(.ultraThinMaterial))
                                    .overlay(
                                        Capsule()
                                            .stroke(AmenTheme.Colors.borderSoft, lineWidth: 0.8)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }

                if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.systemScaled(11, weight: .bold))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(AmenTheme.Colors.surfaceGrouped)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct SupportInlineCardView: View {
    let model: SupportInlineCardModel
    let actions: [SupportAction]
    let onTap: (SupportAction) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.accentPrimary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)

                    Text(model.message)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.systemScaled(11, weight: .bold))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            SupportChipsRowView(
                chips: Array(actions.prefix(3)).map { action in
                    SupportActionChip(action: action)
                },
                onTap: onTap,
                onDismiss: nil
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(AmenTheme.Colors.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(AmenTheme.Colors.borderSoft, lineWidth: 0.8)
                )
        )
    }
}

struct SupportInterventionSheetView: View {
    let model: SupportInterventionSheetModel
    let actions: [SupportAction]
    let onAction: (SupportAction) -> Void
    let onDismiss: () -> Void
    let onContinue: (() -> Void)?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.title)
                        .font(AMENFont.bold(24))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)

                    Text(model.message)
                        .font(AMENFont.regular(15))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    ForEach(actions) { action in
                        Button {
                            onAction(action)
                        } label: {
                            HStack {
                                Text(action.title)
                                    .font(AMENFont.semiBold(15))
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.systemScaled(12, weight: .semibold))
                            }
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(AmenTheme.Colors.surfaceGrouped)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(AmenTheme.Colors.borderSoft, lineWidth: 0.8)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if model.allowContinue, let onContinue {
                    Button("Continue Anyway") {
                        onContinue()
                    }
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }

                Spacer()
            }
            .padding(20)
            .background(AmenTheme.Colors.backgroundBase.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }
}

private struct SupportDestinationSheetModifier: ViewModifier {
    @ObservedObject private var executor = SupportActionExecutor.shared

    func body(content: Content) -> some View {
        content
            .sheet(item: $executor.activeDestination, onDismiss: {
                executor.clearDestination()
            }) { destination in
                destinationView(for: destination)
            }
    }

    @ViewBuilder
    private func destinationView(for destination: SupportDestination) -> some View {
        switch destination.kind {
        case .resources:
            ResourcesView()
        case .berean:
            BereanLandingView()
        case .findChurch:
            FindChurchView()
        case .mentalHealth:
            MentalHealthDetailView()
        case .nonprofits:
            GivingHomeView()
        case .trustedCircle:
            TrustedCircleView()
        case .churchNotes:
            ChurchNotesView()
        case .helpingSomeoneElse:
            PlaceholderResourceView(
                title: destination.title ?? "Helping Someone Else",
                description: "Guidance for what to say, what to avoid, and when to escalate urgently.",
                icon: "person.2.wave.2.fill",
                iconColor: Color(hex: "EC4899")
            )
        case .prayerSupport:
            PlaceholderResourceView(
                title: destination.title ?? "Prayer Support",
                description: "Keep prayer central while moving toward care, church, or practical next steps.",
                icon: "hands.sparkles.fill",
                iconColor: Color(hex: "F59E0B")
            )
        }
    }
}

extension View {
    func supportDestinationSheet() -> some View {
        modifier(SupportDestinationSheetModifier())
    }
}
