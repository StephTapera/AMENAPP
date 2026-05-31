//
//  PersonalizedGreetingView.swift
//  AMENAPP
//
//  Premium personalized greeting header with liquid glass design
//

import SwiftUI

struct PersonalizedGreetingView: View {
    @ObservedObject private var greetingService = GreetingService.shared
    @ObservedObject private var userService = UserService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var appeared = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Greeting text
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingService.currentGreeting.text)
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundStyle(.black)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel(greetingService.currentGreeting.text)
                
                // Subtle tagline based on greeting type
                if let tagline = getTagline() {
                    Text(tagline)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.black.opacity(0.5))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            
            Spacer()
            
            // Profile avatar
            if let user = userService.currentUser {
                Button {
                    // Navigate to profile
                    HapticManager.impact(style: .light)
                } label: {
                    if let imageURL = user.profileImageURL,
                       !imageURL.isEmpty,
                       let url = URL(string: imageURL) {
                        CachedAsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.6),
                                                    Color.white.opacity(0.2)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2
                                        )
                                )
                                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
                        } placeholder: {
                            initialsAvatar(for: user)
                        }
                    } else {
                        initialsAvatar(for: user)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(greetingBackground)
        .opacity(appeared ? 1.0 : 0.0)
        .offset(y: appeared ? 0 : -10)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.3)
                : .spring(response: 0.5, dampingFraction: 0.75),
            value: appeared
        )
        .onAppear {
            withAnimation(reduceMotion ? nil : .default) {
                appeared = true
            }
        }
        .onChange(of: greetingService.currentGreeting) { oldValue, newValue in
            // Smooth transition when greeting changes
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
                // Content updates automatically via @ObservedObject
            }
        }
    }
    
    // MARK: - Subviews
    
    private func initialsAvatar(for user: UserModel) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color.black, Color.black.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 48, height: 48)
            .overlay(
                Text(user.initials)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.white)
            )
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
    
    private var greetingBackground: some View {
        ZStack {
            // Base white background
            Rectangle()
                .fill(Color.white)
            
            // Subtle liquid glass effect
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blur(radius: 20)
            
            // Subtle border
            VStack {
                Spacer()
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.08),
                                Color.black.opacity(0.03)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func getTagline() -> String? {
        switch greetingService.currentGreeting.type {
        case .birthday:
            return "We hope you have a blessed day"
        case .sunday:
            return "Enjoy your day of rest"
        case .morning:
            return "Let's start the day together"
        case .evening:
            return "Reflect on your day"
        default:
            return nil
        }
    }
}

// MARK: - Compact Greeting View (for smaller screens or alternate layouts)

struct CompactGreetingView: View {
    @ObservedObject private var greetingService = GreetingService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var appeared = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greetingService.currentGreeting.text)
                .font(.custom("OpenSans-Bold", size: 24))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.white)
        .opacity(appeared ? 1.0 : 0.0)
        .offset(y: appeared ? 0 : -8)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.25)
                : .spring(response: 0.4, dampingFraction: 0.75),
            value: appeared
        )
        .onAppear {
            withAnimation(reduceMotion ? nil : .default) {
                appeared = true
            }
        }
    }
}

// MARK: - Preview

#Preview("Full Greeting") {
    VStack(spacing: 0) {
        PersonalizedGreetingView()
        
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Compact Greeting") {
    VStack(spacing: 0) {
        CompactGreetingView()
        
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}
