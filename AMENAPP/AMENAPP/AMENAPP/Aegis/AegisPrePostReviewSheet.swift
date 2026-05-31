// AegisPrePostReviewSheet.swift
// AMENAPP — Aegis/
//
// Pre-post safety review sheet — shown when an AegisSafetyDecision
// contains any actionable (caution/warn/block) results before publishing.
//
// Design contracts honoured:
//   - Liquid Glass surfaces via .amenGlass()
//   - AmenTheme color tokens only (no system blue as primary)
//   - Motion.adaptive(_:) with reduce-motion env + @Environment check
//   - AMENFont type scale
//   - Non-punitive, pastoral copy throughout
//   - Firebase Analytics events on all user actions

import SwiftUI
import FirebaseAnalytics

// MARK: - AegisPrePostReviewSheet

struct AegisPrePostReviewSheet: View {

    let decision: AegisSafetyDecision
    var onProceed: () -> Void    // user confirms and posts
    var onRevise:  () -> Void    // user wants to edit content
    var onCancel:  () -> Void    // user cancels post entirely

    // MARK: State
    @State private var acknowledged: Set<String> = []
    @State private var infoSectionExpanded: Bool = false

    // MARK: Environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Computed

    /// Results worth showing: .caution, .warn, .block only.
    private var actionableResults: [AegisDetectionResult] {
        decision.detectionResults.filter { $0.severity >= .caution }
    }

    /// Info-only results for the collapsible disclosure group.
    private var infoResults: [AegisDetectionResult] {
        decision.detectionResults.filter { $0.severity == .info }
    }

    /// All required acknowledgements satisfied?
    private var allAcknowledged: Bool {
        decision.requiredAcknowledgements.allSatisfy { cap in
            // Find the result matching this capability and check its resultId.
            actionableResults
                .first(where: { $0.capabilityId == cap })
                .map { acknowledged.contains($0.resultId) }
                ?? true
        }
    }

    private var isBlocked: Bool { !decision.allowPost }

    private var headerTitle: String {
        switch decision.maxSeverity {
        case .block:   return "We're not able to share this"
        case .warn:    return "Before you share"
        case .caution: return "Take a moment"
        case .info:    return "All checks passed"
        }
    }

