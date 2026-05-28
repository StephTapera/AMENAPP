// BereanEnhancedComponents.swift
// AMEN App — Premium Liquid Glass components for Berean AI
// ChatGPT-level visual polish with spiritual grounding

import SwiftUI

// ─── MARK: Smart Suggestion Pills ──────────────────────────────────────────
/// Intelligent suggestion pills that appear contextually under the composer

struct BereanSmartSuggestionPills: View {
    let suggestions: [String]
    let onSelect: (String) -> Void
    
    @State private var appeared = false
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    SuggestionPill(text: suggestion) {
                        onSelect(suggestion)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.68)
                            .delay(Double(index) * 0.06),
                        value: appeared
                    )
                }
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            withAnimation {
                appeared = true
            }
        }
    }
}

private struct SuggestionPill: View {
    let text: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AmenColor.titleText)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.82))
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.60),
                                            Color.white.opacity(0.10)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.75
                                )
                        )
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                )
        }
        .buttonStyle(GlassPressStyle())
    }
}

// ─── MARK: Enhanced Response Card ──────────────────────────────────────────
/// Premium response card with action chips and contextual tools

struct BereanEnhancedResponseCard: View {
    let message: BereanChatMsg
    let onCopy: () -> Void
    let onShare: () -> Void
    let onAskDeeper: () -> Void
    
    @State private var showActions = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Message content
            Text(message.content)
                .font(AMENFont.regular(16))
                .foregroundStyle(.primary)
                .lineSpacing(3)
            
            // Action chips
            if showActions {
                HStack(spacing: 8) {
                    ResponseActionChip(icon: "doc.on.doc", label: "Copy", action: onCopy)
                    ResponseActionChip(icon: "square.and.arrow.up", label: "Share", action: onShare)
                    ResponseActionChip(icon: "arrow.turn.down.right", label: "Ask deeper", action: onAskDeeper)
                    Spacer()
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.90).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.70)) {
                showActions.toggle()
            }
        }
    }
}

private struct ResponseActionChip: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(AmenColor.mutedText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.70))
                    .overlay(Capsule().stroke(AmenColor.divider, lineWidth: 0.5))
            )
        }
        .buttonStyle(GlassPressStyle())
    }
}

// ─── MARK: Streaming Text View ─────────────────────────────────────────────
/// Elegant typewriter effect for streaming responses

struct BereanStreamingText: View {
    let fullText: String
    let isComplete: Bool
    
    @State private var displayedText = ""
    @State private var cursorVisible = true
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            Text(displayedText)
                .font(.system(size: 15))
                .foregroundColor(AmenColor.bereanBubbleText)
            
            if !isComplete {
                Text("▌")
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(AmenColor.accent)
                    .opacity(cursorVisible ? 1 : 0.2)
            }
        }
        .onChange(of: fullText) { newText in
            displayedText = newText
        }
        .onAppear {
            startCursorBlink()
        }
    }
    
    private func startCursorBlink() {
        Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                cursorVisible.toggle()
            }
        }
    }
}

// ─── MARK: Context-Aware Floating Toolbar ──────────────────────────────────
/// Toolbar that adapts based on scroll position and focus state

struct BereanContextToolbar: View {
    @Binding var isScrolling: Bool
    @Binding var isFocused: Bool
    
    let onNewChat: () -> Void
    let onHistory: () -> Void
    let onSettings: () -> Void
    
    @State private var toolbarOpacity: Double = 1.0
    @State private var toolbarScale: CGFloat = 1.0
    
    var body: some View {
        HStack(spacing: 16) {
            ToolbarButton(icon: "plus.message", action: onNewChat)
            ToolbarButton(icon: "clock.arrow.circlepath", action: onHistory)
            Spacer()
            ToolbarButton(icon: "gearshape", action: onSettings)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.88))
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().stroke(Color.white.opacity(0.40), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 6)
        )
        .opacity(toolbarOpacity)
        .scaleEffect(toolbarScale)
        .onChange(of: isScrolling) { scrolling in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                toolbarOpacity = scrolling ? 0.3 : 1.0
                toolbarScale = scrolling ? 0.94 : 1.0
            }
        }
        .onChange(of: isFocused) { focused in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                toolbarOpacity = focused ? 0 : 1.0
                toolbarScale = focused ? 0.90 : 1.0
            }
        }
    }
}

