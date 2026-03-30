//
//  SpotlightView.swift
//  AMENAPP
//
//  Spotlight: Intelligent content discovery with safe, meaningful recommendations
//  Design: Dark frosted glass, spatial animations, swipeable categories
//

import SwiftUI
import FirebaseAuth

struct SpotlightView: View {
    @StateObject private var viewModel = SpotlightViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedFilter: SpotlightFilter = .all
    @State private var isRefreshing = false
    
    var body: some View {
        ZStack(alignment: .top) {
            // Dark gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.12, blue: 0.15),
                    Color(red: 0.08, green: 0.08, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Navigation header with X button
                navigationHeader
                
                // Swipeable category filter chips
                categoryFilterBar
                    .padding(.bottom, 16)
                
                // Main content
                ScrollView {
                    VStack(spacing: 16) {
                        // Spotlight cards
                        if viewModel.isLoading && viewModel.spotlightPosts.isEmpty {
                            loadingState
                        } else if viewModel.spotlightPosts.isEmpty {
                            emptyState
                        } else {
                            postsGrid
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("scroll")).minY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
                .refreshable {
                    await refreshContent()
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await viewModel.loadSpotlight()
        }
        .onChange(of: selectedFilter) { oldValue, newValue in
            Task {
                await viewModel.filterByCategory(newValue)
            }
        }
    }
    
    // MARK: - Header Components
    
    private var navigationHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Spotlight")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Curated for you")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.6), .white.opacity(0.15))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 20)
    }
    
    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SpotlightFilter.allCases) { filter in
                    SpotlightCategoryChip(
                        title: filter.title,
                        icon: filter.icon,
                        isSelected: selectedFilter == filter,
                        action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedFilter = filter
                            }
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Content Grid
    
    private var postsGrid: some View {
        LazyVStack(spacing: 16) {
            ForEach(Array(viewModel.spotlightPosts.enumerated()), id: \.element.id) { index, post in
                SpotlightCard(
                    post: post,
                    explanation: viewModel.getExplanation(for: post)
                )
                .transition(.opacity.combined(with: .offset(y: 10)))
                .animation(
                    .spring(response: 0.4, dampingFraction: 0.8)
                        .delay(Double(index % 10) * 0.03),
                    value: viewModel.spotlightPosts.count
                )
            }
            
            // "You're all caught up" end state
            if !viewModel.hasMoreContent {
                caughtUpMessage
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 100)
    }
    
    // MARK: - States
    
    private var loadingState: some View {
        VStack(spacing: 20) {
            ForEach(0..<3) { _ in
                SpotlightCardSkeleton()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.circle")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 80)
            
            Text("No Spotlight content yet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            
            Text("Check back soon for meaningful posts from your community")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    private var caughtUpMessage: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.8))
            
            Text("You're all caught up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
            
            Text("Check back later for more")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Helper Properties
    
    private var headerOpacity: Double {
        let threshold: CGFloat = 50
        if scrollOffset > 0 {
            return 1.0
        } else if scrollOffset < -threshold {
            return 0.0
        } else {
            return 1.0 + (scrollOffset / threshold)
        }
    }
    
    private var headerOffset: CGFloat {
        scrollOffset > 0 ? 0 : min(scrollOffset / 2, 0)
    }
    
    // MARK: - Actions
    
    private func refreshContent() async {
        isRefreshing = true
        await viewModel.refreshSpotlight()
        isRefreshing = false
    }
}

// MARK: - Spotlight Filter Enum

enum SpotlightFilter: String, CaseIterable, Identifiable {
    case all = "all"
    case prayer = "prayer"
    case testimonies = "testimonies"
    case discussions = "openTable"
    case local = "local"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .all: return "For You"
        case .prayer: return "Prayer"
        case .testimonies: return "Testimonies"
        case .discussions: return "Discussions"
        case .local: return "Local"
        }
    }
    
    var icon: String {
        switch self {
        case .all: return "sparkles"
        case .prayer: return "hands.sparkles.fill"
        case .testimonies: return "star.bubble.fill"
        case .discussions: return "bubble.left.and.bubble.right.fill"
        case .local: return "location.fill"
        }
    }
}

// MARK: - Loading Skeleton

struct SpotlightCardSkeleton: View {
    @State private var shimmerOffset: CGFloat = -1
    @State private var cardWidth: CGFloat = 390  // reasonable default

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author header
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 120, height: 12)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 80, height: 10)
                }
                
                Spacer()
            }
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 14)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 14)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 200, height: 14)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.08))
                )
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
        .mask(
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            .white,
                            .white,
                            .white,
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .offset(x: shimmerOffset * cardWidth)
        )
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { cardWidth = geo.size.width }
            }
        )
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 1
            }
        }
    }
}

// MARK: - Category Chip Component

struct SpotlightCategoryChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    if isSelected {
                        // Selected: Frosted glass with gradient
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.25),
                                                Color.white.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    } else {
                        // Unselected: Subtle frosted glass
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    }
                }
            )
            .scaleEffect(isSelected ? 1.0 : 0.95)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(SpotlightCategoryChipButtonStyle())
    }
}

struct SpotlightCategoryChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    SpotlightView()
}
