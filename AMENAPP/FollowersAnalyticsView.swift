//
//  FollowersAnalyticsView.swift
//  AMENAPP
//
//  Created by Steph on 1/28/26.
//
//  Analytics and insights for followers and following
//

import SwiftUI
import Charts
import FirebaseAuth
import Combine

// MARK: - Followers Analytics View

struct FollowersAnalyticsView: View {
    @StateObject private var viewModel = FollowersAnalyticsViewModel()
    @State private var selectedTimeRange: TimeRange = .week
    
    enum TimeRange: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
        case all = "All Time"
        
        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .year: return 365
            case .all: return 0
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Stats Cards
                    statsCardsView
                    
                    // Time Range Selector
                    timeRangeSelectorView
                    
                    // Growth Chart
                    growthChartView
                    
                    // Top Followers
                    topFollowersView
                    
                    // Mutual Followers
                    mutualFollowersView
                    
                    // Engagement Insights
                    engagementInsightsView
                }
                .padding(.vertical, 20)
            }
            .background(Color(white: 0.98))
            .navigationTitle("Follower Analytics")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await viewModel.loadAnalytics(timeRange: selectedTimeRange)
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }
    
    // MARK: - Stats Cards
    
    private var statsCardsView: some View {
        HStack(spacing: 16) {
            FollowerStatCard(
                value: "\(viewModel.totalFollowers)",
                label: "Followers",
                icon: "person.2.fill",
                color: .blue,
                change: viewModel.followerChange
            )
            
            FollowerStatCard(
                value: "\(viewModel.totalFollowing)",
                label: "Following",
                icon: "person.badge.plus",
                color: .purple,
                change: viewModel.followingChange
            )
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Time Range Selector
    
    private var timeRangeSelectorView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    TimeRangeChip(
                        range: range,
                        isSelected: selectedTimeRange == range
                    ) {
                        withAnimation {
                            selectedTimeRange = range
                        }
                        Task {
                            await viewModel.loadAnalytics(timeRange: range)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Growth Chart
    
    @available(iOS 16.0, *)
    private var growthChartView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Follower Growth")
                .font(.custom("OpenSans-Bold", size: 18))
                .padding(.horizontal, 20)
            
            if viewModel.growthData.isEmpty {
                emptyChartView
            } else {
                Chart {
                    ForEach(viewModel.growthData) { data in
                        LineMark(
                            x: .value("Date", data.date),
                            y: .value("Followers", data.count)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                        
                        AreaMark(
                            x: .value("Date", data.date),
                            y: .value("Followers", data.count)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .blue.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
                }
                .frame(height: 200)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
                )
                .padding(.horizontal, 20)
            }
        }
    }
    
    private var emptyChartView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            
            Text("Not enough data yet")
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        )
        .padding(.horizontal, 20)
    }
    
    // MARK: - Top Followers
    
    private var topFollowersView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Top Followers")
                    .font(.custom("OpenSans-Bold", size: 18))
                
                Spacer()
                
                // Commenting out until MyFollowersListView is implemented
                // NavigationLink("See All") {
                //     MyFollowersListView()
                // }
                // .font(.custom("OpenSans-SemiBold", size: 14))
                // .foregroundStyle(.blue)
            }
            .padding(.horizontal, 20)
            
            if viewModel.topFollowers.isEmpty {
                emptyFollowersView
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(viewModel.topFollowers.prefix(5).enumerated()), id: \.element.id) { index, user in
                        TopFollowerRow(user: user, rank: index + 1)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    private var emptyFollowersView: some View {
        Text("No followers yet")
            .font(.custom("OpenSans-Regular", size: 15))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }
    
    // MARK: - Mutual Followers
    
    private var mutualFollowersView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Mutual Connections")
                    .font(.custom("OpenSans-Bold", size: 18))
                
                Spacer()
                
                Text("\(viewModel.mutualFollowersCount)")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 20)
            
            if !viewModel.mutualFollowers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.mutualFollowers.prefix(10)) { user in
                            MutualFollowerCard(user: user)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
    
    // MARK: - Engagement Insights
    
    private var engagementInsightsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Engagement Insights")
                .font(.custom("OpenSans-Bold", size: 18))
                .padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                InsightCard(
                    icon: "chart.bar.fill",
                    title: "Avg. Engagement Rate",
                    value: String(format: "%.1f%%", viewModel.engagementRate),
                    trend: viewModel.engagementTrend,
                    color: .green
                )
                
                InsightCard(
                    icon: "arrow.up.right",
                    title: "New Followers This Week",
                    value: "+\(viewModel.newFollowersThisWeek)",
                    trend: nil,
                    color: .blue
                )
                
                InsightCard(
                    icon: "arrow.2.squarepath",
                    title: "Follower/Following Ratio",
                    value: String(format: "%.2f", viewModel.followerRatio),
                    trend: nil,
                    color: .purple
                )
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Follower Stat Card

struct FollowerStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    let change: Int?
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(color)
                
                Spacer()
                
                if let change = change {
                    HStack(spacing: 4) {
                        Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(abs(change))")
                            .font(.custom("OpenSans-Bold", size: 12))
                    }
                    .foregroundStyle(change >= 0 ? .green : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill((change >= 0 ? Color.green : Color.red).opacity(0.15))
                    )
                }
            }
            
            Text(value)
                .font(.custom("OpenSans-Bold", size: 32))
                .foregroundStyle(.black)
            
            Text(label)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        )
    }
}

