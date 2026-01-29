//
//  EnhancedUIComponents.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//

import SwiftUI

// MARK: - Elegant Loading Spinner (Matching Welcome Screen Aesthetic)
struct AmenLoadingSpinner: View {
    @State private var rotation: Double = 0
    var size: CGFloat = 50
    var lineWidth: CGFloat = 2
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
                .frame(width: size, height: size)
            
            // Animated arc
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.5)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(rotation))
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Elegant Button Style (Matching Dark Theme)
struct AmenButtonStyle: ButtonStyle {
    var isPrimary: Bool = true
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .light, design: .default))
            .tracking(1.5)
            .foregroundColor(isPrimary ? .black : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isPrimary ? Color.white : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: isPrimary ? 0 : 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Elegant Text Field (Dark Theme)
struct AmenTextField: View {
    var title: String
    @Binding var text: String
    var isSecure: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .light))
                .tracking(2)
                .foregroundColor(.white.opacity(0.6))
            
            Group {
                if isSecure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                }
            }
            .font(.system(size: 16, weight: .light))
            .foregroundColor(.white)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

// MARK: - Animated Gradient Background
struct AnimatedGradientBackground: View {
    @State private var animateGradient = false
    
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.15, green: 0.15, blue: 0.15),
                Color(red: 0.08, green: 0.08, blue: 0.08),
                Color.black
            ],
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}

// MARK: - Elegant Card Style
struct AmenCardStyle: ViewModifier {
    var opacity: Double = 0.05
    
    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(opacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.1),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
    }
}

extension View {
    func amenCardStyle(opacity: Double = 0.05) -> some View {
        modifier(AmenCardStyle(opacity: opacity))
    }
}

// MARK: - Shimmer Effect Modifier
struct ShimmerEffect: ViewModifier {
    @State private var offset: CGFloat = -200
    var duration: Double = 2.0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.4),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 100)
                    .offset(x: offset)
                    .blur(radius: 5)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    offset = 400
                }
            }
    }
}

extension View {
    func shimmerEffect(duration: Double = 2.0) -> some View {
        modifier(ShimmerEffect(duration: duration))
    }
}

// MARK: - Elegant Tab Bar Item
struct AmenTabBarItem: View {
    var icon: String
    var title: String
    var isSelected: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            
            Text(title)
                .font(.system(size: 10, weight: .light))
                .tracking(1)
                .foregroundColor(isSelected ? .white : .white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Blur Background
struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemMaterialDark
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

// MARK: - Haptic Feedback Helper
struct HapticFeedback {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
    
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Preview Examples
#Preview("Loading Spinner") {
    ZStack {
        Color.black.ignoresSafeArea()
        AmenLoadingSpinner()
    }
}

#Preview("Buttons") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 20) {
            Button("PRIMARY BUTTON") {}
                .buttonStyle(AmenButtonStyle(isPrimary: true))
            
            Button("SECONDARY BUTTON") {}
                .buttonStyle(AmenButtonStyle(isPrimary: false))
        }
        .padding()
    }
}

#Preview("Text Fields") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 20) {
            AmenTextField(title: "Email", text: .constant(""))
            AmenTextField(title: "Password", text: .constant(""), isSecure: true)
        }
        .padding()
    }
}

#Preview("Card Style") {
    ZStack {
        AnimatedGradientBackground()
        
        VStack(spacing: 20) {
            Text("AMEN")
                .font(.system(size: 32, weight: .thin, design: .serif))
                .tracking(8)
                .foregroundColor(.white)
            
            Text("This is a card with the elegant AMEN design aesthetic.")
                .font(.system(size: 14, weight: .light))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .amenCardStyle()
        .padding()
    }
}

#Preview("Tab Bar Items") {
    ZStack {
        Color.black.ignoresSafeArea()
        HStack(spacing: 0) {
            AmenTabBarItem(icon: "house.fill", title: "HOME", isSelected: true)
            AmenTabBarItem(icon: "message.fill", title: "MESSAGES", isSelected: false)
            AmenTabBarItem(icon: "plus.circle.fill", title: "CREATE", isSelected: false)
            AmenTabBarItem(icon: "books.vertical.fill", title: "RESOURCES", isSelected: false)
            AmenTabBarItem(icon: "person.fill", title: "PROFILE", isSelected: false)
        }
        .padding(.vertical, 12)
        .background(BlurView())
    }
}

#Preview("Shimmer Effect") {
    ZStack {
        Color.black.ignoresSafeArea()
        Text("AMEN")
            .font(.system(size: 64, weight: .thin, design: .serif))
            .tracking(10)
            .foregroundColor(.white)
            .shimmerEffect()
    }
}
