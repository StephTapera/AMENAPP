// CreatorProfileView.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3
//
// The Creator Hub screen shell. Skeleton-first: on appear it renders skeletons
// IMMEDIATELY; if a cached payload exists (CreatorHubService.cachedPayloads) it renders
// that instantly for zero-flash re-entry; then it awaits assembleProfile to hydrate.
//
// Scroll-aware header collapse feeds CreatorHubHeroHeader.collapseProgress. A sticky
// LiquidGlassPillBar selects the active CreatorHubModuleKind, and a switch renders the
// matching module view (built by sibling agents).
//
// Gating: the whole view is behind CreatorHubFlags.profilesEnabled. We read
// AMENFeatureFlags.shared.creatorProfilesEnabled when present; the `enabled` param
// (default false) is the fallback so this file compiles/ships dark until the flag exists.
//
// Conventions: white bg / black text; translucent glass pill bar (no glass-on-glass);
// AmenTheme.Colors.* tokens; Dynamic Type; VoiceOver labels; reduce-motion handled in
// child components; skeleton-first.

import SwiftUI

struct CreatorProfileView: View {
    let creatorId: String
    /// Master flag fallback. Pass the resolved CreatorHubFlags.profilesEnabled value here
    /// until AMENFeatureFlags.shared.creatorProfilesEnabled is wired (see report).
    var enabled: Bool = false
    /// Viewer relationship — passed through to hero quick-action affordances.
    var supportEnabled: Bool = false

    @State private var payload: CreatorHubProfilePayload?
    @State private var selectedModule: CreatorHubModuleKind = .overview
    @State private var collapseProgress: Double = 0
    @State private var loadError: String?
    @State private var didStartLoad = false
    /// Creator Spotlight (App-Store-style public page) entry. Flag-gated OFF — the
    /// button and sheet never appear unless creatorSpotlightEnabled is true.
    @State private var showSpotlight = false

    @Namespace private var pillNamespace
    @Environment(\.dismiss) private var dismiss

    // MARK: Resolved gate

    /// True if the master flag is enabled either via AMENFeatureFlags or the param fallback.
    private var isGateOpen: Bool {
        // NOTE(flag): `creatorProfilesEnabled` must be added to AMENFeatureFlags.swift
        // (see report). Until then the `enabled` param is the only signal.
        enabled
    }

    var body: some View {
        Group {
            if isGateOpen {
                content
            } else {
                disabledState
            }
        }
        .background(AmenTheme.Colors.backgroundPrimary.ignoresSafeArea())
    }

    // MARK: Disabled (flag OFF)

    private var disabledState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("Creator Profiles aren’t available yet.")
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Creator Profiles are not available yet")
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                scrollOffsetReader

                header

                pillBar
                    .padding(.top, -22)            // float the bar onto the hero edge
                    .zIndex(1)

