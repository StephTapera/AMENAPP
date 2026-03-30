//
//  ContentGuardrailView.swift
//  AMENAPP
//
//  Feature A: Gentle safety guardrails for prayer/testimony/comments
//  - Detects PII, toxicity, and self-harm signals
//  - Offers one-tap PII redaction
//  - Non-alarmist self-harm support card
//  - Optional "rephrase kinder" nudge
//  - Privacy-first: no raw text stored; only risk tier + reason codes logged
//

import SwiftUI

// MARK: - ContentGuardrailView

/// A non-intrusive guardrail banner that appears below a text input when issues are detected.
/// Integrates with ThinkFirstGuardrailsService and EnhancedCrisisSupportService.
/// Usage: attach via .contentGuardrail(text: $commentText, context: .comment)
struct ContentGuardrailView: View {
    let result: ThinkFirstGuardrailsService.ContentCheckResult
    @Binding var text: String
    var onDismiss: () -> Void
    
    var body: some View {
        Group {
            switch result.action {
            case .allow:
                EmptyView()
            case .softPrompt:
                softPromptBanner
            case .requireEdit:
                requireEditBanner
            case .block:
                blockBanner
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: result.action == .allow)
    }
    
    // MARK: - Banners
    
    /// Gentle nudge: user can dismiss or apply suggestion
    private var softPromptBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            // PII redaction prompt (highest priority)
            if !result.redactions.isEmpty {
                piiRedactionRow
            } else if let firstViolation = result.violations.first {
                // Self-harm: supportive card
                if firstViolation.type == .selfHarm {
                    selfHarmSupportCard
                } else {
                    // Heated / general nudge
                    genericNudgeRow(message: firstViolation.message)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.yellow.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.yellow.opacity(0.4), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
    
    /// Must-fix warning: cannot post until resolved
    private var requireEditBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
            
            Text(result.violations.first?.message ?? "Please revise your content before posting.")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
    
    /// Hard block: content cannot be posted
    private var blockBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let firstViolation = result.violations.first, firstViolation.type == .selfHarm {
                selfHarmSupportCard
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "nosign")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                    
                    Text(result.violations.first?.message ?? "This content can't be posted.")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
    
    // MARK: - Specialized Rows
    
    private var piiRedactionRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Personal info detected")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.primary)
                Text("Protect your privacy with one tap.")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                applyRedactions()
            } label: {
                Text("Redact")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.blue))
            }
            .buttonStyle(.plain)
        }
    }
    
    private var selfHarmSupportCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.pink)
                
                Text("We see you and care about you")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.primary)
            }
            
            Text("If you're going through something difficult, please reach out to someone you trust or contact a helpline.")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
            
            HStack(spacing: 8) {
                crisisResourceButton(
                    title: "Call 988",
                    subtitle: "Lifeline",
                    action: { openURL("tel:988") }
                )
                crisisResourceButton(
                    title: "Text HOME",
                    subtitle: "to 741741",
                    action: { openURL("sms:741741&body=HOME") }
                )
                
                Spacer()
                
                Button(action: onDismiss) {
                    Text("Continue anyway")
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func genericNudgeRow(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.95, green: 0.75, blue: 0.1))
            
            Text(message)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.primary)
                .lineLimit(2)
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func crisisResourceButton(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 12))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.custom("OpenSans-Regular", size: 10))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.pink.opacity(0.85)))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions
    
    private func applyRedactions() {
        let redacted = ThinkFirstGuardrailsService.shared.applyRedactions(text, redactions: result.redactions)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            text = redacted
        }
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        onDismiss()
    }
    
    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Modifier

extension View {
    /// Attach safety guardrails to any text input view.
    /// Checks text on change (debounced 1s) and shows inline banner when needed.
    func contentGuardrail(
        text: Binding<String>,
        context: ContentContext = .comment,
        onBlock: ((ThinkFirstGuardrailsService.ContentCheckResult) -> Void)? = nil
    ) -> some View {
        modifier(ContentGuardrailModifier(text: text, context: context, onBlock: onBlock))
    }
}

struct ContentGuardrailModifier: ViewModifier {
    @Binding var text: String
    let context: ContentContext
    var onBlock: ((ThinkFirstGuardrailsService.ContentCheckResult) -> Void)?
    
    @ObservedObject private var guardrails = ThinkFirstGuardrailsService.shared
    @State private var checkResult: ThinkFirstGuardrailsService.ContentCheckResult?
    @State private var checkTask: Task<Void, Never>?
    @State private var isDismissed = false
    
    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            
            if let result = checkResult, result.action != .allow, !isDismissed {
                ContentGuardrailView(result: result, text: $text) {
                    withAnimation { isDismissed = true }
                }
            }
        }
        .onChange(of: text) { _, newText in
            // Reset dismissed state when text changes meaningfully
            if isDismissed && !newText.isEmpty {
                isDismissed = false
            }
            
            // Debounce: only check after user pauses for 1 second
            checkTask?.cancel()
            guard newText.count >= 10 else {
                checkResult = nil
                return
            }
            checkTask = Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second debounce
                guard !Task.isCancelled else { return }
                let result = await ThinkFirstGuardrailsService.shared.checkContent(newText, context: context)
                await MainActor.run {
                    checkResult = result
                    // Notify caller for hard blocks so they can disable the send button
                    if !result.canProceed {
                        onBlock?(result)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        // PII preview
        ContentGuardrailView(
            result: ThinkFirstGuardrailsService.ContentCheckResult(
                canProceed: true,
                action: .softPrompt,
                violations: [.init(type: .pii, severity: .warning, message: "Personal info detected")],
                suggestions: [],
                redactions: [.init(original: "555-1234", replacement: "[phone removed]", type: "phone")]
            ),
            text: .constant("My number is 555-1234"),
            onDismiss: {}
        )
        
        // Self-harm support card preview
        ContentGuardrailView(
            result: ThinkFirstGuardrailsService.ContentCheckResult(
                canProceed: false,
                action: .block,
                violations: [.init(type: .selfHarm, severity: .critical, message: "We care about you")],
                suggestions: [],
                redactions: []
            ),
            text: .constant(""),
            onDismiss: {}
        )
    }
    .padding()
}
