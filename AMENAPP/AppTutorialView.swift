//
//  AppTutorialView.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//

import SwiftUI

/// Interactive tutorial showcasing app features after sign-up
/// Smart animations, tips, and walkthroughs using app's design system
struct AppTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    @State private var progress: CGFloat = 0
    @State private var showFeatureHighlight = false
    @State private var animateContent = false
    
    private let tutorialPages: [TutorialPage] = [
        // Page 1: Welcome & Overview
        TutorialPage(
            icon: "hands.sparkles",
            iconColor: Color(red: 0.6, green: 0.5, blue: 1.0),
            title: "Welcome to AMEN!",
            subtitle: "Where faith meets innovation",
            description: "Your new home for AI-powered Bible study, authentic community, and spiritual growth. Let's explore what makes AMEN special.",
            features: [
                Feature(icon: "book.pages.fill", title: "AI Bible Study", description: "Berean Assistant helps you understand Scripture"),
                Feature(icon: "person.3.fill", title: "Faith Community", description: "Connect with believers worldwide"),
                Feature(icon: "lightbulb.fill", title: "Share Ideas", description: "Inspire and be inspired")
            ],
            backgroundColor: Color(red: 0.96, green: 0.94, blue: 1.0),
            accentColor: Color(red: 0.6, green: 0.5, blue: 1.0),
            tipText: "Swipe left to continue your journey"
        ),
        
        // Page 2: #OPENTABLE - Ideas & Innovation
        TutorialPage(
            icon: "table.furniture.fill",
            iconColor: Color(red: 1.0, green: 0.7, blue: 0.4),
            title: "#OPENTABLE",
            subtitle: "Where AI meets faith, ideas meet innovation",
            description: "Share your God-inspired ideas, from tech innovations to ministry concepts. Get feedback, find collaborators, and build together.",
            features: [
                Feature(icon: "brain.head.profile", title: "AI & Faith", description: "Discuss tech ethics with biblical values"),
                Feature(icon: "briefcase.fill", title: "Faith-Based Business", description: "Build kingdom-focused startups"),
                Feature(icon: "lightbulb.fill", title: "Top Ideas", description: "See what's trending in the community")
            ],
            backgroundColor: Color(red: 1.0, green: 0.97, blue: 0.93),
            accentColor: Color(red: 1.0, green: 0.7, blue: 0.4),
            tipText: "Tap the pencil button to share your ideas"
        ),
        
        // Page 3: Berean AI Assistant
        TutorialPage(
            icon: "touchid",
            iconColor: Color(red: 0.4, green: 0.7, blue: 1.0),
            title: "Berean AI Assistant",
            subtitle: "Your personal Bible study companion",
            description: "Get instant help understanding Scripture, exploring biblical themes, and deepening your faith. Powered by AI, rooted in God's Word.",
            features: [
                Feature(icon: "book.fill", title: "Scripture Analysis", description: "Contextual, thematic, and linguistic insights"),
                Feature(icon: "text.book.closed.fill", title: "Study Plans", description: "Custom Bible study roadmaps"),
                Feature(icon: "brain.fill", title: "Memory Tools", description: "Learn and memorize Scripture")
            ],
            backgroundColor: Color(red: 0.93, green: 0.96, blue: 1.0),
            accentColor: Color(red: 0.4, green: 0.7, blue: 1.0),
            tipText: "Look for the fingerprint icon in the top-left"
        ),
        
        // Page 4: Community Features
        TutorialPage(
            icon: "person.3.fill",
            iconColor: Color(red: 0.4, green: 0.85, blue: 0.7),
            title: "Community",
            subtitle: "Connect, share, and grow together",
            description: "Engage with believers through testimonies, prayer requests, and meaningful discussions. Your faith journey is better together.",
            features: [
                Feature(icon: "hands.sparkles.fill", title: "Testimonies", description: "Share how God is working in your life"),
                Feature(icon: "heart.fill", title: "Prayer Requests", description: "Pray for and support others"),
                Feature(icon: "message.fill", title: "Direct Messages", description: "Build authentic relationships")
            ],
            backgroundColor: Color(red: 0.92, green: 0.99, blue: 0.96),
            accentColor: Color(red: 0.4, green: 0.85, blue: 0.7),
            tipText: "Use the bottom tabs to navigate the app"
        ),
        
        // Page 5: Resources & Growth
        TutorialPage(
            icon: "books.vertical.fill",
            iconColor: Color(red: 1.0, green: 0.6, blue: 0.7),
            title: "Resources",
            subtitle: "Tools for spiritual growth",
            description: "Access devotionals, study guides, podcasts, and more. Everything you need to deepen your walk with Christ.",
            features: [
                Feature(icon: "book.pages.fill", title: "Daily Devotionals", description: "Start each day with God's Word"),
                Feature(icon: "text.book.closed.fill", title: "Study Guides", description: "Deep dive into biblical topics"),
                Feature(icon: "headphones", title: "Podcasts", description: "Faith-based audio content")
            ],
            backgroundColor: Color(red: 1.0, green: 0.95, blue: 0.96),
            accentColor: Color(red: 1.0, green: 0.6, blue: 0.7),
            tipText: "Check out the Resources tab for more"
        ),
        
        // Page 6: Let's Begin!
        TutorialPage(
            icon: "checkmark.circle.fill",
            iconColor: Color(red: 0.3, green: 0.8, blue: 0.5),
            title: "You're All Set!",
            subtitle: "Ready to start your journey?",
            description: "Welcome to the AMEN community! We're excited to see how God will use you here. Remember, this is a space for growth, encouragement, and innovation.",
            features: [
                Feature(icon: "hand.thumbsup.fill", title: "Be Authentic", description: "Share your real faith journey"),
                Feature(icon: "heart.circle.fill", title: "Show Love", description: "Encourage and support others"),
                Feature(icon: "sparkles", title: "Stay Curious", description: "Ask questions and learn together")
            ],
            backgroundColor: Color(red: 0.92, green: 0.99, blue: 0.94),
            accentColor: Color(red: 0.3, green: 0.8, blue: 0.5),
            tipText: "Tap 'Get Started' to enter the app"
        )
    ]
    
    var body: some View {
        ZStack {
            // Background gradient that changes per page
            backgroundGradient
            
            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Text("Skip")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color(.systemBackground).opacity(0.7))
                            )
                    }
                }
                .padding()
                .opacity(currentPage == tutorialPages.count - 1 ? 0 : 1)
                
                // Main content
                TabView(selection: $currentPage) {
                    ForEach(0..<tutorialPages.count, id: \.self) { index in
                        TutorialPageView(page: tutorialPages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)
                
                // Bottom controls
                VStack(spacing: 20) {
                    // Page indicators
                    HStack(spacing: 8) {
                        ForEach(0..<tutorialPages.count, id: \.self) { index in
                            Capsule()
                                .fill(index == currentPage ? 
                                      tutorialPages[currentPage].accentColor : 
                                      Color.gray.opacity(0.3))
                                .frame(width: index == currentPage ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                        }
                    }
                    
                    // Action button
                    Button {
                        if currentPage == tutorialPages.count - 1 {
                            // Last page - finish tutorial
                            dismiss()
                        } else {
                            // Next page
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                currentPage += 1
                            }
                        }
                        
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                    } label: {
                        HStack(spacing: 8) {
                            Text(currentPage == tutorialPages.count - 1 ? "Get Started" : "Next")
                                .font(.custom("OpenSans-Bold", size: 16))
                            
                            Image(systemName: currentPage == tutorialPages.count - 1 ? "arrow.right.circle.fill" : "arrow.right")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            tutorialPages[currentPage].accentColor,
                                            tutorialPages[currentPage].accentColor.opacity(0.8)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: tutorialPages[currentPage].accentColor.opacity(0.3), radius: 12, y: 6)
                        )
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                }
            }
        }
        .onAppear {
            // Haptic welcome
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        }
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                tutorialPages[currentPage].backgroundColor,
                tutorialPages[currentPage].backgroundColor.opacity(0.6),
                Color(.systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: currentPage)
    }
}

