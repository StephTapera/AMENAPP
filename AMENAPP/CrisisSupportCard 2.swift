//
//  CrisisSupportCard.swift
//  AMENAPP
//
//  Gentle, supportive crisis intervention UI
//  Non-punitive, compassionate design
//

import SwiftUI
import FirebaseAuth

// MARK: - Crisis Support Card

/// Main support card shown for moderate/high/critical risk
struct CrisisSupportCard: View {
    let riskAssessment: CrisisRiskAssessment
    let onDismiss: () -> Void
    let onCallHotline: () -> Void
    let onTextCrisisLine: () -> Void
    let onNotifyTrusted: () -> Void
    let onGroundingExercise: () -> Void
    
    @State private var showDontShowAgain = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header - calm, supportive
            VStack(spacing: 16) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("You're not alone")
                    .font(.custom("OpenSans-Bold", size: 24))
                    .foregroundStyle(.primary)
                
                Text("It sounds like you're going through a lot. There are people who care and want to help.")
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 32)
            .padding(.horizontal, 24)
            
            // Support options
            ScrollView {
                VStack(spacing: 12) {
                    // 988 Hotline (primary)
                    SupportOptionButton(
                        icon: "phone.fill",
                        title: "Call 988",
                        subtitle: "Talk to someone now (24/7)",
                        color: .blue,
                        isPrimary: true,
                        action: onCallHotline
                    )
                    
                    // Crisis Text Line
                    SupportOptionButton(
                        icon: "message.fill",
                        title: "Text Crisis Line",
                        subtitle: "Text HOME to 741741",
                        color: .cyan,
                        isPrimary: false,
                        action: onTextCrisisLine
                    )
                    
                    // Trusted person
                    if riskAssessment.riskLevel == .high || riskAssessment.riskLevel == .critical {
                        SupportOptionButton(
                            icon: "person.2.fill",
                            title: "Notify a trusted person",
                            subtitle: "Let someone know you need support",
                            color: .purple,
                            isPrimary: false,
                            action: onNotifyTrusted
                        )
                    }
                    
                    // Grounding exercise
                    SupportOptionButton(
                        icon: "wind",
                        title: "Try a grounding exercise",
                        subtitle: "60 seconds to calm your mind",
                        color: .green,
                        isPrimary: false,
                        action: onGroundingExercise
                    )
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
            
            Divider()
            
            // Footer - dismissal options
            VStack(spacing: 12) {
                Button {
                    onDismiss()
                } label: {
                    Text("I'm okay for now")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 16)
                
                Button {
                    showDontShowAgain = true
                } label: {
                    Text("Don't show this again")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 16)
            }
        }
        .background(Color(.systemBackground))
        .alert("Pause Support Prompts?", isPresented: $showDontShowAgain) {
            Button("24 hours", role: .none) {
                Task {
                    if let userId = Auth.auth().currentUser?.uid {
                        try? await EnhancedCrisisSupportService.shared.dismissSupport(userId: userId, durationHours: 24)
                    }
                }
                onDismiss()
            }
            Button("1 week", role: .none) {
                Task {
                    if let userId = Auth.auth().currentUser?.uid {
                        try? await EnhancedCrisisSupportService.shared.dismissSupport(userId: userId, durationHours: 168)
                    }
                }
                onDismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("AMEN can pause support prompts for a while. You can always turn them back on in Settings → Safety.")
        }
    }
}

// MARK: - Support Option Button

struct SupportOptionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isPrimary: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(color.opacity(isPrimary ? 0.15 : 0.1))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.custom("OpenSans-SemiBold", size: 17))
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                isPrimary ? color.opacity(0.3) : Color.clear,
                                lineWidth: isPrimary ? 2 : 0
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Subtle Support Link

/// Small "Need support?" link for low-risk situations
struct SubtleSupportLink: View {
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                
                Text("Need support?")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Grounding Exercise View

struct GroundingExerciseView: View {
    let exercise: GroundingExercise
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var isComplete = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Calm gradient background
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.2, blue: 0.4),
                        Color(red: 0.2, green: 0.3, blue: 0.5)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 32) {
                    if !isComplete {
                        // Exercise in progress
                        VStack(spacing: 24) {
                            Image(systemName: exercise.type.icon)
                                .font(.system(size: 64))
                                .foregroundStyle(.white.opacity(0.9))
                            
                            Text(exercise.name)
                                .font(.custom("OpenSans-Bold", size: 24))
                                .foregroundStyle(.white)
                            
                            // Current step
                            Text(exercise.steps[currentStep])
                                .font(.custom("OpenSans-SemiBold", size: 20))
                                .foregroundStyle(.white.opacity(0.95))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            // Progress indicator
                            HStack(spacing: 8) {
                                ForEach(0..<exercise.steps.count, id: \.self) { index in
                                    Circle()
                                        .fill(index <= currentStep ? Color.white : Color.white.opacity(0.3))
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .padding(.top, 16)
                        }
                        
                        Spacer()
                        
                        // Next button
                        Button {
                            if currentStep < exercise.steps.count - 1 {
                                withAnimation {
                                    currentStep += 1
                                }
                            } else {
                                withAnimation {
                                    isComplete = true
                                }
                            }
                        } label: {
                            Text(currentStep < exercise.steps.count - 1 ? "Next" : "Finish")
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.2))
                                )
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                    } else {
                        // Complete
                        VStack(spacing: 24) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 72))
                                .foregroundStyle(.white)
                            
                            Text("Well done")
                                .font(.custom("OpenSans-Bold", size: 28))
                                .foregroundStyle(.white)
                            
                            Text("How are you feeling now?")
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundStyle(.white.opacity(0.8))
                            
                            Button {
                                dismiss()
                            } label: {
                                Text("Close")
                                    .font(.custom("OpenSans-SemiBold", size: 17))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.white.opacity(0.2))
                                    )
                            }
                            .padding(.horizontal, 32)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.top, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Support Card - Moderate Risk") {
    CrisisSupportCard(
        riskAssessment: CrisisRiskAssessment(
            riskScore: 0.5,
            riskLevel: .moderate,
            reasonCodes: [.hopelessness, .isolation],
            context: .post,
            falsePositiveFilters: [],
            timestamp: Date()
        ),
        onDismiss: {},
        onCallHotline: {},
        onTextCrisisLine: {},
        onNotifyTrusted: {},
        onGroundingExercise: {}
    )
}

#Preview("Grounding Exercise") {
    GroundingExerciseView(exercise: GroundingExercise.exercises[0])
}
