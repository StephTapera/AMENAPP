//
//  AmenConnectView.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import SwiftUI
import Combine

struct AmenConnectView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = AmenConnectViewModel()
    @State private var showProfileSetup = false
    @State private var showFilters = false
    @State private var showMatches = false
    @State private var showMenu = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Modern dark background with subtle gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.08, blue: 0.08),
                        Color(red: 0.12, green: 0.10, blue: 0.10),
                        Color(red: 0.15, green: 0.12, blue: 0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Enhanced Header with liquid glass X button
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
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(AmenConnectLiquidGlassButtonStyle())
                        
                        Spacer()
                        
                        // AMEN | Connect logo with accent
                        HStack(spacing: 6) {
                            Text("AMEN")
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.white)
                            Text("|")
                                .foregroundStyle(Color.orange.opacity(0.6))
                            Text("Connect")
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.orange, Color(red: 1.0, green: 0.6, blue: 0.2)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        
                        Spacer()
                        
                        // Menu button
                        Button {
                            showMenu = true
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        Color.black.opacity(0.3)
                            .background(.ultraThinMaterial.opacity(0.5))
                    )
                    
                    // Modern tab selector with orange accent
                    HStack(spacing: 0) {
                        ForEach([("For You", AmenConnectViewModel.ShowingMode.forYou), 
                                 ("Nearby", AmenConnectViewModel.ShowingMode.nearby)], id: \.0) { tab in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    viewModel.showingMode = tab.1
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    Text(tab.0)
                                        .font(.custom("OpenSans-SemiBold", size: 15))
                                        .foregroundStyle(
                                            viewModel.showingMode == tab.1 ? .white : .white.opacity(0.5)
                                        )
                                    
                                    // Orange accent bar
                                    Rectangle()
                                        .fill(
                                            viewModel.showingMode == tab.1 ?
                                            LinearGradient(
                                                colors: [Color.orange, Color(red: 1.0, green: 0.6, blue: 0.2)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            ) :
                                            LinearGradient(
                                                colors: [Color.clear, Color.clear],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(height: 3)
                                        .cornerRadius(1.5)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .background(Color.white.opacity(0.05))
                    
                    // Card Stack
                    if viewModel.profiles.isEmpty {
                        AmenConnectEmptyStateView()
                    } else {
                        ZStack {
                            ForEach(Array(viewModel.profiles.enumerated()), id: \.element.id) { index, profile in
                                if index >= viewModel.currentIndex && index < viewModel.currentIndex + 3 {
                                    ProfileCardView(profile: profile)
                                        .zIndex(Double(viewModel.profiles.count - index))
                                        .offset(
                                            x: index == viewModel.currentIndex ? viewModel.dragOffset.width : 0,
                                            y: CGFloat(index - viewModel.currentIndex) * 8
                                        )
                                        .scaleEffect(
                                            index == viewModel.currentIndex ? 1 : 0.95 - CGFloat(index - viewModel.currentIndex) * 0.05
                                        )
                                        .rotationEffect(
                                            index == viewModel.currentIndex ?
                                            .degrees(Double(viewModel.dragOffset.width) / 20) : .zero
                                        )
                                        .opacity(index < viewModel.currentIndex + 3 ? 1 : 0)
                                        .gesture(
                                            index == viewModel.currentIndex ?
                                            DragGesture()
                                                .onChanged { value in
                                                    viewModel.dragOffset = value.translation
                                                }
                                                .onEnded { value in
                                                    viewModel.handleSwipe(value.translation)
                                                }
                                            : nil
                                        )
                                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.dragOffset)
                                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.currentIndex)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    
                    Spacer()
                    
                    // Modern action buttons with orange accent
                    HStack(spacing: 24) {
                        // Pass Button - minimalist design
                        Button {
                            viewModel.passCurrentProfile()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 64, height: 64)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                                )
                        }
                        .buttonStyle(AmenConnectScaleButtonStyle())
                        
                        // Like Button - warm orange glow (inspired by the lamp)
                        Button {
                            viewModel.likeCurrentProfile()
                        } label: {
                            ZStack {
                                // Outer glow
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                Color.orange.opacity(0.4),
                                                Color.orange.opacity(0.2),
                                                Color.clear
                                            ],
                                            center: .center,
                                            startRadius: 30,
                                            endRadius: 50
                                        )
                                    )
                                    .frame(width: 100, height: 100)
                                    .blur(radius: 10)
                                
                                // Main button
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 1.0, green: 0.6, blue: 0.2),
                                                Color.orange
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 80, height: 80)
                                    .background(
                                        Circle()
                                            .fill(Color(red: 0.12, green: 0.10, blue: 0.10))
                                            .overlay(
                                                Circle()
                                                    .stroke(
                                                        LinearGradient(
                                                            colors: [
                                                                Color.orange.opacity(0.6),
                                                                Color.orange.opacity(0.2)
                                                            ],
                                                            startPoint: .top,
                                                            endPoint: .bottom
                                                        ),
                                                        lineWidth: 2
                                                    )
                                            )
                                            .shadow(color: .orange.opacity(0.5), radius: 25, y: 12)
                                    )
                            }
                        }
                        .buttonStyle(AmenConnectScaleButtonStyle())
                        
                        // Message Button
                        Button {
                            viewModel.superLikeCurrentProfile()
                        } label: {
                            Image(systemName: "message.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 64, height: 64)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                                )
                        }
                        .buttonStyle(AmenConnectScaleButtonStyle())
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
                
                // Match notification overlay
                if viewModel.showMatchNotification {
                    MatchNotificationView(profile: viewModel.matchedProfile!)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(100)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showProfileSetup) {
            AmenConnectProfileSetupView()
        }
        .sheet(isPresented: $showFilters) {
            FiltersView(filters: $viewModel.filters)
        }
        .onAppear {
            viewModel.loadProfiles()
        }
    }
}

// MARK: - Profile Card View

struct ProfileCardView: View {
    let profile: AmenConnectProfile
    @State private var showFullBio = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background image or placeholder
            if let photoData = profile.profilePhoto,
               let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 600)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            } else {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color.pink.opacity(0.3), Color.purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 600)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 100))
                            .foregroundStyle(.white.opacity(0.5))
                    )
            }
            
            // Gradient overlay
            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.3),
                    .black.opacity(0.7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
            
            // Profile Info
            VStack(alignment: .leading, spacing: 12) {
                // Name and Age
                HStack(alignment: .bottom, spacing: 8) {
                    Text(profile.name)
                        .font(.custom("OpenSans-Bold", size: 32))
                        .foregroundStyle(.white)
                    
                    Text("\(profile.age)")
                        .font(.custom("OpenSans-SemiBold", size: 28))
                        .foregroundStyle(.white.opacity(0.9))
                }
                
                // Interest Tags
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(profile.interests, id: \.self) { interest in
                            Text(interest)
                                .font(.custom("OpenSans-SemiBold", size: 13))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(.white.opacity(0.25))
                                        .overlay(
                                            Capsule()
                                                .stroke(.white.opacity(0.3), lineWidth: 1)
                                        )
                                )
                        }
                    }
                }
                
                // Bio
                if !profile.bio.isEmpty {
                    Text(profile.bio)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.white)
                        .lineLimit(showFullBio ? nil : 3)
                        .onTapGesture {
                            withAnimation {
                                showFullBio.toggle()
                            }
                        }
                }
                
                Divider()
                    .background(.white.opacity(0.3))
                    .padding(.vertical, 4)
                
                // Faith Information
                VStack(alignment: .leading, spacing: 10) {
                    AmenConnectProfileInfoRow(
                        icon: "cross.fill",
                        text: profile.savedDescription,
                        color: .white
                    )
                    
                    AmenConnectProfileInfoRow(
                        icon: profile.isBaptized ? "checkmark.circle.fill" : "circle",
                        text: profile.baptismStatus,
                        color: .white
                    )
                    
                    AmenConnectProfileInfoRow(
                        icon: "building.2.fill",
                        text: profile.churchName,
                        color: .white
                    )
                    
                    AmenConnectProfileInfoRow(
                        icon: "mappin.circle.fill",
                        text: profile.location,
                        color: .white
                    )
                    
                    if let denomination = profile.denomination {
                        AmenConnectProfileInfoRow(
                            icon: "book.fill",
                            text: denomination,
                            color: .white
                        )
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 600)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
    }
}