// MARK: - Tutorial Page View

struct TutorialPageView: View {
    let page: TutorialPage
    @State private var animateIcon = false
    @State private var animateFeatures = false
    @State private var showTip = false
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                // Icon with glow effect
                ZStack {
                    // Pulsing glow
                    Circle()
                        .fill(page.accentColor.opacity(0.2))
                        .frame(width: 140, height: 140)
                        .blur(radius: 20)
                        .scaleEffect(animateIcon ? 1.2 : 1.0)
                        .opacity(animateIcon ? 0.3 : 0.6)
                    
                    // Icon background
                    Circle()
                        .fill(page.accentColor.opacity(0.15))
                        .frame(width: 120, height: 120)
                        .overlay(
                            Circle()
                                .stroke(page.accentColor.opacity(0.3), lineWidth: 2)
                        )
                    
                    // Icon
                    Image(systemName: page.icon)
                        .font(.system(size: 60, weight: .semibold))
                        .foregroundStyle(page.iconColor)
                        .symbolEffect(.bounce, value: animateIcon)
                }
                .scaleEffect(animateIcon ? 1.0 : 0.8)
                .opacity(animateIcon ? 1.0 : 0)
                
                // Title & Subtitle
                VStack(spacing: 8) {
                    Text(page.title)
                        .font(.custom("OpenSans-Bold", size: 32))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .opacity(animateIcon ? 1.0 : 0)
                        .offset(y: animateIcon ? 0 : 20)
                    
                    Text(page.subtitle)
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(page.accentColor)
                        .multilineTextAlignment(.center)
                        .opacity(animateIcon ? 1.0 : 0)
                        .offset(y: animateIcon ? 0 : 20)
                }
                .padding(.horizontal)
                
                // Description
                Text(page.description)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 40)
                    .opacity(animateIcon ? 1.0 : 0)
                    .offset(y: animateIcon ? 0 : 20)
                
                // Features
                VStack(spacing: 16) {
                    ForEach(Array(page.features.enumerated()), id: \.offset) { index, feature in
                        FeatureCard(feature: feature, accentColor: page.accentColor)
                            .opacity(animateFeatures ? 1.0 : 0)
                            .offset(y: animateFeatures ? 0 : 30)
                            .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(index) * 0.1), value: animateFeatures)
                    }
                }
                .padding(.horizontal, 24)
                
                // Tip
                if !page.tipText.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(page.accentColor)
                        
                        Text(page.tipText)
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(page.accentColor.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(page.accentColor.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)
                    .opacity(showTip ? 1.0 : 0)
                    .offset(y: showTip ? 0 : 20)
                }
                
                Spacer(minLength: 120)
            }
            .padding(.top, 40)
        }
        .onAppear {
            // Staggered animations
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animateIcon = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    animateFeatures = true
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    showTip = true
                }
            }
        }
    }
}

// MARK: - Feature Card

struct FeatureCard: View {
    let feature: Feature
    let accentColor: Color
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: feature.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.primary)
                
                Text(feature.description)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accentColor.opacity(0.2), lineWidth: 1)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Models

struct TutorialPage {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String
    let features: [Feature]
    let backgroundColor: Color
    let accentColor: Color
    let tipText: String
}

struct Feature {
    let icon: String
    let title: String
    let description: String
}

// MARK: - Preview

#Preview {
    AppTutorialView()
}
