import SwiftUI

struct BereanPulseCardView: View {
    let card: BereanPulseCard
    let isExpanded: Bool
    let permissionManager: BereanPulsePermissionManager
    let onExpand: () -> Void
    let onPrimaryAction: () -> Void
    let onLike: () -> Void
    let onDislike: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onHide: () -> Void
    let onAskBerean: () -> Void
    let onWhyNow: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            titleBlock
            sourceChips

            if !card.permissionRequirements.isEmpty {
                permissionBanner
            }

            if isExpanded {
                BereanPulseCardDetailView(card: card)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text(card.insight)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actionRow
        }
        .padding(18)
        .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.07), radius: 18, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: onExpand)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(accessibilitySummary))
        .accessibilityHint(Text("Double tap to expand or collapse this Berean Pulse card."))
        // Pattern 2: canonical bouncy spring for card expand/collapse
        .animation(reduceMotion ? .none : Motion.liquidSpring, value: isExpanded)
    }

    private var accessibilitySummary: String {
        let mode = String(localized: card.mode.titleKey)
        return "\(mode). \(card.title). \(card.whyNow)."
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(String(localized: card.mode.titleKey), systemImage: card.mode.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.05), in: Capsule(style: .continuous))
                .accessibilityElement(children: .combine)

            Text("\(Int(card.matchScore * 100))% match")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.04), in: Capsule(style: .continuous))

            if card.privacyLevel != .low {
                Label(card.privacyLevel.rawValue.capitalized, systemImage: "lock.shield")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.04), in: Capsule(style: .continuous))
                    .accessibilityElement(children: .combine)
            }

            Spacer(minLength: 0)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.04), in: Circle())
                .accessibilityHidden(true)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(card.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Why now: \(card.whyNow)")
                .font(.callout)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var sourceChips: some View {
        let visibleSignals = card.sourceSignals.filter(\.isUserVisible)
        if !visibleSignals.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visibleSignals) { signal in
                        Text(signal.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(minHeight: 44)
                            .background(Color.black.opacity(0.04), in: Capsule(style: .continuous))
                            .accessibilityLabel(Text("Source signal: \(signal.title)"))
                    }
                }
            }
        }
    }

    private var permissionBanner: some View {
        let source = card.permissionRequirements.first ?? .amenActivity
        let status = permissionManager.status(for: source)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: status == .granted ? "checkmark.shield" : "lock")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: source.titleKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(permissionManager.limitedExplanation(for: source))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.75)
        )
        .accessibilityElement(children: .combine)
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    BereanPulseActionChip(
                        title: card.recommendedActionTitle,
                        systemImage: "arrow.up.right",
                        action: onPrimaryAction,
                        isPrimary: true,
                        isDisabled: !card.primaryActionIsAvailable
                    )
                    BereanPulseActionChip(title: "Ask Berean", systemImage: "sparkles", action: onAskBerean)
                    BereanPulseActionChip(title: "Why this", systemImage: "questionmark.circle", action: onWhyNow)
                    BereanPulseActionChip(title: card.isSaved ? "Saved" : "Save", systemImage: card.isSaved ? "bookmark.fill" : "bookmark", action: onSave)
                    BereanPulseActionChip(title: "Share", systemImage: "square.and.arrow.up", action: onShare)
                    BereanPulseActionChip(title: "Hide", systemImage: "eye.slash", action: onHide)
                }
            }

            HStack(spacing: 8) {
                feedbackButton(
                    systemName: card.feedbackState == .liked ? "hand.thumbsup.fill" : "hand.thumbsup",
                    label: String(localized: "Like \(card.title)"),
                    action: onLike,
                    isSelected: card.feedbackState == .liked
                )
                feedbackButton(
                    systemName: card.feedbackState == .disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                    label: String(localized: "Dislike \(card.title)"),
                    action: onDislike,
                    isSelected: card.feedbackState == .disliked
                )
            }
        }
    }

    private func feedbackButton(systemName: String, label: String, action: @escaping () -> Void, isSelected: Bool) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 44, height: 44)
                .background(isSelected ? Color.primary : Color.white.opacity(0.76), in: Circle())
                .overlay(Circle().strokeBorder(Color.black.opacity(isSelected ? 0.0 : 0.08), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
