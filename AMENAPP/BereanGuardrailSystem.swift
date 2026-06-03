// BereanGuardrailSystem.swift
// AMEN App — Human Connection Guardrail Layer for Berean AI
// Ensures AI never replaces real community, church, or human relationships

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// ─── MARK: Guardrail Detection Engine ──────────────────────────────────────

@MainActor
final class BereanGuardrailEngine: ObservableObject {
    @Published var shouldShowCommunityPrompt = false
    @Published var communityPromptType: CommunityPromptType?
    @Published var riskLevel: GuardrailRiskLevel = .none
    
    private lazy var db = Firestore.firestore()
    private var userId: String { Auth.auth().currentUser?.uid ?? "" }
    
    // Track user patterns
    private var struggleCount = 0
    private var isolationLanguageCount = 0
    private var lastCommunityPrompt: Date?
    private var conversationStartDate = Date()
    
    enum GuardrailRiskLevel {
        case none
        case moderate  // Show gentle community nudge
        case high      // Show stronger encouragement
        case critical  // Crisis intervention
    }
    
    enum CommunityPromptType {
        case firstTimeOnboarding
        case repeatedStruggle
        case isolationDetected
        case emotionalDistress
        case checkIn24h
        case checkIn3day
        case checkIn7day
        case crisis
        case medicalAdvice
    }
    
    // ─── Detect Signals ─────────────────────────────────────────────────────
    
    func analyzeMessage(_ content: String, role: BereanChatMsg.BereanChatMsgRole) {
        guard role == .user else { return }

        // Medical advice requests (checked before crisis — refusal is immediate, not throttled)
        if detectMedicalAdviceRequest(in: content) {
            riskLevel = .moderate
            communityPromptType = .medicalAdvice
            shouldShowCommunityPrompt = true
            return
        }

        // Crisis signals (highest priority)
        if detectCrisisSignals(in: content) {
            riskLevel = .critical
            communityPromptType = .crisis
            shouldShowCommunityPrompt = true
            return
        }
        
        // Isolation language
        if detectIsolationLanguage(in: content) {
            isolationLanguageCount += 1
            if isolationLanguageCount >= 2 {
                riskLevel = .high
                communityPromptType = .isolationDetected
                shouldShowCommunityPrompt = shouldShowPrompt()
            }
        }
        
        // Repeated struggle patterns
        if detectStruggleLanguage(in: content) {
            struggleCount += 1
            if struggleCount >= 3 {
                riskLevel = .moderate
                communityPromptType = .repeatedStruggle
                shouldShowCommunityPrompt = shouldShowPrompt()
            }
        }
        
        // Emotional distress
        if detectEmotionalDistress(in: content) {
            riskLevel = .high
            communityPromptType = .emotionalDistress
            shouldShowCommunityPrompt = shouldShowPrompt()
        }
        
        // Time-based check-ins
        checkTimeBasedPrompts()
    }
    
    // ─── Detection Patterns ─────────────────────────────────────────────────
    
    private func detectMedicalAdviceRequest(in text: String) -> Bool {
        let medicalPatterns = [
            "diagnose", "diagnosis", "do i have", "what disease", "what condition",
            "what medication", "prescribe", "should i take", "what dose", "dosage",
            "is it safe to take", "can i take", "what drug", "what pill",
            "treat my", "cure my", "my symptoms are", "i have symptoms",
            "medical advice", "doctor advice", "should i see a doctor"
        ]
        let lower = text.lowercased()
        return medicalPatterns.contains { lower.contains($0) }
    }

    private func detectCrisisSignals(in text: String) -> Bool {
        let crisisKeywords = [
            // Active suicidal ideation
            "kill myself", "end it all", "no reason to live", "better off dead",
            "can't go on", "suicide", "self-harm", "hurt myself",
            "overwhelming despair", "nothing left",
            // Passive suicidal ideation — synced from WellnessRiskLayer vocabulary
            "wish i was dead", "don't want to be here anymore",
            "want to disappear", "wish i could just disappear",
            "wouldn't mind if i never woke up"
        ]
        let lowercased = text.lowercased()
        return crisisKeywords.contains { lowercased.contains($0) }
    }
    
    private func detectIsolationLanguage(in text: String) -> Bool {
        let isolationKeywords = [
            "all alone", "no one understands", "nobody cares",
            "isolated", "by myself", "no friends", "lonely",
            "no one to talk to", "walk alone"
        ]
        let lowercased = text.lowercased()
        return isolationKeywords.contains { lowercased.contains($0) }
    }
    
