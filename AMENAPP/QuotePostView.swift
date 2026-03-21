// QuotePostView.swift
// AMENAPP
//
// Compose a quote-post (repost with comment).
// PROMPT 1 — Quoted card shimmer pulse + long-press reaction tray
// PROMPT 2 — Smart @ mention + # hashtag suggestion tray

import SwiftUI
import FirebaseAuth

// MARK: - TrayType

enum TrayType { case mention, hashtag }

// MARK: - QuotePostView

struct QuotePostView: View {
    @Environment(\.dismiss) private var dismiss

    // The post being quoted
    let quotedPost: Post

    // Called when the user taps "Post"
    var onPost: ((String, Post) -> Void)?

    // MARK: Composer state
    @State private var composerText = ""
    @FocusState private var composerFocused: Bool

    // MARK: PROMPT 1 — Shimmer + Reaction Tray
    @State private var shimmerOffset: CGFloat = -UIScreen.main.bounds.width
    @State private var showReactionTray = false
    @State private var selectedReaction = ""
    @State private var cardScale: CGFloat = 1.0

    // MARK: PROMPT 2 — @ / # Tray
    @State private var trayVisible = false
    @State private var trayChips: [String] = []
    @State private var trayType: TrayType = .mention
    @State private var atIconScale: CGFloat = 1.0
    @State private var hashIconScale: CGFloat = 1.0

    private let mentionSuggestions = [
        "@PastorJohn", "@AMENApp", "@GraceLeads", "@FaithCom", "@ChurchLife",
        "@WorshipTeam", "@PrayerCircle", "@YouthMinistry"
    ]
    private let hashtagSuggestions = [
        "#OpenTable", "#AMEN", "#SermonNotes", "#FaithWalk", "#ChurchLife",
        "#Prayer", "#Testimony", "#Scripture", "#Worship", "#Community"
    ]

