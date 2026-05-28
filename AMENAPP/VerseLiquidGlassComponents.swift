//
//  VerseLiquidGlassComponents.swift
//  AMENAPP
//
//  Liquid Glass design components for Scripture Drawer
//  Premium, minimal, Apple-quality glass materials and effects
//

import SwiftUI

// MARK: - Liquid Glass Design Tokens

struct VerseGlassTokens {
    // Glass materials
    static let glassFill = Color.white.opacity(0.08)
    static let glassStroke = Color.white.opacity(0.18)
    static let glassHighlight = Color.white.opacity(0.25)
    static let glassShadow = Color.black.opacity(0.06)
    
    // Depth and elevation
    static let elevationLight = Color.white.opacity(0.4)
    static let elevationDark = Color.black.opacity(0.12)
    
    // Accent (subtle, consistent with AMEN brand)
    static let accentPrimary = Color.blue.opacity(0.85)
    static let accentSubtle = Color.blue.opacity(0.12)
    static let accentGlow = Color.blue.opacity(0.2)
    
    // Corner radii
    static let radiusSmall: CGFloat = 12
    static let radiusMedium: CGFloat = 16
    static let radiusLarge: CGFloat = 20
    static let radiusXL: CGFloat = 28
    
    // Spacing
    static let spacingTight: CGFloat = 8
    static let spacingBase: CGFloat = 12
    static let spacingComfy: CGFloat = 16
    static let spacingLoose: CGFloat = 20
}

// MARK: - Liquid Glass Container

struct LiquidGlassContainer<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = VerseGlassTokens.radiusMedium
    var hasBorder: Bool = true
    var hasHighlight: Bool = true
    
    init(cornerRadius: CGFloat = VerseGlassTokens.radiusMedium, hasBorder: Bool = true, hasHighlight: Bool = true, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.hasBorder = hasBorder
        self.hasHighlight = hasHighlight
        self.content = content()
    }
    
    var body: some View {
        content
            .background {
                ZStack {
                    // Base glass fill
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(VerseGlassTokens.glassFill)
                    
                    // Inner highlight (top edge)
                    if hasHighlight {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        VerseGlassTokens.glassHighlight,
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                }
            }
            .overlay {
                if hasBorder {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(VerseGlassTokens.glassStroke, lineWidth: 0.5)
                }
            }
            .shadow(color: VerseGlassTokens.glassShadow, radius: 12, x: 0, y: 4)
    }
}

// MARK: - Verse Glass Capsule Button

struct VerseGlassCapsuleButton: View {
    let title: String
    let icon: String?
    let isSelected: Bool
    let action: () -> Void
    
    init(_ title: String, icon: String? = nil, isSelected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.systemScaled(12, weight: .medium))
                }
                Text(title)
                    .font(.systemScaled(13, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    Capsule()
                        .fill(VerseGlassTokens.accentPrimary)
                        .shadow(color: VerseGlassTokens.accentGlow, radius: 8, y: 3)
                } else {
                    Capsule()
                        .fill(VerseGlassTokens.glassFill)
                        .overlay {
                            Capsule()
                                .strokeBorder(VerseGlassTokens.glassStroke, lineWidth: 0.5)
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Icon Orb

struct GlassIconOrb: View {
    let icon: String
    var size: CGFloat = 48
    var iconSize: CGFloat = 22
    
    var body: some View {
        ZStack {
            Circle()
                .fill(VerseGlassTokens.glassFill)
                .overlay {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [VerseGlassTokens.glassHighlight, Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    Circle()
                        .strokeBorder(VerseGlassTokens.glassStroke, lineWidth: 0.5)
                }
            
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(VerseGlassTokens.accentPrimary)
        }
        .frame(width: size, height: size)
        .shadow(color: VerseGlassTokens.glassShadow, radius: 8, y: 3)
    }
}

// MARK: - Drag Handle

struct GlassDragHandle: View {
    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 36, height: 4.5)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

// MARK: - Search Capsule with Rotating Placeholder

struct VerseSearchCapsule: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onSubmit: () -> Void
    let onClear: () -> Void
    
    @State private var placeholderIndex = 0
    @State private var placeholderOpacity: Double = 1.0
    
    private let placeholders = [
        "John 3:16",
        "verse about peace",
        "strength",
        "Philippians 4:13",
        "hope",
        "fear not",
        "David",
        "verse for today",
        "Christmas",
        "Paul on love"
    ]
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.systemScaled(16, weight: isFocused ? .semibold : .medium))
                .foregroundStyle(isFocused ? VerseGlassTokens.accentPrimary : Color.secondary)
            
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholders[placeholderIndex])
                        .font(.systemScaled(15))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .opacity(placeholderOpacity)
                }
                
                TextField("", text: $text)
                    .font(.systemScaled(15))
                    .foregroundStyle(Color.primary)
                    .focused($isFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit(onSubmit)
            }
            
            if !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(16))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            Capsule()
                .fill(VerseGlassTokens.glassFill)
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [VerseGlassTokens.glassHighlight, Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            isFocused ? VerseGlassTokens.accentPrimary.opacity(0.4) : VerseGlassTokens.glassStroke,
                            lineWidth: isFocused ? 1.5 : 0.5
                        )
                }
        }
        .shadow(color: VerseGlassTokens.glassShadow, radius: isFocused ? 16 : 8, y: isFocused ? 6 : 3)
        .animation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8)), value: isFocused)
        .onAppear {
            startPlaceholderRotation()
        }
    }
    
    private func startPlaceholderRotation() {
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            guard text.isEmpty && !isFocused else { return }
            
            withAnimation(.easeOut(duration: 0.3)) {
                placeholderOpacity = 0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                placeholderIndex = (placeholderIndex + 1) % placeholders.count
                
                withAnimation(.easeIn(duration: 0.3)) {
                    placeholderOpacity = 1.0
                }
            }
        }
    }
}

