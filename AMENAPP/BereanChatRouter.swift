import SwiftUI

/// Canonical Berean chat surfaces.
enum BereanChatSurface {
    case primary
    case structured
}

/// Product entry points that can launch a Berean conversation.
enum BereanChatEntryPoint {
    case general
    case homeFeed
    case bereanHome
    case studyHub
    case chatsList
    case postReflection
    case dailyVerse
    case discovery
}

/// Central routing rule for Berean chat surfaces.
///
/// Rule:
/// - `BereanChatView` is the default and only production entry surface for user-facing
///   chat launches because it is the guarded Claude path used by the rest of the app.
/// - `BereanConversationView` is a legacy structured-study surface and must only be
///   selected explicitly with `forceStructuredSurface`.
enum BereanChatRouter {
    static func resolveSurface(
        entryPoint: BereanChatEntryPoint,
        existingSessionId: String?,
        postContext: BereanPostContext?,
        forceStructuredSurface: Bool
    ) -> BereanChatSurface {
        if forceStructuredSurface {
            return .structured
        }

        _ = entryPoint
        _ = existingSessionId
        _ = postContext
        return .primary
    }
}

/// Thin routing wrapper so call sites do not instantiate competing Berean surfaces directly.
struct BereanChatRouteView: View {
    var entryPoint: BereanChatEntryPoint = .general
    var initialMode: BereanPersonalityMode = .shepherd
    var initialQuery: String? = nil
    var conversationTitle: String? = nil
    var postContext: BereanPostContext? = nil
    var existingSessionId: String? = nil
    var forceStructuredSurface = false

    var body: some View {
        switch BereanChatRouter.resolveSurface(
            entryPoint: entryPoint,
            existingSessionId: existingSessionId,
            postContext: postContext,
            forceStructuredSurface: forceStructuredSurface
        ) {
        case .primary:
            BereanChatView(
                initialMode: initialMode,
                initialQuery: initialQuery,
                conversationTitle: conversationTitle,
                postContext: postContext,
                existingSessionId: existingSessionId
            )
        case .structured:
            BereanConversationView(
                conversationId: existingSessionId ?? UUID().uuidString,
                initialPrompt: initialQuery
            )
        }
    }
}