    // MARK: Bottom toolbar height for tray positioning
    private let toolbarHeight: CGFloat = 52

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    composerSection
                    Divider()
                    quotedCardSection
                    Spacer()
                }

                // PROMPT 2 — Suggestion tray overlaid above toolbar
                VStack {
                    Spacer()
                    if trayVisible {
                        suggestionTray
                            .padding(.bottom, toolbarHeight + 8)
                    }
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
                // Dismiss tray on tap outside (PROMPT 1 + 2)
                .onTapGesture {
                    if showReactionTray { showReactionTray = false }
                    if trayVisible { trayVisible = false }
                }
            }
            .navigationTitle("Quote Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        onPost?(composerText, quotedPost)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomToolbar
            }
        }
    }

    // MARK: - Composer

    private var composerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            // Author avatar
            Circle()
                .fill(Color(.secondarySystemBackground))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                )

            TextEditor(text: $composerText)
                .font(.system(size: 16))
                .frame(minHeight: 80, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($composerFocused)
                .onChange(of: composerText) { _, newVal in
                    triggerShimmer()
                    detectTriggerChar(in: newVal)
                }
                .overlay(alignment: .topLeading) {
                    if composerText.isEmpty {
                        Text("Add your thoughts…")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Quoted Card (PROMPT 1)

    private var quotedCardSection: some View {
        ZStack(alignment: .top) {
            // Quoted card
            quotedCard
                .scaleEffect(cardScale)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: cardScale)
                .onLongPressGesture(minimumDuration: 0.4) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                        showReactionTray = true
                    }
                }

            // Reaction tray above card
            if showReactionTray {
                reactionTray
                    .offset(y: -48)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.75, anchor: .bottom).combined(with: .opacity),
                        removal: .scale(scale: 0.75, anchor: .bottom).combined(with: .opacity)
                    ))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var quotedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: author + reaction badge
            HStack(spacing: 8) {
                AsyncImage(url: URL(string: quotedPost.authorProfileImageURL ?? "")) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        Color(.systemGray5)
                            .overlay(Text(quotedPost.authorInitials).font(.caption.bold()).foregroundStyle(.secondary))
                    }
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())

                Text(quotedPost.authorName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                if !selectedReaction.isEmpty {
                    Text(selectedReaction)
                        .font(.system(size: 14))
                        .transition(.scale.combined(with: .opacity))
                }

                Spacer()

                if let tag = quotedPost.topicTag, !tag.isEmpty {
                    Text("#\(tag)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange.opacity(0.1)))
                }

                Text(quotedPost.timeAgo)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            // Content
            Text(quotedPost.content)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineLimit(4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
        // PROMPT 1 — Shimmer overlay
        .overlay {
            shimmerOverlay
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - PROMPT 1: Shimmer overlay

    private var shimmerOverlay: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.45), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: shimmerOffset)
        .allowsHitTesting(false)
    }

    private func triggerShimmer() {
        shimmerOffset = -UIScreen.main.bounds.width
        withAnimation(.easeInOut(duration: 0.65)) {
            shimmerOffset = UIScreen.main.bounds.width
        }
    }

    // MARK: - PROMPT 1: Reaction Tray

    private var reactionTray: some View {
        let emojis = ["🙏", "❤️", "🔥", "✨", "💯"]
        return HStack(spacing: 8) {
            ForEach(Array(emojis.enumerated()), id: \.offset) { index, emoji in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) {
                        selectedReaction = emoji
                        showReactionTray = false
                    }
                    // Card scale bounce
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                        cardScale = 1.05
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            cardScale = 1.0
                        }
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(emoji)
                        .font(.system(size: 20))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color(.separator), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .scaleEffect(showReactionTray ? 1 : 0.75)
                .opacity(showReactionTray ? 1 : 0)
                .animation(
                    .spring(response: 0.32, dampingFraction: 0.62)
                    .delay(Double(index) * 0.04),
                    value: showReactionTray
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    // MARK: - PROMPT 2: Suggestion Tray

    private var suggestionTray: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(trayType == .mention ? "People" : "Hashtags")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(trayChips.enumerated()), id: \.element) { index, chip in
                        Button {
                            injectSuggestion(chip)
                            // Bounce the relevant toolbar icon
                            if trayType == .mention {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { atIconScale = 1.25 }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    withAnimation(.spring(response: 0.25)) { atIconScale = 1.0 }
                                }
                            } else {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { hashIconScale = 1.25 }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    withAnimation(.spring(response: 0.25)) { hashIconScale = 1.0 }
                                }
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text(chip)
                                .font(.subheadline)
                                .foregroundStyle(trayType == .mention ? Color.blue : Color.orange)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color(.systemGray6))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color(.separator), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .opacity(trayVisible ? 1 : 0)
                        .offset(y: trayVisible ? 0 : 8)
                        .animation(
                            .spring(response: 0.35, dampingFraction: 0.72)
                            .delay(Double(index) * 0.055),
                            value: trayVisible
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 12, y: -4)
        .padding(.horizontal, 16)
        .offset(y: trayVisible ? 0 : 14)
        .scaleEffect(trayVisible ? 1 : 0.94, anchor: .bottom)
        .opacity(trayVisible ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: trayVisible)
    }

    // MARK: - PROMPT 2: Trigger Detection

    private func detectTriggerChar(in text: String) {
        // Find last @ or #
        var lastAt: String.Index? = nil
        var lastHash: String.Index? = nil

        for idx in text.indices {
            if text[idx] == "@" { lastAt = idx }
            if text[idx] == "#" { lastHash = idx }
        }

        let triggerIdx: String.Index?
        let type: TrayType
        let triggerChar: Character

        if let at = lastAt, let hash = lastHash {
            if at > hash { triggerIdx = at; type = .mention; triggerChar = "@" }
            else          { triggerIdx = hash; type = .hashtag; triggerChar = "#" }
        } else if let at = lastAt {
            triggerIdx = at; type = .mention; triggerChar = "@"
        } else if let hash = lastHash {
            triggerIdx = hash; type = .hashtag; triggerChar = "#"
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { trayVisible = false }
            trayChips = []
            return
        }

        guard let idx = triggerIdx else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { trayVisible = false }
            return
        }

        let afterTrigger = text[text.index(after: idx)...]
        let partial = String(afterTrigger.prefix(while: { !$0.isWhitespace }))

        if afterTrigger.first?.isWhitespace == true || (afterTrigger.isEmpty && text.last == triggerChar) {
            // Show all if just typed trigger char
            let all = type == .mention ? mentionSuggestions : hashtagSuggestions
            let chips = Array(all.prefix(5))
            trayChips = chips
            trayType = type
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { trayVisible = !chips.isEmpty }
            return
        }

        if partial.contains(" ") {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { trayVisible = false }
            trayChips = []
            return
        }

        let source = type == .mention ? mentionSuggestions : hashtagSuggestions
        let filtered = source.filter {
            $0.lowercased().contains(partial.lowercased())
        }
        let chips = Array(filtered.prefix(5))
        trayChips = chips
        trayType = type

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            trayVisible = !chips.isEmpty
        }
    }

    private func injectSuggestion(_ suggestion: String) {
        let triggerChar: Character = trayType == .mention ? "@" : "#"
        if let range = composerText.range(of: String(triggerChar), options: .backwards) {
            composerText = String(composerText[..<range.lowerBound]) + suggestion + " "
        } else {
            composerText += suggestion + " "
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            trayVisible = false
        }
        trayChips = []
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 4) {
            // @ mention shortcut
            Button {
                composerText += "@"
                composerFocused = true
                detectTriggerChar(in: composerText)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "at")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .scaleEffect(atIconScale)
            }
            .buttonStyle(.plain)

            // # hashtag shortcut
            Button {
                composerText += "#"
                composerFocused = true
                detectTriggerChar(in: composerText)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "number")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .scaleEffect(hashIconScale)
            }
            .buttonStyle(.plain)

            Spacer()

            // Character count
            Text("\(composerText.count) / 280")
                .font(.caption)
                .foregroundStyle(composerText.count > 260 ? .orange : .secondary)
                .padding(.trailing, 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(Divider(), alignment: .top)
    }
}

// MARK: - Preview Helper

struct QuotePostView_Previews: PreviewProvider {
    static var previews: some View {
        QuotePostView(
            quotedPost: Post(
                id: UUID(),
                firebaseId: nil,
                authorId: "uid",
                authorName: "Pastor John",
                authorUsername: "@pastorjohn",
                authorInitials: "PJ",
                authorProfileImageURL: nil,
                timeAgo: "2h",
                content: "Walking by faith means trusting God even when the path isn't clear.",
                category: .openTable,
                topicTag: "OPENTABLE",
                visibility: .everyone,
                allowComments: true,
                commentPermissions: nil,
                imageURLs: nil,
                linkURL: nil,
                linkPreviewTitle: nil,
                linkPreviewDescription: nil,
                linkPreviewImageURL: nil,
                linkPreviewSiteName: nil,
                linkPreviewType: nil,
                verseReference: nil,
                verseText: nil,
                createdAt: Date(),
                amenCount: 12,
                lightbulbCount: 3,
                commentCount: 5,
                repostCount: 1
            )
        )
    }
}
