
//
//  LiveActivityViews.swift
//  AMENAPP — Widget Extension Target Only
//
//  Contains the Dynamic Island + Lock Screen UI for all Live Activity types.
//  This file must be added to the AMENWidgetExtension target (NOT the main app target).
//
//  ═══════════════════════════════════════════════════════════════════════
//  TO COMPLETE THE DYNAMIC ISLAND SETUP:
//  ═══════════════════════════════════════════════════════════════════════
//
//  1. In Xcode: File → New → Target → Widget Extension
//     Name: AMENWidgetExtension
//     Uncheck "Include Configuration App Intent"
//
//  2. Move this file (LiveActivityViews.swift) to the AMENWidgetExtension target.
//     Also move LiveActivityAttributes.swift to BOTH targets (shared).
//
//  3. Create AMENWidgetBundle.swift in AMENWidgetExtension:
//
//     import WidgetKit
//     import SwiftUI
//     import ActivityKit
//
//     @main
//     struct AMENWidgetBundle: WidgetBundle {
//         var body: some Widget {
//             ReplyAssistWidget()
//             // ChurchServiceWidget()
//             // PrayerReminderWidget()
//         }
//     }
//
//  4. Link ActivityKit.framework to the AMENAPP main target.
//     Add NSSupportsLiveActivities = YES to Info.plist (already done).
//
//  5. After linking, replace LiveActivityBridge.stub with LiveActivityBridge+Real
//     (the real implementation that calls Activity<ReplyActivityAttributes>.request()).
//
//  ═══════════════════════════════════════════════════════════════════════
//  REPLY ASSIST — Dynamic Island UI
//  ═══════════════════════════════════════════════════════════════════════
//
//  Regions:
//    • compactLeading  — SF symbol icon
//    • compactTrailing — short title pill ("New comment")
//    • minimal         — SF symbol only (when two activities share the island)
//    • expanded        — full UI with 3 reply chips + Open button
//    • lockScreen      — privacy-respecting lock screen banner
//
//  Design rules:
//    • No user-generated content shown unless privacyLevel == .previewAllowed
//    • Chips are pre-moderated text (≤60 chars). Tapping deep-links into the app —
//      the reply is NEVER auto-sent from the island.
//    • Consistent with AMEN's Liquid Glass palette: white text on dark tinted surface,
//      capsule chips with translucent fill.
//

// ─────────────────────────────────────────────────────────────────────────────
// The code below uses #if canImport(ActivityKit) so it compiles safely even
// when this file is accidentally included in a target without ActivityKit.
// In the Widget Extension target, ActivityKit is always available.
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(ActivityKit)
import ActivityKit
import SwiftUI
import WidgetKit

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Reply Assist Widget
// ─────────────────────────────────────────────────────────────────────────────

