//
//  PrayerToolkitView.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI

struct PrayerToolkitView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedCategory: PrayerCategory = .all
    
    enum PrayerCategory: String, CaseIterable {
        case all = "All"
        case structured = "Structured"
        case scripture = "Scripture"
        case intercession = "Intercession"
        case thanksgiving = "Thanksgiving"
    }
    
    var filteredTools: [PrayerTool] {
        if selectedCategory == .all {
            return prayerTools
        }
        return prayerTools.filter { $0.category == selectedCategory.rawValue }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PrayerCategory.allCases, id: \.self) { category in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedCategory = category
                                }
                            } label: {
                                Text(category.rawValue)
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(selectedCategory == category ? .white : .black)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(selectedCategory == category ? Color.black : Color.gray.opacity(0.1))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 16)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "hands.sparkles.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.purple)
                                    .symbolEffect(.pulse, options: .repeating.speed(0.5))
                                
                                Text("Prayer Toolkit")
                                    .font(.custom("OpenSans-Bold", size: 24))
                            }
                            
                            Text("Resources to deepen and enrich your prayer life")
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        
                        // Prayer Timer Card (Featured) - Now swipeable with auto-rotation
                        FeaturedPrayerCard()
                        
                        // Prayer Tools
                        ForEach(filteredTools) { tool in
                            PrayerToolCard(tool: tool)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Prayer Toolkit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
}

// MARK: - Prayer Banner Data
struct PrayerBanner: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let description: String
    let gradientColors: [Color]
}

let prayerBanners = [
    PrayerBanner(
        icon: "timer",
        title: "Prayer Timer",
        subtitle: "Structured prayer with guided prompts",
        description: "Set dedicated time for prayer with ACTS framework: Adoration, Confession, Thanksgiving, and Supplication",
        gradientColors: [.purple, .pink]
    ),
    PrayerBanner(
        icon: "book.closed.fill",
        title: "Scripture Prayers",
        subtitle: "Pray God's Word back to Him",
        description: "Transform Bible verses into personal prayers and align your heart with God's will through His Word",
        gradientColors: [.blue, .cyan]
    ),
    PrayerBanner(
        icon: "hands.sparkles.fill",
        title: "ACTS Prayer Guide",
        subtitle: "Framework for meaningful prayer",
        description: "Learn to pray with purpose using Adoration, Confession, Thanksgiving, and Supplication",
        gradientColors: [.orange, .red]
    ),
    PrayerBanner(
        icon: "heart.fill",
        title: "Gratitude Prayers",
        subtitle: "Cultivate a thankful heart",
        description: "Focus on God's blessings and faithfulness through regular thanksgiving and praise",
        gradientColors: [.green, .teal]
    )
]

struct FeaturedPrayerCard: View {
    @State private var currentIndex = 0
    @State private var shimmerPhase: CGFloat = 0
    @State private var autoScrollTimer: Timer?
    
    var currentBanner: PrayerBanner {
        prayerBanners[currentIndex]
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Swipeable banner
            TabView(selection: $currentIndex) {
                ForEach(Array(prayerBanners.enumerated()), id: \.element.id) { index, banner in
                    PrayerBannerContent(banner: banner, shimmerPhase: $shimmerPhase)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 220)
            
            // Custom page indicator
            HStack(spacing: 8) {
                ForEach(0..<prayerBanners.count, id: \.self) { index in
                    Capsule()
                        .fill(currentIndex == index ? currentBanner.gradientColors[0] : Color.gray.opacity(0.3))
                        .frame(width: currentIndex == index ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentIndex)
                }
            }
            .padding(.horizontal)
        }
        .onAppear {
            startAutoScroll()
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                shimmerPhase = 400
            }
        }
        .onDisappear {
            stopAutoScroll()
        }
    }
    
    private func startAutoScroll() {
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentIndex = (currentIndex + 1) % prayerBanners.count
            }
        }
    }
    
    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }
}

struct PrayerBannerContent: View {
    let banner: PrayerBanner
    @Binding var shimmerPhase: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [banner.gradientColors[0].opacity(0.6), banner.gradientColors[1].opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                    
                    Image(systemName: banner.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, options: .repeating)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(banner.title)
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.white)
                    