// Removed duplicate ProfileInfoRow - defined below

// MARK: - Empty State View

struct AmenConnectEmptyStateView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.pink, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 12) {
                Text("No More Profiles")
                    .font(.custom("OpenSans-Bold", size: 24))
                    .foregroundStyle(.primary)
                
                Text("Check back later for new connections or adjust your filters")
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Match Notification View

struct MatchNotificationView: View {
    let profile: AmenConnectProfile
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Background blur
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Celebration animation
                Text("🎉")
                    .font(.system(size: 80))
                
                VStack(spacing: 12) {
                    Text("You matched!")
                        .font(.custom("OpenSans-Bold", size: 36))
                        .foregroundStyle(.white)
                    
                    Text("Let's get to know\neach other better!")
                        .font(.custom("OpenSans-Regular", size: 18))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                
                // Profile preview
                if let photoData = profile.profilePhoto,
                   let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 200, height: 200)
                        .clipShape(Circle())
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
                }
                
                VStack(spacing: 8) {
                    Text(profile.name)
                        .font(.custom("OpenSans-Bold", size: 24))
                        .foregroundStyle(.white)
                    
                    Text(profile.location)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.white.opacity(0.8))
                }
                
                // Message button
                Button {
                    // Navigate to messages
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 18))
                        
                        Text("MESSAGE")
                            .font(.custom("OpenSans-Bold", size: 16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 28)
                            .fill(
                                LinearGradient(
                                    colors: [.pink, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: .pink.opacity(0.5), radius: 15, y: 8)
                    )
                }
                .padding(.horizontal, 40)
                
                Button {
                    dismiss()
                } label: {
                    Text("Keep Swiping")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(40)
        }
    }
}

