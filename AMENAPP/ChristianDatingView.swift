//
//  ChristianDatingView.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI

struct ChristianDatingView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab: DatingTab = .discover
    @State private var showMatchNotification = false
    @State private var matchedProfile: DatingProfile?
    @State private var showProfileDetail = false
    @State private var selectedProfile: DatingProfile?
    @State private var likedProfiles: Set<UUID> = []
    @State private var passedProfiles: Set<UUID> = []
    @Namespace private var tabNamespace
    
    enum DatingTab: String, CaseIterable {
        case discover = "Discover"
        case matches = "Matches"
        case messages = "Messages"
    }
    
    var availableProfiles: [DatingProfile] {
        DatingProfile.sampleProfiles().filter { !passedProfiles.contains($0.id) && !likedProfiles.contains($0.id) }
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Custom header with liquid glass X button
                HStack(spacing: 16) {
                    // Liquid Glass X button to exit
                    Button {
                        dismiss()
                    } label: {
                        ZStack {
                            // Liquid glass background
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 36, height: 36)
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
                                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                            
                            // X icon
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(LiquidGlassButtonStyle())
                    
                    Spacer()
                    
                    // Title
                    Text("Christian Dating")
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    // Filter button
                    Button {
                        // Filter action
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                // Custom tab selector
                HStack(spacing: 0) {
                    ForEach(DatingTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTab = tab
                            }
                        } label: {
                            VStack(spacing: 8) {
                                Text(tab.rawValue)
                                    .font(.custom("OpenSans-Bold", size: 16))
                                    .foregroundStyle(selectedTab == tab ? .black : .secondary)
                                
                                if selectedTab == tab {
                                    Capsule()
                                        .fill(Color.black)
                                        .frame(height: 3)
                                        .matchedGeometryEffect(id: "tab", in: tabNamespace)
                                } else {
                                    Capsule()
                                        .fill(Color.clear)
                                        .frame(height: 3)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal)
                
                Divider()
                    .padding(.top, 8)
                
                // Content based on selected tab
                ScrollView {
                    VStack(spacing: 20) {
                        switch selectedTab {
                        case .discover:
                            DiscoverContent(
                                profiles: availableProfiles,
                                onLike: { profile in
                                    likeProfile(profile)
                                },
                                onPass: { profile in
                                    passProfile(profile)
                                },
                                onMessage: { profile in
                                    selectedProfile = profile
                                    showProfileDetail = true
                                },
                                onTap: { profile in
                                    selectedProfile = profile
                                    showProfileDetail = true
                                }
                            )
                        case .matches:
                            MatchesContent(likedProfiles: Array(likedProfiles))
                        case .messages:
                            MessagesContent()
                        }
                    }
                    .padding(.vertical)
                }
            }
            
            // Match notification overlay
            if showMatchNotification, let profile = matchedProfile {
                MatchNotificationOverlay(
                    profile: profile,
                    onMessage: {
                        showMatchNotification = false
                        selectedProfile = profile
                        showProfileDetail = true
                    },
                    onDismiss: {
                        showMatchNotification = false
                    }
                )
                .transition(.scale.combined(with: .opacity))
                .zIndex(100)
            }
        }
        .navigationBarHidden(true)
        .sheet(item: $selectedProfile) { profile in
            DatingProfileDetailView(profile: profile)
        }
    }
    
    // MARK: - Actions
    
    private func likeProfile(_ profile: DatingProfile) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            likedProfiles.insert(profile.id)
        }
        
        // Simulate match (30% chance)
        if Bool.random() && Bool.random() && Bool.random() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                matchedProfile = profile
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    showMatchNotification = true
                }
            }
        }
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    private func passProfile(_ profile: DatingProfile) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            passedProfiles.insert(profile.id)
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
}

