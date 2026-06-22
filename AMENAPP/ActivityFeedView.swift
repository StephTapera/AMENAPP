//
//  ActivityFeedView.swift
//  AMENAPP
//
//  Created by Assistant on 1/24/26.
//
//  View for displaying recent activity from followed users and communities
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ActivityFeedView: View {
    @ObservedObject private var activityService = ActivityFeedService.shared
    @ObservedObject private var featureFlags = AMENFeatureFlags.shared
    @State private var selectedTab: FeedTab = .global
    @State private var userChurchId: String?
    @State private var isLoadingChurch = false
    @State private var scrollOffset: CGFloat = 0
    
    enum FeedTab: String, CaseIterable {
        case global = "Global"
        case community = "Community"
    }
    
    private var communityActivities: [Activity] {
        guard let churchId = userChurchId else { return [] }
        return activityService.communityActivities[churchId] ?? []
    }
    
    var body: some View {
        if featureFlags.collapsibleGlassHeaderEnabled {
            glassBody
        } else {
            legacyBody
        }
    }

    // MARK: - Legacy body (rendered unchanged when the glass header flag is OFF)

    private var legacyBody: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker

                // Smart Header Orchestrator (feature-flagged, off by default)
                SmartHeaderOrchestrator(
                    screenType: .feed,
                    userName: Auth.auth().currentUser?.displayName ?? "",
                    intentMode: nil,
                    scrollOffset: scrollOffset,
                    hasVerseReady: DailyVerseGenkitService.shared.todayVerse != nil
                )

                // Activity List
                ScrollView {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geo.frame(in: .named("activityScroll")).minY
                        )
                    }
                    .frame(height: 0)
                    LazyVStack(spacing: 12) {
                        if selectedTab == .global {
                            if let errorMessage = activityService.globalFeedError {
                                feedErrorState(message: errorMessage)
                            } else if activityService.isLoading && activityService.globalActivities.isEmpty {
                                AMENLoadingIndicator()
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 60)
                            } else if activityService.globalActivities.isEmpty {
                                emptyState
                            } else {
                                ForEach(activityService.globalActivities) { activity in
                                    ActivityRow(activity: activity)
                                }
                            }
                        } else {
                            if isLoadingChurch {
                                AMENLoadingIndicator()
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 60)
                            } else if userChurchId == nil {
                                communityNochurchState
                            } else if communityActivities.isEmpty {
                                communityEmptyState
                            } else {
                                ForEach(communityActivities) { activity in
                                    ActivityRow(activity: activity)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .coordinateSpace(name: "activityScroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = -value
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                activityService.startObservingGlobalFeed()
                Task { await loadUserChurch() }
            }
            .onDisappear {
                activityService.stopObservingGlobalFeed()
                if let churchId = userChurchId {
                    activityService.stopObservingCommunityFeed(communityId: churchId)
                }
            }
        }
    }
    
    // MARK: - Shared tab picker (Global / Community pills)

    private var tabPicker: some View {
        HStack(spacing: 8) {
            ForEach(FeedTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.78))) {
                        selectedTab = tab
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(tab.rawValue)
                        .font(.custom(isSelected ? "OpenSans-SemiBold" : "OpenSans-Regular", size: 14))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(.regularMaterial)
                                    .overlay(
                                        Capsule().strokeBorder(
                                            LinearGradient(
                                                colors: [.white.opacity(0.55), .white.opacity(0.12)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 0.5
                                        )
                                    )
                                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                            } else {
                                Capsule()
                                    .fill(Color.primary.opacity(0.05))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Collapsible glass header body (rendered when the flag is ON)

    private var glassBody: some View {
        CollapsibleGlassScrollView(
            coordinateSpace: "activityGlassScroll",
            header: { progress, topInset in
                CollapsibleGlassHeader(
                    progress: progress,
                    title: "Activity",
                    subtitle: glassSubtitle,
                    topInset: topInset
                )
            },
            content: {
                LazyVStack(spacing: 14, pinnedViews: [.sectionHeaders]) {
                    Section {
                        glassRows
                    } header: {
                        tabPicker
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        )
        .background(Color(.systemBackground).ignoresSafeArea())
        .onAppear {
            activityService.startObservingGlobalFeed()
            Task { await loadUserChurch() }
        }
        .onDisappear {
            activityService.stopObservingGlobalFeed()
            if let churchId = userChurchId {
                activityService.stopObservingCommunityFeed(communityId: churchId)
            }
        }
    }

    private var glassSubtitle: String {
        switch selectedTab {
        case .global:
            let n = activityService.globalActivities.count
            return n == 0 ? "From people you follow" : "\(n) recent update\(n == 1 ? "" : "s")"
        case .community:
            let n = communityActivities.count
            return n == 0 ? "Your church community" : "\(n) in your community"
        }
    }

    @ViewBuilder private var glassRows: some View {
        if selectedTab == .global {
            if let errorMessage = activityService.globalFeedError {
                feedErrorState(message: errorMessage)
            } else if activityService.isLoading && activityService.globalActivities.isEmpty {
                AMENLoadingIndicator()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else if activityService.globalActivities.isEmpty {
                emptyState
            } else {
                ForEach(activityService.globalActivities) { activity in
                    GlassContentCard {
                        ActivityRow(activity: activity, inGlassSurface: true)
                    }
                }
            }
        } else {
            if isLoadingChurch {
                AMENLoadingIndicator()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else if userChurchId == nil {
                communityNochurchState
            } else if communityActivities.isEmpty {
                communityEmptyState
            } else {
                ForEach(communityActivities) { activity in
                    GlassContentCard {
                        ActivityRow(activity: activity, inGlassSurface: true)
                    }
                }
            }
        }
    }

    private func loadUserChurch() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Skip the Firestore fetch if we already have the church ID — the listener
        // is already active, so there's nothing to do on repeated view appearances.
        guard userChurchId == nil else { return }
        isLoadingChurch = true
        defer { isLoadingChurch = false }

        do {
            lazy var db = Firestore.firestore()
            let snapshot = try await db.collection("userChurchRelations")
                .whereField("userId", isEqualTo: uid)
                .order(by: "since", descending: true)
                .limit(to: 1)
                .getDocuments()

            if let doc = snapshot.documents.first,
               let churchId = doc.data()["churchId"] as? String {
                // Only start the listener if we haven't already started one for this church
                if userChurchId != churchId {
                    userChurchId = churchId
                    activityService.startObservingCommunityFeed(communityId: churchId)
                }
            }
        } catch {
            dlog("⚠️ Could not load user's church: \(error.localizedDescription)")
        }
    }

    private var communityNochurchState: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2")
                .font(.systemScaled(48))
                .foregroundStyle(.secondary)

            Text("No Church Connected")
                .font(AMENFont.bold(18))
                .foregroundStyle(.primary)

            Text("Connect with your church in the Find Church tab\nto see your community's activity here.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var communityEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.systemScaled(48))
                .foregroundStyle(.secondary)

            Text("No Community Activity Yet")
                .font(AMENFont.bold(18))
                .foregroundStyle(.primary)

            Text("When members of your church interact with posts,\nyou'll see their activity here.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.systemScaled(48))
                .foregroundStyle(.secondary)
            
            Text("No Recent Activity")
                .font(AMENFont.bold(18))
                .foregroundStyle(.primary)
            
            Text("When people you follow interact with posts,\nyou'll see their activity here.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func feedErrorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.systemScaled(48))
                .foregroundStyle(.secondary)

            Text("Could Not Load Activity")
                .font(AMENFont.bold(18))
                .foregroundStyle(.primary)

            Text("Check your connection and try again.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                activityService.retryGlobalFeed()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(AMENFont.semiBold(15))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    let activity: Activity
    /// When hosted inside a `GlassContentCard`, the card supplies the surface — so the
    /// row drops its own background/padding to avoid a card-inside-a-card look.
    var inGlassSurface: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconBackgroundColor)
                    .frame(width: 40, height: 40)
                
                Image(systemName: activity.icon)
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(iconForegroundColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.displayText)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.primary)
                
                if let postContent = activity.postContent {
                    Text(postContent)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Text(activity.timeAgo)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
        }
        .padding(inGlassSurface ? 0 : 12)
        .background {
            if !inGlassSurface {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            }
        }
    }
    
    private var iconBackgroundColor: Color {
        switch activity.type {
        case .postCreated:
            return Color.blue.opacity(0.15)
        case .postLiked:
            return Color.orange.opacity(0.15)
        case .postAmened:
            return Color.black.opacity(0.08)
        case .commented:
            return Color.green.opacity(0.15)
        case .reposted:
            return Color.purple.opacity(0.15)
        case .followedUser:
            return Color.pink.opacity(0.15)
        case .prayingStarted:
            return Color.blue.opacity(0.15)
        }
    }
    
    private var iconForegroundColor: Color {
        switch activity.type {
        case .postCreated:
            return .blue
        case .postLiked:
            return .orange
        case .postAmened:
            return .black
        case .commented:
            return .green
        case .reposted:
            return .purple
        case .followedUser:
            return .pink
        case .prayingStarted:
            return .blue
        }
    }
}

#Preview {
    ActivityFeedView()
}