    private func detectStruggleLanguage(in text: String) -> Bool {
        let struggleKeywords = [
            "struggling with", "can't overcome", "keep failing",
            "same sin", "stuck in", "trapped", "hopeless",
            "giving up", "exhausted", "worn out"
        ]
        let lowercased = text.lowercased()
        return struggleKeywords.contains { lowercased.contains($0) }
    }
    
    private func detectEmotionalDistress(in text: String) -> Bool {
        let distressKeywords = [
            "depressed", "anxiety", "panic", "terrified",
            "broken", "shattered", "falling apart", "can't cope",
            "drowning", "suffocating"
        ]
        let lowercased = text.lowercased()
        return distressKeywords.contains { lowercased.contains($0) }
    }
    
    // ─── Time-Based Check-ins ───────────────────────────────────────────────
    
    private func checkTimeBasedPrompts() {
        let hoursSinceStart = Date().timeIntervalSince(conversationStartDate) / 3600
        
        if hoursSinceStart >= 24 && hoursSinceStart < 25 {
            communityPromptType = .checkIn24h
            shouldShowCommunityPrompt = shouldShowPrompt()
        } else if hoursSinceStart >= 72 && hoursSinceStart < 73 {
            communityPromptType = .checkIn3day
            shouldShowCommunityPrompt = shouldShowPrompt()
        } else if hoursSinceStart >= 168 && hoursSinceStart < 169 {
            communityPromptType = .checkIn7day
            shouldShowCommunityPrompt = shouldShowPrompt()
        }
    }
    
    // ─── Prompt Throttling ──────────────────────────────────────────────────
    
    private func shouldShowPrompt() -> Bool {
        // Don't spam prompts — wait at least 2 hours between community nudges
        guard let last = lastCommunityPrompt else { return true }
        return Date().timeIntervalSince(last) > 7200
    }
    
    func markPromptShown() {
        lastCommunityPrompt = Date()
    }
    
    // ─── Save Interaction ───────────────────────────────────────────────────
    
    func logCommunityPromptShown(type: CommunityPromptType, userAction: String) {
        db.collection("users").document(userId)
            .collection("guardrailEvents")
            .addDocument(data: [
                "promptType": "\(type)",
                "action": userAction,
                "timestamp": Timestamp(date: Date())
            ])
    }
}

// ─── MARK: Community Prompt Cards ──────────────────────────────────────────

struct BereanCommunityPromptCard: View {
    let promptType: BereanGuardrailEngine.CommunityPromptType
    let onFindChurch: () -> Void
    let onReachOut: () -> Void
    let onContinue: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Icon + Title
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AmenColor.accentMuted)
                        .frame(width: 40, height: 40)
                    Image(systemName: promptIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AmenColor.accent)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(promptTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AmenColor.titleText)
                    Text("Community reminder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AmenColor.mutedText)
                }
            }
            
            // Message
            Text(promptMessage)
                .font(.system(size: 14))
                .foregroundColor(AmenColor.bodyText)
                .lineSpacing(4)
            
            // Actions
            VStack(spacing: 8) {
                if promptType == .crisis {
                    // Crisis actions
                    GuardrailActionButton(
                        title: "Find Help Near Me",
                        icon: "mappin.and.ellipse",
                        style: .critical,
                        action: onFindChurch
                    )
                } else {
                    // Standard actions
                    GuardrailActionButton(
                        title: "Find a Church",
                        icon: "building.2",
                        style: .primary,
                        action: onFindChurch
                    )
                    
                    GuardrailActionButton(
                        title: "Reach Out to Someone",
                        icon: "person.2",
                        style: .secondary,
                        action: onReachOut
                    )
                }
                
                Button(action: onContinue) {
                    Text(promptType == .crisis ? "I understand" : "Keep Reflecting")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AmenColor.mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.90))
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            promptType == .crisis
                                ? Color(hex: "DC3232").opacity(0.30)
                                : AmenColor.accent.opacity(0.20),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 8)
        )
    }
    
    // ─── Computed Properties ────────────────────────────────────────────────
    
    private var promptIcon: String {
        switch promptType {
        case .crisis: return "exclamationmark.triangle.fill"
        case .isolationDetected: return "heart.circle"
        case .repeatedStruggle: return "hands.sparkles"
        case .emotionalDistress: return "person.crop.circle.badge.checkmark"
        case .medicalAdvice: return "stethoscope"
        default: return "person.2.fill"
        }
    }

    private var promptTitle: String {
        switch promptType {
        case .crisis:
            return "Please reach out right now"
        case .isolationDetected:
            return "Don't walk this alone"
        case .repeatedStruggle:
            return "This might need community"
        case .emotionalDistress:
            return "Let someone walk with you"
        case .checkIn24h, .checkIn3day, .checkIn7day:
            return "Have you shared this?"
        case .firstTimeOnboarding:
            return "AI is not enough"
        case .medicalAdvice:
            return "Please consult a medical professional"
        }
    }

    private var promptMessage: String {
        switch promptType {
        case .crisis:
            return "I'm really glad you said this. You shouldn't handle this alone. Please reach out to someone right now — a trusted person, a pastor, or a professional."
        case .isolationDetected:
            return "I can help you think through this, but walking with someone in real life will matter more than anything I can say here."
        case .repeatedStruggle:
            return "This might be something you shouldn't carry alone. Is there someone you trust you can talk to today?"
        case .emotionalDistress:
            return "What you're feeling is real and important. Having someone you trust walk with you through this could make all the difference."
        case .checkIn24h:
            return "You've been working through this for a day. Have you shared this with anyone you trust?"
        case .checkIn3day:
            return "You've been reflecting on this for a few days. Have you shared this struggle with someone in your life?"
        case .checkIn7day:
            return "You've been processing this for a week. Would it help to share this with someone you trust?"
        case .firstTimeOnboarding:
            return "Berean can guide you with Scripture and reflection, but it does not replace real community, church, or trusted people in your life. If you're struggling, don't walk alone."
        case .medicalAdvice:
            return "Berean can offer prayer, scripture, and spiritual encouragement, but cannot provide medical diagnoses or prescriptions. For any health concern, please speak with a qualified medical professional."
        }
    }
}

