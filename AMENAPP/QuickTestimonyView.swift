//
//  QuickTestimonyView.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//

import SwiftUI

// MARK: - Quick Testimony Popup
struct QuickTestimonyView: View {
    @Environment(\.dismiss) var dismiss
    @State private var testimonyText = ""
    @State private var selectedCategory: QuickTestimonyCategory = .healing
    @State private var isPosting = false
    @State private var showSuccessAnimation = false
    @State private var characterWarningShake = false
    @FocusState private var isTextFieldFocused: Bool
    
    // Character limits
    private let maxCharacters = 280
    private let warningThreshold = 260
    
    // Haptic feedback
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)
    private let hapticMedium = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        ZStack {
            // Dismiss on background tap
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissKeyboard()
                }
            
            VStack(spacing: 0) {
                Spacer()
                
                // Main Content Card
                VStack(spacing: 0) {
                    // Header
                    headerSection
                    
                    // Category Selector
                    categorySection
                    
                    // Text Input
                    textInputSection
                    
                    // Character Counter
                    characterCounterSection
                    
                    // Quick Tips
                    quickTipsSection
                    
                    // Action Buttons
                    actionButtonsSection
                }
                .background(liquidGlassBackground)
                .cornerRadius(24, corners: [.topLeft, .topRight])
                .shadow(color: .black.opacity(0.3), radius: 30, y: -10)
            }
            .ignoresSafeArea(edges: .bottom)
            
            // Success Animation Overlay
            if showSuccessAnimation {
                successAnimationOverlay
            }
        }
        .onAppear {
            hapticLight.prepare()
            hapticMedium.prepare()
            // Auto-focus text field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.pink, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Quick Testimony")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                Text("Share God's goodness in your life")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            Button {
                hapticLight.impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.5))
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }
    
    // MARK: - Category Section
    private var categorySection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(QuickTestimonyCategory.allCases, id: \.self) { category in
                    QuickTestimonyCategoryChip(
                        category: category,
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedCategory = category
                            hapticLight.impactOccurred()
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Text Input Section
    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedCategory.prompt)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 24)
            
            TextEditor(text: $testimonyText)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.white)
                .focused($isTextFieldFocused)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120, maxHeight: 180)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    isTextFieldFocused ? Color.white.opacity(0.3) : Color.white.opacity(0.1),
                                    lineWidth: 1
                                )
                        )
                )
                .padding(.horizontal, 24)
                .onChange(of: testimonyText) { _, newValue in
                    if newValue.count > maxCharacters {
                        testimonyText = String(newValue.prefix(maxCharacters))
                        hapticMedium.impactOccurred()
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
                            characterWarningShake = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            characterWarningShake = false
                        }
                    }
                }
        }
    }
    
    // MARK: - Character Counter Section
    private var characterCounterSection: some View {
        HStack {
            Spacer()
            
            HStack(spacing: 8) {
                // Warning icon
                if testimonyText.count >= warningThreshold {
                    Image(systemName: testimonyText.count == maxCharacters ? "exclamationmark.circle.fill" : "exclamationmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(testimonyText.count == maxCharacters ? .red : .orange)
                        .symbolEffect(.bounce, value: testimonyText.count == maxCharacters)
                }
                
                // Character count
                HStack(spacing: 4) {
                    Text("\(testimonyText.count)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(characterCountColor)
                        .contentTransition(.numericText())
                    
                    Text("/")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.4))
                    
                    Text("\(maxCharacters)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(characterCountBackgroundColor)
                        .overlay(
                            Capsule()
                                .stroke(characterCountBorderColor, lineWidth: 1)
                        )
                )
                
                // Progress ring
                if testimonyText.count >= warningThreshold {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 2.5)
                            .frame(width: 28, height: 28)
                        
                        Circle()
                            .trim(from: 0, to: characterProgress)
                            .stroke(characterProgressColor, lineWidth: 2.5)
                            .frame(width: 28, height: 28)
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: characterProgress)
                    }
                }
            }
            .offset(x: characterWarningShake ? -5 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.3).repeatCount(3, autoreverses: true), value: characterWarningShake)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
    
    // MARK: - Quick Tips Section
    private var quickTipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.yellow.opacity(0.8))
                
                Text("Quick Tips")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            HStack(spacing: 12) {
                ForEach(selectedCategory.tips, id: \.self) { tip in
                    Text(tip)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        )
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }
    
    // MARK: - Action Buttons Section
    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            // Cancel Button
            Button {
                hapticLight.impactOccurred()
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.08))
                    )
            }
            
            // Post Button
            Button {
                postTestimony()
            } label: {
                HStack(spacing: 8) {
                    if isPosting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                        
                        Text("Share Testimony")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            canPost ?
                            LinearGradient(
                                colors: [Color.pink, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(
                            color: canPost ? Color.pink.opacity(0.4) : Color.clear,
                            radius: canPost ? 12 : 0,
                            y: canPost ? 6 : 0
                        )
                )
            }
            .disabled(!canPost || isPosting)
            .scaleEffect(canPost ? 1.0 : 0.97)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canPost)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }
    
    // MARK: - Liquid Glass Background
    private var liquidGlassBackground: some View {
        ZStack {
            // Base dark layer
            Rectangle()
                .fill(Color(red: 0.12, green: 0.12, blue: 0.12))
            
            // Glass layer
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Blur overlay
            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.8))
            
            // Border highlight
            VStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.1),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 1)
                
                Spacer()
            }
        }
    }
    
    // MARK: - Success Animation
    private var successAnimationOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Success checkmark
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.green, Color.mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .shadow(color: .green.opacity(0.5), radius: 20, y: 10)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(showSuccessAnimation ? 1.0 : 0.5)
                .opacity(showSuccessAnimation ? 1.0 : 0)
                
                Text("Testimony Shared!")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(showSuccessAnimation ? 1.0 : 0)
                    .offset(y: showSuccessAnimation ? 0 : 20)
            }
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    showSuccessAnimation = true
                }
            }
        }
        .transition(.opacity)
    }
    
    // MARK: - Computed Properties
    
    private var canPost: Bool {
        !testimonyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        testimonyText.count <= maxCharacters &&
        !isPosting
    }
    
    private var characterProgress: CGFloat {
        min(CGFloat(testimonyText.count) / CGFloat(maxCharacters), 1.0)
    }
    
    private var characterCountColor: Color {
        if testimonyText.count == maxCharacters {
            return .red
        } else if testimonyText.count >= warningThreshold {
            return .orange
        } else {
            return .white
        }
    }
    
    private var characterCountBackgroundColor: Color {
        if testimonyText.count == maxCharacters {
            return Color.red.opacity(0.15)
        } else if testimonyText.count >= warningThreshold {
            return Color.orange.opacity(0.15)
        } else {
            return Color.white.opacity(0.1)
        }
    }
    
    private var characterCountBorderColor: Color {
        if testimonyText.count == maxCharacters {
            return Color.red.opacity(0.3)
        } else if testimonyText.count >= warningThreshold {
            return Color.orange.opacity(0.3)
        } else {
            return Color.white.opacity(0.2)
        }
    }
    
    private var characterProgressColor: LinearGradient {
        if testimonyText.count == maxCharacters {
            return LinearGradient(colors: [.red, .red.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
        } else if testimonyText.count >= warningThreshold {
            return LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
        } else {
            return LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
        }
    }
    
    // MARK: - Helper Functions
    
    private func dismissKeyboard() {
        isTextFieldFocused = false
    }
    
    private func postTestimony() {
        guard canPost else { return }
        
        isPosting = true
        hapticMedium.impactOccurred()
        
        // Simulate posting
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isPosting = false
            showSuccessAnimation = true
            
            let successHaptic = UINotificationFeedbackGenerator()
            successHaptic.notificationOccurred(.success)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        }
    }
}

