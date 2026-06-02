//
//  PostAttachmentSystem.swift
//  AMENAPP
//
//  Unified Liquid Glass attachment system for Church Note, Going Sunday, and Verse posts.
//  Enhances existing post cards without changing their design.
//  All three attachment types share one pill style, one expanded card, and typed full-screen destinations.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import UIKit

// MARK: - Attachment Kind

enum PostAttachmentKind: Equatable {
    case churchNote
    case goingSunday
    case verse
}

// MARK: - Shared Glass Background

/// Reusable Liquid Glass background — matches the established ChurchNotePreviewCard direction.
/// .ultraThinMaterial + white overlay + hairline border.
func attachmentGlassBackground(radius: CGFloat = 14) -> some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
        .fill(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.white.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.black.opacity(0.07), lineWidth: 0.8)
        )
}

// MARK: - Icon Well

/// Left icon well — dark rounded square, matches existing ChurchNotePreviewCard icon well.
struct AttachmentIconWell: View {
    let systemName: String
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.black.opacity(0.70))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.40, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Collapsed Pill

/// Unified Liquid Glass pill for all three attachment types.
/// Exact direction: left icon well, title/subtitle stack, optional trailing metadata, right chevron.
struct LiquidGlassAttachmentPill: View {
    let kind: PostAttachmentKind
    let title: String
    let subtitle: String?
    let iconSystemName: String
    let isExpanded: Bool
    var trailingMetadata: String? = nil
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: {
            HapticManager.impact(style: .light)
            onTap()
        }) {
            HStack(spacing: 10) {
                AttachmentIconWell(systemName: iconSystemName)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                if let meta = trailingMetadata {
                    Text(meta)
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(
                        reduceMotion ? .linear(duration: 0) : .interactiveSpring(response: 0.28, dampingFraction: 0.86),
                        value: isExpanded
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(attachmentGlassBackground())
        }
        .buttonStyle(.plain)
        .pressableButton()
        .accessibilityLabel(pillAccessibilityLabel)
        .accessibilityHint(isExpanded ? "Double tap to collapse" : "Double tap to expand")
        .accessibilityAddTraits(.isButton)
    }

    private var pillAccessibilityLabel: String {
        let state = isExpanded ? "expanded" : "collapsed"
        switch kind {
        case .churchNote:   return "Church note: \(title), \(state)"
        case .goingSunday:  return "Going Sunday: \(title), \(state)"
        case .verse:        return "Scripture: \(title), \(state)"
        }
    }
}

// MARK: - Expanded Card

/// Inline expanded preview card — appears directly below the collapsed pill with spring animation.
/// Content varies by attachment type. One card, one visual family.
struct LiquidGlassAttachmentExpandedCard: View {
    let kind: PostAttachmentKind
    let title: String
    let subtitle: String?
    var bodyPreview: String? = nil

    // Church Note specific
    var worshipSongs: [WorshipSongReference] = []

    // Going Sunday specific
    var churchServiceTime: String? = nil
    var churchEventName: String? = nil
    var churchEventTime: String? = nil

    // Verse specific
    var verseText: String? = nil
    var translation: String? = nil

    // Actions
    var onOpen: (() -> Void)? = nil
    var onPreview: (() -> Void)? = nil
    var onReadFull: (() -> Void)? = nil
    var onReflect: (() -> Void)? = nil
    var onGetDirections: (() -> Void)? = nil
    var onPrepReminder: (() -> Void)? = nil
    var onInviteFriend: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            expandedHeader
            typeContent
            actionRow
        }
        .padding(14)
        .background(attachmentGlassBackground(radius: 16))
    }

    // MARK: Header

    private var expandedHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(.primary)
            if let sub = subtitle {
                Text(sub)
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: Type-specific content

    @ViewBuilder
    private var typeContent: some View {
        switch kind {
        case .churchNote:
            churchNoteExpandedContent
        case .goingSunday:
            goingSundayExpandedContent
        case .verse:
            verseExpandedContent
        }
    }

    @ViewBuilder
    private var churchNoteExpandedContent: some View {
        if let preview = bodyPreview, !preview.isEmpty {
            Text(preview)
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .lineSpacing(2)
        }
        if !worshipSongs.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "music.note")
                    .font(.systemScaled(10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(worshipSongs.prefix(2).map(\.title).joined(separator: " · "))
                    .font(.systemScaled(11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var goingSundayExpandedContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let time = churchServiceTime, !time.isEmpty {
                Label(time, systemImage: "clock")
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
            }
            if let event = churchEventName, !event.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.systemScaled(11))
                        .foregroundStyle(.secondary)
                    Text(event)
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(.primary)
                    if let evTime = churchEventTime, !evTime.isEmpty {
                        Text("· \(evTime)")
                            .font(.systemScaled(11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var verseExpandedContent: some View {
        if let text = verseText, !text.isEmpty {
            Text(text)
                .font(.systemScaled(14))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .lineSpacing(3)
                .italic()
        }
        if let trans = translation, !trans.isEmpty {
            Text(trans)
                .font(.systemScaled(10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
    }

    // MARK: Action Buttons

    @ViewBuilder
    private var actionRow: some View {
        switch kind {
        case .churchNote:
            HStack(spacing: 8) {
                if let onOpen   { expandedActionButton("Open",    icon: "arrow.up.right.square", primary: true,  action: onOpen) }
                if let onPreview { expandedActionButton("Preview", icon: "eye",                  primary: false, action: onPreview) }
            }

        case .goingSunday:
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    if let onOpen          { expandedActionButton("Open",        icon: "arrow.up.right.square", primary: true,  action: onOpen) }
                    if let onGetDirections { expandedActionButton("Directions",  icon: "map",                   primary: false, action: onGetDirections) }
                }
                HStack(spacing: 8) {
                    if let onPrepReminder  { expandedActionButton("Prep Reminder", icon: "bell",              primary: false, action: onPrepReminder) }
                    if let onInviteFriend  { expandedActionButton("Invite",        icon: "person.badge.plus", primary: false, action: onInviteFriend) }
                }
            }

        case .verse:
            HStack(spacing: 8) {
                if let onOpen     { expandedActionButton("Open",      icon: "book",          primary: true,  action: onOpen) }
                if let onReadFull { expandedActionButton("Read Full", icon: "text.alignleft", primary: false, action: onReadFull) }
                if let onReflect  { expandedActionButton("Reflect",   icon: "sparkles",      primary: false, action: onReflect) }
            }
        }
    }

    @ViewBuilder
    private func expandedActionButton(
        _ label: String,
        icon: String,
        primary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            HapticManager.impact(style: .light)
            action()
        }) {
            Label(label, systemImage: icon)
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(primary ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(primary ? Color.black.opacity(0.82) : Color.white.opacity(0.50))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.black.opacity(primary ? 0 : 0.08), lineWidth: 0.6)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Post Attachment Container

/// Manages collapsed → expanded toggle for a single post attachment.
/// Animates with spring motion. Only renders glass layers, no nested blurs.
struct PostAttachmentContainer: View {
    let kind: PostAttachmentKind
    let title: String
    let subtitle: String?
    let iconSystemName: String
    var trailingMetadata: String? = nil
    var bodyPreview: String? = nil

    // Church Note
    var worshipSongs: [WorshipSongReference] = []

    // Going Sunday
    var churchServiceTime: String? = nil
    var churchEventName: String? = nil
    var churchEventTime: String? = nil

    // Verse
    var verseText: String? = nil
    var translation: String? = nil

    // Actions routed from PostCard
    var onOpen: (() -> Void)? = nil
    var onPreview: (() -> Void)? = nil
    var onReadFull: (() -> Void)? = nil
    var onReflect: (() -> Void)? = nil
    var onGetDirections: (() -> Void)? = nil
    var onPrepReminder: (() -> Void)? = nil
    var onInviteFriend: (() -> Void)? = nil

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var expandAnimation: Animation {
        reduceMotion ? .linear(duration: 0) : .interactiveSpring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.18)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LiquidGlassAttachmentPill(
                kind: kind,
                title: title,
                subtitle: subtitle,
                iconSystemName: iconSystemName,
                isExpanded: isExpanded,
                trailingMetadata: trailingMetadata,
                onTap: {
                    withAnimation(expandAnimation) {
                        isExpanded.toggle()
                    }
                }
            )

            if isExpanded {
                LiquidGlassAttachmentExpandedCard(
                    kind: kind,
                    title: title,
                    subtitle: subtitle,
                    bodyPreview: bodyPreview,
                    worshipSongs: worshipSongs,
                    churchServiceTime: churchServiceTime,
                    churchEventName: churchEventName,
                    churchEventTime: churchEventTime,
                    verseText: verseText,
                    translation: translation,
                    onOpen: onOpen,
                    onPreview: onPreview,
                    onReadFull: onReadFull,
                    onReflect: onReflect,
                    onGetDirections: onGetDirections,
                    onPrepReminder: onPrepReminder,
                    onInviteFriend: onInviteFriend
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                        removal:   .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                    )
                )
            }
        }
        .animation(expandAnimation, value: isExpanded)
    }
}

// MARK: - Attachment Reaction Kind

enum AttachmentReactionKind: String, CaseIterable {
    case spokeToMe = "spoke_to_me"
    case amen      = "amen"
    case praying   = "praying"

    var emoji: String {
        switch self {
        case .spokeToMe: return "✨"
        case .amen:      return "🙏"
        case .praying:   return "🕊️"
        }
    }

    var label: String {
        switch self {
        case .spokeToMe: return "Spoke to me"
        case .amen:      return "Amen"
        case .praying:   return "Praying"
        }
    }
}

// MARK: - Church Note Attachment Detail

/// Full-screen Church Note detail with reactions, reflective comments CTA, Berean prayer points,
/// and an Open in Selah option.
struct ChurchNoteAttachmentDetailView: View {
    let note: ChurchNote
    var postId: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var reactions: [AttachmentReactionKind: Int] = [:]
    @State private var userReaction: AttachmentReactionKind? = nil
    @State private var prayerPoints: [String] = []
    @State private var isGeneratingPrayerPoints = false
    @State private var showComments = false
    @State private var showSelah = false
    @State private var selahMessage: BereanMessage? = nil
    @State private var showPrayerPointsError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    noteHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 20)

                    noteMetadata
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                    if !note.worshipSongs.isEmpty {
                        worshipSection
                            .padding(.bottom, 20)
                    }

                    noteBody
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    prayerPointsSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    reactionBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    Divider().padding(.horizontal, 20)

                    commentsCTA
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }
            }
            .navigationTitle("Church Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selahMessage = buildSelahMessage()
                        showSelah = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "book.pages")
                                .font(.systemScaled(14))
                            Text("Selah")
                                .font(.systemScaled(14, weight: .medium))
                        }
                        .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Open in Selah reading view")
                }
            }
            .sheet(isPresented: $showComments) {
                if let pid = postId {
                    NoteReflectionCommentsSheet(postId: pid)
                }
            }
            .sheet(isPresented: $showSelah) {
                if let msg = selahMessage {
                    SelahView(message: msg, originalQuery: note.title)
                }
            }
        }
    }

    // MARK: Header

    private var noteHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "book.closed.fill")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Church Note")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().stroke(Color(.separator).opacity(0.5), lineWidth: 0.6))
            )

            Text(note.title)
                .font(.systemScaled(26, weight: .bold))
                .foregroundStyle(.primary)
                .lineSpacing(2)
        }
    }

    // MARK: Metadata

    private var noteMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let sermon = note.sermonTitle { NoteMetadataRow(label: "Sermon", value: sermon) }
            if let pastor = note.pastor     { NoteMetadataRow(label: "Pastor", value: pastor) }
            if let church = note.churchName { NoteMetadataRow(label: "Church", value: church) }
            NoteMetadataRow(label: "Date", value: note.date.formatted(date: .long, time: .omitted))
            if !note.scriptureReferences.isEmpty {
                NoteMetadataRow(label: "Scripture", value: note.scriptureReferences.joined(separator: ", "))
            }
        }
    }

    // MARK: Worship

    private var worshipSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WORSHIP")
                .font(.systemScaled(11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(note.worshipSongs) { song in
                        WorshipMusicPill(song: song)
                            .frame(width: min(280, UIScreen.main.bounds.width - 40))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Note Body

    @ViewBuilder
    private var noteBody: some View {
        let bodyText = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bodyText.isEmpty {
            Text(bodyText)
                .font(.systemScaled(15))
                .foregroundStyle(.primary)
                .lineSpacing(4)
        }
    }

    // MARK: Prayer Points

    @ViewBuilder
    private var prayerPointsSection: some View {
        if !prayerPoints.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Prayer Points", systemImage: "hands.sparkles")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(prayerPoints.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .center)
                        Text(prayerPoints[index])
                            .font(.systemScaled(14))
                            .foregroundStyle(.primary)
                            .lineSpacing(2)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
            }
            .padding(14)
            .background(attachmentGlassBackground())
        } else if note.content.count > 80 || !note.scriptureReferences.isEmpty {
            prayerPointsCTA
        }
    }

    private var prayerPointsCTA: some View {
        Button {
            Task { await generatePrayerPoints() }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(.systemGray6))
                        .frame(width: 36, height: 36)
                    Image(systemName: "hands.sparkles")
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Turn into Prayer Points")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Distill this note into prayerful responses")
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isGeneratingPrayerPoints {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .background(attachmentGlassBackground())
        }
        .buttonStyle(.plain)
        .disabled(isGeneratingPrayerPoints)
    }

    // MARK: Reactions

    private var reactionBar: some View {
        HStack(spacing: 10) {
            ForEach(AttachmentReactionKind.allCases, id: \.self) { reaction in
                Button {
                    toggleReaction(reaction)
                } label: {
                    HStack(spacing: 5) {
                        Text(reaction.emoji).font(.systemScaled(13))
                        Text(reaction.label)
                            .font(.systemScaled(12, weight: userReaction == reaction ? .semibold : .regular))
                            .foregroundStyle(userReaction == reaction ? .primary : .secondary)
                        if let count = reactions[reaction], count > 0 {
                            Text("\(count)")
                                .font(.systemScaled(11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(userReaction == reaction
                                  ? Color.black.opacity(0.07)
                                  : Color(.secondarySystemBackground))
                            .overlay(
                                Capsule().stroke(
                                    userReaction == reaction
                                        ? Color.black.opacity(0.14)
                                        : Color.clear,
                                    lineWidth: 0.8
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reaction.label)
            }
            Spacer()
        }
    }

    // MARK: Comments CTA

    private var commentsCTA: some View {
        Button {
            showComments = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Share a reflection...")
                    .font(.systemScaled(14))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Logic

    private func toggleReaction(_ reaction: AttachmentReactionKind) {
        HapticManager.impact(style: .light)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            if userReaction == reaction {
                userReaction = nil
                reactions[reaction, default: 0] = max(0, (reactions[reaction] ?? 0) - 1)
            } else {
                if let prev = userReaction {
                    reactions[prev, default: 0] = max(0, (reactions[prev] ?? 0) - 1)
                }
                userReaction = reaction
                reactions[reaction, default: 0] += 1
            }
        }
        if let pid = postId {
            Task { await persistReaction(reaction, postId: pid) }
        }
    }

    private func persistReaction(_ reaction: AttachmentReactionKind, postId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        let ref = db.collection("posts").document(postId)
            .collection("attachmentReactions").document(uid)
        if userReaction == reaction {
            try? await ref.setData([
                "kind": reaction.rawValue,
                "userId": uid,
                "createdAt": FieldValue.serverTimestamp()
            ])
        } else {
            try? await ref.delete()
        }
    }

    private func generatePrayerPoints() async {
        isGeneratingPrayerPoints = true
        defer { isGeneratingPrayerPoints = false }

        // Derive pastoral prayer points from note content.
        // In production: call `generatePrayerPointsFromChurchNote` Cloud Function.
        let content = note.content
        let refs    = note.scriptureReferences

        var points: [String] = []

        // Extract takeaway blocks
        if content.contains("Takeaway") || content.contains("takeaway") {
            points.append("Lord, let the key takeaway from this sermon take root in my heart and bear fruit this week.")
        }

        // Scripture-based prayer points
        for ref in refs.prefix(3) {
            points.append("Father, let the truth of \(ref) be alive in my life. Teach me to walk it out daily.")
        }

        // Action step prayer
        if let step = note.actionStepThisWeek, !step.isEmpty {
            points.append("Give me the courage and grace to follow through on: \(step)")
        } else if !content.isEmpty {
            points.append("Holy Spirit, help me to apply what I heard today with a willing and humble heart.")
        }

        // Intercession based on sermon themes
        if !note.title.isEmpty {
            points.append("I pray for others in my community who also need to hear this message about \(note.title.lowercased()).")
        }

        // Ensure we always have at least one point
        if points.isEmpty {
            points = [
                "Lord, seal the truths from this church note in my heart.",
                "Give me grace to live out what I've received.",
                "Let Your word not return void — work it in me and through me."
            ]
        }

        await MainActor.run {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                prayerPoints = points
            }
            HapticManager.notification(type: .success)
        }
    }

    private func buildSelahMessage() -> BereanMessage {
        var content = note.title + "\n\n"
        content += note.content
        if let sermon = note.sermonTitle { content += "\n\nSermon: \(sermon)" }
        if !note.scriptureReferences.isEmpty {
            content += "\n\nKey Scriptures: " + note.scriptureReferences.joined(separator: ", ")
        }
        if let step = note.actionStepThisWeek, !step.isEmpty {
            content += "\n\nAction This Week: \(step)"
        }
        return BereanMessage(
            id: UUID(),
            content: content,
            role: .assistant,
            timestamp: note.date,
            verseReferences: note.scriptureReferences,
            isBookmarked: false
        )
    }
}

// MARK: - Note Reflection Comments Sheet

private struct NoteReflectionCommentsSheet: View {
    let postId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // Route to the post's existing CommentsView.
            // This reuses the post comment system — reflections live as post comments.
            PostCardReflectionCommentsProxy(postId: postId)
                .navigationTitle("Reflections")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// Lightweight proxy that loads a Post by Firestore ID and presents CommentsView.
private struct PostCardReflectionCommentsProxy: View {
    let postId: String
    @State private var post: Post? = nil
    @State private var isLoading = true

    var body: some View {
        Group {
            if let post {
                CommentsView(post: post)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Reflections unavailable")
                        .font(.systemScaled(15))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await loadPost()
        }
    }

    private func loadPost() async {
        defer { isLoading = false }
        guard !postId.isEmpty else { return }
        let db = Firestore.firestore()
        if let doc = try? await db.collection("posts").document(postId).getDocument(),
           doc.exists {
            post = try? doc.data(as: Post.self)
        }
    }
}

// MARK: - Going Sunday Attachment Detail

/// Full-screen church detail for Going Sunday posts.
/// Routes to the specific church captured in the post snapshot.
/// Actions: Get Directions (Apple Maps), Prep Reminder, Invite a Friend.
struct GoingSundayAttachmentDetailView: View {
    let churchName: String
    var denomination: String? = nil
    var address: String? = nil
    var serviceTime: String? = nil
    var eventName: String? = nil
    var eventTime: String? = nil
    var postId: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showReminderSheet = false
    @State private var reminderConfirmed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    churchHero
                        .padding(.bottom, 20)

                    churchInfo
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    actionCluster
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle(churchName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showReminderSheet) {
                PrepReminderSheet(
                    churchName: churchName,
                    serviceTime: serviceTime,
                    eventTime: eventTime,
                    onConfirm: { reminderConfirmed = true }
                )
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
        }
    }

    // MARK: Hero

    private var churchHero: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color(.systemGray6), Color(.systemGray5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 150)

            VStack(spacing: 8) {
                Text(churchInitials)
                    .font(.systemScaled(38, weight: .bold))
                    .foregroundStyle(Color(.systemGray2))
            }
        }
    }

    private var churchInitials: String {
        churchName
            .components(separatedBy: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map(String.init)
            .joined()
            .uppercased()
    }

    // MARK: Info

    private var churchInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(churchName)
                .font(.systemScaled(22, weight: .bold))
                .foregroundStyle(.primary)

            if let denom = denomination, !denom.isEmpty {
                Text(denom)
                    .font(.systemScaled(14))
                    .foregroundStyle(.secondary)
            }
            if let addr = address, !addr.isEmpty {
                Label(addr, systemImage: "mappin.and.ellipse")
                    .font(.systemScaled(13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let time = serviceTime, !time.isEmpty {
                Label(time, systemImage: "clock")
                    .font(.systemScaled(13))
                    .foregroundStyle(.secondary)
            }
            if let event = eventName, !event.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                    Text(event)
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(.primary)
                    if let et = eventTime, !et.isEmpty {
                        Text("· \(et)")
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private var actionCluster: some View {
        VStack(spacing: 10) {
            churchActionButton("Get Directions", icon: "location.fill", primary: true, action: openDirections)
            churchActionButton(
                reminderConfirmed ? "Reminder Set ✓" : "Prep Reminder",
                icon: "bell.fill",
                primary: false,
                action: { showReminderSheet = true }
            )
            churchActionButton("Invite a Friend", icon: "person.badge.plus", primary: false, action: shareChurch)
        }
    }

    @ViewBuilder
    private func churchActionButton(
        _ label: String,
        icon: String,
        primary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.systemScaled(15, weight: .medium))
                Text(label)
                    .font(.systemScaled(15, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(primary ? .white : .primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(primary ? Color.black : Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private func openDirections() {
        HapticManager.impact(style: .medium)
        let query = [churchName, address].compactMap { $0 }.joined(separator: " ")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "maps://?q=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }

    private func shareChurch() {
        HapticManager.impact(style: .light)
        var shareText = "Join me at \(churchName)"
        if let time = serviceTime, !time.isEmpty { shareText += " — \(time)" }
        if let addr = address, !addr.isEmpty { shareText += "\n\(addr)" }
        let av = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }
}

// MARK: - Prep Reminder Sheet

struct PrepReminderSheet: View {
    let churchName: String
    var serviceTime: String?
    var eventTime: String?
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: ReminderOption = .tomorrowMorning

    enum ReminderOption: String, CaseIterable, Identifiable {
        case tonight        = "Tonight"
        case tomorrowMorning = "Tomorrow morning"
        case oneHourBefore  = "1 hour before service"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Set Prep Reminder")
                .font(.systemScaled(17, weight: .semibold))
                .padding(.top, 20)

            Text("When would you like to be reminded\nto prepare for \(churchName)?")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            VStack(spacing: 8) {
                ForEach(ReminderOption.allCases) { option in
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                            selected = option
                        }
                    } label: {
                        HStack {
                            Text(option.rawValue)
                                .font(.systemScaled(15, weight: selected == option ? .semibold : .regular))
                                .foregroundStyle(.primary)
                            Spacer()
                            if selected == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.black)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selected == option
                                      ? Color.black.opacity(0.06)
                                      : Color(.secondarySystemBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Button {
                HapticManager.notification(type: .success)
                onConfirm()
                dismiss()
            } label: {
                Text("Set Reminder")
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.black)
                    )
                    .padding(.horizontal, 20)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }
}

// MARK: - Verse Attachment Detail

/// Full-screen verse detail with Open in Selah (Read Full) and Reflect modes.
/// Share Context has been removed per product spec.
struct VerseAttachmentDetailView: View {
    let reference: String
    var verseText: String? = nil
    var translation: String = "NIV"

    @Environment(\.dismiss) private var dismiss
    @State private var showSelah = false
    @State private var selahQuery = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    verseHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    if let text = verseText, !text.isEmpty {
                        Text(text)
                            .font(.systemScaled(18))
                            .foregroundStyle(.primary)
                            .lineSpacing(5)
                            .italic()
                            .padding(.horizontal, 20)
                    }

                    actionRow
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                }
                .padding(.bottom, 40)
            }
            .navigationTitle(reference)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showSelah) {
            SelahView(
                message: buildSelahMessage(query: selahQuery),
                originalQuery: selahQuery
            )
        }
    }

    private var verseHeader: some View {
        HStack(spacing: 8) {
            Text(reference)
                .font(.systemScaled(22, weight: .bold))
                .foregroundStyle(.primary)

            Text(translation)
                .font(.systemScaled(10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.07)))

            Spacer()
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            verseActionButton("Read Full", icon: "text.alignleft", primary: true) {
                selahQuery = "Read \(reference)"
                showSelah = true
            }
            verseActionButton("Reflect", icon: "sparkles", primary: false) {
                selahQuery = "Reflect on \(reference): what is God saying to me through this?"
                showSelah = true
            }
        }
    }

    @ViewBuilder
    private func verseActionButton(
        _ label: String,
        icon: String,
        primary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            HapticManager.impact(style: .light)
            action()
        }) {
            Label(label, systemImage: icon)
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(primary ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(primary ? Color.black.opacity(0.85) : Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.black.opacity(primary ? 0 : 0.06), lineWidth: 0.6)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func buildSelahMessage(query: String) -> BereanMessage {
        let isReflect = query.contains("Reflect")
        let content: String
        if isReflect {
            content = "Pause and reflect on \(reference).\n\n\(verseText ?? reference)\n\nWhat is God saying to you through this today?"
        } else {
            content = "\(reference) (\(translation))\n\n\(verseText ?? reference)"
        }
        return BereanMessage(
            id: UUID(),
            content: content,
            role: .assistant,
            timestamp: Date(),
            verseReferences: [reference],
            isBookmarked: false
        )
    }
}