// ─── MARK: Guardrail Action Button ─────────────────────────────────────────

struct GuardrailActionButton: View {
    let title: String
    let icon: String
    let style: ActionStyle
    let action: () -> Void
    
    enum ActionStyle {
        case primary
        case secondary
        case critical
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(style == .critical ? .white : (style == .primary ? AmenColor.accent : AmenColor.titleText))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        style == .critical
                            ? Color(hex: "DC3232")
                            : (style == .primary ? AmenColor.accentMuted : Color.white.opacity(0.60))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                style == .critical
                                    ? Color.clear
                                    : (style == .primary ? AmenColor.accent.opacity(0.30) : AmenColor.divider),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(GlassPressStyle())
    }
}

// ─── MARK: Onboarding Guardrail View ───────────────────────────────────────

struct BereanOnboardingGuardrailView: View {
    let onFindChurch: () -> Void
    let onTalkToSomeone: () -> Void
    let onContinue: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Hero
            VStack(alignment: .leading, spacing: 8) {
                Text("Before we begin...")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(AmenColor.titleText)
                
                Text("Berean can guide you with Scripture and reflection, but it does not replace real community, church, or trusted people in your life.")
                    .font(.system(size: 16))
                    .foregroundColor(AmenColor.bodyText)
                    .lineSpacing(4)
                
                Text("If you're struggling, don't walk alone.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AmenColor.titleText)
            }
            .padding(.top, 32)
            
            Spacer()
            
            // Actions
            VStack(spacing: 12) {
                GuardrailActionButton(
                    title: "Find a Church",
                    icon: "building.2",
                    style: .primary,
                    action: onFindChurch
                )
                
                GuardrailActionButton(
                    title: "Talk to Someone I Trust",
                    icon: "person.2",
                    style: .secondary,
                    action: onTalkToSomeone
                )
                
                Button(action: onContinue) {
                    Text("Continue to Berean")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AmenColor.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 24)
        .background(AmenColor.background)
    }
}

// ─── MARK: Inline Community Nudge ──────────────────────────────────────────
/// Subtle inline reminder that appears occasionally in chat responses

struct BereanInlineCommunityNudge: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 12))
                .foregroundColor(AmenColor.accent)
            
            Text("Remember: real community matters more than any AI can offer.")
                .font(.system(size: 12))
                .foregroundColor(AmenColor.mutedText)
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AmenColor.accentMuted.opacity(0.30))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AmenColor.accent.opacity(0.15), lineWidth: 0.5)
                )
        )
    }
}
