// ContextAwareCommentComposer.swift
// AMENAPP — MusicContentLayer
//
// SwiftUI sheet for context-aware comment composition with local safety scanning.
// Prefixed names avoid collision with module-level ModerationWarningBanner
// (MediaModerationView.swift) and ContextPill (TrustOSContracts.swift).

import SwiftUI

// MARK: - Comment Content Context

enum CommentContentContext: String, Codable, Sendable {
    case general, sermonNote, prayerRequest, worshipRelease, testimony
    case grief, event, scripture, churchAnnouncement, communityDiscussion

    var contextLabel: String {
        switch self {
        case .general:             return "General"
        case .sermonNote:          return "Sermon Note"
        case .prayerRequest:       return "Prayer Request"
        case .worshipRelease:      return "Worship Release"
        case .testimony:           return "Testimony"
        case .grief:               return "Grief & Loss"
        case .event:               return "Event"
        case .scripture:           return "Scripture"
        case .churchAnnouncement:  return "Church Announcement"
        case .communityDiscussion: return "Community Discussion"
        }
    }

    var guidanceText: String {
        switch self {
        case .general:             return "Share your thoughts with care and kindness."
        case .sermonNote:          return "Reflect on what the message meant to you personally."
        case .prayerRequest:       return "Feel free to share your heart — this is a safe space for prayer."
        case .worshipRelease:      return "Share how this music moved or encouraged your spirit."
        case .testimony:           return "Your story matters. Share what God has done in your life."
        case .grief:               return "Take your time. This community stands with you in your grief."
        case .event:               return "Share excitement, questions, or anything about this event."
        case .scripture:           return "How has this passage spoken to you? Share your reflection."
        case .churchAnnouncement:  return "Keep it clear and encouraging for everyone in the community."
        case .communityDiscussion: return "Engage respectfully — iron sharpens iron."
        }
    }

    var guidanceIcon: String {
        switch self {
        case .general:             return "text.bubble"
        case .sermonNote:          return "book.fill"
        case .prayerRequest:       return "hands.sparkles"
        case .worshipRelease:      return "music.note"
        case .testimony:           return "star.fill"
        case .grief:               return "heart.fill"
        case .event:               return "calendar"
        case .scripture:           return "text.book.closed.fill"
        case .churchAnnouncement:  return "megaphone.fill"
        case .communityDiscussion: return "bubble.left.and.bubble.right.fill"
        }
    }
}

// MARK: - Safety Types

struct CommentSafetyResult: Sendable {
    let isSafe: Bool
    let toxicityScore: Double
    let flags: [CommentSafetyFlag]
    let suggestedRewrite: String?
}

enum CommentSafetyFlag: String, Sendable {
    case toxicity, harassment, spam, sensitiveReligious, lowEffort, potentiallyHurtful
}

// MARK: - Comment Safety Service

struct CommentSafetyService: Sendable {
    private static let profanityKeywords: Set<String> = [
        "damn","hell","crap","ass","bastard","idiot","stupid","moron",
        "hate","loser","dumb","jerk","shut up","go to hell","worthless"
    ]
    private static let harassmentPatterns: [String] = [
        "you are nothing","nobody cares","just leave","kill yourself",
        "you should die","no one likes you","get out"
    ]
    private static let spamPatterns: [String] = [
        "click here","follow me","dm me","buy now","limited offer",
        "check my bio","link in bio","free gift"
    ]

    func scan(_ text: String) -> CommentSafetyResult {
        let lower = text.lowercased()
        var flags: [CommentSafetyFlag] = []
        var score = 0.0

        let profanityHits = Self.profanityKeywords.filter { lower.contains($0) }
        if !profanityHits.isEmpty { flags.append(.toxicity); score += min(Double(profanityHits.count) * 0.25, 0.75) }

        let harassHits = Self.harassmentPatterns.filter { lower.contains($0) }
        if !harassHits.isEmpty { flags.append(.harassment); score += min(Double(harassHits.count) * 0.4, 0.9) }

        let spamHits = Self.spamPatterns.filter { lower.contains($0) }
        if !spamHits.isEmpty { flags.append(.spam); score += min(Double(spamHits.count) * 0.3, 0.6) }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 3 { flags.append(.lowEffort); score += 0.1 }

        let toxicityScore = min(score, 1.0)
        let isSafe = toxicityScore <= 0.7 && !flags.contains(.harassment)
        let suggestedRewrite: String? = isSafe ? nil :
            "Consider rewriting your comment with kindness and respect for others in this community."

        return CommentSafetyResult(isSafe: isSafe, toxicityScore: toxicityScore,
                                   flags: flags, suggestedRewrite: suggestedRewrite)
    }
}

// MARK: - CommentModerationWarningBanner
// Renamed from ModerationWarningBanner to avoid collision with MediaModerationView.swift

private struct CommentModerationWarningBanner: View {
    let result: CommentSafetyResult
    let onRewrite: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.red)
                Text("This comment may not meet community standards.")
                    .font(.caption).foregroundStyle(.primary)
            }
            if !result.flags.isEmpty {
                Text("Detected: \(result.flags.map(\.rawValue).joined(separator: ", "))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if result.suggestedRewrite != nil {
                Button(action: onRewrite) {
                    Label("Rewrite with care", systemImage: "pencil.and.sparkles")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.red)
                .accessibilityLabel("Rewrite comment with suggested safe version")
            }
        }
        .padding(12)
        .background {
            if reduceTransparency {
                Color.red.opacity(0.12).clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)
                    .overlay(Color.red.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.3), lineWidth: 1))
            }
        }
        .shadow(color: .red.opacity(0.08), radius: 4, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Moderation warning: \(result.flags.map(\.rawValue).joined(separator: ", "))")
    }
}