    private var headerSubtitle: String {
        switch decision.maxSeverity {
        case .block:
            return "We've noticed something in this post that goes against our community guidelines. Let's revise it together."
        case .warn:
            return "There's something worth reviewing before this reaches your community. You can still share — we just want you to be aware."
        case .caution:
            return "We noticed a few things that might be worth considering before you post. This is just a gentle heads-up."
        case .info:
            return "Everything looks good. Your post is ready to share."
        }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            // ── Drag handle ──────────────────────────────────────────
            dragHandle

            // ── Header row (title + cancel) ──────────────────────────
            headerRow

            Divider()
                .background(AmenTheme.Colors.separatorSubtle)

            // ── Scrollable content ───────────────────────────────────
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Header description card
                    headerDescriptionCard
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    // Actionable detection results
                    if !actionableResults.isEmpty {
                        resultsSection
                            .padding(.top, 12)
                    }

                    // Collapsible info-only results
                    if !infoResults.isEmpty {
                        infoDisclosureSection
                            .padding(.top, 8)
                            .padding(.horizontal, 16)
                    }

                    // Care resources
                    if decision.routeToCare && !decision.careResources.isEmpty {
                        careResourcesSection
                            .padding(.top, 12)
                    }

                    // Bottom spacer — enough room for the sticky action bar
                    Spacer(minLength: 120)
                }
            }

            // ── Sticky action bar ────────────────────────────────────
            actionBar
        }
        .background(Color(.systemBackground))
        .onAppear {
            Analytics.logEvent("aegis_pre_post_shown", parameters: [
                "max_severity": decision.maxSeverity.rawValue,
                "allow_post": decision.allowPost,
                "result_count": actionableResults.count
            ])
        }
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color(.systemGray4))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(AMENFont.bold(18))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
            }
            Spacer()
            Button(action: {
                onCancel()
            }) {
                Text("Never mind")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel and discard post")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Header Description Card

    private var headerDescriptionCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: headerIcon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(headerIconColor)
                .frame(width: 28)

            Text(headerSubtitle)
                .font(AMENFont.regular(14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .amenGlass(.thin, cornerRadius: 14)
    }

    private var headerIcon: String {
        switch decision.maxSeverity {
        case .block:   return "hand.raised.fill"
        case .warn:    return "exclamationmark.triangle.fill"
        case .caution: return "lightbulb.fill"
        case .info:    return "checkmark.seal.fill"
        }
    }

    private var headerIconColor: Color {
        switch decision.maxSeverity {
        case .block:   return .red
        case .warn:    return .orange
        case .caution: return AmenTheme.Colors.amenGold
        case .info:    return Color.green
        }
    }

    // MARK: - Detection Results Section

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What we noticed")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .padding(.horizontal, 16)

            LazyVStack(spacing: 8) {
                ForEach(actionableResults) { result in
                    let requiresAck = decision.requiredAcknowledgements.contains(result.capabilityId)
                    let isAcked = acknowledged.contains(result.resultId)

                    AegisDetectionResultCard(
                        result: result,
                        isAcknowledged: isAcked,
                        onAcknowledge: requiresAck ? {
                            withAnimation(
                                reduceMotion
                                    ? .easeInOut(duration: 0.14)
                                    : Motion.adaptive(Motion.popToggle)
                            ) {
                                acknowledged.insert(result.resultId)
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } : nil
                    )
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Info Disclosure Section

    private var infoDisclosureSection: some View {
        DisclosureGroup(
            isExpanded: $infoSectionExpanded,
            content: {
                VStack(spacing: 8) {
                    ForEach(infoResults) { result in
                        AegisDetectionResultCard(result: result)
                    }
                }
                .padding(.top, 8)
                .animation(
                    reduceMotion ? .easeInOut(duration: 0.16) : Motion.adaptive(Motion.springRelease),
                    value: infoSectionExpanded
                )
            },
            label: {
                Text("\(infoResults.count) other check\(infoResults.count == 1 ? "" : "s") passed")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
        )
        .accentColor(AmenTheme.Colors.textTertiary)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.16) : Motion.adaptive(Motion.springRelease),
            value: infoSectionExpanded
        )
    }

    // MARK: - Care Resources Section

    private var careResourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Support resources")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .padding(.horizontal, 16)

            VStack(spacing: 8) {
                ForEach(decision.careResources) { resource in
                    AegisCareResourceRow(resource: resource) {
                        Analytics.logEvent("aegis_care_resource_tapped", parameters: [
                            "resource_id": resource.id,
                            "resource_type": resource.resourceType.rawValue
                        ])
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AmenTheme.Colors.separatorSubtle)

            HStack(spacing: 12) {
                if decision.allowPost {
                    // Revise button
                    Button(action: {
                        onRevise()
                        Analytics.logEvent("aegis_pre_post_revised", parameters: [
                            "max_severity": decision.maxSeverity.rawValue
                        ])
                    }) {
                        Text("Revise")
                            .font(AMENFont.semiBold(15))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .amenGlass(.regular, cornerRadius: 14)
                    .buttonStyle(AmenPressStyle(scale: 0.97))
                    .accessibilityLabel("Revise your post")

                    // Post anyway button — requires all acknowledgements
                    Button(action: {
                        guard allAcknowledged else { return }
                        onProceed()
                        Analytics.logEvent("aegis_pre_post_proceeded", parameters: [
                            "max_severity": decision.maxSeverity.rawValue,
                            "acknowledged_count": acknowledged.count
                        ])
                    }) {
                        Text("Post anyway")
                            .font(AMENFont.semiBold(15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(allAcknowledged
                                          ? AmenTheme.Colors.amenBlue
                                          : AmenTheme.Colors.amenBlue.opacity(0.4))
                            }
                    }
                    .buttonStyle(AmenPressStyle(scale: 0.97))
                    .disabled(!allAcknowledged)
                    .animation(
                        reduceMotion ? .easeInOut(duration: 0.16) : Motion.adaptive(Motion.springRelease),
                        value: allAcknowledged
                    )
                    .accessibilityLabel(allAcknowledged
                        ? "Post anyway"
                        : "Post anyway — acknowledge all notices first")
                    .accessibilityHint(allAcknowledged ? "" : "Tap 'I understand' on each notice to enable")

                } else {
                    // Blocked: single "Revise content" CTA
                    VStack(spacing: 8) {
                        Button(action: {
                            onRevise()
                            Analytics.logEvent("aegis_pre_post_revised", parameters: [
                                "max_severity": decision.maxSeverity.rawValue,
                                "reason": "blocked"
                            ])
                        }) {
                            Text("Revise content")
                                .font(AMENFont.semiBold(15))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(AmenTheme.Colors.amenBlue)
                                }
                        }
                        .buttonStyle(AmenPressStyle(scale: 0.97))
                        .accessibilityLabel("Revise your content to meet community guidelines")

                        Button(action: {
                            // Expand info section to give context
                            withAnimation(
                                reduceMotion ? .easeInOut(duration: 0.16) : Motion.adaptive(Motion.springRelease)
                            ) {
                                infoSectionExpanded = true
                            }
                        }) {
                            Text("Learn why")
                                .font(AMENFont.regular(14))
                                .foregroundStyle(AmenTheme.Colors.amenBlue)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Learn why this post was blocked")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - AegisCareResourceRow (private)

private struct AegisCareResourceRow: View {

    let resource: AegisCareResource
    var onTap: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: handleTap) {
            HStack(alignment: .top, spacing: 12) {
                // Icon
                Image(systemName: resourceIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(resourceIconColor)
                    .frame(width: 32, height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(resourceIconColor.opacity(0.12))
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(resource.title)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)

                    Text(resource.body)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)

                    if let label = resource.actionLabel {
                        Text(label)
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(AmenTheme.Colors.amenBlue)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
            .padding(14)
            .amenGlass(.regular, cornerRadius: 14)
        }
        .buttonStyle(AmenPressStyle(scale: 0.98))
        .accessibilityLabel("\(resource.title): \(resource.body)")
        .accessibilityHint(resource.actionLabel ?? "")
        .disabled(resource.actionUrl == nil && resource.resourceType == .externalLink)
    }

    private func handleTap() {
        onTap?()
        if let urlString = resource.actionUrl, let url = URL(string: urlString) {
            openURL(url)
        }
    }

    private var resourceIcon: String {
        switch resource.resourceType {
        case .pastoralGuidance: return "hands.sparkles.fill"
        case .crisisLine:       return "phone.fill"
        case .legalInfo:        return "doc.text.fill"
        case .externalLink:     return "link"
        case .inAppAction:      return "arrow.right.circle.fill"
        }
    }

    private var resourceIconColor: Color {
        switch resource.resourceType {
        case .pastoralGuidance: return AmenTheme.Colors.amenPurple
        case .crisisLine:       return .red
        case .legalInfo:        return AmenTheme.Colors.amenGold
        case .externalLink:     return AmenTheme.Colors.amenBlue
        case .inAppAction:      return AmenTheme.Colors.amenBlue
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Caution — allow post") {
    let results: [AegisDetectionResult] = [
        .make(capability: .pauseBeforePosting, severity: .caution, confidence: 0.72,
              action: "Take a breath — consider how this might land with your community."),
        .make(capability: .contextCollapseGuard, severity: .caution, confidence: 0.61,
              action: "This post may read differently outside your usual circle."),
        .make(capability: .hiddenPublicMetrics, severity: .info, confidence: 0.99,
              action: "Engagement counts are hidden for your wellbeing."),
    ]
    let decision = AegisSafetyDecision(
        decisionId: UUID().uuidString,
        allowPost: true,
        requiredAcknowledgements: [.pauseBeforePosting],
        audienceRestriction: nil,
        redactions: [],
        routeToCare: false,
        careResources: [],
        detectionResults: results,
        timestamp: Date(),
        policyVersion: AegisContractsVersion
    )

    AegisPrePostReviewSheet(
        decision: decision,
        onProceed: {},
        onRevise: {},
        onCancel: {}
    )
}

#Preview("Block — revise required") {
    let results: [AegisDetectionResult] = [
        .make(capability: .donationFraud, severity: .block, confidence: 0.97,
              action: "This post appears to solicit funds in a way that violates our guidelines.",
              care: [
                  AegisCareResource(
                      id: "c1",
                      title: "Stewardship Guidelines",
                      body: "Learn how AMEN supports transparent giving and ministry fundraising.",
                      actionLabel: "Read guidelines",
                      actionUrl: "https://amen.app/giving/guidelines",
                      resourceType: .pastoralGuidance
                  )
              ]),
        .make(capability: .spiritualAbuse, severity: .warn, confidence: 0.84,
              action: "Some language here may feel coercive. Let's soften the approach."),
    ]
    let decision = AegisSafetyDecision(
        decisionId: UUID().uuidString,
        allowPost: false,
        requiredAcknowledgements: [],
        audienceRestriction: nil,
        redactions: results,
        routeToCare: true,
        careResources: [
            AegisCareResource(
                id: "c2",
                title: "Talk to a Pastor",
                body: "A pastor in our network can help you share your needs in a safe, transparent way.",
                actionLabel: "Connect now",
                actionUrl: nil,
                resourceType: .pastoralGuidance
            )
        ],
        detectionResults: results,
        timestamp: Date(),
        policyVersion: AegisContractsVersion
    )

    AegisPrePostReviewSheet(
        decision: decision,
        onProceed: {},
        onRevise: {},
        onCancel: {}
    )
}
#endif
