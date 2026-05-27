//
//  CommentsRepliesSettingsView.swift
//  AMENAPP
//
//  Created by Agent 6 — 2026-05-27.
//
//  Centralised "Comments & Replies" settings surface. Aggregates settings
//  that were previously scattered across PrivacySettingsView (whoCanComment,
//  hiddenWords) and NotificationsSettingsView (replies, mentions, reactions,
//  digest). Also exposes the Smart Prompts toggle wired to
//  AMENFeatureFlags.commentsSmartPromptsV1 via a user-level UserDefaults override.
//
//  Persistence strategy:
//   - whoCanComment   → users/{uid}/whoCanComment  (Firestore, same key as PrivacySettingsView)
//   - mutedWords      → users/{uid}/hiddenWords    (Firestore, same key as HiddenWordsSettingsView)
//                       also cached in UserDefaults amen.hiddenWords.{uid} for CommentsView read path
//   - notification prefs → users/{uid}/notificationSettings (Firestore, same map as NotificationsSettingsView)
//   - smartPrompts    → UserDefaults amen.commentsSmartPromptsEnabled.{uid} (local-only override)
//
//  NOTE: Server-side enforcement of whoCanComment is deferred — this is display-only
//  on the client. whoCanComment is read by CommentsView TODO once CF enforces it.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - CommentsRepliesSettingsView

struct CommentsRepliesSettingsView: View {
    // MARK: State

    // Who can comment
    @State private var whoCanComment: AudienceOption = .everyone

    // Muted words
    @State private var mutedWords: [String] = []
    @State private var showAddWordSheet = false

    // Notification prefs
    @State private var notifyReplies: Bool = true
    @State private var notifyMentions: Bool = true
    /// Reaction notification granularity: "off" | "milestones" | "all"
    @State private var reactionNotifLevel: String = "milestones"
    @State private var dailyDigest: Bool = false

    // Smart Prompts (user-level override, stored in UserDefaults)
    @State private var smartPromptsEnabled: Bool = {
        guard let uid = Auth.auth().currentUser?.uid else { return true }
        let key = "amen.commentsSmartPromptsEnabled.\(uid)"
        // Default: follow the feature flag
        if UserDefaults.standard.object(forKey: key) == nil {
            return AMENFeatureFlags.shared.commentsSmartPromptsV1
        }
        return UserDefaults.standard.bool(forKey: key)
    }()

    // Loading / saving
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var db: Firestore { Firestore.firestore() }
    private var uid: String? { Auth.auth().currentUser?.uid }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // MARK: WHO CAN COMMENT
                sectionHeader("WHO CAN COMMENT")

