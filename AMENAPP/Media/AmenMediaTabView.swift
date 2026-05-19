// AmenMediaTabView.swift
// AMENAPP
//
// Central routing hub for all media experiences.
// Routes between discovery, finite sessions, upload, and settings.
// Gated by AMENFeatureFlags.shared.mediaFiniteSessionsEnabled.
// Does NOT open directly into an infinite feed.

import SwiftUI
import FirebaseAuth

// MARK: - Session Type Bridge

extension AmenMediaSessionType {
    var asSessionType: AmenMediaSession.SessionType {
        switch self {
        case .morningInspiration:     return .morningInspiration
        case .fiveMinuteSelah:        return .selahReflection
        case .prayerSafeTestimonies:  return .testimonies
        case .churchNotesStudyPath:   return .learningSession
        case .sermonClipReflection:   return .sermonHighlights
        case .familySafeWatch:        return .friendsAndFamily
        case .localChurchUpdates:     return .churchMoments
        case .savedVideos:            return .encouragement
        case .communityMoments:       return .churchMoments
        case .discoverFeed:           return .creativeDiscovery
        }
    }

    var defaultItemCount: Int {
        switch self {
        case .fiveMinuteSelah:    return 3
        case .morningInspiration: return 6
        case .savedVideos:        return 8
        default:                  return 5
        }
    }
}

// MARK: - AmenMediaTabView

/// Primary media entry point. Every session is finite.
/// No entry point leads directly to an infinite autoplay feed.
struct AmenMediaTabView: View {
    @State private var activeSession: AmenMediaSession?
    @State private var showIntentPicker   = false
    @State private var showUploadFlow     = false
    @State private var showPersonalization = false
    @State private var savedSessionTitle: String? = nil

    private var currentUID: String {
        Auth.auth().currentUser?.uid ?? "anonymous"
    }

    var body: some View {
        mainContent
            .fullScreenCover(
                isPresented: Binding(
                    get: { activeSession != nil },
                    set: { if !$0 { activeSession = nil } }
                )
            ) {
                if let session = activeSession {
                    AmenMediaSessionView(session: session)
                }
            }
            .sheet(isPresented: $showIntentPicker) {
                AmenMediaSessionIntentPicker { sessionType in
                    activeSession = makeSession(fromIntent: sessionType)
                }
            }
            .sheet(isPresented: $showUploadFlow) {
                AmenMediaUploadFlowView()
            }
            .sheet(isPresented: $showPersonalization) {
                AmenMediaPersonalizationView()
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        if AMENFeatureFlags.shared.mediaFiniteSessionsEnabled {
            AmenImmersiveMediaHomeView(
                onStartSession: { sessionType in
                    activeSession = makeSession(from: sessionType)
                },
                continueSessionTitle: savedSessionTitle,
                onContinueSession: savedSessionTitle != nil ? {
                    resumeSavedSession()
                } : nil
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            showIntentPicker = true
                        } label: {
                            Image(systemName: "play.circle")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .accessibilityLabel("Choose a session intent")

                        Button {
                            showUploadFlow = true
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .accessibilityLabel("Upload media")

                        Button {
                            showPersonalization = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .accessibilityLabel("Media personalization settings")
                    }
                }
            }
        } else {
            ChristianMediaView()
        }
    }

    // MARK: - Session Factory

    /// Creates a finite AmenMediaSession from an AmenMediaSessionType (home view callback).
    /// itemIds are placeholders — production fetches from backend before starting.
    private func makeSession(from type: AmenMediaSessionType) -> AmenMediaSession {
        let count = type.defaultItemCount
        return AmenMediaSession(
            id: UUID().uuidString,
            ownerUid: currentUID,
            sessionType: type.asSessionType,
            intent: type.title,
            communityIds: [],
            itemIds: (1...max(1, count)).map { "placeholder_\($0)" },
            currentIndex: 0,
            status: .active,
            finiteQueue: true,
            maxItems: count,
            maxDurationSeconds: count * 120,
            reflectionPromptShown: false,
            sourceSurface: AmenMediaSourceSurface.discovery.rawValue
        )
    }

    /// Creates a finite session from the intent picker (AmenMediaSession.SessionType).
    private func makeSession(fromIntent type: AmenMediaSession.SessionType) -> AmenMediaSession {
        let count = type.defaultMaxItems
        return AmenMediaSession(
            id: UUID().uuidString,
            ownerUid: currentUID,
            sessionType: type,
            intent: type.displayName,
            communityIds: [],
            itemIds: (1...max(1, count)).map { "placeholder_\($0)" },
            currentIndex: 0,
            status: .active,
            finiteQueue: true,
            maxItems: count,
            maxDurationSeconds: count * 120,
            reflectionPromptShown: false,
            sourceSurface: AmenMediaSourceSurface.discovery.rawValue
        )
    }

    private func resumeSavedSession() {
        let count = 5
        activeSession = AmenMediaSession(
            id: UUID().uuidString,
            ownerUid: currentUID,
            sessionType: .morningInspiration,
            intent: savedSessionTitle ?? "Saved session",
            communityIds: [],
            itemIds: (1...count).map { "saved_\($0)" },
            currentIndex: 2,
            status: .active,
            finiteQueue: true,
            maxItems: count,
            maxDurationSeconds: count * 120,
            reflectionPromptShown: false,
            sourceSurface: AmenMediaSourceSurface.savedQueue.rawValue
        )
    }
}

#Preview {
    AmenMediaTabView()
}
