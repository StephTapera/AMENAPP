//
//  MentalHealthDetailView.swift
//  AMENAPP
//
//  Created by Steph on 2/2/26.
//

import SwiftUI

struct MentalHealthDetailView: View {
    @State private var selectedCategory: MentalHealthCategory = .all
    
    enum MentalHealthCategory: String, CaseIterable {
        case all = "All"
        case counseling = "Counseling"
        case resources = "Resources"
        case meditation = "Meditation"
        case support = "Support"
    }
    
    var filteredResources: [MentalHealthResource] {
        guard selectedCategory != .all else {
            return MentalHealthResource.allResources
        }
        return MentalHealthResource.allResources.filter { $0.category == selectedCategory }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Hero Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(.green.opacity(0.15))
                                .frame(width: 64, height: 64)
                            
                            Image(systemName: "heart.text.square.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.green)
                                .symbolEffect(.pulse, options: .repeating.speed(0.8))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mental Health")
                                .font(.custom("OpenSans-Bold", size: 28))
                                .foregroundStyle(.primary)
                            
                            Text("Faith-based wellness support")
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text("Caring for your mental health is caring for the temple God gave you. Find resources, support, and guidance on your wellness journey.")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }
                .padding(.horizontal)
                .padding(.top)
                
                // Scripture Encouragement
                scriptureCard
                
                // Category Filter
                categoryPicker
                
                // Resources Grid
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(filteredResources) { resource in
                        MentalHealthResourceCard(resource: resource)
                    }
                }
                .padding(.horizontal)
                
                // Self-Care Tips
                selfCareTipsSection
                
                // Prayer Section
                prayerSection
                
                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
        .navigationTitle("Mental Health")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var scriptureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "book.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)
                
                Text("Scripture for Wellness")
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.primary)
            }
            
            Text("\"Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God. And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus.\"")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.primary)
                .italic()
                .lineSpacing(4)
            
            Text("— Philippians 4:6-7")
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.blue.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.blue.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }
    
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MentalHealthCategory.allCases, id: \.self) { category in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedCategory = category
                        }
                        
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        Text(category.rawValue)
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(selectedCategory == category ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedCategory == category ? Color.green : Color(.systemGray6))
                            )
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var selfCareTipsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Self-Care Practices")
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.primary)
                .padding(.horizontal)
            
            VStack(spacing: 10) {
                SelfCareTipCard(
                    icon: "heart.fill",
                    title: "Rest & Sleep",
                    description: "Prioritize 7-9 hours of quality sleep each night",
                    color: .pink
                )
                
                SelfCareTipCard(
                    icon: "figure.walk",
                    title: "Physical Activity",
                    description: "Regular exercise boosts mood and reduces stress",
                    color: .orange
                )
                
                SelfCareTipCard(
                    icon: "fork.knife",
                    title: "Healthy Nutrition",
                    description: "Nourish your body with wholesome foods",
                    color: .green
                )
                
                SelfCareTipCard(
                    icon: "person.2.fill",
                    title: "Social Connection",
                    description: "Stay connected with loved ones and community",
                    color: .blue
                )
                
                SelfCareTipCard(
                    icon: "book.fill",
                    title: "Limit News Intake",
                    description: "Take breaks from constant information streams",
                    color: .purple
                )
            }
            .padding(.horizontal)
        }
    }
    
    private var prayerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hands.sparkles.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.purple)
                
                Text("Prayer for Peace")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
            }
            
            Text("Lord, grant me peace in times of anxiety. Help me to cast my worries upon You, knowing that You care for me. Fill my mind with Your truth and my heart with Your love. Guide me toward healing and wholeness. Amen.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.purple.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.purple.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }
}

// MARK: - Mental Health Resource Card

private struct MentalHealthResourceCard: View {
    let resource: MentalHealthResource
    
