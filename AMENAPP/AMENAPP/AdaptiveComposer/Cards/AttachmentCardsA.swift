// AttachmentCardsA.swift
// AMEN — Smart Attachment Cards Set A
// Scripture, Prayer, Event, ChurchNote, Poll + GenericAttachmentCard + dispatcher
import SwiftUI

// MARK: - Internal gold color (avoids collision with AmenAdaptiveColors.amenGold / AmenTheme)

private let _acAmenGold = Color(red: 198 / 255, green: 151 / 255, blue: 63 / 255)

// MARK: - AttachmentCardView (dispatcher — exhaustive, no default)

struct AttachmentCardView: View {
    let attachment: ComposerAttachment
    let onRemove: () -> Void

    var body: some View {
        switch attachment {
        // Set A
        case .scripture(let payload):
            AC_ScriptureCard(payload: payload, onRemove: onRemove)
        case .prayer(let payload):
            AC_PrayerCard(payload: payload, onRemove: onRemove)
        case .event(let payload):
            AC_EventCard(payload: payload, onRemove: onRemove)
        case .churchNote(let payload):
            AC_ChurchNoteCard(payload: payload, onRemove: onRemove)
        case .poll(let payload):
            AC_PollCard(payload: payload, onRemove: onRemove)
        // Set B
        case .music(let payload):
            AC_MusicCard(payload: payload, onRemove: onRemove)
        case .podcast(let payload):
            AC_PodcastCard(payload: payload, onRemove: onRemove)
        case .youtube(let payload):
            AC_YouTubeCard(payload: payload, onRemove: onRemove)
        case .location(let payload):
            AC_LocationCard(payload: payload, onRemove: onRemove)
        case .file(let payload):
            AC_FileCard(payload: payload, onRemove: onRemove)
        case .checklist(let payload):
            AC_ChecklistCard(payload: payload, onRemove: onRemove)
        // Set C
        case .donation(let payload):
            AC_DonationCard(payload: payload, onRemove: onRemove)
        case .volunteer(let payload):
            AC_VolunteerCard(payload: payload, onRemove: onRemove)
        case .announcement(let payload):
            AC_AnnouncementCard(payload: payload, onRemove: onRemove)
        case .rsvp(let payload):
            AC_RSVPCard(payload: payload, onRemove: onRemove)
        case .directions(let payload):
            AC_DirectionsCard(payload: payload, onRemove: onRemove)
        case .voice(let payload):
            AC_VoiceCard(payload: payload, onRemove: onRemove)
        case .video(let payload):
            AC_VideoCard(payload: payload, onRemove: onRemove)
        case .task(let payload):
            AC_TaskCard(payload: payload, onRemove: onRemove)
        case .reminder(let payload):
            AC_ReminderCard(payload: payload, onRemove: onRemove)
        case .link(let payload):
            AC_LinkCard(payload: payload, onRemove: onRemove)
        case .bibleStudy(let payload):
            AC_BibleStudyCard(payload: payload, onRemove: onRemove)
        case .discussionThread(let payload):
            AC_DiscussionThreadCard(payload: payload, onRemove: onRemove)
        // Church-only types — dedicated card views in a future church-tools build;
        // rendered with a labeled generic card until then.
        case .sermon(let payload):
            AC_GenericAttachmentCard(typeLabel: "Sermon · \(payload.title)", onRemove: onRemove)
        case .worshipSong(let payload):
            AC_GenericAttachmentCard(typeLabel: "Worship · \(payload.title)", onRemove: onRemove)
        case .teachingSeries(let payload):
            AC_GenericAttachmentCard(typeLabel: "Series · \(payload.seriesTitle)", onRemove: onRemove)
        case .ministryForm(let payload):
            AC_GenericAttachmentCard(typeLabel: "Ministry Form · \(payload.title)", onRemove: onRemove)
        }
    }
}

// MARK: - AC_CardContainer (shared glass shell)

