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
                .font(.systemScaled(20, weight: .semibold))
                .foregroundColor(toast.style.color)
            
            // Message
            Text(toast.message)
                .font(.systemScaled(14, weight: .medium))
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
                        .font(.systemScaled(14, weight: .semibold))
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
                    .font(.systemScaled(12, weight: .semibold))
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
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}

/// Toast notification manager
@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()
    
    @Published var currentToast: ToastNotification?
    @Published var showCopyHUD: Bool = false
    
    private var dismissTimer: Timer?
    private var copyHUDTimer: Timer?
    
    private init() {}
    
    func showCopyLinkHUD() {
        copyHUDTimer?.invalidate()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            showCopyHUD = true
        }
        copyHUDTimer = Timer.scheduledTimer(withTimeInterval: 1.9, repeats: false) { [weak self] _ in
            withAnimation(.easeOut(duration: 0.22)) {
                self?.showCopyHUD = false
            }
        }
    }
    
    func show(_ toast: ToastNotification, duration: TimeInterval = 4.0) {
        // Dismiss any existing toast
        dismissTimer?.invalidate()
        
        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))) {
            currentToast = toast
        }
        
        // Auto-dismiss after duration
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }
    
    func dismiss() {
        dismissTimer?.invalidate()
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
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
            
            // Top-banner toast
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
            
            // Centered Liquid Glass copy HUD
            if toastManager.showCopyHUD {
                LiquidGlassCopyHUD()
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.76).combined(with: .opacity),
                            removal: .scale(scale: 0.88).combined(with: .opacity)
                        )
                    )
                    .zIndex(1000)
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

// MARK: - Liquid Glass Copy HUD

/// Centered floating capsule with animated checkmark — shown on copy-link long press.
struct LiquidGlassCopyHUD: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var checkTrim: CGFloat = 0
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 11) {
            // Checkmark circle
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 30, height: 30)

                CheckmarkPath()
                    .trim(from: 0, to: checkTrim)
                    .stroke(
                        Color.primary.opacity(0.80),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 15, height: 15)
                    .animation(
                        reduceMotion ? .none : .easeOut(duration: 0.34).delay(0.10),
                        value: checkTrim
                    )
            }

            Text("Link copied")
                .font(AMENFont.semiBold(16))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(
            ZStack {
                Capsule(style: .continuous).fill(.ultraThinMaterial)
                Capsule(style: .continuous).fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.70), Color.white.opacity(0.42)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        )
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.72), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.14), radius: 22, y: 6)
        .scaleEffect(appeared ? 1.0 : 0.76)
        .opacity(appeared ? 1.0 : 0)
        .onAppear {
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.15)
                    : .spring(response: 0.30, dampingFraction: 0.70)
            ) {
                appeared = true
            }
            checkTrim = 1
        }
    }
}

private struct CheckmarkPath: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.width * 0.18, y: rect.height * 0.52))
        p.addLine(to: CGPoint(x: rect.width * 0.42, y: rect.height * 0.76))
        p.addLine(to: CGPoint(x: rect.width * 0.82, y: rect.height * 0.26))
        return p
    }
}
