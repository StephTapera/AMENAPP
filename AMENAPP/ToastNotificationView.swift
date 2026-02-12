//
//  ToastNotificationView.swift
//  AMENAPP
//
//  Toast notification component for messaging errors and status updates
//

import SwiftUI
import Combine

/// Toast notification style
enum ToastStyle {
    case error
    case success
    case warning
    case info
    
    var color: Color {
        switch self {
        case .error: return .red
        case .success: return .green
        case .warning: return .orange
        case .info: return .blue
        }
    }
    
    var icon: String {
        switch self {
        case .error: return "xmark.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

/// Toast notification model
struct ToastNotification: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let style: ToastStyle
    let action: (() -> Void)?
    let actionLabel: String?
    
    init(message: String, style: ToastStyle, action: (() -> Void)? = nil, actionLabel: String? = nil) {
        self.message = message
        self.style = style
        self.action = action
        self.actionLabel = actionLabel
    }
    
    static func == (lhs: ToastNotification, rhs: ToastNotification) -> Bool {
        lhs.id == rhs.id
    }
}

/// Toast notification view
struct ToastNotificationView: View {
    let toast: ToastNotification
    let onDismiss: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: toast.style.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(toast.style.color)
            
            // Message
            Text(toast.message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Action button (e.g., "Retry")
            if let action = toast.action, let actionLabel = toast.actionLabel {
                Button(action: {
                    action()
                    onDismiss()
                }) {
                    Text(actionLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(toast.style.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            toast.style.color.opacity(0.15)
                        )
                        .cornerRadius(8)
                }
            }
            
            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Glassmorphic background
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                
                // Colored accent border
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(toast.style.color.opacity(0.3), lineWidth: 1.5)
            }
        )
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height < 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height < -50 {
                        onDismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}

/// Toast notification manager
class ToastManager: ObservableObject {
    static let shared = ToastManager()
    
    @Published var currentToast: ToastNotification?
    
    private var dismissTimer: Timer?
    
    private init() {}
    
    func show(_ toast: ToastNotification, duration: TimeInterval = 4.0) {
        // Dismiss any existing toast
        dismissTimer?.invalidate()
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentToast = toast
        }
        
        // Auto-dismiss after duration
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }
    
    func dismiss() {
        dismissTimer?.invalidate()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentToast = nil
        }
    }
    
    // Convenience methods
    func showError(_ message: String, retry: (() -> Void)? = nil) {
        let toast = ToastNotification(
            message: message,
            style: .error,
            action: retry,
            actionLabel: retry != nil ? "Retry" : nil
        )
        show(toast)
    }
    
    func showSuccess(_ message: String) {
        let toast = ToastNotification(message: message, style: .success)
        show(toast, duration: 2.0)
    }
    
    func showWarning(_ message: String) {
        let toast = ToastNotification(message: message, style: .warning)
        show(toast, duration: 3.0)
    }
    
    func showInfo(_ message: String) {
        let toast = ToastNotification(message: message, style: .info)
        show(toast, duration: 3.0)
    }
}

/// View modifier for toast notifications
struct MessagingToastModifier: ViewModifier {
    @ObservedObject var toastManager = ToastManager.shared
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            // Toast overlay
            if let toast = toastManager.currentToast {
                VStack {
                    ToastNotificationView(toast: toast, onDismiss: {
                        toastManager.dismiss()
                    })
                    .padding(.horizontal, 16)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    
                    Spacer()
                }
                .zIndex(999)
            }
        }
    }
}

extension View {
    /// Add toast notification support to any view
    func withToast() -> some View {
        self.modifier(MessagingToastModifier())
    }
}
