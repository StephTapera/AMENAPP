import SwiftUI
struct CategoryPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            HapticManager.impact(style: .light)
            action()
        }) {
            Text(title)
                .font(.custom(isSelected ? "OpenSans-Bold" : "OpenSans-SemiBold", size: adaptiveFontSize))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, adaptivePadding)
                .padding(.vertical, adaptiveVerticalPadding)
                .lineLimit(1)
                .background(glassmorphicBackground)
                .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeIn(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
    
    // MARK: - Glassmorphic Background
    
    @ViewBuilder
    private var glassmorphicBackground: some View {
        ZStack {
            if isSelected {
                selectedGlassBackground
            } else {
                unselectedGlassBackground
            }
        }
    }
    
    // Selected state: Frosted glass with inner glow, rim light, and shadow
    private var selectedGlassBackground: some View {
        ZStack {
            // Base frosted glass layer
            Capsule()
                .fill(.ultraThinMaterial)
            
            // Stronger inner glow effect (white from top) - MORE VISIBLE
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.6),
                            Color.white.opacity(0.25),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Enhanced rim light (more prominent highlight on edges)
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.8),
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
            
            // Stronger outer border (black/gray) - MORE VISIBLE
            Capsule()
                .strokeBorder(
                    Color.black.opacity(0.35),
                    lineWidth: 1.5
                )
                .padding(0.5)
        }
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        .shadow(color: .white.opacity(0.2), radius: 6, x: 0, y: -2)
    }
    
    // Unselected state: Subtle glass with minimal styling
    private var unselectedGlassBackground: some View {
        ZStack {
            // Base frosted glass layer (more transparent)
            Capsule()
                .fill(.ultraThinMaterial.opacity(0.5))
            
            // Very subtle gradient
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Subtle border
            Capsule()
                .strokeBorder(
                    Color.black.opacity(0.1),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Adaptive Sizing (Smaller)
    
    private var adaptiveFontSize: CGFloat {
        // Reduced font size for smaller pills
        switch horizontalSizeClass {
        case .compact:
            return 12  // Smaller on iPhone portrait
        default:
            return 13  // Smaller on iPad/landscape
        }
    }
    
    private var adaptivePadding: CGFloat {
        // Reduced horizontal padding for compact design
        switch horizontalSizeClass {
        case .compact:
            return 12
        default:
            return 14
        }
    }
    
    private var adaptiveVerticalPadding: CGFloat {
        // Reduced vertical padding for smaller pills
        return 8
    }
}

struct CommunityCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let backgroundColor: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon)
                    .font(.systemScaled(20))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text(title)
                    .font(AMENFont.bold(13))
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.black.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 100)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.easeIn(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Smart Community Card (Compact Liquid Glass Design)

struct SmartCommunityCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let backgroundColor: Color
    let accentColor: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            HapticManager.impact(style: .light)
            action()
        }) {
            HStack(spacing: 10) {
                // Compact icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .symbolEffect(.bounce, value: isPressed)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AMENFont.bold(13))
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(AMENFont.regular(10))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.systemScaled(10, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    // Liquid Glass effect
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                    
                    // Subtle tint overlay
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    iconColor.opacity(0.08),
                                    iconColor.opacity(0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Border
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: iconColor.opacity(0.1), radius: 8, y: 2)
            .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.smooth(duration: 0.2)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

struct TrendingCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let backgroundColor: Color
    
    @State private var isPressed = false
    @State private var showDetails = false
    
    var body: some View {
        Button {
            showDetails = true
            HapticManager.impact(style: .light)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.systemScaled(24))
                    .foregroundStyle(.primary)
                    .frame(height: 40)
                
                Text(title)
                    .font(AMENFont.bold(12))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 100, height: 100)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.94 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.easeIn(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
        .sheet(isPresented: $showDetails) {
            TrendingTopicDetailView(title: title, icon: icon)
        }
    }
}

// MARK: - Trending Topic Detail View

struct TrendingTopicDetailView: View {
    @Environment(\.dismiss) var dismiss
    let title: String
    let icon: String

    @State private var showJoinDiscussion = false
    @State private var isFollowingTopic = false
    @State private var selectedResource: (String, String)? = nil
    
    // Mock data based on topic
    private var topicContent: (description: String, stats: [(String, String)], relatedTopics: [String], resources: [(String, String)]) {
        switch title {
        case "AI & Faith":
            return (
                "Explore how artificial intelligence intersects with Christian faith, ethics, and ministry. Join discussions on using AI responsibly while maintaining biblical values.",
                [
                    ("Active Discussions", "234"),
                    ("Community Members", "1.2K"),
                    ("Resources Shared", "89")
                ],
                ["Tech Ethics", "Digital Ministry", "AI in Bible Study", "Church Innovation"],
                [
                    ("AI Ethics Framework", "Christian guide to AI"),
                    ("Faith & Technology Podcast", "Weekly discussions"),
                    ("AI Ministry Tools", "Practical applications")
                ]
            )
        case "Tech Ethics":
            return (
                "Navigate the ethical implications of technology through a Christian worldview. Discuss privacy, digital rights, and moral responsibility in the tech age.",
                [
                    ("Active Topics", "156"),
                    ("Members", "890"),
                    ("Weekly Posts", "67")
                ],
                ["Data Privacy", "Social Media Ethics", "Digital Stewardship", "Tech Responsibility"],
                [
                    ("Christian Tech Ethics Guide", "Comprehensive resource"),
                    ("Digital Boundaries", "Setting healthy limits"),
                    ("Tech Sabbath Ideas", "Unplug with purpose")
                ]
            )
        case "Startups":
            return (
                "Connect with Christian entrepreneurs building faith-driven businesses. Share ideas, get feedback, and find co-founders who share your values.",
                [
                    ("Active Startups", "78"),
                    ("Founders", "234"),
                    ("Success Stories", "45")
                ],
                ["Faith-Based Business", "Kingdom Entrepreneurship", "Startup Funding", "Mission-Driven Companies"],
                [
                    ("Startup Prayer Group", "Weekly support"),
                    ("Christian Investor Network", "Faith-based funding"),
                    ("Business with Purpose", "Course & mentorship")
                ]
            )
        case "Scripture":
            return (
                "Deep dive into God's Word with community-driven Bible study. Share insights, ask questions, and grow together in understanding.",
                [
                    ("Daily Readers", "567"),
                    ("Study Groups", "89"),
                    ("Verses Discussed", "1.5K")
                ],
                ["Bible Study Methods", "Hermeneutics", "Original Languages", "Devotional Reading"],
                [
                    ("Daily Reading Plan", "1-year Bible plan"),
                    ("Study Tools", "Concordance & lexicons"),
                    ("Verse Memorization", "Scripture memory app")
                ]
            )
        default:
            return (
                "Explore this topic with the community. Share insights, ask questions, and learn together in faith.",
                [
                    ("Active Members", "100+"),
                    ("Discussions", "50+"),
                    ("Resources", "25+")
                ],
                ["Related Topics"],
                [("Community Resources", "Learn more")]
            )
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.05))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: icon)
                                .font(.systemScaled(40))
                                .foregroundStyle(.primary)
                        }
                        
                        Text(title)
                            .font(AMENFont.bold(28))
                            .foregroundStyle(.primary)
                        
                        Text(topicContent.description)
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.black.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    
                    // Stats
                    HStack(spacing: 12) {
                        ForEach(topicContent.stats, id: \.0) { stat in
                            VStack(spacing: 6) {
                                Text(stat.1)
                                    .font(AMENFont.bold(22))
                                    .foregroundStyle(.primary)
                                
                                Text(stat.0)
                                    .font(AMENFont.regular(12))
                                    .foregroundStyle(.black.opacity(0.6))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.white)
                                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showJoinDiscussion = true
                            NotificationCenter.default.post(
                                name: Notification.Name("amenOpenDiscussion"),
                                object: nil,
                                userInfo: ["discussionId": title, "topic": title]
                            )
                        } label: {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                Text("Join Discussion")
                                    .font(AMENFont.bold(16))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.black)
                            .cornerRadius(14)
                        }
                        
                        HStack(spacing: 12) {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation { isFollowingTopic.toggle() }
                                NotificationCenter.default.post(
                                    name: Notification.Name("amenFollowTopic"),
                                    object: nil,
                                    userInfo: [
                                        "topic": title,
                                        "isFollowing": !isFollowingTopic
                                    ]
                                )
                            } label: {
                                HStack {
                                    Image(systemName: isFollowingTopic ? "bell.slash.fill" : "bell.fill")
                                    Text(isFollowingTopic ? "Following" : "Follow")
                                        .font(AMENFont.bold(14))
                                }
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.white)
                                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.black.opacity(0.15), lineWidth: 1)
                                )
                            }
                            
                            ShareLink(item: "Check out the \(title) discussion on Amen!") {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share")
                                        .font(AMENFont.bold(14))
                                }
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.white)
                                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.black.opacity(0.15), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Related Topics
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Related Topics")
                            .font(AMENFont.bold(18))
                            .foregroundStyle(.primary)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(topicContent.relatedTopics, id: \.self) { topic in
                                    Text(topic)
                                        .font(AMENFont.semiBold(13))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(.white)
                                                .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                                        )
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Resources
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Helpful Resources")
                            .font(AMENFont.bold(18))
                            .foregroundStyle(.primary)
                            .padding(.horizontal)
                        
                        VStack(spacing: 10) {
                            ForEach(topicContent.resources, id: \.0) { resource in
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    selectedResource = resource
                                    NotificationCenter.default.post(
                                        name: Notification.Name("amenOpenResource"),
                                        object: nil,
                                        userInfo: [
                                            "resourceId": resource.0,
                                            "topic": title
                                        ]
                                    )
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(resource.0)
                                                .font(AMENFont.bold(14))
                                                .foregroundStyle(.primary)
                                            
                                            Text(resource.1)
                                                .font(AMENFont.regular(12))
                                                .foregroundStyle(.black.opacity(0.6))
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.systemScaled(12, weight: .semibold))
                                            .foregroundStyle(.black.opacity(0.3))
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.white)
                                            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 24)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(28))
                            .foregroundStyle(.black.opacity(0.3))
                    }
                }
            }
            .sheet(isPresented: $showJoinDiscussion) {
                NavigationStack {
                    VStack(spacing: 16) {
                        Text("Discussions for \(title)")
                            .font(AMENFont.bold(20))
                            .padding(.top, 24)
                        Text("Discussion threads will appear here.")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showJoinDiscussion = false }
                        }
                    }
                }
            }
            .sheet(item: Binding(
                get: { selectedResource.map { IdentifiableResource(name: $0.0, description: $0.1) } },
                set: { _ in selectedResource = nil }
            )) { res in
                NavigationStack {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(res.name)
                            .font(AMENFont.bold(20))
                            .padding(.top, 24)
                        Text(res.description)
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { selectedResource = nil }
                        }
                    }
                }
            }
        }
    }
}

private struct IdentifiableResource: Identifiable {
    let id = UUID()
    let name: String
    let description: String
}

// Old PostCard removed - now using the enhanced version from PostCard.swift

// MARK: - Reaction Button Component

struct ReactionButton: View {
    let icon: String
    let count: Int?
    let isActive: Bool
    let activeColor: Color
    let namespace: Namespace.ID
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(isActive ? .black : .black.opacity(0.5))
                
                if let count = count {
                    Text("\(count)")
                        .font(AMENFont.semiBold(11))
                        .foregroundStyle(isActive ? .black : .black.opacity(0.5))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? Color.white : Color.black.opacity(0.05))
                    .shadow(color: isActive ? .black.opacity(0.15) : .clear, radius: 8, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? Color.black.opacity(0.2) : Color.black.opacity(0.1), lineWidth: isActive ? 1.5 : 1)
            )
            .scaleEffect(isPressed ? 0.92 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.easeIn(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Format Button Component

struct FormatButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(isActive ? .white : .primary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(isActive ? Color.blue : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