                VStack(spacing: 0) {
                    Picker(selection: $whoCanComment) {
                        ForEach(AudienceOption.allCases) { opt in
                            Label(opt.label, systemImage: opt.icon).tag(opt)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Who can comment on my posts")
                                .font(AMENFont.semiBold(15))
                            Text("Controls who sees the comment composer on your posts")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .cardStyle()
                .onChange(of: whoCanComment) { _, _ in persist() }

                footerText("Everyone, followers only, or nobody. Existing comments are not affected.")

                // MARK: MUTED WORDS
                sectionHeader("MUTED WORDS")

                VStack(spacing: 0) {
                    if mutedWords.isEmpty {
                        Text("No words added yet")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                        Divider().padding(.leading, 16)
                    } else {
                        ForEach(mutedWords, id: \.self) { word in
                            HStack {
                                Text(word)
                                    .font(AMENFont.regular(15))
                                Spacer()
                                Button {
                                    removeMutedWord(word)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .accessibilityLabel("Remove \(word) from muted words")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Divider().padding(.leading, 16)
                        }
                    }

                    Button {
                        showAddWordSheet = true
                    } label: {
                        Label("Add word or phrase", systemImage: "plus.circle.fill")
                            .font(AMENFont.semiBold(15))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .cardStyle()
                .sheet(isPresented: $showAddWordSheet) {
                    AddHiddenWordSheet(hiddenWords: $mutedWords) {
                        persist()
                        cacheMutedWords()
                    }
                }

                footerText("Comments containing these words are hidden from your view. Case-insensitive.")

                // MARK: COMMENT NOTIFICATIONS
                sectionHeader("COMMENT NOTIFICATIONS")

                VStack(spacing: 0) {
                    Toggle(isOn: $notifyReplies) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            Text("Replies to my comments")
                                .font(AMENFont.semiBold(15))
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .onChange(of: notifyReplies) { _, _ in persist() }

                    Divider().padding(.leading, 16)

                    Toggle(isOn: $notifyMentions) {
                        HStack(spacing: 12) {
                            Image(systemName: "at")
                                .foregroundStyle(.orange)
                                .frame(width: 24)
                            Text("Mentions in comments")
                                .font(AMENFont.semiBold(15))
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .onChange(of: notifyMentions) { _, _ in persist() }

                    Divider().padding(.leading, 16)

                    Picker(selection: $reactionNotifLevel) {
                        Text("Off").tag("off")
                        Text("Milestones only").tag("milestones")
                        Text("All reactions").tag("all")
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Comment reaction notifications")
                                    .font(AMENFont.semiBold(15))
                                Text(reactionNotifLevelLabel)
                                    .font(AMENFont.regular(13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .onChange(of: reactionNotifLevel) { _, _ in persist() }

                    Divider().padding(.leading, 16)

                    Toggle(isOn: $dailyDigest) {
                        HStack(spacing: 12) {
                            Image(systemName: "newspaper.fill")
                                .foregroundStyle(.brown)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Daily comment digest")
                                    .font(AMENFont.semiBold(15))
                                Text("Summary of comment activity on your posts")
                                    .font(AMENFont.regular(13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .onChange(of: dailyDigest) { _, _ in persist() }
                }
                .cardStyle()

                footerText("Notification preferences are synced with your main Notifications settings.")

                // MARK: SMART PROMPTS
                sectionHeader("AI FEATURES")

                VStack(spacing: 0) {
                    Toggle(isOn: $smartPromptsEnabled) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.purple)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Smart Reply Prompts")
                                    .font(AMENFont.semiBold(15))
                                Text("Show AI-generated scripture-aligned reply starters")
                                    .font(AMENFont.regular(13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.purple)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .onChange(of: smartPromptsEnabled) { _, newValue in
                        guard let uid else { return }
                        UserDefaults.standard.set(newValue, forKey: "amen.commentsSmartPromptsEnabled.\(uid)")
                    }
                }
                .cardStyle()

                footerText("Smart prompts are powered by Berean AI and are never shared publicly.")

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Comments & Replies")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading { ProgressView().scaleEffect(1.2) }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            if let msg = errorMessage { Text(msg) }
        }
        .task { await load() }
    }

    // MARK: - Helpers

    private var reactionNotifLevelLabel: String {
        switch reactionNotifLevel {
        case "off":        return "No reaction notifications"
        case "milestones": return "First 10, 50, 100 reactions only"
        default:           return "Every reaction"
        }
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(AMENFont.bold(11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func footerText(_ text: String) -> some View {
        Text(text)
            .font(AMENFont.regular(12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 8)
    }

    private func removeMutedWord(_ word: String) {
        mutedWords.removeAll { $0 == word }
        persist()
        cacheMutedWords()
    }

    // MARK: - UserDefaults cache (for CommentsView read path)

    /// Writes the muted words and filter flag into UserDefaults so CommentsView
    /// can read them synchronously on the MainActor without a Firestore round-trip.
    private func cacheMutedWords() {
        guard let uid else { return }
        UserDefaults.standard.set(mutedWords, forKey: "amen.hiddenWords.\(uid)")
        UserDefaults.standard.set(true, forKey: "amen.hiddenWordFilterComments.\(uid)")
    }

    // MARK: - Load

    private func load() async {
        guard let uid else { isLoading = false; return }
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            let data = doc.data() ?? [:]
            let notifMap = data["notificationSettings"] as? [String: Any] ?? [:]
            await MainActor.run {
                whoCanComment = AudienceOption(rawValue: data["whoCanComment"] as? String ?? "") ?? .everyone
                mutedWords = data["hiddenWords"] as? [String] ?? []
                notifyReplies = notifMap["replies"] as? Bool ?? true
                notifyMentions = notifMap["mentions"] as? Bool ?? true
                reactionNotifLevel = notifMap["commentReactionLevel"] as? String ?? "milestones"
                dailyDigest = notifMap["weeklyDigest"] as? Bool ?? false
                isLoading = false
            }
            // Prime the UserDefaults cache for CommentsView
            cacheMutedWords()
        } catch {
            await MainActor.run {
                errorMessage = "Could not load settings: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    // MARK: - Persist

    private func persist() {
        guard let uid, !isSaving else { return }
        isSaving = true
        Task {
            do {
                // Merge into user doc — consistent with PrivacySettingsView and NotificationsSettingsView
                try await db.collection("users").document(uid).updateData([
                    "whoCanComment": whoCanComment.rawValue,
                    "hiddenWords": mutedWords,
                    "notificationSettings.replies": notifyReplies,
                    "notificationSettings.mentions": notifyMentions,
                    "notificationSettings.commentReactionLevel": reactionNotifLevel,
                    "notificationSettings.weeklyDigest": dailyDigest,
                    "commentsSettingsUpdatedAt": FieldValue.serverTimestamp()
                ])
                cacheMutedWords()
            } catch {
                await MainActor.run {
                    errorMessage = "Could not save: \(error.localizedDescription)"
                }
            }
            await MainActor.run { isSaving = false }
        }
    }
}

// MARK: - Card style helper

private extension View {
    func cardStyle() -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CommentsRepliesSettingsView()
            .environmentObject(AuthenticationViewModel())
    }
}
