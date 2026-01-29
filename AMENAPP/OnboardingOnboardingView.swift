//
//  OnboardingView.swift
//  AMENAPP
//
//  Created by Steph on 1/18/26.
//
//  Smart, interactive onboarding with personalization and animations
//

import SwiftUI
import PhotosUI

struct OnboardingView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    
    @State private var currentPage = 0
    @State private var selectedInterests: Set<String> = []
    @State private var selectedGoals: Set<String> = []
    @State private var prayerTime: PrayerTime = .morning
    @State private var offset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var selectedProfileImage: UIImage?
    @State private var profileImageURL: String?
    @State private var isUploadingImage = false
    
    @Environment(\.dismiss) var dismiss
    
    let totalPages = 6  // Updated from 5 to 6
    
    enum PrayerTime: String, CaseIterable {
        case morning = "Morning"
        case afternoon = "Afternoon"
        case evening = "Evening"
        case night = "Night"
        case dayAndNight = "Day & Night"
        
        var icon: String {
            switch self {
            case .morning: return "sunrise.fill"
            case .afternoon: return "sun.max.fill"
            case .evening: return "sunset.fill"
            case .night: return "moon.stars.fill"
            case .dayAndNight: return "sun.and.horizon.fill"
            }
        }
        
        var color: Color {
            // Subtle colors matching app design
            switch self {
            case .morning: return .orange
            case .afternoon: return .orange.opacity(0.8)
            case .evening: return .blue
            case .night: return .blue.opacity(0.8)
            case .dayAndNight: return .primary
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Dynamic background based on page
            backgroundGradient
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress bar
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Capsule()
                            .fill(index <= currentPage ? Color.blue : Color.secondary.opacity(0.3))
                            .frame(height: 4)
                            .frame(maxWidth: index == currentPage ? 40 : 20)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                
                // Content
                TabView(selection: $currentPage) {
                    // Page 1: Welcome
                    WelcomePage()
                        .tag(0)
                    
                    // Page 2: Profile Photo
                    ProfilePhotoPage(
                        selectedImage: $selectedProfileImage,
                        isUploading: $isUploadingImage
                    )
                        .tag(1)
                    
                    // Page 3: Features
                    FeaturesPage()
                        .tag(2)
                    
                    // Page 4: Personalization - Interests
                    InterestsPage(selectedInterests: $selectedInterests)
                        .tag(3)
                    
                    // Page 5: Goals
                    GoalsPage(selectedGoals: $selectedGoals)
                        .tag(4)
                    
                    // Page 6: Prayer Time
                    PrayerTimePage(prayerTime: $prayerTime)
                        .tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Navigation Buttons
                HStack(spacing: 16) {
                    if currentPage > 0 {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage -= 1
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 16, weight: .bold))
                                Text("Back")
                                    .font(.custom("OpenSans-Bold", size: 15))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(
                                Capsule()
                                    .fill(Color(.secondarySystemBackground))
                            )
                        }
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                    
                    Spacer()
                    
                    Button {
                        if currentPage < totalPages - 1 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage += 1
                            }
                        } else {
                            // Finish onboarding - notify auth view model
                            authViewModel.completeOnboarding()
                            
                            // Save user preferences to backend
                            saveOnboardingData()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(currentPage == totalPages - 1 ? "Get Started" : "Continue")
                                .font(.custom("OpenSans-Bold", size: 16))
                            
                            Image(systemName: currentPage == totalPages - 1 ? "checkmark" : "arrow.right")
                                .font(.system(size: 16, weight: .bold))
                                .symbolEffect(.bounce, value: currentPage)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(Color.blue)
                                .shadow(color: .blue.opacity(0.3), radius: 12, y: 6)
                        )
                    }
                    .disabled(!canContinue)
                    .opacity(canContinue ? 1.0 : 0.5)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            
            // Skip button (not on last page)
            if currentPage < totalPages - 1 {
                VStack {
                    HStack {
                        Spacer()
                        
                        Button {
                            currentPage = totalPages - 1
                        } label: {
                            Text("Skip")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 60)
                    
                    Spacer()
                }
                .transition(.opacity)
            }
        }
    }
    
    /// Save onboarding preferences to Firestore
    private func saveOnboardingData() {
        Task { @MainActor in
            do {
                let userService = UserService()
                
                // Convert selectedInterests and selectedGoals (Set) to Array
                let interestsArray = Array(selectedInterests)
                let goalsArray = Array(selectedGoals)
                
                print("💾 Saving onboarding data to Firestore...")
                print("   - Interests: \(interestsArray)")
                print("   - Goals: \(goalsArray)")
                print("   - Prayer Time: \(prayerTime.rawValue)")
                
                // Upload profile image if selected
                var imageURL: String? = profileImageURL
                if let image = selectedProfileImage, imageURL == nil {
                    print("📸 Uploading profile image...")
                    do {
                        imageURL = try await userService.uploadProfileImage(image)
                        print("✅ Profile image uploaded: \(imageURL ?? "nil")")
                    } catch {
                        print("⚠️ Failed to upload profile image (continuing anyway): \(error)")
                        // Continue even if image upload fails
                    }
                }
                
                // Save preferences and profile image URL
                try await userService.saveOnboardingPreferences(
                    interests: interestsArray,
                    goals: goalsArray,
                    prayerTime: prayerTime.rawValue,
                    profileImageURL: imageURL
                )
                
                print("✅ Onboarding data saved successfully!")
            } catch {
                print("❌ Failed to save onboarding data: \(error)")
            }
        }
    }
    
    private var canContinue: Bool {
        switch currentPage {
        case 1: return !isUploadingImage  // Profile photo page - can skip
        case 3: return !selectedInterests.isEmpty  // Interests page (was 2)
        case 4: return !selectedGoals.isEmpty  // Goals page (was 3)
        default: return true
        }
    }
    
    private var backgroundGradient: some View {
        // Subtle, consistent gradient background matching app's clean design
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.systemBackground).opacity(0.95)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.05),
                    Color.orange.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