// MARK: - CommentContextIndicatorPill
// Renamed from ContextPill to avoid collision with TrustOSContracts.swift

private struct CommentContextIndicatorPill: View {
    let context: CommentContentContext
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: context.guidanceIcon).font(.caption)
            Text(context.contextLabel).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background {
            if reduceTransparency {
                Color(.systemBackground).clipShape(Capsule())
            } else {
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Color.white.opacity(0.06))
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
            }
        }
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        .accessibilityLabel("Comment context: \(context.contextLabel)")
    }
}

// MARK: - ContextAwareCommentComposer

struct ContextAwareCommentComposer: View {
    let context: CommentContentContext
    let onSubmit: (String) -> Void
    let onDismiss: () -> Void

    @State private var text: String = ""
    @State private var safetyResult: CommentSafetyResult?
    @State private var scanTask: Task<Void, Never>?
    @State private var isScanning = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let safetyService = CommentSafetyService()
    private let maxCharacters = 500

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // Context indicator
                    HStack {
                        CommentContextIndicatorPill(context: context)
                        Spacer()
                    }

                    // Guidance text
                    Label(context.guidanceText, systemImage: context.guidanceIcon)
                        .font(.caption.italic())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Guidance: \(context.guidanceText)")

                    // "Read first" nudge
                    if context != .general && text.count < 10 {
                        HStack(spacing: 6) {
                            Image(systemName: "eye.fill").font(.caption).foregroundStyle(.orange)
                            Text("Read the attached content first before commenting.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        .transition(reduceMotion
                            ? .opacity.animation(.easeOut(duration: 0.12))
                            : .opacity.combined(with: .move(edge: .top)).animation(.spring(response: 0.35, dampingFraction: 0.75))
                        )
                        .accessibilityLabel("Reminder: Read the attached content first before commenting.")
                    }

                    // Text editor
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Write your comment…")
                                .font(.body).foregroundStyle(.tertiary)
                                .padding(.top, 8).padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $text)
                            .font(.body).frame(minHeight: 120).scrollContentBackground(.hidden)
                    }
                    .padding(12)
                    .background {
                        if reduceTransparency {
                            Color(.secondarySystemBackground).clipShape(RoundedRectangle(cornerRadius: 14))
                        } else {
                            RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
                                .overlay(Color.white.opacity(0.06))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1))
                        }
                    }
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                    .onChange(of: text) { _, newValue in scheduleSafetyScan(for: newValue) }
                    .accessibilityLabel("Comment text editor")
                    .accessibilityHint("Enter your comment here. Maximum \(maxCharacters) characters.")

                    // Character count
                    HStack {
                        Spacer()
                        Text("\(text.count)/\(maxCharacters)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(remainingCharacters < 50 ? Color.orange : Color.secondary)
                            .accessibilityLabel("\(text.count) of \(maxCharacters) characters used")
                    }

                    // Scanning indicator
                    if isScanning {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("Checking comment…").font(.caption2).foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Safety scan in progress")
                    }

                    // Moderation warning
                    if let result = safetyResult, !result.isSafe || !result.flags.isEmpty {
                        CommentModerationWarningBanner(result: result) { applyRewrite(result: result) }
                            .transition(reduceMotion
                                ? .opacity.animation(.easeOut(duration: 0.12))
                                : .opacity.combined(with: .move(edge: .bottom)).animation(.spring(response: 0.35, dampingFraction: 0.75))
                            )
                    }

                    // Submit button
                    Button(action: submitComment) {
                        HStack {
                            Spacer()
                            Label("Post Comment", systemImage: "paperplane.fill")
                                .font(.body.weight(.semibold))
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(submitEnabled ? Color.accentColor : Color.secondary.opacity(0.2))
                        }
                        .foregroundStyle(submitEnabled ? .white : .secondary)
                    }
                    .disabled(!submitEnabled)
                    .accessibilityLabel("Post comment")
                    .accessibilityHint(submitEnabled
                        ? "Double tap to post your comment"
                        : "Disabled: comment must be non-empty and pass safety check")
                }
                .padding(20)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: safetyResult?.isSafe)
            }
            .navigationTitle("Add a Comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .accessibilityLabel("Cancel and dismiss comment composer")
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
    }

    // MARK: - Helpers

    private var remainingCharacters: Int { maxCharacters - text.count }

    private var submitEnabled: Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard text.count <= maxCharacters else { return false }
        if let result = safetyResult { return result.isSafe }
        return true
    }

    private func scheduleSafetyScan(for value: String) {
        scanTask?.cancel()
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { safetyResult = nil; return }
        isScanning = true
        scanTask = Task {
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            safetyResult = safetyService.scan(value)
            isScanning = false
        }
    }

    private func applyRewrite(result: CommentSafetyResult) {
        guard let rewrite = result.suggestedRewrite else { return }
        text = rewrite
    }

    private func submitComment() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
    }
}

// MARK: - Preview

#Preview("Prayer Request Context") {
    ContextAwareCommentComposer(
        context: .prayerRequest,
        onSubmit: { _ in },
        onDismiss: { }
    )
}
