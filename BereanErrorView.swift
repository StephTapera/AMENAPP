//
//  BereanErrorView.swift
//  AMENAPP
//
//  Created by Assistant on 2/3/26.
//

import SwiftUI
import Combine

// MARK: - Error Type

enum BereanError: LocalizedError {
    case networkUnavailable
    case aiServiceUnavailable
    case rateLimitExceeded
    case invalidResponse
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "No Internet Connection"
        case .aiServiceUnavailable:
            return "AI Service Unavailable"
        case .rateLimitExceeded:
            return "Rate Limit Exceeded"
        case .invalidResponse:
            return "Invalid Response"
        case .unknown(let message):
            return message
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .networkUnavailable:
            return "Please check your internet connection and try again."
        case .aiServiceUnavailable:
            return "Our AI service is temporarily unavailable. Please try again in a few moments."
        case .rateLimitExceeded:
            return "You've reached the message limit. Upgrade to Pro for unlimited conversations or try again later."
        case .invalidResponse:
            return "We received an unexpected response. Please try again."
        case .unknown:
            return "An unexpected error occurred. Please try again."
        }
    }
    
    var icon: String {
        switch self {
        case .networkUnavailable:
            return "wifi.slash"
        case .aiServiceUnavailable:
            return "exclamationmark.triangle.fill"
        case .rateLimitExceeded:
            return "clock.fill"
        case .invalidResponse:
            return "questionmark.circle.fill"
        case .unknown:
            return "exclamationmark.circle.fill"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .networkUnavailable:
            return Color(red: 1.0, green: 0.6, blue: 0.4)
        case .aiServiceUnavailable:
            return Color(red: 1.0, green: 0.7, blue: 0.5)
        case .rateLimitExceeded:
            return Color(red: 0.6, green: 0.5, blue: 0.9)
        case .invalidResponse:
            return Color(red: 0.5, green: 0.6, blue: 0.9)
        case .unknown:
            return Color(red: 1.0, green: 0.6, blue: 0.7)
        }
    }
}

// MARK: - Error Banner View

struct BereanErrorBanner: View {
    let error: BereanError
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: error.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(error.iconColor)
                
                // Error text
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.localizedDescription)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(white: 0.2))
                    
                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color(white: 0.4))
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                // Actions
                HStack(spacing: 8) {
                    if let onRetry = onRetry {
                        Button {
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                            onRetry()
                        } label: {
                            Text("Retry")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(error.iconColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(error.iconColor.opacity(0.12))
                                )
                        }
                    }
                    
                    Button {
                        withAnimation(.smooth(duration: 0.3)) {
                            onDismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(white: 0.5))
                            .frame(width: 24, height: 24)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(error.iconColor.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 15, y: 5)
            )
            .padding(.horizontal, 16)
            .offset(y: isVisible ? 0 : -120)
            .opacity(isVisible ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Full Screen Error View

struct BereanFullScreenError: View {
    let error: BereanError
    let onRetry: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Error icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                error.iconColor.opacity(0.2),
                                error.iconColor.opacity(0.05),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 140, height: 140)
                
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .stroke(error.iconColor.opacity(0.2), lineWidth: 1)
                    )
                
                Image(systemName: error.icon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(error.iconColor)
            }
            
            // Error message
            VStack(spacing: 12) {
                Text(error.localizedDescription)
                    .font(.custom("Georgia", size: 28))
                    .fontWeight(.light)
                    .foregroundStyle(Color(white: 0.2))
                    .multilineTextAlignment(.center)
                
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color(white: 0.4))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 40)
                }
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 12) {
                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                    onRetry()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                        
                        Text("Try Again")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(error.iconColor)
                            .shadow(color: error.iconColor.opacity(0.3), radius: 15, y: 5)
                    )
                }
                
                Button {
                    onDismiss()
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(white: 0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.96, blue: 0.94),
                    Color(red: 0.95, green: 0.94, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
}

// MARK: - Offline Mode Banner

struct OfflineModeBanner: View {
    @Binding var isOnline: Bool
    
    var body: some View {
        if !isOnline {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 14, weight: .medium))
                
                Text("Offline Mode")
                    .font(.system(size: 13, weight: .semibold))
                
                Spacer()
                
                Text("Limited features")
                    .font(.system(size: 11, weight: .regular))
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Color(red: 1.0, green: 0.6, blue: 0.4)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview("Error Banner") {
    VStack {
        BereanErrorBanner(
            error: .networkUnavailable,
            onRetry: {},
            onDismiss: {}
        )
        
        Spacer()
    }
}

#Preview("Full Screen Error") {
    BereanFullScreenError(
        error: .aiServiceUnavailable,
        onRetry: {},
        onDismiss: {}
    )
}