private struct AC_CardContainer<Content: View>: View {
    let onRemove: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                reduceTransparency
                    ? AnyShapeStyle(Color(.secondarySystemBackground))
                    : AnyShapeStyle(.ultraThinMaterial),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5)
            )

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Remove attachment")
            .padding(.top, 2)
            .padding(.trailing, 2)
        }
    }
}

// MARK: - AC_GenericAttachmentCard

struct AC_GenericAttachmentCard: View {
    let typeLabel: String
    let onRemove: () -> Void

    var body: some View {
        AC_CardContainer(onRemove: onRemove) {
            HStack(spacing: 10) {
                Image(systemName: "paperclip")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHidden(true)
                Text(typeLabel.capitalized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - AC_ScriptureCard

private struct AC_ScriptureCard: View {
    let payload: ScripturePayload
    let onRemove: () -> Void

    @State private var isExpanded = true
    @State private var selectedTranslation: AC_BibleTranslation

    init(payload: ScripturePayload, onRemove: @escaping () -> Void) {
        self.payload = payload
        self.onRemove = onRemove
        let initial = AC_BibleTranslation(rawValue: payload.translation.uppercased()) ?? .niv
        _selectedTranslation = State(initialValue: initial)
    }

    var body: some View {
        AC_CardContainer(onRemove: onRemove) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(_acAmenGold)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payload.reference)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(selectedTranslation.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 44)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scripture: \(payload.reference), \(selectedTranslation.rawValue)")
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text(payload.text)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        ForEach(AC_BibleTranslation.allCases, id: \.self) { translation in
                            AC_TranslationChip(
                                label: translation.rawValue,
                                isSelected: selectedTranslation == translation
                            ) {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    selectedTranslation = translation
                                }
                            }
                        }
                        Spacer()
                    }
                    .accessibilityLabel("Translation picker")

                    Button {
                        // TODO: open Berean study for payload.reference
                    } label: {
                        Label("Study in Berean", systemImage: "magnifyingglass")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(_acAmenGold)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Study \(payload.reference) in Berean")
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private enum AC_BibleTranslation: String, CaseIterable {
    case niv = "NIV"
    case esv = "ESV"
    case kjv = "KJV"
    case nlt = "NLT"
    case nasb = "NASB"
}

private struct AC_TranslationChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? _acAmenGold : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isSelected
                        ? _acAmenGold.opacity(0.15)
                        : Color(.tertiarySystemFill),
                    in: Capsule()
                )
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("\(label) translation\(isSelected ? ", selected" : "")")
    }
}

// MARK: - AC_PrayerCard

private struct AC_PrayerCard: View {
    let payload: PrayerPayload
    let onRemove: () -> Void

    @State private var isExpanded = true
    @State private var localPrayCount: Int

    init(payload: PrayerPayload, onRemove: @escaping () -> Void) {
        self.payload = payload
        self.onRemove = onRemove
        _localPrayCount = State(initialValue: payload.prayCount)
    }

    var body: some View {
        AC_CardContainer(onRemove: onRemove) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "hands.sparkles.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.purple)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        // NEVER show authorId when isAnonymous
                        Text(payload.isAnonymous ? "Anonymous Prayer" : "Prayer Request")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("\(localPrayCount) praying")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 44)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(payload.isAnonymous ? "Anonymous prayer request" : "Prayer request")
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text(payload.text)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            localPrayCount += 1
                        }
                        // TODO: Firestore increment prayCount for circleId
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "hands.sparkles")
                                .accessibilityHidden(true)
                            Text("Pray (\(localPrayCount))")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.purple)
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pray for this request, \(localPrayCount) people praying")
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - AC_EventCard

private struct AC_EventCard: View {
    let payload: EventPayload
    let onRemove: () -> Void

    @State private var isExpanded = true
    @State private var rsvpState: AC_RSVPState = .none

