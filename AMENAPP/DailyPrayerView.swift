//
//  DailyPrayerView.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI

struct EnhancedDailyPrayerView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab: PrayerTab = .today
    @State private var completedPrayers: Set<String> = []
    @Namespace private var tabAnimation
    
    enum PrayerTab: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
        case saved = "Saved"
        
        var icon: String {
            switch self {
            case .today: return "house.fill"
            case .week: return "antenna.radiowaves.left.and.right"
            case .saved: return "books.vertical.fill"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Daily Prayer")
                            .font(.custom("OpenSans-Bold", size: 32))
                        
                        Text("Strengthen your faith daily")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Streak badge
                    VStack(spacing: 4) {
                        Text("7")
                            .font(.custom("OpenSans-Bold", size: 20))
                            .foregroundStyle(.orange)
                        
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                            
                            Text("day streak")
                                .font(.custom("OpenSans-SemiBold", size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.1))
                    )
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                // Liquid Glass Pill Tab Selector (matching image)
                HStack(spacing: 0) {
                    ForEach(PrayerTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                selectedTab = tab
                                let haptic = UIImpactFeedbackGenerator(style: .medium)
                                haptic.impactOccurred()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(selectedTab == tab ? .white : .black.opacity(0.7))
                                
                                if selectedTab == tab {
                                    Text(tab.rawValue)
                                        .font(.custom("OpenSans-Bold", size: 15))
                                        .foregroundStyle(.white)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, selectedTab == tab ? 20 : 16)
                            .padding(.vertical, 12)
                            .background(
                                Group {
                                    if selectedTab == tab {
                                        Capsule()
                                            .fill(Color.black)
                                            .matchedGeometryEffect(id: "selectedTab", in: tabAnimation)
                                            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                                    } else {
                                        Capsule()
                                            .fill(Color.clear)
                                    }
                                }
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(Color.black.opacity(0.05), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                
                // Content
                ScrollView {
                    VStack(spacing: 20) {
                        switch selectedTab {
                        case .today:
                            TodayPrayersContent(completedPrayers: $completedPrayers)
                        case .week:
                            WeekPrayersContent()
                        case .saved:
                            SavedPrayersContent()
                        }
                    }
                    .padding(.vertical)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
}

// MARK: - Today's Prayers Content
struct TodayPrayersContent: View {
    @Binding var completedPrayers: Set<String>
    
    let prayers = [
        EnhancedPrayerItem(
            id: "morning",
            title: "Morning Prayer",
            time: "6:00 AM",
            scripture: "Psalm 5:3",
            content: "In the morning, LORD, you hear my voice; in the morning I lay my requests before you and wait expectantly.",
            category: .morning,
            duration: "5 min"
        ),
        EnhancedPrayerItem(
            id: "gratitude",
            title: "Prayer of Gratitude",
            time: "12:00 PM",
            scripture: "1 Thessalonians 5:18",
            content: "Give thanks in all circumstances; for this is God's will for you in Christ Jesus.",
            category: .gratitude,
            duration: "3 min"
        ),
        EnhancedPrayerItem(
            id: "evening",
            title: "Evening Reflection",
            time: "9:00 PM",
            scripture: "Psalm 4:8",
            content: "In peace I will lie down and sleep, for you alone, LORD, make me dwell in safety.",
            category: .evening,
            duration: "7 min"
        )
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            // Progress card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Today's Progress")
                        .font(.custom("OpenSans-Bold", size: 18))
                    
                    Spacer()
                    
                    Text("\(completedPrayers.count)/\(prayers.count)")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.purple)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 8)
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(completedPrayers.count) / CGFloat(prayers.count), height: 8)
                            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: completedPrayers.count)
                    }
                }
                .frame(height: 8)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.purple.opacity(0.05))
            )
            .padding(.horizontal)
            
            // Prayer items
            ForEach(prayers) { prayer in
                PrayerCard(
                    prayer: prayer,
                    isCompleted: completedPrayers.contains(prayer.id)
                ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        if completedPrayers.contains(prayer.id) {
                            completedPrayers.remove(prayer.id)
                        } else {
                            completedPrayers.insert(prayer.id)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Prayer Card
struct PrayerCard: View {
    let prayer: EnhancedPrayerItem
    let isCompleted: Bool
    let onComplete: () -> Void
    @State private var showDetail = false
    
    var body: some View {
        Button {
            showDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [prayer.category.color.opacity(0.2), prayer.category.color.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: prayer.category.icon)
                            .font(.system(size: 26))
                            .foregroundStyle(prayer.category.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(prayer.title)
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.primary)
                            
                            if isCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 12))
                                Text(prayer.time)
                                    .font(.custom("OpenSans-Regular", size: 13))
                            }
                            
                            HStack(spacing: 4) {
                                Image(systemName: "timer")
                                    .font(.system(size: 12))
                                Text(prayer.duration)
                                    .font(.custom("OpenSans-Regular", size: 13))
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                
                // Scripture preview
                VStack(alignment: .leading, spacing: 6) {
                    Text(prayer.scripture)
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundStyle(.blue)
                    
                    Text(prayer.content)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .lineSpacing(4)
                }
                .padding(.top, 4)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isCompleted ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal)
        .sheet(isPresented: $showDetail) {
            DailyPrayerDetailView(prayer: prayer, isCompleted: isCompleted, onComplete: onComplete)
        }
    }
}

// MARK: - Daily Prayer Detail View
struct DailyPrayerDetailView: View {
    @Environment(\.dismiss) var dismiss
    let prayer: EnhancedPrayerItem
    let isCompleted: Bool
    let onComplete: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [prayer.category.color.opacity(0.2), prayer.category.color.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: prayer.category.icon)
                            .font(.system(size: 48))
                            .foregroundStyle(prayer.category.color)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        // Title
                        Text(prayer.title)
                            .font(.custom("OpenSans-Bold", size: 28))
                        
                        // Meta info
                        HStack(spacing: 20) {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                Text(prayer.time)
                            }
                            
                            HStack(spacing: 6) {
                                Image(systemName: "timer")
                                Text(prayer.duration)
                            }
                        }
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        
                        // Scripture
                        VStack(alignment: .leading, spacing: 12) {
                            Text(prayer.scripture)
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.blue)
                            
                            Text(prayer.content)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .lineSpacing(6)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.05))
                        )
                        
                        // Prayer guide
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Prayer Guide")
                                .font(.custom("OpenSans-Bold", size: 18))
                            
                            Text(prayer.guide)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .lineSpacing(6)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.05))
                        )
                    }
                    .padding(.horizontal)
                    
                    // Complete button
                    Button {
                        onComplete()
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                            
                            Text(isCompleted ? "Completed" : "Mark as Complete")
                                .font(.custom("OpenSans-Bold", size: 17))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isCompleted ? Color.green : Color.black)
                                .shadow(color: (isCompleted ? Color.green : Color.black).opacity(0.3), radius: 12, y: 4)
                        )
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Week Prayers Content
struct WeekPrayersContent: View {
    let weekDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    @State private var selectedDay = 2 // Wednesday
    