                moduleBody
                    .padding(.top, 16)
            }
        }
        .coordinateSpace(name: "creatorScroll")
        .task { await startLoadIfNeeded() }
        .overlay(alignment: .top) { errorBanner }
        .overlay(alignment: .topTrailing) { spotlightButton }
        .sheet(isPresented: $showSpotlight) {
            CreatorSpotlightView(creatorId: creatorId)
        }
    }

    // MARK: Creator Spotlight entry (flag-gated)

    /// Opens the App-Store-style public Creator Page. Hidden entirely unless
    /// creatorSpotlightEnabled is ON — so this is inert in the current build.
    @ViewBuilder
    private var spotlightButton: some View {
        if AMENFeatureFlags.shared.creatorSpotlightEnabled {
            Button {
                showSpotlight = true
            } label: {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
            .accessibilityLabel("Open creator spotlight page")
        }
    }

    // MARK: Scroll offset → collapseProgress

    private var scrollOffsetReader: some View {
        GeometryReader { geo in
            Color.clear
                .onChange(of: geo.frame(in: .named("creatorScroll")).minY) { _, minY in
                    // minY goes negative as we scroll up. Collapse over the first ~220pt.
                    let raw = min(max(-minY / 220, 0), 1)
                    collapseProgress = raw
                }
        }
        .frame(height: 0)
    }

    // MARK: Header (skeleton → real)

    @ViewBuilder
    private var header: some View {
        if let payload {
            CreatorHubHeroHeader(
                profile: payload.profile,
                heroState: payload.heroState,
                supportEnabled: supportEnabled,
                collapseProgress: collapseProgress,
                onAction: handleQuickAction
            )
        } else {
            SkeletonHeroPlaceholder()
        }
    }

    // MARK: Pill bar

    @ViewBuilder
    private var pillBar: some View {
        if payload != nil {
            LiquidGlassPillBar(
                selected: $selectedModule,
                indicatorNamespace: pillNamespace,
                onFocus: { module in
                    // TODO(prefetch): prefetch likely next module via pageCreatorModule on pill focus.
                    _ = module
                }
            )
            .padding(.horizontal, 16)
        } else {
            SkeletonPillBar()
                .padding(.top, 8)
        }
    }

    // MARK: Module body

    @ViewBuilder
    private var moduleBody: some View {
        if let payload {
            moduleView(for: selectedModule, payload: payload)
                .padding(.horizontal, 16)
        } else {
            VStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in SkeletonCardRow() }
            }
            .padding(.horizontal, 16)
        }
    }

    /// Maps the selected module to its sibling-built module view.
    /// These view types are provided by other Wave-3 agents; they take simple params.
    @ViewBuilder
    private func moduleView(for module: CreatorHubModuleKind, payload: CreatorHubProfilePayload) -> some View {
        switch module {
        case .overview:
            FeaturedSmartModuleCard(
                featured: payload.featuredModule,
                heroState: payload.heroState
            )
        case .events:
            EventListModule(creatorId: creatorId, events: payload.firstPages.events)
        case .teachings:
            TeachingLibraryModule(creatorId: creatorId, teachings: payload.firstPages.teachings)
        case .resources:
            ResourceCenterModule(creatorId: creatorId, resources: payload.firstPages.resources)
        case .prayer:
            PrayerBoardModule(creatorId: creatorId, requests: payload.firstPages.prayer)
        case .community:
            CommunityModule(creatorId: creatorId, posts: payload.firstPages.community)
        case .courses:
            CoursesModule(creatorId: creatorId, courses: payload.firstPages.courses)
        case .askAI:
            CreatorAssistantView(creatorId: creatorId)
        }
    }

    // MARK: Error banner

    @ViewBuilder
    private var errorBanner: some View {
        if let loadError, payload == nil {
            Text(loadError)
                .font(.footnote.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.textInverse)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(AmenTheme.Colors.statusError))
                .padding(.top, 12)
                .accessibilityLabel("Couldn’t load this profile")
        }
    }

    // MARK: Loading

    private func startLoadIfNeeded() async {
        guard !didStartLoad else { return }
        didStartLoad = true

        // Instant cached re-entry.
        if let cached = CreatorHubService.shared.cachedPayloads[creatorId] {
            payload = cached
        }

        // Hydrate / refresh from the backend.
        do {
            let fresh = try await CreatorHubService.shared.assembleProfile(creatorId: creatorId)
            payload = fresh
            loadError = nil
        } catch {
            if payload == nil {
                loadError = "We couldn’t load this profile. Pull to try again."
            }
        }
    }

    // MARK: Quick actions

    private func handleQuickAction(_ action: CreatorHubQuickAction) {
        switch action {
        case .pray:
            selectedModule = .prayer
        case .follow, .message, .support, .share:
            // Wired by Wave 4 (follow/message/support/share flows).
            break
        }
    }
}

#if DEBUG
#Preview("Creator profile – flag off") {
    CreatorProfileView(creatorId: "preview", enabled: false)
}
#endif