struct ReplyAssistWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReplyActivityAttributes.self) { context in
            // Lock Screen / Banner view
            ReplyActivityLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // ── Expanded ──────────────────────────────────────────────
                DynamicIslandExpandedRegion(.leading) {
                    ReplyExpandedLeading(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ReplyExpandedBottom(context: context)
                }
            } compactLeading: {
                // Small SF symbol on the left of the pill
                Image(systemName: context.attributes.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20)
            } compactTrailing: {
                // Short text label on the right of the pill
                Text(context.attributes.compactTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } minimal: {
                // Single dot icon when island is shared with another activity
                Image(systemName: context.attributes.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .keylineTint(.white.opacity(0.3))
            .contentMargins(.horizontal, 14, for: .expanded)
            .contentMargins(.top, 12, for: .expanded)
            .contentMargins(.bottom, 14, for: .expanded)
        }
    }
}

// MARK: - Expanded Leading (title + optional snippet)

private struct ReplyExpandedLeading: View {
    let context: ActivityViewContext<ReplyActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: context.attributes.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(context.attributes.compactTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Only show actor name / snippet when privacy allows
            if let name = context.attributes.displayName,
               context.state.privacyLevel == .previewAllowed {
                Text(name)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            if let snippet = context.state.contextSnippet,
               context.state.privacyLevel == .previewAllowed {
                Text(snippet)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Expanded Bottom (chips + Open button)

private struct ReplyExpandedBottom: View {
    let context: ActivityViewContext<ReplyActivityAttributes>

    var body: some View {
        if context.state.suggestionsReady {
            HStack(spacing: 8) {
                if !context.state.suggestion1.isEmpty {
                    replyChip(
                        label: chipLabel(context.state.suggestion1, type: context.attributes.replyType, index: 0),
                        url: deepLink(prefill: context.state.suggestion1, context: context)
                    )
                }
                if !context.state.suggestion2.isEmpty {
                    replyChip(
                        label: chipLabel(context.state.suggestion2, type: context.attributes.replyType, index: 1),
                        url: deepLink(prefill: context.state.suggestion2, context: context)
                    )
                }
                if !context.state.suggestion3.isEmpty {
                    replyChip(
                        label: chipLabel(context.state.suggestion3, type: context.attributes.replyType, index: 2),
                        url: deepLink(prefill: context.state.suggestion3, context: context)
                    )
                }
                Spacer(minLength: 0)
                openButton(context: context)
            }
        } else {
            // Loading state
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(0.7)
                Text("Generating replies…")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
            }
        }
    }

    // Chip button — tapping opens the app with the reply pre-filled.
    // The reply is NEVER auto-sent; the user must confirm in-app.
    @ViewBuilder
    private func replyChip(label: String, url: URL?) -> some View {
        if let url {
            Link(destination: url) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.18), in: Capsule())
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func openButton(context: ActivityViewContext<ReplyActivityAttributes>) -> some View {
        if let url = openDeepLink(context: context) {
            Link(destination: url) {
                Text("Open")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.28), in: Capsule())
            }
        }
    }

    // MARK: - Deep link builders

    private func deepLink(prefill text: String, context: ActivityViewContext<ReplyActivityAttributes>) -> URL? {
        let attrs = context.attributes
        var comps = URLComponents()
        comps.scheme = "amen"
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        switch attrs.replyType {
        case .comment, .toneAssist:
            comps.host = "comment"
            comps.queryItems = [
                URLQueryItem(name: "postId", value: attrs.entityId),
                URLQueryItem(name: "commentId", value: attrs.subEntityId),
                URLQueryItem(name: "prefill", value: encoded)
            ]
        case .dm:
            comps.host = "chat"
            comps.queryItems = [
                URLQueryItem(name: "threadId", value: attrs.entityId),
                URLQueryItem(name: "prefill", value: encoded)
            ]
        }
        return comps.url
    }

    private func openDeepLink(context: ActivityViewContext<ReplyActivityAttributes>) -> URL? {
        deepLink(prefill: "", context: context)
            .flatMap { URL(string: $0.absoluteString.replacingOccurrences(of: "&prefill=", with: "")) }
    }

    private func chipLabel(_ text: String, type: ReplyActivityAttributes.ReplyType, index: Int) -> String {
        if type == .toneAssist && index == 0 { return "Rewrite gentler" }
        return text.count > 22 ? String(text.prefix(20)) + "…" : text
    }
}

// MARK: - Lock Screen / Notification Banner View

struct ReplyActivityLockScreenView: View {
    let context: ActivityViewContext<ReplyActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: context.attributes.symbolName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.compactTitle)
                    .font(.system(size: 15, weight: .semibold))

                // Privacy-safe: only show name/snippet when user opted in
                if let name = context.attributes.displayName,
                   context.state.privacyLevel == .previewAllowed {
                    Text(name)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if context.state.suggestionsReady && !context.state.suggestion1.isEmpty {
                Text("Tap to reply")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Previews

#Preview("Compact", as: .dynamicIsland(.compact), using: ReplyActivityAttributes(
    replyType: .comment,
    entityId: "post-123",
    subEntityId: "comment-456",
    displayName: "Sarah",
    createdAtISO: ISO8601DateFormatter().string(from: Date()),
    expiresAtISO: ISO8601DateFormatter().string(from: Date().addingTimeInterval(900))
)) {
    ReplyAssistWidget()
} contentStates: {
    ReplyActivityAttributes.ContentState(
        suggestion1: "Amen! 🙏",
        suggestion2: "What scripture inspired this?",
        suggestion3: "Praying for you.",
        suggestionsReady: true,
        privacyLevel: .noPreview,
        contextSnippet: nil
    )
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: ReplyActivityAttributes(
    replyType: .comment,
    entityId: "post-123",
    subEntityId: "comment-456",
    displayName: "Sarah",
    createdAtISO: ISO8601DateFormatter().string(from: Date()),
    expiresAtISO: ISO8601DateFormatter().string(from: Date().addingTimeInterval(900))
)) {
    ReplyAssistWidget()
} contentStates: {
    ReplyActivityAttributes.ContentState(
        suggestion1: "Amen! 🙏",
        suggestion2: "What scripture inspired this?",
        suggestion3: "Praying for you.",
        suggestionsReady: true,
        privacyLevel: .previewAllowed,
        contextSnippet: "This really spoke to me today…"
    )
}

#Preview("Tone Assist", as: .dynamicIsland(.expanded), using: ReplyActivityAttributes(
    replyType: .toneAssist,
    entityId: "post-789",
    subEntityId: nil,
    displayName: nil,
    createdAtISO: ISO8601DateFormatter().string(from: Date()),
    expiresAtISO: ISO8601DateFormatter().string(from: Date().addingTimeInterval(900))
)) {
    ReplyAssistWidget()
} contentStates: {
    ReplyActivityAttributes.ContentState(
        suggestion1: "I understand your concern, and I'd love to discuss this more.",
        suggestion2: "I hear you.",
        suggestion3: "",
        suggestionsReady: true,
        privacyLevel: .noPreview,
        contextSnippet: nil
    )
}

#endif // canImport(ActivityKit)

// MARK: - Compile-safe stub (non-Widget Extension targets)

#if !canImport(ActivityKit)
import Foundation
// Nothing needed — LiveActivityAttributes.swift defines all shared data types.
#endif