// MARK: - Time Range Chip

struct TimeRangeChip: View {
    let range: FollowersAnalyticsView.TimeRange
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(range.rawValue)
                .font(.custom("OpenSans-Bold", size: 14))
                .foregroundStyle(isSelected ? .white : .black.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.black : Color.white)
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Top Follower Row

struct TopFollowerRow: View {
    let user: FollowUserProfile
    let rank: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // Rank Badge
            ZStack {
                Circle()
                    .fill(rankColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Text("\(rank)")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(rankColor)
            }
            
            // Avatar
            Circle()
                .fill(Color.black)
                .frame(width: 44, height: 44)
                .overlay(
                    Text(user.initials)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.white)
                )
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.black)
                
                Text("@\(user.username)")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Follower count
            Text("\(user.followersCount) followers")
                .font(.custom("OpenSans-SemiBold", size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
    
    private var rankColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .blue
        }
    }
}

// MARK: - Mutual Follower Card

struct MutualFollowerCard: View {
    let user: FollowUserProfile
    
    var body: some View {
        NavigationLink(destination: UserProfileView(userId: user.id)) {
            VStack(spacing: 8) {
                Circle()
                    .fill(Color.black)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Text(user.initials)
                            .font(.custom("OpenSans-Bold", size: 20))
                            .foregroundStyle(.white)
                    )
                
                Text(user.displayName)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                
                Text("@\(user.username)")
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 100)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Insight Card

struct InsightCard: View {
    let icon: String
    let title: String
    let value: String
    let trend: String?
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                
                Text(value)
                    .font(.custom("OpenSans-Bold", size: 22))
                    .foregroundStyle(.black)
                
                if let trend = trend {
                    Text(trend)
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.green)
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - View Model

@MainActor
class FollowersAnalyticsViewModel: ObservableObject {
    @Published var totalFollowers = 0
    @Published var totalFollowing = 0
    @Published var followerChange: Int? = nil
    @Published var followingChange: Int? = nil
    @Published var growthData: [FollowerGrowthData] = []
    @Published var topFollowers: [FollowUserProfile] = []
    @Published var mutualFollowers: [FollowUserProfile] = []
    @Published var mutualFollowersCount = 0
    @Published var engagementRate: Double = 0.0
    @Published var engagementTrend: String? = nil
    @Published var newFollowersThisWeek = 0
    @Published var followerRatio: Double = 0.0
    
    private let followService = FollowService.shared
    
    func loadAnalytics(timeRange: FollowersAnalyticsView.TimeRange) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Load followers and following
        do {
            let followers = try await followService.fetchFollowers(userId: userId)
            let following = try await followService.fetchFollowing(userId: userId)
            
            totalFollowers = followers.count
            totalFollowing = following.count
            
            // Calculate ratio
            followerRatio = totalFollowing > 0 ? Double(totalFollowers) / Double(totalFollowing) : Double(totalFollowers)
            
            // Get top followers (sorted by their follower count)
            topFollowers = followers.sorted { $0.followersCount > $1.followersCount }
            
            // Find mutual followers (people you follow who follow you back)
            let followingIds = Set(following.map { $0.id })
            mutualFollowers = followers.filter { followingIds.contains($0.id) }
            mutualFollowersCount = mutualFollowers.count
            
            // Calculate changes (mock data for now)
            followerChange = Int.random(in: -5...15)
            followingChange = Int.random(in: -3...8)
            newFollowersThisWeek = Int.random(in: 0...20)
            
            // Mock engagement rate
            engagementRate = Double.random(in: 2.0...8.5)
            engagementTrend = "+\(String(format: "%.1f", Double.random(in: 0.1...1.5)))% vs last period"
            
            // Generate growth data
            generateGrowthData(days: timeRange.days)
            
        } catch {
            print("❌ Failed to load analytics: \(error)")
        }
    }
    
    func refresh() async {
        await loadAnalytics(timeRange: .week)
    }
    
    private func generateGrowthData(days: Int) {
        let actualDays = days > 0 ? days : 30
        var data: [FollowerGrowthData] = []
        var currentCount = max(0, totalFollowers - Int.random(in: 0...20))
        
        for i in 0..<actualDays {
            let date = Calendar.current.date(byAdding: .day, value: -actualDays + i, to: Date())!
            currentCount += Int.random(in: -2...5)
            currentCount = max(0, currentCount)
            
            data.append(FollowerGrowthData(date: date, count: currentCount))
        }
        
        growthData = data
    }
}

// MARK: - Growth Data Model

struct FollowerGrowthData: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
}

// MARK: - Preview

#Preview {
    FollowersAnalyticsView()
}