    var body: some View {
        VStack(spacing: 20) {
            // Week selector
            HStack(spacing: 12) {
                ForEach(0..<weekDays.count, id: \.self) { index in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedDay = index
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(weekDays[index])
                                .font(.custom("OpenSans-Bold", size: 13))
                            
                            Circle()
                                .fill(selectedDay == index ? Color.black : Color.gray.opacity(0.2))
                                .frame(width: 8, height: 8)
                        }
                        .foregroundStyle(selectedDay == index ? .black : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedDay == index ? Color.black.opacity(0.05) : Color.clear)
                        )
                    }
                }
            }
            .padding(.horizontal)
            
            Text("Weekly prayer themes coming soon")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .padding(.top, 40)
        }
    }
}

// MARK: - Saved Prayers Content
struct SavedPrayersContent: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Saved Prayers")
                .font(.custom("OpenSans-Bold", size: 24))
            
            Text("Save your favorite prayers and access them anytime")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Models
struct EnhancedPrayerItem: Identifiable {
    let id: String
    let title: String
    let time: String
    let scripture: String
    let content: String
    let category: EnhancedPrayerCategory
    let duration: String
    
    var guide: String {
        switch category {
        case .morning:
            return "Begin your day with gratitude. Thank God for the new day and ask for His guidance in all you do. Pray for strength and wisdom to face today's challenges."
        case .gratitude:
            return "Reflect on God's blessings in your life. Give thanks for both big and small things. Remember His faithfulness and provision."
        case .evening:
            return "Review your day with God. Confess any shortcomings, thank Him for victories, and surrender your worries as you prepare for rest."
        }
    }
}

enum EnhancedPrayerCategory {
    case morning
    case gratitude
    case evening
    
    var color: Color {
        switch self {
        case .morning: return .orange
        case .gratitude: return .green
        case .evening: return .purple
        }
    }
    
    var icon: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .gratitude: return "heart.fill"
        case .evening: return "moon.stars.fill"
        }
    }
}

#Preview("Daily Prayer View") {
    EnhancedDailyPrayerView()
}
