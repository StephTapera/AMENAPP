//
//  BibleStudyGuideView.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI

struct BibleStudyGuideView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedPlan: StudyPlan = .beginner
    @State private var searchText = ""
    
    enum StudyPlan: String, CaseIterable {
        case beginner = "Beginner"
        case intermediate = "Intermediate"
        case advanced = "Advanced"
        case topical = "Topical"
        case chronological = "Chronological"
    }
    
    var filteredPlans: [BibleStudyPlan] {
        var plans: [BibleStudyPlan]
        
        if selectedPlan == .topical {
            plans = bibleStudyPlans.filter { $0.type == "Topical" }
        } else if selectedPlan == .chronological {
            plans = bibleStudyPlans.filter { $0.type == "Chronological" }
        } else {
            plans = bibleStudyPlans.filter { $0.level == selectedPlan.rawValue }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            plans = plans.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText) ||
                $0.topics.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        
        return plans
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Header with Liquid Glass
            VStack(spacing: 16) {
                HStack {
                    // Liquid Glass back button
                    Button {
                        dismiss()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.3),
                                                    Color.white.opacity(0.1)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
                            
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 2) {
                        Text("Bible Study")
                            .font(.custom("OpenSans-Bold", size: 18))
                            .foregroundStyle(.primary)
                        
                        Text("\(filteredPlans.count) Plans")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Stats button
                    Button {
                        // Show stats
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.3),
                                                    Color.white.opacity(0.1)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
                            
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                // Search bar with liquid glass
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search study plans", text: $searchText)
                        .font(.custom("OpenSans-Regular", size: 16))
                    
                    if !searchText.isEmpty {
                        Button {
                            withAnimation {
                                searchText = ""
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
                .padding(.horizontal, 20)
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
            )
            
            // Plan type selector with liquid glass chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StudyPlan.allCases, id: \.self) { plan in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedPlan = plan
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: plan.iconName)
                                    .font(.system(size: 12, weight: .semibold))
                                
                                Text(plan.rawValue)
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                            }
                            .foregroundStyle(selectedPlan == plan ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(selectedPlan == plan ?
                                          LinearGradient(
                                            colors: [.blue, .cyan],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                          ) :
                                          LinearGradient(
                                            colors: [Color(.systemGray6), Color(.systemGray6)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                          )
                                    )
                                    .shadow(
                                        color: selectedPlan == plan ? .blue.opacity(0.3) : .clear,
                                        radius: 8,
                                        y: 4
                                    )
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 12)
            
            ScrollView {
                VStack(spacing: 16) {
                    // Smart header with stats
                    if !searchText.isEmpty {
                        SearchResultsHeader(count: filteredPlans.count, searchTerm: searchText)
                    } else {
                        StudyInsightsCard(planType: selectedPlan)
                    }
                    
                    // Study plans
                    if filteredPlans.isEmpty {
                        BibleStudyEmptyStateView(searchTerm: searchText)
                    } else {
                        ForEach(filteredPlans) { plan in
                            EnhancedBibleStudyPlanCard(plan: plan)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Study Plan Extension
extension BibleStudyGuideView.StudyPlan {
    var iconName: String {
        switch self {
        case .beginner:
            return "leaf.fill"
        case .intermediate:
            return "book.fill"
        case .advanced:
            return "graduationcap.fill"
        case .topical:
            return "list.bullet.rectangle"
        case .chronological:
            return "clock.arrow.circlepath"
        }
    }
}

// MARK: - Search Results Header
struct SearchResultsHeader: View {
    let count: Int
    let searchTerm: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(count) Result\(count == 1 ? "" : "s")")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
                
                Text("for \"\(searchTerm)\"")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Study Insights Card
struct StudyInsightsCard: View {
    let planType: BibleStudyGuideView.StudyPlan
    
    var insightText: String {
        switch planType {
        case .beginner:
            return "Perfect for those starting their Bible study journey"
        case .intermediate:
            return "Deepen your understanding of Scripture"
        case .advanced:
            return "Intensive theological and contextual studies"
        case .topical:
            return "Focus on specific themes and topics"
        case .chronological:
            return "Read the Bible in historical order"
        }
    }
    
    var insightIcon: String {
        switch planType {
        case .beginner:
            return "sparkles"
        case .intermediate:
            return "flame.fill"
        case .advanced:
            return "star.fill"
        case .topical:
            return "lightbulb.fill"
        case .chronological:
            return "timeline.selection"
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                
                Image(systemName: insightIcon)
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(planType.rawValue) Plans")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
                
                Text(insightText)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .cyan.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Bible Study Empty State
struct BibleStudyEmptyStateView: View {
    let searchTerm: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text("No Plans Found")
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.primary)
            
            Text("Try adjusting your search or filters")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}

// MARK: - Enhanced Bible Study Plan Card
struct EnhancedBibleStudyPlanCard: View {
    let plan: BibleStudyPlan
    @State private var isEnrolled = false
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Hero section with gradient
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: plan.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 100)
                
                // Icon overlay
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: plan.icon)
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.3))
                        Spacer()
                    }
                    .padding(16)
                }
                
                // Badge
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                    Text(plan.level)
                        .font(.custom("OpenSans-Bold", size: 11))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            // Content section
            VStack(alignment: .leading, spacing: 14) {
                // Title and stats
                VStack(alignment: .leading, spacing: 8) {
                    Text(plan.title)
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 12))
                            Text("\(plan.duration) days")
                                .font(.custom("OpenSans-SemiBold", size: 13))
                        }
                        
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 12))
                            Text("\(plan.dailyTime) min/day")
                                .font(.custom("OpenSans-SemiBold", size: 13))
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                
                Text(plan.description)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                
                // Topics grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(plan.topics.prefix(4), id: \.self) { topic in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.green)
                            
                            Text(topic)
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.primary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray6))
                        )
                    }
                }
                
                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isEnrolled.toggle()
                            let haptic = UIImpactFeedbackGenerator(style: .medium)
                            haptic.impactOccurred()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isEnrolled ? "checkmark.circle.fill" : "play.circle.fill")
                                .font(.system(size: 18))
                            
                            Text(isEnrolled ? "Enrolled" : "Start Plan")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    isEnrolled ?
                                    LinearGradient(
                                        colors: [.green, .mint],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ) :
                                    LinearGradient(
                                        colors: [.black, .black],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(
                                    color: isEnrolled ? .green.opacity(0.3) : .black.opacity(0.2),
                                    radius: 8,
                                    y: 4
                                )
                        )
                    }
                    
                    Button {
                        // Share action
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18))
                            .foregroundStyle(.primary)
                            .frame(width: 50, height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                            )
                    }
                }
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        )
        .padding(.horizontal, 20)
    }
}

