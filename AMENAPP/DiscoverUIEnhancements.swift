// DiscoverUIEnhancements.swift
// AMENAPP
//
// Visual/UI enhancements for Discover/Search screen
// Premium iOS polish with unified scroll, subtle glass effects, and ambient blue accents
// NO LOGIC CHANGES - only visual presentation improvements

import SwiftUI

// MARK: - Enhanced Search Bar

struct EnhancedSearchBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let placeholder: String
    let onSubmit: () -> Void
    let onClear: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerPhase: CGFloat = 0
    private let borderColor: Color = Color.white.opacity(0.35)
    
    var body: some View {
        HStack(spacing: 10) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .font(.systemScaled(15, weight: .medium))
                .foregroundStyle(.secondary)
            
            // Text field
            TextField(placeholder, text: $text)
                .font(AMENFont.regular(16))
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit(onSubmit)
            
            // Clear button
            if !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            ZStack {
                // Base glass layer
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.88))
                
                // Soft border
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.5)
                
                // Subtle shimmer sweep
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.15),
                                Color.white.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .mask(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .offset(x: shimmerPhase)
                    .opacity(isFocused ? 0.5 : 0.25)
                
                // Active blue accent glow
                if isFocused {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                        .blur(radius: 4)
                }
            }
        )
        .shadow(color: Color.black.opacity(isFocused ? 0.08 : 0.04), radius: isFocused ? 8 : 4, y: isFocused ? 4 : 2)
        .scaleEffect(isFocused ? 1.005 : 1.0)
        .animation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.72)), value: isFocused)
        .onAppear {
            withAnimation(reduceMotion ? nil : .linear(duration: 3.5).repeatForever(autoreverses: false)) {
                shimmerPhase = 400
            }
        }
    }
}

// MARK: - Enhanced Filter Pill

struct EnhancedFilterPill: View {
    let title: String
    let systemImage: String?
    let isActive: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            HapticManager.impact(style: .light)
            action()
        }) {
            HStack(spacing: 6) {
                if let icon = systemImage {
                    Image(systemName: icon)
                        .font(.systemScaled(11, weight: .medium))
                }
                Text(title)
                    .font(.systemScaled(13, weight: isActive ? .semibold : .medium))
            }
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    // Base layer
                    Capsule()
                        .fill(isActive ? Color.primary.opacity(0.08) : Color.clear)
                    
                    // Active state with subtle blue glow
                    if isActive {
                        Capsule()
                            .fill(Color.blue.opacity(0.03))
                        
                        Capsule()
                            .strokeBorder(Color.blue.opacity(0.12), lineWidth: 1)
                            .blur(radius: 1)
                    } else {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
                }
            )
            .shadow(
                color: isActive ? Color.blue.opacity(0.15) : Color.black.opacity(0.02),
                radius: isActive ? 4 : 2,
                y: isActive ? 2 : 1
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Enhanced Topic Pills Row

struct EnhancedTopicPillsRow: View {
    let topics: [DiscoverPillItem]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(topics.indices, id: \.self) { index in
                    EnhancedFilterPill(
                        title: topics[index].title,
                        systemImage: topics[index].systemImage,
                        isActive: topics[index].isActive,
                        action: topics[index].action
                    )
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity).animation(
                                Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))
                                    .delay(Double(index) * 0.03)
                            ),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        )
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Unified Scroll Container with Soft Top Blur

struct DiscoverScrollContainer<Content: View>: View {
    let content: Content
    
    @State private var scrollOffset: CGFloat = 0
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Main scroll content
            ScrollView {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("scroll")).minY)
                }
                .frame(height: 0)
                
                content
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                scrollOffset = value
            }
            
            // Soft feathered top blur - blends naturally into background
            if scrollOffset < -5 {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            Color(.systemBackground).opacity(0.95),
                            Color(.systemBackground).opacity(0.7),
                            Color(.systemBackground).opacity(0.3),
                            Color(.systemBackground).opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)
                    .allowsHitTesting(false)
                    
                    Spacer()
                }
                .ignoresSafeArea(edges: .top)
                .opacity(min(abs(scrollOffset) / CGFloat(50), CGFloat(1)))
            }
        }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Enhanced Card with Entrance Animation