// MARK: - Welcome Page

struct ProfilePhotoPage: View {
    @Binding var selectedImage: UIImage?
    @Binding var isUploading: Bool
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var animate = false
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Text("Add a Profile Photo")
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundStyle(.primary)
                    .offset(y: animate ? 0 : -20)
                    .opacity(animate ? 1.0 : 0)
                
                Text("Show the community who you are")
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .offset(y: animate ? 0 : -20)
                    .opacity(animate ? 1.0 : 0)
            }
            .padding(.top, 60)
            
            // Profile photo preview or placeholder
            ZStack {
                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 200, height: 200)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.blue.opacity(0.3), lineWidth: 4)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
                        .scaleEffect(animate ? 1.0 : 0.8)
                        .opacity(animate ? 1.0 : 0)
                } else {
                    ZStack {
                        Circle()
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 200, height: 200)
                        
                        Circle()
                            .stroke(Color.blue.opacity(0.3), lineWidth: 3)
                            .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [10, 10]))
                            .frame(width: 200, height: 200)
                        
                        Image(systemName: "person.crop.circle.fill.badge.plus")
                            .font(.system(size: 80))
                            .foregroundStyle(Color.secondary)
                    }
                    .scaleEffect(animate ? 1.0 : 0.8)
                    .opacity(animate ? 1.0 : 0)
                }
            }
            
            // Photo picker button
            PhotosPicker(selection: $selectedItem, matching: .images) {
                HStack(spacing: 12) {
                    Image(systemName: selectedImage == nil ? "photo.on.rectangle" : "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 20))
                    
                    Text(selectedImage == nil ? "Choose Photo" : "Change Photo")
                        .font(.custom("OpenSans-Bold", size: 16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.blue)
                        .shadow(color: .blue.opacity(0.3), radius: 12, y: 6)
                )
            }
            .padding(.horizontal, 40)
            .offset(y: animate ? 0 : 20)
            .opacity(animate ? 1.0 : 0)
            
            if selectedImage == nil {
                Text("You can also add a photo later")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .offset(y: animate ? 0 : 20)
                    .opacity(animate ? 1.0 : 0)
            }
            
            Spacer()
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animate = true
            }
        }
    }
}

// MARK: - Welcome Page