struct BibleStudyPlan: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let level: String
    let type: String
    let duration: Int
    let dailyTime: Int
    let topics: [String]
    let icon: String
    let gradientColors: [Color]
}

let bibleStudyPlans = [
    BibleStudyPlan(
        title: "Gospel Foundations",
        description: "Start your journey with the life and teachings of Jesus Christ",
        level: "Beginner",
        type: "Sequential",
        duration: 30,
        dailyTime: 15,
        topics: ["Life of Jesus", "Salvation", "Grace", "Faith"],
        icon: "book.pages",
        gradientColors: [.blue, .cyan]
    ),
    BibleStudyPlan(
        title: "Old Testament Overview",
        description: "Journey through God's covenant with His people",
        level: "Intermediate",
        type: "Sequential",
        duration: 60,
        dailyTime: 20,
        topics: ["Creation", "Law", "Prophets", "Wisdom"],
        icon: "scroll",
        gradientColors: [.purple, .pink]
    ),
    BibleStudyPlan(
        title: "Pauline Epistles Deep Dive",
        description: "Explore the theological richness of Paul's letters",
        level: "Advanced",
        type: "Sequential",
        duration: 90,
        dailyTime: 30,
        topics: ["Theology", "Church", "Spiritual Growth", "End Times"],
        icon: "doc.text",
        gradientColors: [.orange, .red]
    ),
    BibleStudyPlan(
        title: "Prayer & Worship",
        description: "Study what the Bible teaches about communion with God",
        level: "Intermediate",
        type: "Topical",
        duration: 21,
        dailyTime: 15,
        topics: ["Prayer", "Worship", "Praise", "Thanksgiving"],
        icon: "hands.sparkles",
        gradientColors: [.green, .teal]
    ),
    BibleStudyPlan(
        title: "Bible Timeline Journey",
        description: "Read the Bible in the order events actually occurred",
        level: "Advanced",
        type: "Chronological",
        duration: 365,
        dailyTime: 25,
        topics: ["History", "Prophecy", "Fulfillment", "Context"],
        icon: "calendar.circle",
        gradientColors: [.indigo, .blue]
    ),
    BibleStudyPlan(
        title: "Faith in Action",
        description: "Discover how to live out your Christian faith daily",
        level: "Beginner",
        type: "Topical",
        duration: 14,
        dailyTime: 10,
        topics: ["Love", "Service", "Forgiveness", "Witness"],
        icon: "heart.circle",
        gradientColors: [.pink, .orange]
    )
]

#Preview {
    BibleStudyGuideView()
}