struct DiscoverContent: View {
    let profiles: [DatingProfile]
    let onLike: (DatingProfile) -> Void
    let onPass: (DatingProfile) -> Void
    let onMessage: (DatingProfile) -> Void
    let onTap: (DatingProfile) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Featured banner
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.pink)
                    
                    Text("Faith-Based Matching")
                        .font(.custom("OpenSans-Bold", size: 18))
                }
                
                Text("Connect with believers who share your values and faith journey")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.pink.opacity(0.1))
            )
            .padding(.horizontal)
            
            // Profile cards
            if profiles.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "heart.circle")
                        .font(.system(size: 60))
                        .foregroundStyle(.pink.opacity(0.5))
                    
                    Text("No more profiles")
                        .font(.custom("OpenSans-Bold", size: 20))
                    
                    Text("Check back later for new matches!")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                ForEach(profiles) { profile in
                    ProfileCard(
                        profile: profile,
                        onLike: { onLike(profile) },
                        onPass: { onPass(profile) },
                        onMessage: { onMessage(profile) },
                        onTap: { onTap(profile) }
                    )
                }
            }
        }
    }
}

struct ProfileCard: View {
    let profile: DatingProfile
    let onLike: () -> Void
    let onPass: () -> Void
    let onMessage: () -> Void
    let onTap: () -> Void
    
    @State private var isLiked = false
    @State private var isPassed = false
    @State private var showSuperLike = false
    
    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Image placeholder
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: profile.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 320)
                    
                    // Gradient overlay
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .bottom, spacing: 6) {
                            Text(profile.name)
                                .font(.custom("OpenSans-Bold", size: 26))
                            Text("\(profile.age)")
                                .font(.custom("OpenSans-SemiBold", size: 22))
                        }
                        .foregroundStyle(.white)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 12))
                            Text(profile.locationCity)
                                .font(.custom("OpenSans-Regular", size: 14))
                        }
                        .foregroundStyle(.white.opacity(0.9))
                        
                        // Church info
                        if let church = profile.churchName {
                            HStack(spacing: 4) {
                                Image(systemName: "building.2.fill")
                                    .font(.system(size: 12))
                                Text(church)
                                    .font(.custom("OpenSans-Regular", size: 13))
                            }
                            .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(20)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                VStack(alignment: .leading, spacing: 12) {
                    Text(profile.bio)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                    
                    // Faith badge
                    if let faithYears = profile.faithYears {
                        HStack(spacing: 6) {
                            Image(systemName: "cross.fill")
                                .font(.system(size: 11))
                            Text("\(faithYears) years in Christ")
                                .font(.custom("OpenSans-SemiBold", size: 12))
                        }
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.purple.opacity(0.1))
                        )
                    }
                    
                    // Interests
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(profile.interests, id: \.self) { interest in
                                Text(interest)
                                    .font(.custom("OpenSans-SemiBold", size: 12))
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(Color.blue.opacity(0.1))
                                    )
                            }
                        }
                    }
                    
                    // Action buttons with full functionality
                    HStack(spacing: 12) {
                        // Pass Button
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                isPassed = true
                            }
                            onPass()
                            
                            let haptic = UIImpactFeedbackGenerator(style: .medium)
                            haptic.impactOccurred()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 60, height: 60)
                                .background(
                                    ZStack {
                                        Circle()
                                            .fill(Color.gray.opacity(0.2))
                                        
                                        Circle()
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                                    }
                                )
                                .scaleEffect(isPassed ? 0.85 : 1.0)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        
                        // Like Button (Primary)
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                isLiked = true
                            }
                            onLike()
                            
                            let haptic = UINotificationFeedbackGenerator()
                            haptic.notificationOccurred(.success)
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                isLiked = false
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 24, weight: .bold))
                                
                                if !isLiked {
                                    Text("Like")
                                        .font(.custom("OpenSans-Bold", size: 16))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 30)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.pink, Color(red: 1.0, green: 0.3, blue: 0.5)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                    
                                    if isLiked {
                                        RoundedRectangle(cornerRadius: 30)
                                            .fill(Color.white.opacity(0.3))
                                    }
                                }
                            )
                            .scaleEffect(isLiked ? 1.05 : 1.0)
                            .shadow(color: .pink.opacity(0.4), radius: isLiked ? 15 : 8, y: isLiked ? 8 : 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Message/Super Like Button
                        Button {
                            showSuperLike = true
                            onMessage()
                            
                            let haptic = UIImpactFeedbackGenerator(style: .heavy)
                            haptic.impactOccurred()
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showSuperLike = false
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 60, height: 60)
                                
                                if showSuperLike {
                                    Circle()
                                        .fill(Color.blue.opacity(0.3))
                                        .frame(width: 60, height: 60)
                                }
                                
                                Image(systemName: "star.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color.blue, Color.cyan],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            .scaleEffect(showSuperLike ? 1.1 : 1.0)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(16)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            )
            .padding(.horizontal)
            .opacity(isPassed ? 0.5 : 1.0)
            .offset(x: isPassed ? -400 : 0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MatchesContent: View {
    let likedProfiles: [UUID]
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Your Matches")
                    .font(.custom("OpenSans-Bold", size: 20))
                
                Spacer()
                
                Text("\(likedProfiles.count)")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.pink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.pink.opacity(0.15))
                    )
            }
            .padding(.horizontal)
            
            if likedProfiles.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "heart.slash")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                    
                    Text("No matches yet")
                        .font(.custom("OpenSans-Bold", size: 18))
                    
                    Text("Start liking profiles to find your match!")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(DatingProfile.sampleProfiles().filter { likedProfiles.contains($0.id) }) { profile in
                        MatchCard(profile: profile)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct MatchCard: View {
    let profile: DatingProfile
    
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: profile.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 110, height: 110)
                
                Image(systemName: "person.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
                
                // Match indicator
                Circle()
                    .fill(Color.pink)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .offset(x: 40, y: -40)
            }
            
            Text(profile.name)
                .font(.custom("OpenSans-Bold", size: 16))
            
            Text("\(profile.age) • \(profile.locationCity)")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Button {
                // Message action
            } label: {
                Text("Message")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.pink, Color(red: 1.0, green: 0.3, blue: 0.5)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
    }
}

