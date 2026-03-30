//
//  FeedSessionStopScreen.swift
//  AMENAPP
//
//  Finite feed session Stop Screen.
//  Shown at the end of each session (default: 15 cards).
//  User must make a deliberate choice — scroll does NOT continue automatically.
//
//  Actions:
//    Reflect  — single guided reflection prompt
//    Pray     — opens Prayer tab or inline guided prayer
//    Save     — save 1 thing you read
//    Close    — exit feed (most encouraged action)
//    Continue — deliberate tap to extend session (max 2 extensions per sitting)
//

import SwiftUI

// MARK: - Feed Session Stop Screen

struct FeedSessionStopScreen: View {
    @ObservedObject private var session = FeedSessionManager.shared
    
    /// Called when user chooses to continue scrolling (deliberate tap)
    var onContinue: () -> Void
    /// Called when user closes the app/feed
    var onClose: () -> Void
    
    @State private var selectedAction: StopAction? = nil
    @State private var showReflectionPrompt = false
    @State private var showGuidedPrayer = false
    @State private var appeared = false
    
    private let reflectionPrompts = [
        "What's one thing you read today that you want to remember?",
        "Did anything in the feed challenge or encourage your faith?",
        "Is there someone you want to pray for after scrolling today?",
        "What's one step you could take today based on what you read?",
        "How do you feel right now? Grateful? Inspired? Unsettled?"
    ]
    
    @State private var currentPrompt = ""
    
    enum StopAction: Identifiable {
        case reflect, pray, save, close
        var id: Self { self }
    }
    
    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.7)
                    
                    Text("You've reached your session")
                        .font(.custom("OpenSans-Bold", size: 22))
                        .multilineTextAlignment(.center)
                    
                    Text("Take a moment before continuing.")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
                .padding(.horizontal, 32)
                
                Spacer().frame(height: 40)
                
                // Action buttons
                VStack(spacing: 12) {
                    stopActionButton(
                        icon: "lightbulb",
                        title: "Reflect",
                        subtitle: "One question to sit with",
                        color: Color.primary
                    ) {
                        currentPrompt = reflectionPrompts.randomElement() ?? reflectionPrompts[0]
                        showReflectionPrompt = true
                    }
                    
                    stopActionButton(
                        icon: "hands.sparkles.fill",
                        title: "Pray",
                        subtitle: "A moment of guided prayer",
                        color: Color.primary
                    ) {
                        showGuidedPrayer = true
                    }
                    
                    stopActionButton(
                        icon: "bookmark",
                        title: "Save 1 thing",
                        subtitle: "Bookmark something worth keeping",
                        color: Color.primary
                    ) {
                        // Navigate to saved posts — close session and go to profile saved tab
                        session.endSession()
                        onClose()
                    }
                    
                    // Close (most encouraged)
                    Button(action: {
                        session.endSession()
                        onClose()
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 18, weight: .medium))
                            Text("Close for now")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                            Spacer()
                            Text("Good stopping point")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.primary.opacity(0.07))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                        .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                
                Spacer().frame(height: 32)
                
                // Continue option — de-emphasized, deliberate tap required
                continueSection
                    .opacity(appeared ? 1 : 0)
                
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                appeared = true
            }
        }
        .sheet(isPresented: $showReflectionPrompt) {
            ReflectionPromptSheet(prompt: currentPrompt) {
                showReflectionPrompt = false
            }
        }
        .sheet(isPresented: $showGuidedPrayer) {
            GuidedPrayerSheet {
                showGuidedPrayer = false
            }
        }
    }
    
    // MARK: - Continue Section
    
    @ViewBuilder
    private var continueSection: some View {
        let canExtend = session.sessionExtensionsUsed < 2
        
        VStack(spacing: 6) {
            if canExtend {
                Button(action: {
                    session.extendSession()
                    onContinue()
                }) {
                    Text("Continue scrolling")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .underline()
                }
                
                Text("\(2 - session.sessionExtensionsUsed) extension\(2 - session.sessionExtensionsUsed == 1 ? "" : "s") remaining today")
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                Text("You've used your extensions for this session.")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
    
    // MARK: - Stop Action Button
    
    private func stopActionButton(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom("OpenSans-SemiBold", size: 16))
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
            )
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reflection Prompt Sheet

struct ReflectionPromptSheet: View {
    let prompt: String
    var onDismiss: () -> Void
    
    @State private var reflectionText = ""
    @FocusState private var isTextFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Reflect", systemImage: "lightbulb")
                        .font(.custom("OpenSans-Bold", size: 18))
                    
                    Text(prompt)
                        .font(.custom("OpenSans-Regular", size: 17))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal)
                .padding(.top)
                
                TextEditor(text: $reflectionText)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 120)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .focused($isTextFocused)
                    .padding(.horizontal)
                
                Text("Your reflection stays private on this device.")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Save locally if non-empty
                        if !reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            saveReflectionLocally(reflectionText)
                        }
                        onDismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { isTextFocused = true }
    }
    
    private func saveReflectionLocally(_ text: String) {
        var reflections = UserDefaults.standard.array(forKey: "feedReflections") as? [[String: String]] ?? []
        reflections.append(["text": text, "date": ISO8601DateFormatter().string(from: Date())])
        // Keep last 30 reflections
        if reflections.count > 30 { reflections = Array(reflections.suffix(30)) }
        UserDefaults.standard.set(reflections, forKey: "feedReflections")
    }
}

// MARK: - Guided Prayer Sheet

struct GuidedPrayerSheet: View {
    var onDismiss: () -> Void
    
    private let prayerSteps: [(String, String)] = [
        ("Stillness", "Take a breath. God is here."),
        ("Gratitude", "Thank God for one thing from today."),
        ("Others", "Think of someone you encountered or read about. Lift them up."),
        ("Yourself", "What do you need today? Ask honestly."),
        ("Release", "Leave your phone and the feed behind. Walk in peace.")
    ]
    
    @State private var currentStep = 0
    @State private var appeared = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack(spacing: 6) {
                ForEach(0..<prayerSteps.count, id: \.self) { i in
                    Capsule()
                        .fill(i <= currentStep ? Color.primary : Color.primary.opacity(0.15))
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            Spacer()
            
            // Step content
            VStack(spacing: 20) {
                Text(prayerSteps[currentStep].0)
                    .font(.custom("OpenSans-Bold", size: 13))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(2)
                
                Text(prayerSteps[currentStep].1)
                    .font(.custom("OpenSans-Regular", size: 22))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .id(currentStep) // Re-animate on step change
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { appeared = true }
            }
            .onChange(of: currentStep) { _, _ in
                appeared = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(0.05)) { appeared = true }
            }
            
            Spacer()
            
            // Navigation
            HStack {
                if currentStep > 0 {
                    Button(action: { currentStep -= 1 }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .padding(14)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                    .foregroundStyle(.primary)
                }
                
                Spacer()
                
                if currentStep < prayerSteps.count - 1 {
                    Button(action: { currentStep += 1 }) {
                        Text("Next")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(Color.primary)
                            .foregroundStyle(Color(.systemBackground))
                            .clipShape(Capsule())
                    }
                } else {
                    Button(action: onDismiss) {
                        Text("Amen")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(Color.primary)
                            .foregroundStyle(Color(.systemBackground))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .presentationDetents([.medium, .large])
    }
}