    var body: some View {
        AC_CardContainer(onRemove: onRemove) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payload.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(AC_EventCard.formattedDate(payload.startDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 44)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Event: \(payload.title), \(AC_EventCard.formattedDate(payload.startDate))")
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if let location = payload.location {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("\(payload.rsvpCount) going")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        AC_RSVPButton(label: "Going", icon: "checkmark", state: $rsvpState, value: .yes) {
                            // TODO: Firestore RSVP yes
                        }
                        AC_RSVPButton(label: "Maybe", icon: "questionmark", state: $rsvpState, value: .maybe) {
                            // TODO: Firestore RSVP maybe
                        }
                        AC_RSVPButton(label: "Can't Go", icon: "xmark", state: $rsvpState, value: .no) {
                            // TODO: Firestore RSVP no
                        }
                        Spacer()
                    }

                    HStack(spacing: 16) {
                        Button {
                            // TODO: Add to Calendar via EventKit
                        } label: {
                            Label("Add to Calendar", systemImage: "calendar.badge.plus")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.blue)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(payload.title) to Calendar")

                        if payload.location != nil {
                            Button {
                                // TODO: Open Maps with location
                            } label: {
                                Label("Get Directions", systemImage: "map")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.blue)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Get directions to \(payload.location ?? "")")
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    static func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

private enum AC_RSVPState { case yes, no, maybe, none }

private struct AC_RSVPButton: View {
    let label: String
    let icon: String
    @Binding var state: AC_RSVPState
    let value: AC_RSVPState
    let action: () -> Void

    private var isSelected: Bool { state == value }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                state = isSelected ? .none : value
            }
            if !isSelected { action() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? .white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected ? Color.blue : Color(.tertiarySystemFill),
                in: Capsule()
            )
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label)\(isSelected ? ", selected" : "")")
        .accessibilityHint("Tap to select \(label) as your RSVP")
    }
}

// MARK: - AC_ChurchNoteCard

private struct AC_ChurchNoteCard: View {
    let payload: ChurchNotePayload
    let onRemove: () -> Void

    @State private var isExpanded = true

    var body: some View {
        AC_CardContainer(onRemove: onRemove) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "note.text")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(_acAmenGold)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payload.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("Church Note")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 44)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Church note: \(payload.title)")
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text(payload.content)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(6)

                    Button {
                        // TODO: Navigate to Selah with payload.churchId note
                    } label: {
                        Label("Open in Selah", systemImage: "book.closed.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(_acAmenGold)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(payload.title) in Selah")
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - AC_PollCard

private struct AC_PollCard: View {
    let payload: PollPayload
    let onRemove: () -> Void

    @State private var isExpanded = true
    @State private var votedOption: String?

    var body: some View {
        AC_CardContainer(onRemove: onRemove) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payload.question)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(payload.totalVotes) vote\(payload.totalVotes == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 44)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Poll: \(payload.question), \(payload.totalVotes) votes")
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(payload.options, id: \.self) { option in
                        AC_PollOptionRow(
                            option: option,
                            voteCount: payload.votesByOption[option] ?? 0,
                            totalVotes: payload.totalVotes,
                            isVoted: votedOption == option,
                            hasVotedAny: votedOption != nil
                        ) {
                            guard votedOption == nil else { return }
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                votedOption = option
                            }
                            // TODO: Firestore increment votesByOption[option] and totalVotes
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct AC_PollOptionRow: View {
    let option: String
    let voteCount: Int
    let totalVotes: Int
    let isVoted: Bool
    let hasVotedAny: Bool
    let onVote: () -> Void

    private var fraction: Double {
        guard totalVotes > 0 else { return 0 }
        return Double(voteCount) / Double(totalVotes)
    }

    var body: some View {
        Button(action: onVote) {
            ZStack(alignment: .leading) {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isVoted ? Color.green.opacity(0.15) : Color(.tertiarySystemFill))
                        .frame(width: hasVotedAny ? geo.size.width * fraction : geo.size.width)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: fraction)
                }
                HStack {
                    Text(option)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    if hasVotedAny {
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if isVoted {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(minHeight: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(hasVotedAny)
        .accessibilityLabel("\(option)\(isVoted ? ", your vote" : "")\(hasVotedAny ? ", \(Int((fraction * 100).rounded())) percent" : "")")
        .accessibilityHint(hasVotedAny ? "" : "Tap to vote for \(option)")
    }
}