// MARK: - Filters View

struct FiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filters: AmenConnectFilters
    @State private var localFilters: AmenConnectFilters
    
    init(filters: Binding<AmenConnectFilters>) {
        self._filters = filters
        self._localFilters = State(initialValue: filters.wrappedValue)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Age Range
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Age Range")
                            .font(.custom("OpenSans-Bold", size: 18))
                            .foregroundStyle(.primary)
                        
                        Text("\(Int(localFilters.ageRange.lowerBound)) - \(Int(localFilters.ageRange.upperBound))")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.secondary)
                        
                        // Custom range slider would go here
                        // For simplicity, using basic controls
                    }
                    
                    // Distance
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Maximum Distance")
                            .font(.custom("OpenSans-Bold", size: 18))
                            .foregroundStyle(.primary)
                        
                        Text("\(Int(localFilters.maxDistance)) miles")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.secondary)
                        
                        Slider(value: $localFilters.maxDistance, in: 5...100, step: 5)
                            .tint(.pink)
                    }
                    
                    // Baptized Only
                    Toggle("Show only baptized believers", isOn: $localFilters.baptizedOnly)
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .tint(.pink)
                    
                    // Min Years Saved
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Minimum Years Saved")
                            .font(.custom("OpenSans-Bold", size: 18))
                            .foregroundStyle(.primary)
                        
                        Picker("Years", selection: $localFilters.minYearsSaved) {
                            Text("Any").tag(0)
                            Text("1+ years").tag(1)
                            Text("3+ years").tag(3)
                            Text("5+ years").tag(5)
                            Text("10+ years").tag(10)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        localFilters = AmenConnectFilters()
                    }
                    .foregroundStyle(.pink)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        filters = localFilters
                        dismiss()
                    }
                    .foregroundStyle(.pink)
                    .fontWeight(.bold)
                }
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
class AmenConnectViewModel: ObservableObject {
    enum ShowingMode {
        case forYou
        case nearby
    }
    
    @Published var profiles: [AmenConnectProfile] = []
    @Published var currentIndex: Int = 0
    @Published var dragOffset: CGSize = .zero
    @Published var showingMode: ShowingMode = .forYou
    @Published var filters: AmenConnectFilters = AmenConnectFilters()
    
    @Published var showMatchNotification = false
    @Published var matchedProfile: AmenConnectProfile?
    
    func loadProfiles() {
        // TODO: Load from backend
        // For now, using sample data
        profiles = AmenConnectProfile.sampleProfiles
    }
    
    func handleSwipe(_ translation: CGSize) {
        let swipeThreshold: CGFloat = 100
        
        if abs(translation.width) > swipeThreshold {
            if translation.width > 0 {
                likeCurrentProfile()
            } else {
                passCurrentProfile()
            }
        } else {
            // Reset position
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                dragOffset = .zero
            }
        }
    }
    
    func passCurrentProfile() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dragOffset = CGSize(width: -500, height: 0)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.nextProfile()
        }
    }
    
    func likeCurrentProfile() {
        // Simulate match (30% chance for demo)
        let isMatch = Bool.random() && Bool.random()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dragOffset = CGSize(width: 500, height: 0)
        }
        
        if isMatch {
            matchedProfile = profiles[currentIndex]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    self.showMatchNotification = true
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.nextProfile()
        }
    }
    
    func superLikeCurrentProfile() {
        // Similar to like but with super like indication
        likeCurrentProfile()
    }
    
    private func nextProfile() {
        currentIndex += 1
        dragOffset = .zero
        
        if currentIndex >= profiles.count {
            // Reload or show empty state
            currentIndex = profiles.count
        }
    }
}

// MARK: - Button Styles

private struct AmenConnectLiquidGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct AmenConnectScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Profile Info Row

private struct AmenConnectProfileInfoRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color.opacity(0.9))
                .frame(width: 20)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(color)
        }
    }
}

#Preview {
    AmenConnectView()
}