struct MessagesContent: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<5) { _ in
                MessageRow()
            }
        }
        .padding(.horizontal)
    }
}

struct MessageRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                
                Image(systemName: "person.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Jessica M.")
                    .font(.custom("OpenSans-Bold", size: 16))
                
                Text("Hey! How's your day going?")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("2m")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                
                Circle()
                    .fill(Color.pink)
                    .frame(width: 8, height: 8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
    }
}
// MARK: - Match Notification Overlay

struct MatchNotificationOverlay: View {
    let profile: DatingProfile
    let onMessage: () -> Void
    let onDismiss: () -> Void
    
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Background blur
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            VStack(spacing: 28) {
                // Celebration
                Text("🎉")
                    .font(.system(size: 80))
                    .scaleEffect(animate ? 1.0 : 0.5)
                    .opacity(animate ? 1.0 : 0)
                
                VStack(spacing: 12) {
                    Text("It's a Match!")
                        .font(.custom("OpenSans-Bold", size: 36))
                        .foregroundStyle(.white)
                    
                    Text("You and \(profile.name) liked each other!")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                .opacity(animate ? 1.0 : 0)
                .offset(y: animate ? 0 : 20)
                
                // Profile preview
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: profile.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 180, height: 180)
                    
                    Image(systemName: "person.fill")
                        .font(.system(size: 70))
                        .foregroundStyle(.white)
                }
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.pink, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                )
                .scaleEffect(animate ? 1.0 : 0.8)
                .opacity(animate ? 1.0 : 0)
                
                VStack(spacing: 6) {
                    Text(profile.name)
                        .font(.custom("OpenSans-Bold", size: 26))
                        .foregroundStyle(.white)
                    
                    Text("\(profile.age) • \(profile.locationCity)")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .opacity(animate ? 1.0 : 0)
                
                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        onMessage()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "message.fill")
                                .font(.system(size: 18, weight: .semibold))
                            
                            Text("SEND MESSAGE")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 30)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.pink, Color(red: 1.0, green: 0.3, blue: 0.5)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: .pink.opacity(0.5), radius: 20, y: 10)
                        )
                    }
                    
                    Button {
                        onDismiss()
                    } label: {
                        Text("Keep Swiping")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.vertical, 12)
                    }
                }
                .opacity(animate ? 1.0 : 0)
                .offset(y: animate ? 0 : 20)
                .padding(.horizontal, 40)
            }
            .padding(40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animate = true
            }
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        }
    }
}

