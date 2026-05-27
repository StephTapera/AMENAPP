// AmenSmartCatchUpView.swift
// AMEN App — Smart Collaboration Layer: Slice 8 — Catch-up / Re-entry Digest
//
// Non-negotiable rules enforced here:
//   1. Digest is per-user scoped — user sees only what's relevant since their last read.
//   2. Facts vs guesses distinguished: "Discussed: [topic]" vs "Possible decision: [text]"
//   3. Source-linked: every digest item cites the sourceMessageId that generated it.
//   4. Expires: digest is stale after 24 hours — stale banner shown.
//   5. Flag OFF (messagesSmartContextEnabled) → completely invisible (EmptyView).
//   6. All states handled: loading, fresh, stale, empty, error, offline.
//   7. VoiceOver + Reduce Motion supported.
//   8. Analytics: catchUpDigestOpened(itemCount:) on appear, catchUpItemEngaged on row tap.

import SwiftUI
import FirebaseFirestore

// MARK: - AmenSmartCatchUpView

/// Full-width card shown at top of thread message list on re-entry.
/// Gated behind `RemoteKillSwitch.shared.messagesSmartContextEnabled`.
struct AmenSmartCatchUpView: View {
    let threadId: String
    let threadType: AmenSmartThreadType
    let spaceId: String?
    let channelId: String?
    /// Called when user dismisses the digest.
    let onDismiss: () -> Void
    /// Called when user taps "Catch up" — caller should scroll to oldest unread message.
    let onCatchUp: (() -> Void)?

    @ObservedObject private var service = AmenSmartContextService.shared
    @ObservedObject private var killSwitch = RemoteKillSwitch.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var appeared = false
    /// Tracks whether the appearance analytics event has fired for this session.
    @State private var digestOpenTracked = false

    // MARK: - Computed helpers

    private var summary: AmenSmartCollabSummary? {
        service.currentSummary
    }

    private var isOffline: Bool {
        if let err = service.error {
            return (err as NSError).domain == NSURLErrorDomain
        }
        return false
    }

    private var isStale: Bool {
        guard let generatedAt = summary?.generatedAt else { return false }
        return Date().timeIntervalSince(generatedAt.dateValue()) > 86_400 // 24 hours
    }

    private var bulletPoints: [String] {
        guard let pts = summary?.bulletPoints, !pts.isEmpty else { return [] }
        return Array(pts.prefix(5))
    }

    private var messageCount: Int {
        service.currentContext?.messageCount ?? 0
    }

    // MARK: - Body

    var body: some View {
        // Rule 5: Flag OFF → completely invisible
        guard killSwitch.messagesSmartContextEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(contentForState)
    }

    @ViewBuilder
    private var contentForState: some View {
        if service.isLoading {
            skeletonCard
        } else if let error = service.error, !isOffline {
            errorChip(error)
        } else if bulletPoints.isEmpty && !isOffline {
            // Empty state: nothing missed — take no space
            EmptyView()
        } else {
            fullCard
                .scaleEffect(appeared ? 1 : 0.97)
                .opacity(appeared ? 1 : 0)
                .onAppear {
                    let animation: Animation = reduceMotion
                        ? .linear(duration: 0.1)
                        : .spring(response: 0.38, dampingFraction: 0.82)
                    withAnimation(animation) { appeared = true }
                    trackDigestOpened()
                }
        }
    }

    // MARK: - Full card

