//
//  ErrorBannerView.swift
//  AMENAPP
//
//  Created by Claude on 2/15/26.
//
//  Smart error banner/toast with retry mechanism and offline detection
//

import SwiftUI
import Network
import Combine

/// Error banner manager for displaying user-friendly error messages
@MainActor
class ErrorBannerManager: ObservableObject {
    static let shared = ErrorBannerManager()
    
    @Published var currentError: ErrorBanner?
    @Published var isOffline = false
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    init() {
        startNetworkMonitoring()
    }
    
    // MARK: - Network Monitoring
    
    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOffline = path.status != .satisfied
            }
        }
        monitor.start(queue: queue)
    }
    
    // MARK: - Show Error
    
    func showError(
        _ message: String,
        type: ErrorType = .error,
        duration: TimeInterval = 4.0,
        action: ErrorAction? = nil
    ) {
        let error = ErrorBanner(
            id: UUID().uuidString,
            message: message,
            type: type,
            action: action
        )
        
        currentError = error
        
        // Auto-dismiss after duration (unless it has an action)
        if action == nil {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                if currentError?.id == error.id {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        currentError = nil
                    }
                }
            }
        }
    }
    
    func dismissError() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentError = nil
        }
    }
}

// MARK: - Models

struct ErrorBanner: Identifiable {
    let id: String
    let message: String
    let type: ErrorType
    let action: ErrorAction?
}

enum ErrorType {
    case error
    case warning
    case info
    case success
    
    var icon: String {
        switch self {
        case .error: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .success: return .green
        }
    }
}

struct ErrorAction {
    let title: String
    let action: () -> Void
}

// MARK: - Banner View

struct ErrorBannerView: View {
    @ObservedObject var manager: ErrorBannerManager
    
    var body: some View {
        VStack {
            if let error = manager.currentError {
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: error.type.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(error.type.color)
                    
                    // Message
                    Text(error.message)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    // Action button or dismiss
                    if let action = error.action {
                        Button(action: {
                            action.action()
                            manager.dismissError()
                        }) {
                            Text(action.title)
                                .font(.custom("OpenSans-Bold", size: 13))
                                .foregroundStyle(error.type.color)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(error.type.color.opacity(0.15))
                                )
                        }
                    } else {
                        Button(action: {
                            manager.dismissError()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                        .shadow(color: error.type.color.opacity(0.2), radius: 12, y: 4)
                )
                .padding(.horizontal)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
            
            Spacer()
        }
        .zIndex(999)
    }
}

// MARK: - Offline Banner

struct OfflineBannerView: View {
    @ObservedObject var manager: ErrorBannerManager
    
    var body: some View {
        VStack {
            if manager.isOffline {
                HStack(spacing: 10) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    Text("You're offline")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Text("Changes will sync when reconnected")
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Color.orange
                )
                .transition(.move(edge: .top))
            }
            
            Spacer()
        }
        .zIndex(1000)
    }
}

// MARK: - View Modifier

struct ErrorBannerModifier: ViewModifier {
    @ObservedObject var manager = ErrorBannerManager.shared
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            VStack {
                OfflineBannerView(manager: manager)
                
                ErrorBannerView(manager: manager)
                    .padding(.top, manager.isOffline ? 0 : 8)
            }
        }
    }
}

extension View {
    func errorBanner() -> some View {
        modifier(ErrorBannerModifier())
    }
}

// MARK: - Common Error Messages

extension ErrorBannerManager {
    func showNetworkError(retry: @escaping () -> Void) {
        showError(
            "Network error. Check your connection.",
            type: .error,
            action: ErrorAction(title: "Retry", action: retry)
        )
    }
    
    func showPostError(retry: @escaping () -> Void) {
        showError(
            "Failed to post. Try again.",
            type: .error,
            action: ErrorAction(title: "Retry", action: retry)
        )
    }
    
    func showCommentError(retry: @escaping () -> Void) {
        showError(
            "Couldn't post comment. Retry?",
            type: .error,
            action: ErrorAction(title: "Retry", action: retry)
        )
    }
    
    func showLoadError(retry: @escaping () -> Void) {
        showError(
            "Failed to load content.",
            type: .error,
            action: ErrorAction(title: "Retry", action: retry)
        )
    }
    
    func showSuccess(_ message: String) {
        showError(message, type: .success, duration: 2.0)
    }
    
    func showInfo(_ message: String) {
        showError(message, type: .info, duration: 3.0)
    }
}