// MARK: - Quick Testimony Category
enum QuickTestimonyCategory: String, CaseIterable {
    case healing = "Healing"
    case provision = "Provision"
    case breakthrough = "Breakthrough"
    case answered = "Answered Prayer"
    case guidance = "Guidance"
    case restoration = "Restoration"
    
    var icon: String {
        switch self {
        case .healing: return "heart.fill"
        case .provision: return "gift.fill"
        case .breakthrough: return "bolt.fill"
        case .answered: return "hands.sparkles.fill"
        case .guidance: return "location.fill"
        case .restoration: return "arrow.triangle.2.circlepath"
        }
    }
    
    var color: Color {
        switch self {
        case .healing: return .pink
        case .provision: return .green
        case .breakthrough: return .orange
        case .answered: return .purple
        case .guidance: return .blue
        case .restoration: return .cyan
        }
    }
    
    var prompt: String {
        switch self {
        case .healing:
            return "How did God heal you or someone you love?"
        case .provision:
            return "How did God provide for your needs?"
        case .breakthrough:
            return "What breakthrough did you experience?"
        case .answered:
            return "How did God answer your prayers?"
        case .guidance:
            return "How did God guide your path?"
        case .restoration:
            return "What did God restore in your life?"
        }
    }
    
    var tips: [String] {
        switch self {
        case .healing:
            return ["Be specific", "Share emotions", "Give glory to God"]
        case .provision:
            return ["Share the need", "The answer", "Your gratitude"]
        case .breakthrough:
            return ["The struggle", "The victory", "The lesson"]
        case .answered:
            return ["The prayer", "The answer", "The timing"]
        case .guidance:
            return ["The question", "God's answer", "The result"]
        case .restoration:
            return ["What was lost", "How God restored", "The joy"]
        }
    }
}

// MARK: - Quick Testimony Category Chip
struct QuickTestimonyCategoryChip: View {
    let category: QuickTestimonyCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 12, weight: .semibold))
                
                Text(category.rawValue)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(
                        isSelected ?
                        LinearGradient(
                            colors: [category.color, category.color.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ) :
                        LinearGradient(
                            colors: [Color.white.opacity(0.1), Color.white.opacity(0.1)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(
                        color: isSelected ? category.color.opacity(0.3) : Color.clear,
                        radius: isSelected ? 8 : 0,
                        y: isSelected ? 4 : 0
                    )
            )
        }
        .scaleEffect(isSelected ? 1.0 : 0.95)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Helper Extension for Rounded Corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Spacer()
            Text("Main Content")
            Spacer()
        }
    }
    .overlay {
        QuickTestimonyView()
    }
}