                    Text(banner.subtitle)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.9))
                }
                
                Spacer()
            }
            
            Text(banner.description)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(4)
                .lineLimit(3)
            
            HStack {
                Spacer()
                
                HStack(spacing: 6) {
                    Text("Start Now")
                        .font(.custom("OpenSans-Bold", size: 14))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(0.4), lineWidth: 1.5)
                        )
                )
            }
        }
        .padding(20)
        .background(
            ZStack {
                // Base gradient
                LinearGradient(
                    colors: banner.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Glass overlay
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.3)
                
                // Shimmer effect
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.2),
                        Color.white.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: shimmerPhase)
                .blur(radius: 30)
                
                // Radial highlight
                RadialGradient(
                    colors: [.white.opacity(0.1), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 200
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: banner.gradientColors[0].opacity(0.3), radius: 20, x: 0, y: 10)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }
}

struct PrayerToolCard: View {
    let tool: PrayerTool
    @State private var isExpanded = false
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(tool.color.opacity(0.15))
                            .frame(width: 56, height: 56)
                        
                        Image(systemName: tool.icon)
                            .font(.system(size: 24))
                            .foregroundStyle(tool.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tool.title)
                            .font(.custom("OpenSans-Bold", size: 17))
                            .foregroundStyle(.primary)
                        
                        Text(tool.subtitle)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                
                if isExpanded {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tool.description)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.primary)
                            .lineSpacing(4)
                        
                        if !tool.features.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(tool.features, id: \.self) { feature in
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(tool.color)
                                        
                                        Text(feature)
                                            .font(.custom("OpenSans-Regular", size: 13))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            .padding(.horizontal)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct PrayerTool: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let description: String
    let category: String
    let icon: String
    let color: Color
    let features: [String]
}

let prayerTools = [
    PrayerTool(
        title: "ACTS Prayer Model",
        subtitle: "Structured framework for prayer",
        description: "The ACTS model guides you through Adoration (praising God), Confession (acknowledging sins), Thanksgiving (expressing gratitude), and Supplication (making requests).",
        category: "Structured",
        icon: "list.bullet.rectangle",
        color: .blue,
        features: [
            "Clear prayer structure",
            "Balanced approach",
            "Easy to remember",
            "Biblical foundation"
        ]
    ),
    PrayerTool(
        title: "Scripture Prayers",
        subtitle: "Pray God's Word back to Him",
        description: "Transform Bible verses into personal prayers. Praying Scripture aligns your heart with God's will and strengthens your faith.",
        category: "Scripture",
        icon: "book.closed.fill",
        color: .indigo,
        features: [
            "Personalized verses",
            "Topical collections",
            "Daily Scripture focus",
            "Memorization help"
        ]
    ),
    PrayerTool(
        title: "Prayer Journal",
        subtitle: "Record your conversations with God",
        description: "Keep track of prayer requests, answers, and spiritual insights. Watch how God works over time.",
        category: "Structured",
        icon: "book.pages.fill",
        color: .green,
        features: [
            "Request tracking",
            "Answer celebration",
            "Growth reflection",
            "Private & secure"
        ]
    ),
    PrayerTool(
        title: "Intercessory Prayer Guide",
        subtitle: "Pray effectively for others",
        description: "Learn to stand in the gap for family, friends, church, and world. Includes prompts and Scripture to guide your intercession.",
        category: "Intercession",
        icon: "person.2.fill",
        color: .orange,
        features: [
            "Prayer lists",
            "Scripture backing",
            "Specific topics",
            "Reminder system"
        ]
    ),
    PrayerTool(
        title: "Gratitude Prayers",
        subtitle: "Cultivate a thankful heart",
        description: "Focus on God's blessings and faithfulness. Regular thanksgiving transforms your perspective and deepens joy.",
        category: "Thanksgiving",
        icon: "heart.fill",
        color: .pink,
        features: [
            "Daily gratitude prompts",
            "Blessing tracker",
            "Memory builder",
            "Share testimonies"
        ]
    ),
    PrayerTool(
        title: "Listening Prayer",
        subtitle: "Hear God's voice",
        description: "Practice stillness and attentiveness to God's Spirit. Learn to recognize how God speaks through Scripture, impressions, and peace.",
        category: "Structured",
        icon: "ear",
        color: .purple,
        features: [
            "Quiet time guides",
            "Discernment tools",
            "Reflection prompts",
            "Biblical examples"
        ]
    )
]

#Preview {
    PrayerToolkitView()
}
