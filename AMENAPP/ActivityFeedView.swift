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
    @State private var selectedTab: FeedTab = .global
    @State private var userChurchId: String?
    @State private var isLoadingChurch = false
    
    enum FeedTab: String, CaseIterable {
        case global = "Global"
        case community = "Community"
    }
    
    private var communityActivities: [Activity] {
        guard let churchId = userChurchId else { return [] }
        return activityService.communityActivities[churchId] ?? []
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Picker
                Picker("Feed Type", selection: $selectedTab) {
                    ForEach(FeedTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Activity List
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if selectedTab == .global {
                            if activityService.globalActivities.isEmpty {
                                emptyState
                            } else {
                                ForEach(activityService.globalActivities) { activity in
                                    ActivityRow(activity: activity)
                                }
                            }
                        } else {
                            if isLoadingChurch {
                                ProgressView()
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
    
    private func loadUserChurch() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoadingChurch = true
        defer { isLoadingChurch = false }

        do {
            let db = Firestore.firestore()
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
            print("⚠️ Could not load user's church: \(error.localizedDescription)")
        }
    }

    private var communityNochurchState: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Church Connected")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)

            Text("Connect with your church in the Find Church tab\nto see your community's activity here.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var communityEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Community Activity Yet")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)

            Text("When members of your church interact with posts,\nyou'll see their activity here.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No Recent Activity")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)
            
            Text("When people you follow interact with posts,\nyou'll see their activity here.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    let activity: Activity
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconBackgroundColor)
                    .frame(width: 40, height: 40)
                
                Image(systemName: activity.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconForegroundColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.displayText)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.primary)
                
                if let postContent = activity.postContent {
                    Text(postContent)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Text(activity.timeAgo)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
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