struct WelcomePage: View {
    @State private var animate = false
    @StateObject private var userService = UserService()
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Animated Logo
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 180, height: 180)
                    .blur(radius: 30)
                    .scaleEffect(animate ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animate)
                
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
                
                Image(systemName: "cross.fill")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(animate ? 1.0 : 0.8)
            .opacity(animate ? 1.0 : 0)
            
            VStack(spacing: 16) {
                // Personalized welcome with user's display name
                if let user = userService.currentUser, !user.displayName.isEmpty {
                    Text("Welcome, \(user.displayName)!")
                        .font(.custom("OpenSans-Bold", size: 36))
                        .foregroundStyle(.primary)
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                } else {
                    Text("Welcome to AMEN")
                        .font(.custom("OpenSans-Bold", size: 36))
                        .foregroundStyle(.primary)
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                }
                
                Text("Your digital companion for\nspiritual growth and connection")
                    .font(.custom("OpenSans-Regular", size: 18))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .offset(y: animate ? 0 : 20)
                    .opacity(animate ? 1.0 : 0)
            }
            
            Spacer()
            Spacer()
        }
        .padding()
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animate = true
            }
            
            // Fetch current user for personalization
            Task {
                await userService.fetchCurrentUser()
            }
        }
    }
}

// MARK: - Features Page

struct FeaturesPage: View {
    @State private var animate = false
    
    let features = [
        OnboardingFeature(
            icon: "book.fill",
            title: "AI Bible Study",
            description: "Get instant answers to biblical questions",
            color: .blue
        ),
        OnboardingFeature(
            icon: "hands.sparkles.fill",
            title: "Prayer Network",
            description: "Share and support prayer requests",
            color: .blue
        ),
        OnboardingFeature(
            icon: "person.2.fill",
            title: "Community",
            description: "Connect with believers worldwide",
            color: .orange
        ),
        OnboardingFeature(
            icon: "chart.line.uptrend.xyaxis",
            title: "Track Growth",
            description: "Monitor your spiritual journey",
            color: .orange
        )
    ]
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Text("Everything You Need")
                    .font(.custom("OpenSans-Bold", size: 32))
                    .foregroundStyle(.primary)
                    .offset(y: animate ? 0 : -20)
                    .opacity(animate ? 1.0 : 0)
                
                Text("Powerful features to strengthen your faith")
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .offset(y: animate ? 0 : -20)
                    .opacity(animate ? 1.0 : 0)
            }
            .padding(.top, 40)
            
            VStack(spacing: 20) {
                ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                    OnboardingFeatureCard(feature: feature)
                        .offset(x: animate ? 0 : -50)
                        .opacity(animate ? 1.0 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(index) * 0.1), value: animate)
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .onAppear {
            animate = true
        }
    }
}

struct OnboardingFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
    let color: Color
}

struct OnboardingFeatureCard: View {
    let feature: OnboardingFeature
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(feature.color.opacity(0.15))
                    .frame(width: 60, height: 60)
                
                Image(systemName: feature.icon)
                    .font(.system(size: 26))
                    .foregroundStyle(feature.color)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(feature.title)
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
                
                Text(feature.description)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        )
    }
}

// MARK: - Interests Page

struct InterestsPage: View {
    @Binding var selectedInterests: Set<String>
    @State private var animate = false
    
    let interests = [
        ("Bible Study", "book.fill"),
        ("Prayer", "hands.sparkles.fill"),
        ("Worship", "music.note"),
        ("Community", "person.3.fill"),
        ("Devotionals", "heart.text.square.fill"),
        ("Missions", "globe"),
        ("Youth Ministry", "figure.walk"),
        ("Theology", "graduationcap.fill"),
        ("Evangelism", "megaphone.fill"),
        ("Scripture Memorization", "brain.fill"),
        ("Discipleship", "person.2.fill"),
        ("Christian Living", "house.fill"),
        ("Marriage & Family", "heart.circle.fill"),
        ("Social Justice", "scale.3d"),
        ("Apologetics", "lightbulb.fill"),
        ("Church History", "clock.arrow.circlepath")
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Text("What interests you?")
                        .font(.custom("OpenSans-Bold", size: 28))
                        .foregroundStyle(.primary)
                        .offset(y: animate ? 0 : -20)
                        .opacity(animate ? 1.0 : 0)
                    
                    Text("Select topics you'd like to explore")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.secondary)
                        .offset(y: animate ? 0 : -20)
                        .opacity(animate ? 1.0 : 0)
                }
                .padding(.top, 40)
                
                // Interest chips
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(interests.enumerated()), id: \.element.0) { index, interest in
                        OnboardingInterestChip(
                            icon: interest.1,
                            title: interest.0,
                            isSelected: selectedInterests.contains(interest.0)
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedInterests.contains(interest.0) {
                                    selectedInterests.remove(interest.0)
                                } else {
                                    selectedInterests.insert(interest.0)
                                }
                            }
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        }
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(index) * 0.05), value: animate)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 120)
        }
        .onAppear {
            animate = true
        }
    }
}