struct EnhancedCardContainer<Content: View>: View {
    let content: Content
    let delay: Double
    
    @State private var appeared = false
    
    init(delay: Double = 0, @ViewBuilder content: () -> Content) {
        self.delay = delay
        self.content = content()
    }
    
    var body: some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .onAppear {
                withAnimation(
                    Motion.adaptive(.spring(response: 0.45, dampingFraction: 0.78))
                        .delay(delay)
                ) {
                    appeared = true
                }
            }
    }
}

// MARK: - Enhanced Scope Tab Bar

struct EnhancedSearchScopeTabBar: View {
    @Binding var selected: SearchScope
    @Namespace private var ns
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SearchScope.allCases, id: \.self) { scope in
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.72))) {
                            selected = scope
                        }
                        HapticManager.impact(style: .light)
                    } label: {
                        Text(scope.rawValue)
                            .font(.systemScaled(14, weight: selected == scope ? .semibold : .regular))
                            .foregroundStyle(selected == scope ? Color.primary : Color.secondary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 9)
                            .background(
                                ZStack {
                                    if selected == scope {
                                        // Active state with subtle lift
                                        Capsule()
                                            .fill(Color.primary.opacity(0.08))
                                            .matchedGeometryEffect(id: "scope_bg", in: ns)
                                        
                                        // Subtle blue accent
                                        Capsule()
                                            .fill(Color.blue.opacity(0.04))
                                        
                                        Capsule()
                                            .strokeBorder(Color.blue.opacity(0.15), lineWidth: 1)
                                            .blur(radius: 1)
                                    }
                                }
                            )
                            .shadow(
                                color: selected == scope ? Color.blue.opacity(0.12) : .clear,
                                radius: selected == scope ? 4 : 0,
                                y: selected == scope ? 2 : 0
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Enhanced Profile Card with Ambient Glow

struct EnhancedProfileCard: View {
    let person: DiscoveryPerson
    let previewPosts: [DiscoveryPost]
    let onFollow: () -> Void
    let onTapProfile: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFollowing: Bool
    @State private var appeared = false
    @State private var glowPhase: CGFloat = 0
    private let cardBackground: Color = Color(.secondarySystemBackground).opacity(0.5)
    private let borderColor: Color = Color.primary.opacity(0.06)
    
    init(person: DiscoveryPerson, previewPosts: [DiscoveryPost], onFollow: @escaping () -> Void, onTapProfile: @escaping () -> Void) {
        self.person = person
        self.previewPosts = previewPosts
        self.onFollow = onFollow
        self.onTapProfile = onTapProfile
        _isFollowing = State(initialValue: person.isFollowing)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Profile info row
            Button(action: onTapProfile) {
                HStack(spacing: 12) {
                    // Avatar with subtle glow
                    ZStack {
                        // Ambient blue glow
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .blur(radius: 12)
                            .scaleEffect(1.3)
                            .opacity(0.6 + 0.4 * sin(Double(glowPhase)))
                        
                        Group {
                            if let urlStr = person.avatarURL, let url = URL(string: urlStr) {
                                CachedAsyncImage(url: url) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    Circle().fill(Color(.systemGray5))
                                }
                            } else {
                                Circle().fill(Color(.systemGray5))
                                    .overlay(
                                        Text(String(person.displayName.prefix(1)))
                                            .font(.systemScaled(18, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    )
                            }
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                        )
                    }
                    
                    // Name + stats
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(person.username)
                                .font(.systemScaled(15, weight: .semibold))
                                .foregroundStyle(Color.primary)
                            if person.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.systemScaled(13))
                                    .foregroundStyle(.blue)
                            }
                        }
                        Text(person.displayName + " · " + formatFollowers(person.followerCount))
                            .font(.systemScaled(13))
                            .foregroundStyle(Color.secondary)
                    }
                    
                    Spacer()
                    
                    // Enhanced follow button
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.68))) {
                            isFollowing.toggle()
                        }
                        HapticManager.impact(style: .light)
                        onFollow()
                    } label: {
                        Text(isFollowing ? "Following" : "Follow")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(isFollowing ? Color.primary : .white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(isFollowing ? Color(.systemGray5) : Color.primary)
                                    
                                    if !isFollowing {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(Color.blue.opacity(0.15))
                                    }
                                }
                            )
                            .shadow(
                                color: isFollowing ? .clear : Color.blue.opacity(0.25),
                                radius: isFollowing ? 0 : 6,
                                y: isFollowing ? 0 : 3
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            
            // 3-column media preview
            let imagePosts = previewPosts.filter { $0.imageURL != nil }.prefix(3)
            if !imagePosts.isEmpty {
                HStack(spacing: 1) {
                    ForEach(Array(imagePosts)) { post in
                        if let urlStr = post.imageURL, let url = URL(string: urlStr) {
                            CachedAsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(Color(.systemGray6))
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                        }
                    }
                }
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
        .padding(.horizontal, 16)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 15)
        .scaleEffect(appeared ? 1 : 0.96)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.78)).delay(0.08)) {
                appeared = true
            }
            withAnimation(reduceMotion ? nil : .linear(duration: 4).repeatForever(autoreverses: true)) {
                glowPhase = .pi * 2
            }
        }
    }

    private func formatFollowers(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM followers", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK followers", Double(n) / 1_000) }
        return "\(n) followers"
    }
}

