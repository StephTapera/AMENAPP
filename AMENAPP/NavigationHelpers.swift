//
//  NavigationHelpers.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import SwiftUI

/// Navigation destinations for the app
enum AppDestination: Hashable {
    case userProfile(userId: String)
    case postDetail(postId: UUID)
    case editProfile
    case messaging(userId: String, userName: String)
    case settings
}

/// Environment key for navigation path
struct NavigationPathKey: EnvironmentKey {
    static let defaultValue: Binding<NavigationPath> = .constant(NavigationPath())
}

extension EnvironmentValues {
    var navigationPath: Binding<NavigationPath> {
        get { self[NavigationPathKey.self] }
        set { self[NavigationPathKey.self] = newValue }
    }
}

/// View modifier to handle profile navigation
struct ProfileNavigationModifier: ViewModifier {
    let userId: String
    @State private var showProfile = false

    func body(content: Content) -> some View {
        content
            .onTapGesture {
                showProfile = true
            }
            // TODO (NAV-04): UserProfileView is presented as a modal sheet here, but the
            // C6 navigation contract specifies push navigation for profile views so the
            // user can swipe-back and maintains a linear nav stack. This sheet presentation
            // is inconsistent with the push paths used elsewhere (e.g. NavigationLink in
            // HomeView / PostDetailView). Phase 1 should replace .sheet with a
            // NavigationLink / navigationDestination push, and then delete this TODO.
            .sheet(isPresented: $showProfile) {
                UserProfileView(userId: userId)
            }
    }
}

extension View {
    /// Makes a view tappable to navigate to a user profile
    func navigateToProfile(userId: String) -> some View {
        modifier(ProfileNavigationModifier(userId: userId))
    }
}

/// Reusable tappable user header component
struct TappableUserHeader: View {
    let authorName: String
    let authorInitials: String
    let timeAgo: String
    let userId: String // Add this to your Post model
    
    @State private var showProfile = false
    
    var body: some View {
        Button {
            showProfile = true
        } label: {
            HStack(spacing: 12) {
                // Avatar
                Circle()
                    .fill(Color.black)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(authorInitials)
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.white)
                    )
                
                // Name and time
                VStack(alignment: .leading, spacing: 2) {
                    Text(authorName)
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                    
                    Text(timeAgo)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.black.opacity(0.5))
                }
                
                Spacer()
            }
        }
        .buttonStyle(PlainButtonStyle())
        // TODO (NAV-04): Same sheet-vs-push inconsistency as ProfileNavigationModifier above.
        // Replace with push navigation per C6 contract in Phase 1.
        .sheet(isPresented: $showProfile) {
            UserProfileView(userId: userId)
        }
    }
}

/// Small tappable avatar with name
struct TappableAvatarName: View {
    let name: String
    let initials: String
    let userId: String
    let size: CGFloat = 32
    
    @State private var showProfile = false
    
    var body: some View {
        Button {
            showProfile = true
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.black)
                    .frame(width: size, height: size)
                    .overlay(
                        Text(initials)
                            .font(.custom("OpenSans-Bold", size: size * 0.4))
                            .foregroundStyle(.white)
                    )
                
                Text(name)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        // TODO (NAV-04): Same sheet-vs-push inconsistency as ProfileNavigationModifier above.
        // Replace with push navigation per C6 contract in Phase 1.
        .sheet(isPresented: $showProfile) {
            UserProfileView(userId: userId)
        }
    }
}
