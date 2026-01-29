//
//  ExampleIntegrations.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//
//  This file demonstrates how to integrate the new elegant components
//  into your existing AMEN app views.

import SwiftUI

// MARK: - Example 1: Enhanced Login Screen
struct EnhancedLoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            
            VStack(spacing: 32) {
                // Logo Section
                VStack(spacing: 16) {
                    Text("AMEN")
                        .font(.system(size: 56, weight: .thin, design: .serif))
                        .tracking(10)
                        .foregroundColor(.white)
                    
                    Text("Social Media, Reorded")
                        .font(.system(size: 13, weight: .light))
                        .tracking(2.5)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 60)
                
                Spacer()
                
                // Login Form
                VStack(spacing: 20) {
                    AmenTextField(title: "Email", text: $email)
                    AmenTextField(title: "Password", text: $password, isSecure: true)
                    
                    Button("SIGN IN") {
                        HapticFeedback.light()
                        isLoading = true
                        // Perform login
                    }
                    .buttonStyle(AmenButtonStyle(isPrimary: true))
                    .padding(.top, 8)
                    
                    Button("CREATE ACCOUNT") {
                        HapticFeedback.selection()
                        // Navigate to signup
                    }
                    .buttonStyle(AmenButtonStyle(isPrimary: false))
                    
                    Button {
                        // Forgot password
                    } label: {
                        Text("Forgot Password?")
                            .font(.system(size: 13, weight: .light))
                            .tracking(1)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 32)
                
                Spacer()
            }
            
            // Loading Overlay
            if isLoading {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                AmenLoadingSpinner(size: 60)
            }
        }
    }
}

// MARK: - Example 2: Enhanced Profile Header
struct EnhancedProfileHeader: View {
    var username: String = "JohnDoe"
    var bio: String = "Child of God | Prayer Warrior | Testimony Sharer"
    var followers: Int = 1234
    var following: Int = 567
    
    var body: some View {
        VStack(spacing: 20) {
            // Profile Picture with Shimmer
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.8),
                                Color.purple.opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Text(String(username.prefix(2)).uppercased())
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(.white)
            }
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 2)
                    .frame(width: 108, height: 108)
            )
            
            // Username
            Text(username)
                .font(.system(size: 24, weight: .light))
                .tracking(2)
                .foregroundColor(.white)
            
            // Bio
            Text(bio)
                .font(.system(size: 13, weight: .light))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // Stats
            HStack(spacing: 40) {
                VStack(spacing: 4) {
                    Text("\(followers)")
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(.white)
                    
                    Text("FOLLOWERS")
                        .font(.system(size: 10, weight: .light))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 1, height: 30)
                
                VStack(spacing: 4) {
                    Text("\(following)")
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(.white)
                    
                    Text("FOLLOWING")
                        .font(.system(size: 10, weight: .light))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            // Action Buttons
            HStack(spacing: 12) {
                Button("EDIT PROFILE") {
                    HapticFeedback.selection()
                }
                .buttonStyle(AmenButtonStyle(isPrimary: true))
                
                Button("SHARE") {
                    HapticFeedback.light()
                }
                .buttonStyle(AmenButtonStyle(isPrimary: false))
                .frame(width: 100)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 32)
    }
}

// MARK: - Example 3: Example Post Card (renamed to avoid conflict)
struct ExamplePostCard: View {
    var authorName: String = "John Doe"
    var postTime: String = "2h ago"
    var category: String = "#OPENTABLE"
    var content: String = "This is a testimony of God's amazing grace..."
    var likes: Int = 42
    var comments: Int = 8
    