private struct ToolbarButton: View {
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AmenColor.titleText)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(GlassPressStyle())
    }
}

// ─── MARK: Morphing Mode Selector ──────────────────────────────────────────
/// Premium segmented control that morphs between modes

struct BereanMorphingModeSelector: View {
    @Binding var selectedMode: BereanQuickMode
    @Namespace private var animation
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(BereanQuickMode.allCases) { mode in
                BereanModeButton(
                    mode: mode,
                    isSelected: selectedMode == mode,
                    namespace: animation,
                    action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.68)) {
                            selectedMode = mode
                        }
                    }
                )
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.70))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.30), lineWidth: 0.75)
                )
        )
    }
}

private struct BereanModeButton: View {
    let mode: BereanQuickMode
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(mode.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? AmenColor.titleText : AmenColor.mutedText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
                        .matchedGeometryEffect(id: "mode_background", in: namespace)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// ─── MARK: Liquid Loading State ────────────────────────────────────────────
/// Premium loading indicator for Berean responses

struct BereanLiquidLoadingState: View {
    @State private var phase: CGFloat = 0
    
    private func dotOpacity(for index: Int) -> Double {
        let phaseValue = Double(phase)
        return 0.5 + 0.3 * sin(phaseValue * 2 * .pi - Double(index) * 0.5)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.88))
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().stroke(Color.white.opacity(0.30), lineWidth: 0.75))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AmenColor.accent)
                    .rotationEffect(.degrees(phase * 360))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Berean is thinking...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AmenColor.titleText)
                
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(AmenColor.accent.opacity(dotOpacity(for: index)))
                            .frame(width: 4, height: 4)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.70))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.30), lineWidth: 0.75)
                )
        )
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

// ─── MARK: Scripture Reference Card ────────────────────────────────────────
/// Beautiful card for scripture references in responses

struct BereanScriptureReferenceCard: View {
    let reference: String
    let verse: String
    let onOpen: () -> Void
    
    @State private var appeared = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AmenColor.accent)
                
                Text(reference)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AmenColor.accent)
                
                Spacer()
                
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AmenColor.accent)
                }
            }
            
            Text(verse)
                .font(.system(size: 14))
                .foregroundColor(AmenColor.bodyText)
                .lineSpacing(4)
                .italic()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AmenColor.accentMuted.opacity(0.20))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AmenColor.accent.opacity(0.20), lineWidth: 1)
                )
        )
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.94)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.68).delay(0.1)) {
                appeared = true
            }
        }
    }
}

// ─── MARK: Daily Training Prompt Card ──────────────────────────────────────
/// Card for community-based obedience actions

struct BereanDailyTrainingPromptCard: View {
    let prompt: String
    let icon: String
    let onComplete: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AmenColor.accentMuted)
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(AmenColor.accent)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Challenge")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AmenColor.mutedText)
                    .textCase(.uppercase)
                
                Text(prompt)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AmenColor.titleText)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button(action: onComplete) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(AmenColor.accent)
            }
            .buttonStyle(GlassPressStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.88))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.70),
                                    Color.white.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 6)
        )
    }
}

// ─── MARK: Long-Press Context Menu ─────────────────────────────────────────
/// Liquid expansion context menu for message actions

struct BereanLongPressContextMenu: View {
    let actions: [ContextAction]
    
    @State private var appeared = false
    
    struct ContextAction: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let action: () -> Void
    }
    
    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                Button(action: action.action) {
                    HStack(spacing: 12) {
                        Image(systemName: action.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AmenColor.titleText)
                            .frame(width: 20)
                        
                        Text(action.label)
                            .font(.system(size: 15))
                            .foregroundColor(AmenColor.titleText)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.001))
                }
                .buttonStyle(.plain)
                .opacity(appeared ? 1 : 0)
                .offset(x: appeared ? 0 : -10)
                .animation(
                    .spring(response: 0.4, dampingFraction: 0.68)
                        .delay(Double(index) * 0.04),
                    value: appeared
                )
                
                if index < actions.count - 1 {
                    Divider()
                        .padding(.leading, 48)
                }
            }
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.95))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.40), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 12)
        )
        .scaleEffect(appeared ? 1 : 0.88, anchor: .top)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.70)) {
                appeared = true
            }
        }
    }
}