    var body: some View {
        Button {
            if let url = URL(string: resource.url) {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(resource.color.opacity(0.15))
                            .frame(width: 52, height: 52)
                        
                        Image(systemName: resource.icon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(resource.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(resource.name)
                            .font(.custom("OpenSans-Bold", size: 17))
                            .foregroundStyle(.primary)
                        
                        if resource.isFree {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                Text("Free")
                                    .font(.custom("OpenSans-SemiBold", size: 11))
                            }
                            .foregroundStyle(.green)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(resource.color)
                }
                
                Text(resource.description)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                
                if !resource.features.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(resource.features.prefix(3), id: \.self) { feature in
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(resource.color)
                                
                                Text(feature)
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
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
            )
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Self Care Tip Card

struct SelfCareTipCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

// MARK: - Data Models

struct MentalHealthResource: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let url: String
    let icon: String
    let color: Color
    let category: MentalHealthDetailView.MentalHealthCategory
    let isFree: Bool
    let features: [String]
    
    static let allResources = [
        // Counseling
        MentalHealthResource(
            name: "BetterHelp",
            description: "Online therapy with licensed Christian counselors. Get matched with a therapist in 24 hours.",
            url: "https://www.betterhelp.com",
            icon: "person.fill.questionmark",
            color: .blue,
            category: .counseling,
            isFree: false,
            features: [
                "Licensed professional counselors",
                "Text, call, or video sessions",
                "Financial aid available"
            ]
        ),
        MentalHealthResource(
            name: "Faithful Counseling",
            description: "Faith-based online therapy connecting you with Christian counselors.",
            url: "https://www.faithfulcounseling.com",
            icon: "cross.fill",
            color: .purple,
            category: .counseling,
            isFree: false,
            features: [
                "Christian-based therapy",
                "Licensed therapists",
                "Flexible scheduling"
            ]
        ),
        MentalHealthResource(
            name: "Focus on the Family Counseling",
            description: "Free phone consultations with licensed counselors. Get referrals to Christian therapists.",
            url: "https://www.focusonthefamily.com/get-help/counseling-services-and-referrals/",
            icon: "phone.circle.fill",
            color: .green,
            category: .counseling,
            isFree: true,
            features: [
                "Free consultations",
                "Therapist referrals",
                "Faith-based approach"
            ]
        ),
        
        // Resources
        MentalHealthResource(
            name: "Mental Health America",
            description: "Comprehensive mental health screening tools and educational resources.",
            url: "https://www.mhanational.org",
            icon: "heart.circle.fill",
            color: .red,
            category: .resources,
            isFree: true,
            features: [
                "Free screening tools",
                "Educational articles",
                "Local resources"
            ]
        ),
        MentalHealthResource(
            name: "NAMI (National Alliance on Mental Illness)",
            description: "Support, education, and advocacy for individuals and families affected by mental illness.",
            url: "https://www.nami.org",
            icon: "person.2.fill",
            color: .orange,
            category: .resources,
            isFree: true,
            features: [
                "Support groups",
                "Educational programs",
                "Advocacy resources"
            ]
        ),
        MentalHealthResource(
            name: "SAMHSA National Helpline",
            description: "Free, confidential, 24/7 treatment referral service.",
            url: "https://www.samhsa.gov/find-help/national-helpline",
            icon: "phone.fill",
            color: .blue,
            category: .resources,
            isFree: true,
            features: [
                "24/7 availability",
                "Treatment referrals",
                "Confidential support"
            ]
        ),
        
        // Meditation & Prayer
        MentalHealthResource(
            name: "Pray.com",
            description: "Christian meditation, prayer, and sleep content to reduce anxiety and find peace.",
            url: "https://www.pray.com",
            icon: "hands.sparkles.fill",
            color: .purple,
            category: .meditation,
            isFree: false,
            features: [
                "Guided prayers",
                "Bible-based meditations",
                "Sleep stories"
            ]
        ),
        MentalHealthResource(
            name: "Abide - Christian Meditation",
            description: "Biblical meditation app with sleep stories and mindfulness exercises.",
            url: "https://www.abide.co",
            icon: "moon.stars.fill",
            color: .indigo,
            category: .meditation,
            isFree: false,
            features: [
                "Scripture-based meditation",
                "Sleep content",
                "Stress relief exercises"
            ]
        ),
        MentalHealthResource(
            name: "YouVersion Bible Plans",
            description: "Free devotional plans focused on anxiety, depression, and mental wellness.",
            url: "https://www.bible.com/reading-plans",
            icon: "book.fill",
            color: .blue,
            category: .meditation,
            isFree: true,
            features: [
                "Mental health plans",
                "Daily devotionals",
                "100% free"
            ]
        ),
        
        // Support Groups
        MentalHealthResource(
            name: "Celebrate Recovery",
            description: "Christ-centered 12-step recovery program for hurts, habits, and hang-ups.",
            url: "https://www.celebraterecovery.com",
            icon: "person.3.fill",
            color: .green,
            category: .support,
            isFree: true,
            features: [
                "Support groups nationwide",
                "Biblical foundation",
                "Free to attend"
            ]
        ),
        MentalHealthResource(
            name: "GriefShare",
            description: "Support groups for people grieving the death of a loved one.",
            url: "https://www.griefshare.org",
            icon: "heart.fill",
            color: .pink,
            category: .support,
            isFree: true,
            features: [
                "Grief support groups",
                "Christian perspective",
                "Find local groups"
            ]
        ),
        MentalHealthResource(
            name: "DivorceCare",
            description: "Support groups for people experiencing separation or divorce.",
            url: "https://www.divorcecare.org",
            icon: "figure.2.arms.open",
            color: .orange,
            category: .support,
            isFree: true,
            features: [
                "Weekly support groups",
                "Expert teaching",
                "Faith-based healing"
            ]
        )
    ]
}

#Preview {
    NavigationStack {
        MentalHealthDetailView()
    }
}
