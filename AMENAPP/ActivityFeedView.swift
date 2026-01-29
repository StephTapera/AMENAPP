//
//  ActivityFeedView.swift
//  AMENAPP
//
//  Created by Assistant on 1/24/26.
//
//  View for displaying recent activity from followed users and communities
//

import SwiftUI

struct ActivityFeedView: View {
    @StateObject private var activityService = ActivityFeedService.shared
    @State private var selectedTab: FeedTab = .global
    
    enum FeedTab: String, CaseIterable {
        case global = "Global"
        case community = "Community"
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
                            Text("Community feed coming soon")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                activityService.startObservingGlobalFeed()
            }
            .onDisappear {
                activityService.stopObservingGlobalFeed()
            }
        }
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
