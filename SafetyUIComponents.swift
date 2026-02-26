//
//  SafetyUIComponents.swift
//  AMENAPP
//
//  User-Facing Safety UI Components
//  Moderation feedback, revision prompts, appeals, safety settings
//

import SwiftUI
import FirebaseAuth

// MARK: - Moderation Feedback Sheet

/// Sheet shown when content is flagged by moderation
struct ModerationFeedbackSheet: View {
    let result: CommentSafetySystem.SafetyCheckResult
    let onRevise: () -> Void
    let onCancel: () -> Void
    let onAppeal: (() -> Void)?
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: iconForAction)
                .font(.system(size: 50))
                .foregroundStyle(colorForAction)
                .padding(.top, 20)
            
            // Title
            Text(titleForAction)
                .font(.custom("OpenSans-Bold", size: 22))
                .multilineTextAlignment(.center)
            
            // Message
            if let message = result.userMessage {
                Text(message)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            // Suggested Revisions
            if let suggestions = result.suggestedRevisions, !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Try this instead:")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.primary)
                    
                    ForEach(suggestions, id: \.self) { suggestion in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.orange)
                                .padding(.top, 2)
                            
                            Text(suggestion)
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal, 24)
            }
            
            Spacer()
            
            // Actions
            VStack(spacing: 12) {
                if result.requiresRevision {
                    // Revise button (primary)
                    Button {
                        dismiss()
                        onRevise()
                    } label: {
                        Text("Revise Comment")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    
                    // Cancel button (secondary)
                    Button {
                        dismiss()
                        onCancel()
                    } label: {
                        Text("Cancel")
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                    }
                } else {
                    // Got it button
                    Button {
                        dismiss()
                    } label: {
                        Text("Got It")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
                
                // Appeal option for blocking actions
                if result.isBlocked, let appealAction = onAppeal {
                    Button {
                        dismiss()
                        appealAction()
                    } label: {
                        Text("I Disagree - Submit Appeal")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.blue)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
    
    private var iconForAction: String {
        if result.isBlocked {
            return "exclamationmark.triangle.fill"
        } else if result.requiresRevision {
            return "pencil.circle.fill"
        } else {
            return "lightbulb.fill"
        }
    }
    
    private var colorForAction: Color {
        if result.isBlocked {
            return .red
        } else if result.requiresRevision {
            return .orange
        } else {
            return .blue
        }
    }
    
    private var titleForAction: String {
        if result.isBlocked {
            return "Can't Post This"
        } else if result.requiresRevision {
            return "Let's Revise This"
        } else {
            return "Quick Tip"
        }
    }
}

// MARK: - Inline Warning Banner

/// Inline warning shown above comment input
struct SafetyWarningBanner: View {
    let message: String
    let type: WarningType
    @Binding var isVisible: Bool
    
    enum WarningType {
        case nudge      // Blue - gentle suggestion
        case warning    // Orange - moderate concern
        case blocked    // Red - cannot post
    }
    
    var body: some View {
        if isVisible {
            HStack(spacing: 12) {
                Image(systemName: iconForType)
                    .font(.system(size: 16))
                    .foregroundStyle(colorForType)
                
                Text(message)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                Button {
                    withAnimation {
                        isVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(colorForType.opacity(0.1))
            .cornerRadius(8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    private var iconForType: String {
        switch type {
        case .nudge: return "lightbulb.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .blocked: return "xmark.circle.fill"
        }
    }
    
    private var colorForType: Color {
        switch type {
        case .nudge: return .blue
        case .warning: return .orange
        case .blocked: return .red
        }
    }
}

// MARK: - Cooldown Timer

/// Shows cooldown timer when user is rate limited
struct CooldownTimer: View {
    let endTime: Date
    @State private var remainingSeconds: Int = 0
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            
            Text("Take a Breath")
                .font(.custom("OpenSans-Bold", size: 18))
            
            Text("You can comment again in:")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
            
            Text(timeString)
                .font(.custom("OpenSans-Bold", size: 32))
                .foregroundStyle(.orange)
                .monospacedDigit()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(16)
        .onAppear {
            updateRemainingTime()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                updateRemainingTime()
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private var timeString: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func updateRemainingTime() {
        let remaining = Int(endTime.timeIntervalSinceNow)
        remainingSeconds = max(0, remaining)
    }
}

// MARK: - Appeal Submission View

struct AppealSubmissionView: View {
    let enforcementId: String
    @Environment(\.dismiss) var dismiss
    @State private var appealReason: String = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.blue)
                    
                    Text("Submit an Appeal")
                        .font(.custom("OpenSans-Bold", size: 22))
                    
                    Text("If you believe this decision was made in error, please explain why. Our team will review your appeal within 24 hours.")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 24)
                
                // Text editor
                VStack(alignment: .leading, spacing: 8) {
                    Text("Why do you believe this was a mistake?")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                    
                    TextEditor(text: $appealReason)
                        .frame(height: 150)
                        .padding(12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Submit button
                Button {
                    submitAppeal()
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Submit Appeal")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(appealReason.count >= 20 ? Color.blue : Color.gray)
                .cornerRadius(12)
                .disabled(appealReason.count < 20 || isSubmitting)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Appeal Submitted", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your appeal has been submitted. We'll review it within 24 hours and notify you of the decision.")
            }
        }
    }
    
    private func submitAppeal() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isSubmitting = true
        
        Task {
            do {
                _ = try await AntiHarassmentEngine.shared.submitAppeal(
                    userId: userId,
                    enforcementId: enforcementId,
                    reason: appealReason
                )
                
                await MainActor.run {
                    isSubmitting = false
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    // Show error
                }
            }
        }
    }
}

// MARK: - Safety Dashboard View

struct SafetyDashboardView: View {
    private let harassmentEngine = AntiHarassmentEngine.shared
    @State private var dashboard: AntiHarassmentEngine.SafetyDashboard?
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if isLoading {
                        ProgressView()
                            .padding(.top, 100)
                    } else if let dashboard = dashboard {
                        // Account Status
                        statusSection(dashboard: dashboard)
                        
                        // Active Restrictions
                        if !dashboard.activeRestrictions.isEmpty {
                            restrictionsSection(restrictions: dashboard.activeRestrictions)
                        }
                        
                        // Pending Appeals
                        if dashboard.pendingAppeals > 0 {
                            appealsSection(count: dashboard.pendingAppeals)
                        }
                        
                        // Enhanced Protection
                        if dashboard.protectionEnabled {
                            protectionSection()
                        }
                        
                        // Community Guidelines
                        guidelinesSection()
                    }
                }
                .padding(20)
            }
            .navigationTitle("Account Safety")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            await loadDashboard()
        }
    }
    
    private func statusSection(dashboard: AntiHarassmentEngine.SafetyDashboard) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Account Status")
                .font(.custom("OpenSans-Bold", size: 18))
            
            HStack(spacing: 16) {
                Image(systemName: dashboard.enforcementCount == 0 ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(dashboard.enforcementCount == 0 ? .green : .orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(dashboard.enforcementCount == 0 ? "Good Standing" : "Active Warnings")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                    
                    Text(dashboard.enforcementCount == 0 ? 
                         "Your account has no active violations" :
                         "\(dashboard.enforcementCount) \(dashboard.enforcementCount == 1 ? "violation" : "violations") in past 30 days")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private func restrictionsSection(restrictions: [AntiHarassmentEngine.UserRestriction]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Active Restrictions")
                .font(.custom("OpenSans-Bold", size: 18))
            
            ForEach(restrictions, id: \.userId) { restriction in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(restriction.type.rawValue.capitalized)
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        
                        Spacer()
                        
                        Text("Ends \(timeUntil(restriction.endDate))")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(restriction.reason)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    private func appealsSection(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pending Appeals")
                .font(.custom("OpenSans-Bold", size: 18))
            
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.blue)
                
                Text("\(count) \(count == 1 ? "appeal" : "appeals") under review")
                    .font(.custom("OpenSans-Regular", size: 15))
                
                Spacer()
            }
            .padding(16)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private func protectionSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enhanced Protection")
                .font(.custom("OpenSans-Bold", size: 18))
            
            HStack(spacing: 12) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
                
                Text("Enhanced protection is enabled on your account. Comments require your approval.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private func guidelinesSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Community Guidelines")
                .font(.custom("OpenSans-Bold", size: 18))
            
            NavigationLink {
                CommunityGuidelinesView()
            } label: {
                HStack {
                    Image(systemName: "book.fill")
                        .foregroundStyle(.blue)
                    
                    Text("Review Community Guidelines")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
            }
        }
    }
    
    private func timeUntil(_ date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        let hours = Int(remaining / 3600)
        let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "in \(hours)h \(minutes)m"
        } else {
            return "in \(minutes)m"
        }
    }
    
    private func loadDashboard() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let data = try await harassmentEngine.getSafetyDashboard(userId: userId)
            await MainActor.run {
                self.dashboard = data
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}

// MARK: - Community Guidelines View

struct CommunityGuidelinesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Our Community Guidelines")
                    .font(.custom("OpenSans-Bold", size: 24))
                    .padding(.top, 20)
                
                ForEach(PolicyViolation.allCases, id: \.self) { violation in
                    if let policy = SafetyPolicyFramework.getPolicy(for: violation) {
                        policySection(policy: policy)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Guidelines")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func policySection(policy: SafetyPolicyFramework.PolicyDefinition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(policy.violation.description)
                .font(.custom("OpenSans-Bold", size: 16))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("✅ What's Allowed:")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.green)
                
                ForEach(policy.allowed.prefix(3), id: \.self) { item in
                    Text("• \(item)")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("❌ What's Not Allowed:")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.red)
                
                ForEach(policy.notAllowed.prefix(3), id: \.self) { item in
                    Text("• \(item)")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Preview Helpers

#if DEBUG
struct SafetyUIComponents_Previews: PreviewProvider {
    static var previews: some View {
        SafetyDashboardView()
    }
}
#endif