// MARK: - Profile Detail View

struct DatingProfileDetailView: View {
    @Environment(\.dismiss) var dismiss
    let profile: DatingProfile
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Large profile image
                    ZStack(alignment: .bottomLeading) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: profile.gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 400)
                        
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.7)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .bottom, spacing: 8) {
                                Text(profile.name)
                                    .font(.custom("OpenSans-Bold", size: 34))
                                Text("\(profile.age)")
                                    .font(.custom("OpenSans-SemiBold", size: 28))
                            }
                            .foregroundStyle(.white)
                            
                            HStack(spacing: 6) {
                                Image(systemName: "mappin.circle.fill")
                                Text(profile.locationCity)
                                    .font(.custom("OpenSans-Regular", size: 16))
                            }
                            .foregroundStyle(.white.opacity(0.9))
                        }
                        .padding(24)
                    }
                    
                    VStack(alignment: .leading, spacing: 20) {
                        // Bio
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About")
                                .font(.custom("OpenSans-Bold", size: 20))
                            
                            Text(profile.bio)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundStyle(.primary)
                                .lineSpacing(6)
                        }
                        
                        Divider()
                        
                        // Faith info
                        if let church = profile.churchName, let faithYears = profile.faithYears {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Faith Journey")
                                    .font(.custom("OpenSans-Bold", size: 20))
                                
                                HStack(spacing: 12) {
                                    Image(systemName: "building.2.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.purple)
                                        .frame(width: 32)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Church")
                                            .font(.custom("OpenSans-SemiBold", size: 13))
                                            .foregroundStyle(.secondary)
                                        Text(church)
                                            .font(.custom("OpenSans-Regular", size: 15))
                                    }
                                }
                                
                                HStack(spacing: 12) {
                                    Image(systemName: "cross.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.purple)
                                        .frame(width: 32)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Years in Christ")
                                            .font(.custom("OpenSans-SemiBold", size: 13))
                                            .foregroundStyle(.secondary)
                                        Text("\(faithYears) years")
                                            .font(.custom("OpenSans-Regular", size: 15))
                                    }
                                }
                            }
                            
                            Divider()
                        }
                        
                        // Interests
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Interests")
                                .font(.custom("OpenSans-Bold", size: 20))
                            
                            DatingFlowLayout(spacing: 8) {
                                ForEach(profile.interests, id: \.self) { interest in
                                    Text(interest)
                                        .font(.custom("OpenSans-SemiBold", size: 14))
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(
                                            Capsule()
                                                .fill(Color.blue.opacity(0.1))
                                        )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                            )
                    }
                    
                    Button {
                        // Like action
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 24, weight: .bold))
                            Text("Like")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 30)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.pink, Color(red: 1.0, green: 0.3, blue: 0.5)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: .pink.opacity(0.4), radius: 15, y: 8)
                        )
                    }
                    
                    Button {
                        // Message action
                    } label: {
                        Image(systemName: "star.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.blue)
                            .frame(width: 60, height: 60)
                            .background(
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea(edges: .bottom)
                )
            }
        }
    }
}

// MARK: - Dating Flow Layout for wrapping content

struct DatingFlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = DatingFlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = DatingFlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct DatingFlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

// MARK: - Button Style

private struct LiquidGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    NavigationStack {
        ChristianDatingView()
    }
}
