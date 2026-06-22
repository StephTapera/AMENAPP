import SwiftUI
import Foundation

// MARK: - AmenDailyDigestView
//
// Home presentation for Agent A. This extends the canonical Pulse engine rather than
// reading a parallel spiritualOS_digest collection or calling getSpiritualDigest.
// Placement: top of Home tab, above the feed. Bounded, finite, and flag-off invisible.

struct AmenDailyDigestView: View {

    @ObservedObject var viewModel: AmenDailyDigestViewModel
    var userId: String

    @AppStorage("spiritualOS_enabled") private var masterEnabled: Bool = false
    @AppStorage("spiritualOS_daily_enabled") private var isEnabled: Bool = false

    @StateObject private var pulseViewModel = AmenPulseViewModel()
    @Namespace private var morph
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !(masterEnabled && isEnabled) {
            EmptyView()
        } else {
            content
                .task { await pulseViewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch pulseViewModel.phase {
        case .loading:
            loadingState
        case .failed(let message):
            errorState(message)
        case .empty:
            quietState
        case .loaded:
            pulseDailyContent
        }
    }

    @ViewBuilder
    private var pulseDailyContent: some View {
        if let card = primaryPulseCard {
            VStack(alignment: .leading, spacing: 12) {
                header
                PulseHeroCardView(
                    card: card,
                    namespace: morph,
                    isSourceForMorph: true,
                    isHidden: false,
                    onOpen: { route(card) }
                )
                .accessibilityHint(PulseActionRouter.shared.canRoute(card) ? "Double tap to open" : "Open Pulse for the full daily briefing")

                openPulseButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        } else {
            quietState
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Amen Daily")
                    .font(.systemScaled(26, weight: .bold))
                    .foregroundStyle(Color.amenBlack)
                Text("A bounded Pulse briefing for today")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(Color.amenSlate.opacity(0.72))
            }
            Spacer(minLength: 12)
            Text(Self.dateEyebrow)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.amenSlate.opacity(0.58))
                .textCase(.uppercase)
        }
        .accessibilityElement(children: .combine)
    }

    private var primaryPulseCard: PulseCard? {
        pulseViewModel.visibleCards.first(where: { $0.kind == .dailyBriefHero })
            ?? pulseViewModel.visibleCards.first(where: { $0.kind != .terminus })
            ?? pulseViewModel.digest?.cards.first(where: { $0.kind != .terminus })
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.amenSlate.opacity(0.12))
                .frame(width: 152, height: 22)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.amenSlate.opacity(0.10))
                .frame(height: 260)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .accessibilityLabel("Loading Amen Daily")
    }

    private var quietState: some View {
        VStack(spacing: 10) {
            Image(systemName: "wind")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Color.amenSlate.opacity(0.7))
            Text("Nothing needs you right now.")
                .font(.systemScaled(17, weight: .semibold))
                .foregroundStyle(Color.amenBlack)
            Text("Pulse will be here when there is something timely to carry.")
                .font(.systemScaled(13))
                .foregroundStyle(Color.amenSlate.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.amenSlate.opacity(0.7))
            Text("Amen Daily could not load.")
                .font(.systemScaled(17, weight: .semibold))
                .foregroundStyle(Color.amenBlack)
            Text(message)
                .font(.systemScaled(12))
                .foregroundStyle(Color.amenSlate.opacity(0.75))
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await pulseViewModel.load() }
            }
            .font(.systemScaled(14, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
    }

    private var openPulseButton: some View {
        Button {
            DeepLinkRouter.shared.navigate(to: .intelligence(cardId: nil))
        } label: {
            Label("Open full Pulse", systemImage: "sparkles")
                .font(.systemScaled(14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .accessibilityHint("Opens the bounded Pulse surface")
    }

    private func route(_ card: PulseCard) {
        if PulseActionRouter.shared.canRoute(card) {
            PulseActionRouter.shared.route(card)
        } else {
            DeepLinkRouter.shared.navigate(to: .intelligence(cardId: card.id))
        }
    }

    private static var dateEyebrow: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: Date())
    }
}