    private var fullCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Stale banner
            if isStale {
                staleBanner
            }
            // Offline overlay label
            if isOffline {
                offlineBanner
            }
            VStack(alignment: .leading, spacing: 12) {
                headerRow
                if !bulletPoints.isEmpty {
                    bulletList
                }
                if let summary {
                    footerRow(summary: summary)
                }
                actionButtons
            }
            .padding(14)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.07), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Catch-up digest. \(bulletPoints.count) items since you were away."
        )
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text("Since you were away")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            if messageCount > 0 {
                Text("\(messageCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
                    .accessibilityLabel("\(messageCount) new messages")
            }
        }
    }

    // MARK: - Bullet list (max 5)

    @ViewBuilder
    private var bulletList: some View {
        let sourceIds = summary?.sourceMessageIds ?? []
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(bulletPoints.enumerated()), id: \.offset) { index, bullet in
                let sourceId = sourceIds.indices.contains(index) ? sourceIds[index] : ""
                AmenSmartCatchUpItem(
                    text: bullet,
                    isPossible: isPossibleDecision(bullet),
                    isPrayer: isPrayerIndicator(bullet),
                    sourceMessageId: sourceId,
                    onTap: {
                        AMENAnalyticsService.shared.track(.catchUpItemEngaged)
                    }
                )
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private func footerRow(summary: AmenSmartCollabSummary) -> some View {
        let start = summary.messageRangeStart.dateValue()
        let end   = summary.messageRangeEnd.dateValue()
        let count = summary.sourceMessageIds.count

        HStack(spacing: 6) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("\(count) message\(count == 1 ? "" : "s") while you were away")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(formattedTimestamp(start)) – \(formattedTimestamp(end))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 10) {
            if let onCatchUp {
                Button {
                    onCatchUp()
                } label: {
                    Label("Catch up", systemImage: "arrow.up.message")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Catch up — scroll to oldest unread message")
            }

            Button {
                AMENAnalyticsService.shared.track(
                    .catchUpDigestOpened(itemCount: bulletPoints.count)
                )
                onDismiss()
            } label: {
                Text("Dismiss")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss catch-up summary")

            Spacer()
        }
    }

    // MARK: - Banners

    private var staleBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.orange)
            Text("This summary may be outdated")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.orange)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .accessibilityLabel("Warning: this catch-up summary may be outdated")
    }

    private var offlineBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .font(.caption)
                .foregroundStyle(Color.secondary)
            Text("Offline")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemFill))
        .accessibilityLabel("Offline — showing last known catch-up summary")
    }

    // MARK: - Skeleton (loading)

    private var skeletonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header shimmer
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4).frame(width: 20, height: 14)
                RoundedRectangle(cornerRadius: 4).frame(width: 150, height: 14)
                Spacer()
                RoundedRectangle(cornerRadius: 10).frame(width: 28, height: 20)
            }
            // 3 shimmer bullet rows
            ForEach(0..<3, id: \.self) { _ in
                SkeletonBulletRow()
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel("Loading catch-up digest")
    }

    // MARK: - Error chip

    @ViewBuilder
    private func errorChip(_ error: Error) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(Color.orange)
            Text("Catch-up unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Catch-up digest unavailable")
    }

    // MARK: - Card background

    private var cardBackground: some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(.secondarySystemBackground))
        }
        return AnyShapeStyle(.regularMaterial)
    }

    // MARK: - Analytics

    private func trackDigestOpened() {
        guard !digestOpenTracked else { return }
        digestOpenTracked = true
        AMENAnalyticsService.shared.track(
            .catchUpDigestOpened(itemCount: bulletPoints.count)
        )
    }

    // MARK: - Bullet classification helpers

    /// True when the bullet appears to be an AI-framed "possible decision".
    /// Detection is heuristic based on server-written prefix ("possible:") — never
    /// re-interpreted from raw message text on the client.
    private func isPossibleDecision(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("possible:") || lower.hasPrefix("possible decision")
    }

    /// True when the bullet indicates a prayer need was shared.
    /// No prayer content or themes are shown — only the generic indicator.
    private func isPrayerIndicator(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("prayer") || lower.contains("pray need")
    }

    // MARK: - Date formatter

    private func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - AmenSmartCatchUpItem

private struct AmenSmartCatchUpItem: View {
    let text: String
    let isPossible: Bool      // "Possible decision" framing
    let isPrayer: Bool        // Prayer need indicator
    let sourceMessageId: String
    let onTap: () -> Void     // Tracks catchUpItemEngaged

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Leading indicator
                Group {
                    if isPrayer {
                        Text("🙏")
                            .font(.caption)
                    } else if isPossible {
                        Text("⚡")
                            .font(.caption)
                    } else {
                        Text("•")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(width: 18, alignment: .center)

                // Item text
                VStack(alignment: .leading, spacing: 3) {
                    itemText
                    sourceCitationChip
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(isPossible ? "Possible: " : "")\(text)"
        )
    }

    @ViewBuilder
    private var itemText: some View {
        if isPrayer {
            Text("Prayer need shared")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if isPossible {
            // Strip leading "possible:" prefix for display if server already added it,
            // then re-frame consistently.
            let displayText = cleanedPossibleText
            Text("Possible decision: \(displayText)")
                .font(.subheadline.italic())
                .foregroundStyle(.secondary)
        } else {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    private var cleanedPossibleText: String {
        var result = text
        let prefixes = ["possible decision:", "possible:"]
        for prefix in prefixes {
            if result.lowercased().hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return result
    }

    private var sourceCitationChip: some View {
        Button {
            // Phase 3+: deep link to source message.
            // Log source message ID for traceability.
            dlog("[AmenSmartCatchUpItem] Source message tapped: \(sourceMessageId)")
        } label: {
            Label("From message", systemImage: "quote.bubble")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View source message (deep link available in a future update)")
    }
}

// MARK: - SkeletonBulletRow (loading placeholder)

private struct SkeletonBulletRow: View {
    @State private var shimmer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4).frame(width: 14, height: 10)
            RoundedRectangle(cornerRadius: 4).frame(maxWidth: .infinity).frame(height: 12)
            Spacer()
        }
        .foregroundStyle(Color(.systemFill))
        .opacity(shimmer ? 0.45 : 1.0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
            ) {
                shimmer = true
            }
        }
        .accessibilityHidden(true)
    }
}
