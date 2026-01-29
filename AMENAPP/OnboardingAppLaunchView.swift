//
//  AppLaunchView.swift
//  AMENAPP
//
//  Created by Steph on 1/18/26.
//
//  First screen users see - Choose between login, signup, or demo
//

import SwiftUI

struct AppLaunchView: View {
    @State private var showOnboarding = false
    @State private var showAuth = false
    @State private var authMode: AuthMode = .login
    @State private var animate = false
    @State private var pulseAnimation = false
    
    enum AuthMode {
        case login
        case signup
    }
    
    var body: some View {
        ZStack {
            // Animated gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.4, green: 0.2, blue: 0.8),
                    Color(red: 0.6, green: 0.3, blue: 0.9),
                    Color(red: 0.5, green: 0.3, blue: 0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Floating circles
            GeometryReader { geometry in
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 250, height: 250)
                    .blur(radius: 40)
                    .offset(x: -50, y: -50)
                    .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 350, height: 350)
                    .blur(radius: 60)
                    .offset(x: geometry.size.width - 200, y: geometry.size.height - 250)
                    .scaleEffect(pulseAnimation ? 1.0 : 1.2)
            }
            
            VStack(spacing: 0) {
                Spacer()
                
                // Logo and branding
                VStack(spacing: 24) {
                    // Animated Logo
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 160, height: 160)
                            .blur(radius: 30)
                            .scaleEffect(animate ? 1.0 : 0.8)
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: 120, height: 120)
                            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                            .scaleEffect(animate ? 1.0 : 0.8)
                        
                        Image(systemName: "cross.fill")
                            .font(.system(size: 60, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.5, green: 0.3, blue: 0.9), Color(red: 0.6, green: 0.4, blue: 1.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(animate ? 1.0 : 0.8)
                    }
                    .opacity(animate ? 1.0 : 0)
                    
                    VStack(spacing: 12) {
                        Text("AMEN")
                            .font(.custom("OpenSans-Bold", size: 48))
                            .foregroundStyle(.white)
                            .offset(y: animate ? 0 : 20)
                            .opacity(animate ? 1.0 : 0)
                        
                        Text("Connect. Grow. Pray Together.")
                            .font(.custom("OpenSans-Regular", size: 17))
                            .foregroundStyle(.white.opacity(0.9))
                            .offset(y: animate ? 0 : 20)
                            .opacity(animate ? 1.0 : 0)
                    }
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 16) {
                    // Sign Up Button (Primary)
                    Button {
                        authMode = .signup
                        showAuth = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 18, weight: .bold))
                            
                            Text("Create Account")
                                .font(.custom("OpenSans-Bold", size: 17))
                        }
                        .foregroundStyle(Color(red: 0.5, green: 0.3, blue: 0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                        )
                    }
                    .scaleEffect(animate ? 1.0 : 0.9)
                    .opacity(animate ? 1.0 : 0)
                    
                    // Login Button (Secondary)
                    Button {
                        authMode = .login
                        showAuth = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 18, weight: .bold))
                            
                            Text("Login")
                                .font(.custom("OpenSans-Bold", size: 17))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.4), lineWidth: 2)
                                )
                        )
                    }
                    .scaleEffect(animate ? 1.0 : 0.9)
                    .opacity(animate ? 1.0 : 0)
                    
                    // Divider
                    HStack(spacing: 16) {
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 1)
                        
                        Text("OR")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                        
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 1)
                    }
                    .padding(.vertical, 8)
                    .opacity(animate ? 1.0 : 0)
                    
                    // Demo/Preview Button
                    Button {
                        showOnboarding = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                                .symbolEffect(.pulse.byLayer, options: .repeating)
                            
                            Text("Try Demo Mode")
                                .font(.custom("OpenSans-Bold", size: 17))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.15),
                                            Color.white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                )
                        )
                    }
                    .scaleEffect(animate ? 1.0 : 0.9)
                    .opacity(animate ? 1.0 : 0)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 60)
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .fullScreenCover(isPresented: $showAuth) {
            MinimalAuthenticationView(initialMode: authMode)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animate = true
            }
            
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }
}

#Preview {
    AppLaunchView()
}
