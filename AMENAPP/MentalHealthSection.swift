//
//  MentalHealthSection.swift
//  AMENAPP
//
//  Created by Steph on 2/2/26.
//

import SwiftUI

// MARK: - Mental Health & Wellness Section
struct MentalHealthSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "heart.circle.fill")
                    .foregroundStyle(.green)
                    .symbolEffect(.pulse, options: .repeating.speed(0.7))
                Text("Mental Health & Wellness")
                    .font(.custom("OpenSans-Bold", size: 20))
            }
            .padding(.horizontal)
            
            // Featured: Faith-Based Counseling
            MentalHealthFeaturedCard(
                icon: "person.2.badge.gearshape.fill",
                iconColor: .green,
                title: "Faith-Based Counseling",
                subtitle: "Find Christian therapists & counselors",
                description: "Connect with licensed professionals who integrate faith into mental health care.",
                actionTitle: "Find a Counselor",
                gradientColors: [Color.green, Color.teal]
            )
            
            // Mental Health Resources
            MentalHealthResourceCard(
                icon: "brain.head.profile",
                iconColor: .purple,
                title: "Understanding Mental Health",
                description: "Biblical perspective on anxiety, depression, and emotional wellness",
                category: "Learning"
            )
            
            MentalHealthResourceCard(
                icon: "leaf.fill",
                iconColor: .green,
                title: "Stress & Anxiety Relief",
                description: "Practical tools and prayers for managing stress",
                category: "Tools"
            )
            
            MentalHealthResourceCard(
                icon: "bed.double.fill",
                iconColor: .indigo,
                title: "Sleep & Rest",
                description: "Biblical guidance on rest and healthy sleep habits",
                category: "Wellness"
            )
            
            MentalHealthResourceCard(
                icon: "figure.walk",
                iconColor: .orange,
                title: "Physical & Spiritual Health",
                description: "Caring for your body as a temple of the Holy Spirit",
                category: "Wellness"
            )
            
            MentalHealthResourceCard(
                icon: "book.closed.fill",
                iconColor: .blue,
                title: "Mental Health Devotionals",
                description: "Daily encouragement for emotional and spiritual health",
                category: "Reading"
            )
            
            // Support Groups
            SupportGroupCard()
        }
    }
}

// MARK: - Mental Health Featured Card
struct MentalHealthFeaturedCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String
    let actionTitle: String
    let gradientColors: [Color]
    
    @State private var shimmerPhase: CGFloat = 0
    @State private var showComingSoon = false
    
    var body: some View {
        Button {
            showComingSoon = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 52, height: 52)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [iconColor.opacity(0.6), iconColor.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                        
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.custom("OpenSans-Bold", size: 17))
                            .foregroundStyle(.white)
                        
                        Text(subtitle)
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    
                    Spacer()
                }
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineSpacing(3)
                
                HStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Text(actionTitle)
                            .font(.custom("OpenSans-Bold", size: 14))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(0.4), lineWidth: 1.5)
                        )
                )
            }
            .padding(18)
            .background(
                ZStack {
                    // Base gradient
                    LinearGradient(
                        colors: gradientColors,
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
                    .blur(radius: 25)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: gradientColors[0].opacity(0.3), radius: 16, x: 0, y: 8)
            .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
            .padding(.horizontal)
            .onAppear {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    shimmerPhase = 400
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showComingSoon) {
            ResourceComingSoonPlaceholder(
                title: "Faith-Based Counseling",
                icon: "person.2.badge.gearshape.fill",
                iconColor: .green,
                description: "Connect with licensed Christian counselors and therapists who integrate biblical principles into mental health care. Find the right professional to support your journey to wellness."
            )
        }
    }
}

// MARK: - Mental Health Resource Card
struct MentalHealthResourceCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let category: String
    
    @State private var showComingSoon = false
    
    var body: some View {
        Button {
            showComingSoon = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundStyle(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Text(description)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    Text(category)
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(iconColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(iconColor.opacity(0.1))
                        )
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
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
        .sheet(isPresented: $showComingSoon) {
            ResourceComingSoonPlaceholder(
                title: title,
                icon: icon,
                iconColor: iconColor,
                description: description
            )
        }
    }
}

// MARK: - Support Group Card
struct SupportGroupCard: View {
    @State private var showComingSoon = false
    
    var body: some View {
        Button {
            showComingSoon = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.cyan)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Support Groups")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.primary)
                        
                        Text("COMING SOON")
                            .font(.custom("OpenSans-Bold", size: 9))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.orange)
                            )
                    }
                    
                    Text("Join faith-based support groups for mental health")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.cyan.opacity(0.3), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            .padding(.horizontal)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showComingSoon) {
            ResourceComingSoonPlaceholder(
                title: "Support Groups",
                icon: "person.3.fill",
                iconColor: .cyan,
                description: "Connect with others facing similar challenges in faith-based support groups. Share experiences, find encouragement, and grow together in a safe, supportive environment."
            )
        }
    }
}

#Preview {
    ScrollView {
        MentalHealthSection()
    }
}
