//
//  ProactiveFrictionView.swift
//  AMENAPP
//
//  Pre-post friction UI for sexual content risk signals.
//  Point 10 of the sexual content / minors safety plan.
//
//  Usage: Embed in CreatePostView / DM compose before the final "Post" tap.
//
//  Behaviour:
//    - Score < 0.35:  invisible (no friction)
//    - Score 0.35–0.54: subtle inline hint below the text field
//    - Score 0.55–0.74: yellow warning banner with "This may violate policy"
//    - Score ≥ 0.75:  orange/red banner requiring acknowledgement before posting
//    - Repeat offender flag:  always shows the acknowledgement banner at lower threshold (0.55+)
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Friction Level

enum FrictionLevel {
    case none
    case hint             // Soft inline hint
    case warning          // Yellow warning banner
    case requireAcknowledge // Must tap "I understand" before posting
    case hardBlock        // Cannot post — content must be revised
}

// MARK: - Proactive Friction View

struct ProactiveFrictionView: View {
    let riskScore: Double
    let isRepeatOffender: Bool
    let onAcknowledge: (() -> Void)?
    let onRevise: (() -> Void)?

    @State private var acknowledged = false
    @State private var showDetails = false

    var level: FrictionLevel {
        if riskScore >= 0.9 { return .hardBlock }
        let threshold: Double = isRepeatOffender ? 0.55 : 0.75
        if riskScore >= threshold { return .requireAcknowledge }
        if riskScore >= 0.55 { return .warning }
        if riskScore >= 0.35 { return .hint }
        return .none
    }

    var body: some View {
        switch level {
        case .none:
            EmptyView()
        case .hint:
            hintBanner
        case .warning:
            warningBanner
        case .requireAcknowledge:
            acknowledgeBanner
        case .hardBlock:
            hardBlockBanner
        }
    }

    // MARK: - Hint

    private var hintBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Does this keep AMEN's values? Consider keeping it faith-appropriate.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Warning Banner

    private var warningBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text("This content may not be appropriate")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(isRepeatOffender
                     ? "Your account has had prior content warnings. This content may violate our sexual content policy and result in restrictions."
                     : "This looks like it may violate AMEN's sexual content policy. Please keep posts wholesome and faith-appropriate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
    }

    // MARK: - Acknowledge Banner

    private var acknowledgeBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .foregroundStyle(.red)
                    .font(.subheadline)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text("This looks sexual or explicit")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    Text(isRepeatOffender
                         ? "Your account has prior sexual content violations. Posting this may result in an immediate restriction. You must confirm before proceeding."
                         : "AMEN doesn't allow pornographic, sexually explicit, or soliciting content. If this content violates our policy it will be removed and may result in account restrictions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !acknowledged {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        acknowledged = true
                        onAcknowledge?()
                    }
                } label: {
                    Text("I understand — my content follows AMEN's guidelines")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.12))
                        .foregroundStyle(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    onRevise?()
                } label: {
                    Text("Revise my post")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Acknowledged — your content will still be reviewed by our safety system.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Hard Block Banner

    private var hardBlockBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "nosign")
                    .foregroundStyle(.red)
                    .font(.subheadline)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text("This content can't be posted")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    Text("This looks pornographic, sexually explicit, or soliciting. AMEN doesn't allow that. Please revise your content before posting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                onRevise?()
            } label: {
                Text("Revise my post")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.12))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .background(Color.red.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Computed: can the user proceed?

    /// Returns true when the post action should be allowed to proceed.
    var canProceed: Bool {
        switch level {
        case .none, .hint, .warning:
            return true
        case .requireAcknowledge:
            return acknowledged
        case .hardBlock:
            return false
        }
    }
}

// MARK: - Modifier: attach live friction to a text field

struct SexualRiskFrictionModifier: ViewModifier {
    @Binding var text: String
    let isDM: Bool
    let isRepeatOffender: Bool
    let onAcknowledge: (() -> Void)?
    let onRevise: (() -> Void)?

    @State private var riskScore: Double = 0
    @State private var debounceTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            ProactiveFrictionView(
                riskScore: riskScore,
                isRepeatOffender: isRepeatOffender,
                onAcknowledge: onAcknowledge,
                onRevise: onRevise
            )
        }
        .onChange(of: text) { _, newText in
            // Debounce: don't re-score on every keystroke
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                guard !Task.isCancelled else { return }
                let score = SexualRiskScorer.score(newText)
                await MainActor.run { riskScore = score }
            }
        }
    }
}

extension View {
    /// Attaches live sexual-risk friction to a text input view.
    func sexualRiskFriction(
        text: Binding<String>,
        isDM: Bool = false,
        isRepeatOffender: Bool = false,
        onAcknowledge: (() -> Void)? = nil,
        onRevise: (() -> Void)? = nil
    ) -> some View {
        modifier(SexualRiskFrictionModifier(
            text: text,
            isDM: isDM,
            isRepeatOffender: isRepeatOffender,
            onAcknowledge: onAcknowledge,
            onRevise: onRevise
        ))
    }
}

// MARK: - Repeat Offender Checker (lightweight)

/// Checks whether the current user should be treated as a repeat offender
/// for friction purposes. Cached in UserDefaults to avoid a Firestore call
/// on every keystroke.
@MainActor
final class RepeatOffenderCache {
    static let shared = RepeatOffenderCache()
    private var cachedValue: Bool = false
    private var lastFetched: Date = .distantPast
    private let db = Firestore.firestore()
    private let cacheInterval: TimeInterval = 300  // 5 min

    private init() {}

    func isRepeatOffender() async -> Bool {
        if Date().timeIntervalSince(lastFetched) < cacheInterval {
            return cachedValue
        }
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        do {
            let snap = try await db.collection("enforcement_actions")
                .whereField("userId", isEqualTo: uid)
                .whereField("violationCode", in: [
                    SexualPolicyViolationCode.solicitation.rawValue,
                    SexualPolicyViolationCode.explicitContent.rawValue,
                    SexualPolicyViolationCode.explicitText.rawValue,
                    SexualPolicyViolationCode.sexualHarassment.rawValue
                ])
                .limit(to: 2)
                .getDocuments()
            cachedValue = !snap.isEmpty
            lastFetched = Date()
            return cachedValue
        } catch {
            return cachedValue
        }
    }
}