// MARK: - Enhanced AI Answer Card

struct EnhancedAIAnswerCard: View {
    let query: String
    let answer: String
    let isLoading: Bool
    let onAskMore: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var pulsePhase: CGFloat = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with ambient glow
            HStack(spacing: 8) {
                ZStack {
                    // Subtle blue pulse
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.15))
                        .blur(radius: 6)
                        .scaleEffect(1 + 0.1 * sin(pulsePhase))
                    
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.systemScaled(12, weight: .semibold))
                                .foregroundStyle(Color(.systemBackground))
                        )
                }
                .frame(width: 28, height: 28)
                
                Text("Berean AI")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                
                Spacer()
            }
            
            if isLoading {
                // Animated typing dots
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.blue.opacity(0.5))
                            .frame(width: 7, height: 7)
                            .scaleEffect(isLoading ? 1.0 : 0.6)
                            .animation(
                                reduceMotion ? .none : .easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(i) * 0.15),
                                value: isLoading
                            )
                    }
                }
                .padding(.vertical, 6)
            } else if !answer.isEmpty {
                Text(answer)
                    .font(.systemScaled(14, weight: .regular))
                    .foregroundStyle(Color.secondary)
                    .lineSpacing(4)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                
                Button(action: onAskMore) {
                    HStack(spacing: 6) {
                        Text("Ask Berean more about this")
                            .font(.systemScaled(13, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.systemScaled(11))
                    }
                    .foregroundStyle(Color.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground).opacity(0.6))
                
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.blue.opacity(0.02))
                
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.blue.opacity(0.1), lineWidth: 1)
            }
        )
        .shadow(color: Color.blue.opacity(0.08), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.42, dampingFraction: 0.76)).delay(0.12)) {
                appeared = true
            }
            withAnimation(reduceMotion ? nil : .linear(duration: 2.5).repeatForever(autoreverses: true)) {
                pulsePhase = .pi * 2
            }
        }
    }
}

// MARK: - Grid Card with Soft Entrance

struct EnhancedGridCard<Content: View>: View {
    let index: Int
    let content: Content
    
    @State private var appeared = false
    
    init(index: Int, @ViewBuilder content: () -> Content) {
        self.index = index
        self.content = content()
    }
    
    var body: some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
            .scaleEffect(appeared ? 1 : 0.96)
            .onAppear {
                withAnimation(
                    Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.76))
                        .delay(Double(index % 6) * 0.04)
                ) {
                    appeared = true
                }
            }
    }
}