// MARK: - Suggestion Chip

struct VerseSuggestionChip: View {
    let suggestion: VerseSuggestion
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: suggestion.icon)
                    .font(.systemScaled(11, weight: .medium))
                Text(suggestion.title)
                    .font(.systemScaled(13, weight: .medium))
            }
            .foregroundStyle(VerseGlassTokens.accentPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                Capsule()
                    .fill(VerseGlassTokens.accentSubtle)
                    .overlay {
                        Capsule()
                            .strokeBorder(VerseGlassTokens.accentPrimary.opacity(0.2), lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Verse Result Card (Liquid Glass)

struct VerseResultCard: View {
    let result: SmartVerseResult
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    // Reference row
                    HStack(spacing: 8) {
                        Text(result.verse.reference.displayString)
                            .font(.systemScaled(14, weight: .bold))
                            .foregroundStyle(isSelected ? VerseGlassTokens.accentPrimary : Color.primary)
                        
                        Text(result.verse.translation)
                            .font(.systemScaled(10, weight: .semibold))
                            .foregroundStyle(isSelected ? VerseGlassTokens.accentPrimary : Color.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                Capsule()
                                    .fill(isSelected ? VerseGlassTokens.accentSubtle : Color.primary.opacity(0.06))
                            }
                    }
                    
                    // Verse text
                    Text(result.verse.text)
                        .font(.systemScaled(13.5))
                        .foregroundStyle(Color.primary.opacity(0.8))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Topic chips (if any)
                    if !result.topics.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(result.topics.prefix(2), id: \.self) { topic in
                                Text(topic.rawValue)
                                    .font(.systemScaled(10, weight: .medium))
                                    .foregroundStyle(Color.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background {
                                        Capsule()
                                            .fill(Color.primary.opacity(0.05))
                                    }
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Selection indicator
                ZStack {
                    Circle()
                        .fill(isSelected ? VerseGlassTokens.accentPrimary : VerseGlassTokens.glassFill)
                        .frame(width: 28, height: 28)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.systemScaled(12, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.clear : VerseGlassTokens.glassStroke,
                            lineWidth: 0.5
                        )
                }
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: VerseGlassTokens.radiusMedium, style: .continuous)
                    .fill(isSelected ? VerseGlassTokens.accentSubtle : VerseGlassTokens.glassFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: VerseGlassTokens.radiusMedium, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [VerseGlassTokens.glassHighlight, Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: VerseGlassTokens.radiusMedium, style: .continuous)
                            .strokeBorder(
                                isSelected ? VerseGlassTokens.accentPrimary.opacity(0.3) : VerseGlassTokens.glassStroke,
                                lineWidth: isSelected ? 1.5 : 0.5
                            )
                    }
            }
            .shadow(color: isSelected ? VerseGlassTokens.accentGlow : VerseGlassTokens.glassShadow, radius: isSelected ? 12 : 6, y: isSelected ? 6 : 3)
            .scaleEffect(isSelected ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75)), value: isSelected)
    }
}

// MARK: - Selected Verse Footer (Sticky)

struct SelectedVerseFooter: View {
    let verse: BibleVerse
    let onAttach: () -> Void
    let onClear: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Subtle top divider
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
            
            HStack(spacing: 12) {
                // Verse preview
                VStack(alignment: .leading, spacing: 4) {
                    Text(verse.reference.displayString)
                        .font(.systemScaled(13, weight: .bold))
                        .foregroundStyle(VerseGlassTokens.accentPrimary)
                    
                    Text(verse.text)
                        .font(.systemScaled(12))
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Clear button
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 32, height: 32)
                        .background {
                            Circle()
                                .fill(VerseGlassTokens.glassFill)
                        }
                }
                .buttonStyle(.plain)
                
                // Attach button
                Button(action: onAttach) {
                    Text("Attach")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .background {
                            Capsule()
                                .fill(VerseGlassTokens.accentPrimary)
                        }
                        .shadow(color: VerseGlassTokens.accentGlow, radius: 10, y: 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [VerseGlassTokens.glassHighlight, Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
            }
        }
    }
}