struct OnboardingInterestChip: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(isSelected ? Color.blue : .secondary)
                
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(isSelected ? Color.blue : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 2)
                    )
                    .shadow(color: isSelected ? .blue.opacity(0.2) : .clear, radius: 12, y: 4)
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Goals Page

struct GoalsPage: View {
    @Binding var selectedGoals: Set<String>
    @State private var animate = false
    
    let goals = [
        ("Grow in Faith", "chart.line.uptrend.xyaxis", Color.blue),
        ("Daily Bible Reading", "book.fill", Color.blue),
        ("Consistent Prayer", "hands.sparkles.fill", Color.blue),
        ("Build Community", "person.3.fill", Color.orange),
        ("Share the Gospel", "megaphone.fill", Color.orange),
        ("Serve Others", "heart.fill", Color.orange)
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Text("What are your goals?")
                        .font(.custom("OpenSans-Bold", size: 28))
                        .foregroundStyle(.primary)
                        .offset(y: animate ? 0 : -20)
                        .opacity(animate ? 1.0 : 0)
                    
                    Text("We'll personalize your experience")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.secondary)
                        .offset(y: animate ? 0 : -20)
                        .opacity(animate ? 1.0 : 0)
                }
                .padding(.top, 40)
                
                VStack(spacing: 12) {
                    ForEach(Array(goals.enumerated()), id: \.element.0) { index, goal in
                        GoalCard(
                            icon: goal.1,
                            title: goal.0,
                            color: goal.2,
                            isSelected: selectedGoals.contains(goal.0)
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedGoals.contains(goal.0) {
                                    selectedGoals.remove(goal.0)
                                } else {
                                    selectedGoals.insert(goal.0)
                                }
                            }
                            let haptic = UIImpactFeedbackGenerator(style: .medium)
                            haptic.impactOccurred()
                        }
                        .offset(x: animate ? 0 : -50)
                        .opacity(animate ? 1.0 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(index) * 0.1), value: animate)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 120)
        }
        .onAppear {
            animate = true
        }
    }
}

struct GoalCard: View {
    let icon: String
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isSelected ? color : color.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? .white : color)
                }
                
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 17))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28))
                    .foregroundStyle(isSelected ? color : .secondary.opacity(0.5))
                    .symbolEffect(.bounce, value: isSelected)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? color.opacity(0.1) : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? color.opacity(0.3) : Color.clear, lineWidth: 2)
                    )
                    .shadow(color: isSelected ? color.opacity(0.2) : .clear, radius: 12, y: 4)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Prayer Time Page

struct PrayerTimePage: View {
    @Binding var prayerTime: OnboardingView.PrayerTime
    @State private var animate = false
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Text("When do you pray?")
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundStyle(.primary)
                    .offset(y: animate ? 0 : -20)
                    .opacity(animate ? 1.0 : 0)
                
                Text("We'll send you gentle reminders")
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.secondary)
                    .offset(y: animate ? 0 : -20)
                    .opacity(animate ? 1.0 : 0)
            }
            .padding(.top, 60)
            
            VStack(spacing: 16) {
                ForEach(Array(OnboardingView.PrayerTime.allCases.enumerated()), id: \.element) { index, time in
                    PrayerTimeCard(
                        time: time,
                        isSelected: prayerTime == time
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            prayerTime = time
                        }
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                    }
                    .offset(x: animate ? 0 : 50)
                    .opacity(animate ? 1.0 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(index) * 0.1), value: animate)
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .onAppear {
            animate = true
        }
    }
}

struct PrayerTimeCard: View {
    let time: OnboardingView.PrayerTime
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isSelected ? time.color.opacity(0.2) : Color(.tertiarySystemBackground))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: time.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(isSelected ? time.color : .secondary)
                        .symbolEffect(.bounce, value: isSelected)
                }
                
                Text(time.rawValue)
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 32))
                    .foregroundStyle(isSelected ? time.color : .secondary.opacity(0.5))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isSelected ? time.color.opacity(0.1) : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(isSelected ? time.color.opacity(0.3) : Color.clear, lineWidth: 2)
                    )
                    .shadow(color: isSelected ? time.color.opacity(0.2) : .clear, radius: 12, y: 4)
            )
            .scaleEffect(isSelected ? 1.03 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AuthenticationViewModel())
}