    @State private var isLiked = false
    @State private var isBookmarked = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(String(authorName.prefix(2)).uppercased())
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(authorName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text(postTime)
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                Text(category)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1)
                    .foregroundColor(.amenGold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.amenGold.opacity(0.15))
                    )
            }
            
            // Content
            Text(content)
                .font(.system(size: 15, weight: .light))
                .foregroundColor(.white.opacity(0.9))
                .lineSpacing(4)
            
            // Action Bar
            HStack(spacing: 24) {
                Button {
                    HapticFeedback.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isLiked.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 18))
                            .foregroundColor(isLiked ? .red : .white.opacity(0.7))
                            .scaleEffect(isLiked ? 1.2 : 1.0)
                        
                        Text("\(likes + (isLiked ? 1 : 0))")
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                Button {
                    HapticFeedback.selection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "message")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text("\(comments)")
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                Button {
                    HapticFeedback.selection()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Button {
                    HapticFeedback.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isBookmarked.toggle()
                    }
                } label: {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 18))
                        .foregroundColor(isBookmarked ? .amenGold : .white.opacity(0.7))
                }
            }
            .padding(.top, 8)
        }
        .padding(20)
        .amenCardStyle(opacity: 0.08)
        .padding(.horizontal)
    }
}

// MARK: - Example 4: Enhanced Search Bar
struct EnhancedSearchBar: View {
    @Binding var searchText: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(.white.opacity(0.5))
            
            TextField("", text: $searchText, prompt:
                Text("Search AMEN...")
                    .foregroundColor(.white.opacity(0.4))
            )
            .font(.system(size: 15, weight: .light))
            .foregroundColor(.white)
            .focused($isFocused)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    HapticFeedback.selection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isFocused ? Color.white.opacity(0.3) : Color.white.opacity(0.1),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - Example 5: Enhanced Empty State
struct EnhancedEmptyState: View {
    var icon: String = "tray"
    var title: String = "No Content Yet"
    var subtitle: String = "Be the first to share something amazing"
    var actionTitle: String = "CREATE POST"
    var action: () -> Void = {}
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundColor(.white.opacity(0.3))
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 20, weight: .light))
                    .tracking(2)
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            
            Button(actionTitle) {
                HapticFeedback.light()
                action()
            }
            .buttonStyle(AmenButtonStyle(isPrimary: true))
            .frame(width: 200)
        }
        .padding(40)
    }
}

// MARK: - Example 6: Enhanced Category Pills
struct EnhancedCategoryPill: View {
    var title: String
    var icon: String?
    var isSelected: Bool = false
    var action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticFeedback.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                action()
            }
        }) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .tracking(1)
            }
            .foregroundColor(isSelected ? .black : .white.opacity(0.8))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white : Color.white.opacity(0.1))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.clear : Color.white.opacity(0.2),
                        lineWidth: 1
                    )
            )
        }
        .scaleEffect(isSelected ? 1.05 : 1.0)
    }
}

// MARK: - Previews
#Preview("Login") {
    EnhancedLoginView()
}

#Preview("Profile Header") {
    ZStack {
        AnimatedGradientBackground()
        EnhancedProfileHeader()
    }
}

#Preview("Post Card") {
    ZStack {
        Color.black.ignoresSafeArea()
        ExamplePostCard()
    }
}

#Preview("Search Bar") {
    ZStack {
        Color.black.ignoresSafeArea()
        EnhancedSearchBar(searchText: .constant(""))
            .padding()
    }
}

#Preview("Empty State") {
    ZStack {
        AnimatedGradientBackground()
        EnhancedEmptyState()
    }
}

#Preview("Category Pills") {
    ZStack {
        Color.black.ignoresSafeArea()
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                EnhancedCategoryPill(title: "#OPENTABLE", icon: "bubble.left.and.bubble.right", isSelected: true) {}
                EnhancedCategoryPill(title: "Testimonies", icon: "hands.sparkles", isSelected: false) {}
                EnhancedCategoryPill(title: "Prayer", icon: "hands.clap", isSelected: false) {}
                EnhancedCategoryPill(title: "Scripture", icon: "book", isSelected: false) {}
            }
            .padding()
        }
    }
}
