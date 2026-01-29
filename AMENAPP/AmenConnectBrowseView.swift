//
//  AmenConnectBrowseView.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import SwiftUI
import Combine

/// Alternative grid-based browse view (similar to left screen in reference image)
struct AmenConnectBrowseView: View {
    @StateObject private var viewModel = AmenConnectViewModel()
    @State private var showCardView = false
    @State private var showFilters = false
    @State private var selectedProfile: AmenConnectProfile?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        ForEach(viewModel.profiles) { profile in
                            ProfileGridCard(profile: profile)
                                .onTapGesture {
                                    selectedProfile = profile
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("AMEN Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 0) {
                        Button {
                            viewModel.showingMode = .forYou
                        } label: {
                            Text("For you")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(
                                    viewModel.showingMode == .forYou ? .primary : .secondary
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            viewModel.showingMode == .forYou ?
                                            Color(.systemGray6) : Color.clear
                                        )
                                )
                        }
                        
                        Button {
                            viewModel.showingMode = .nearby
                        } label: {
                            Text("Nearby")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(
                                    viewModel.showingMode == .nearby ? .primary : .secondary
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            viewModel.showingMode == .nearby ?
                                            Color(.systemGray6) : Color.clear
                                        )
                                )
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showCardView = true
                        } label: {
                            Image(systemName: "square.stack.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        
                        Button {
                            showFilters = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .sheet(item: $selectedProfile) { profile in
                ProfileDetailView(profile: profile)
            }
            .fullScreenCover(isPresented: $showCardView) {
                AmenConnectView()
            }
            .sheet(isPresented: $showFilters) {
                FiltersView(filters: $viewModel.filters)
            }
            .onAppear {
                viewModel.loadProfiles()
            }
        }
    }
}

// MARK: - Grid Card View

struct ProfileGridCard: View {
    let profile: AmenConnectProfile
    @State private var isPressed = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // Profile Image
                if let photoData = profile.profilePhoto,
                   let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.pink.opacity(0.3), Color.purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.white.opacity(0.5))
                        )
                }
                
                // Gradient overlay
                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.6)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )
                
                // Profile Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .bottom, spacing: 4) {
                        Text(profile.name.components(separatedBy: " ").first ?? profile.name)
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.white)
                        
                        Text("\(profile.age)")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    
                    // Top interest
                    if let firstInterest = profile.interests.first {
                        Text(firstInterest)
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.systemGray5), lineWidth: 0.5)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        }
        .aspectRatio(0.75, contentMode: .fit)
        .onLongPressGesture(
            minimumDuration: 0,
            pressing: { pressing in
                isPressed = pressing
            },
            perform: {}
        )
    }
}

// MARK: - Profile Detail View

struct ProfileDetailView: View {
    let profile: AmenConnectProfile
    @Environment(\.dismiss) private var dismiss
    @State private var showFullBio = false
    @State private var currentImageIndex = 0
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Image Section with Page Control
                    ZStack(alignment: .bottom) {
                        TabView(selection: $currentImageIndex) {
                            if let photoData = profile.profilePhoto,
                               let uiImage = UIImage(data: photoData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 500)
                                    .clipped()
                                    .tag(0)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: 500)
                        
                        // Gradient overlay
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.3)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .frame(height: 500)
                        
                        // Name and age overlay
                        HStack(alignment: .bottom, spacing: 8) {
                            Text(profile.name)
                                .font(.custom("OpenSans-Bold", size: 34))
                                .foregroundStyle(.white)
                            
                            Text("\(profile.age)")
                                .font(.custom("OpenSans-SemiBold", size: 28))
                                .foregroundStyle(.white.opacity(0.9))
                            
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                    }
                    
                    // Content Section
                    VStack(alignment: .leading, spacing: 24) {
                        // Interests
                        if !profile.interests.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Interests")
                                    .font(.custom("OpenSans-Bold", size: 18))
                                    .foregroundStyle(.primary)
                                
                                FlowLayout(spacing: 8) {
                                    ForEach(profile.interests, id: \.self) { interest in
                                        Text(interest)
                                            .font(.custom("OpenSans-SemiBold", size: 14))
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .fill(Color(.systemGray6))
                                            )
                                    }
                                }
                            }
                        }
                        
                        // Bio
                        if !profile.bio.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("About")
                                    .font(.custom("OpenSans-Bold", size: 18))
                                    .foregroundStyle(.primary)
                                
                                Text(profile.bio)
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(showFullBio ? nil : 4)
                                
                                if profile.bio.count > 100 {
                                    Button {
                                        withAnimation {
                                            showFullBio.toggle()
                                        }
                                    } label: {
                                        Text(showFullBio ? "Show less" : "Show more")
                                            .font(.custom("OpenSans-SemiBold", size: 14))
                                            .foregroundStyle(.pink)
                                    }
                                }
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        // Faith Journey
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Faith Journey")
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.primary)
                            
                            DetailInfoRow(
                                icon: "cross.fill",
                                title: "Faith",
                                value: profile.savedDescription
                            )
                            
                            DetailInfoRow(
                                icon: profile.isBaptized ? "checkmark.circle.fill" : "circle",
                                title: "Baptism",
                                value: profile.baptismStatus
                            )
                            
                            if let denomination = profile.denomination {
                                DetailInfoRow(
                                    icon: "book.fill",
                                    title: "Denomination",
                                    value: denomination
                                )
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        // Church Information
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Church")
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.primary)
                            
                            DetailInfoRow(
                                icon: "building.2.fill",
                                title: "Church Name",
                                value: profile.churchName
                            )
                            
                            DetailInfoRow(
                                icon: "mappin.circle.fill",
                                title: "Location",
                                value: profile.location
                            )
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        // Looking For
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Looking For")
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.primary)
                            
                            Text(profile.lookingFor)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                        }
                    }
                    .padding(24)
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(.black.opacity(0.5))
                            )
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Share profile
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(.black.opacity(0.5))
                            )
                    }
                }
            }
            .overlay(alignment: .bottom) {
                // Action buttons
                HStack(spacing: 20) {
                    Button {
                        // Pass
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(.white)
                                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                            )
                    }
                    
                    Button {
                        // Like
                    } label: {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.pink, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 68, height: 68)
                            .background(
                                Circle()
                                    .fill(.white)
                                    .shadow(color: .pink.opacity(0.3), radius: 15, y: 6)
                            )
                    }
                    
                    Button {
                        // Message
                    } label: {
                        Image(systemName: "message.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.blue)
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(.white)
                                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                            )
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 20)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea(edges: .bottom)
                )
            }
        }
    }
}

struct DetailInfoRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.pink)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                
                Text(value)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.primary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Flow Layout for Interest Tags
// Note: FlowLayout is defined in OnboardingAdvancedComponents.swift and reused here

#Preview {
    AmenConnectBrowseView()
}
