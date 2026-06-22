// AttachmentCardsA.swift
// AMEN — Smart Attachment Cards Set A
// Scripture, Prayer, Event, ChurchNote, Poll + GenericAttachmentCard + dispatcher
import SwiftUI
import EventKit
import FirebaseFirestore
import FirebaseAuth
import MapKit
import CoreLocation

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
        let initial = AC_BibleTranslation(rawValue: payload.translation.uppercased()) ?? .kjv // TODO(legal): was .niv default — now KJV (public domain)
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

                    // BTN-002 LANE-8: gated OFF — BereanNavigationService not yet available at this call site
                    if AMENFeatureFlags.shared.bereanIslandEnabled {
                        Button {
                            // Wire: post deep-link notification for BereanIslandStateMachine to pick up
                            NotificationCenter.default.post(
                                name: Notification.Name("berean.openStudy"),
                                object: nil,
                                userInfo: ["reference": payload.reference]
                            )
                        } label: {
                            Label("Study in Berean", systemImage: "magnifyingglass")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(_acAmenGold)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Study \(payload.reference) in Berean")
                        .accessibilityHint("Opens Berean AI study for this passage")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// TODO(legal): Add NIV/ESV/NLT/NASB back once commercial licenses confirmed (AMEN-CONTENT-001).
// NIV (Biblica), ESV (Crossway), NLT (Tyndale), NASB (Lockman Foundation) are copyrighted — removed from picker.
// Allowed: KJV (public domain), WEB (public domain), BSB (open license).
private enum AC_BibleTranslation: String, CaseIterable {
    case kjv = "KJV"
    case web = "WEB"
    case bsb = "BSB"
    // case niv = "NIV"   // TODO(legal): restore once NIV (Biblica) license confirmed
    // case esv = "ESV"   // TODO(legal): restore once ESV (Crossway) license confirmed
    // case nlt = "NLT"   // TODO(legal): restore once NLT (Tyndale) license confirmed
    // case nasb = "NASB" // TODO(legal): restore once NASB (Lockman Foundation) license confirmed
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
                        // BTN-002 LANE-8: Firestore increment prayCount for this prayer request
                        if let circleId = payload.circleId,
                           let uid = Auth.auth().currentUser?.uid {
                            let db = Firestore.firestore()
                            db.collection("prayerCircles").document(circleId)
                                .updateData([
                                    "prayCount": FieldValue.increment(Int64(1)),
                                    "prayedBy.\(uid)": FieldValue.serverTimestamp()
                                ])
                        }
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
    let payload: AdaptiveComposerEventPayload
    let onRemove: () -> Void

    @State private var isExpanded = true
    @State private var rsvpState: AC_RSVPState = .none
    @State private var isAddingToCalendar = false

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
                        // BTN-002 LANE-8: RSVP buttons wired to Firestore via CalendarService
                        AC_RSVPButton(label: "Going", icon: "checkmark", state: $rsvpState, value: .yes) {
                            Task { try? await CalendarService.shared.rsvp(
                                eventId: AC_EventCard.payloadKey(payload),
                                status: .going
                            )}
                        }
                        AC_RSVPButton(label: "Maybe", icon: "questionmark", state: $rsvpState, value: .maybe) {
                            Task { try? await CalendarService.shared.rsvp(
                                eventId: AC_EventCard.payloadKey(payload),
                                status: .maybe
                            )}
                        }
                        AC_RSVPButton(label: "Can't Go", icon: "xmark", state: $rsvpState, value: .no) {
                            Task { try? await CalendarService.shared.rsvp(
                                eventId: AC_EventCard.payloadKey(payload),
                                status: .notGoing
                            )}
                        }
                        Spacer()
                    }

                    HStack(spacing: 16) {
                        // BTN-002 LANE-8: Add to Calendar — wired to EventKit via EKEventStore
                        Button {
                            Task {
                                isAddingToCalendar = true
                                let granted = await CalendarService.shared.requestCalendarPermission()
                                if granted {
                                    // Build and save a minimal EKEvent directly
                                    let store = EKEventStore()
                                    let ekEvent = EKEvent(eventStore: store)
                                    ekEvent.title = payload.title
                                    ekEvent.startDate = payload.startDate
                                    ekEvent.endDate = payload.endDate ?? payload.startDate.addingTimeInterval(3600)
                                    ekEvent.location = payload.location
                                    ekEvent.calendar = store.defaultCalendarForNewEvents
                                    try? store.save(ekEvent, span: .thisEvent)
                                }
                                isAddingToCalendar = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if isAddingToCalendar {
                                    ProgressView().scaleEffect(0.7)
                                }
                                Label("Add to Calendar", systemImage: "calendar.badge.plus")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.blue)
                            }
                            .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(isAddingToCalendar)
                        .accessibilityLabel("Add \(payload.title) to Calendar")

                        if let location = payload.location {
                            // BTN-002 LANE-8: Get Directions — wired to MKMapItem
                            Button {
                                let geocoder = CLGeocoder()
                                geocoder.geocodeAddressString(location) { placemarks, _ in
                                    let coordinate = placemarks?.first?.location?.coordinate
                                    let placemark = MKPlacemark(
                                        coordinate: coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                                    )
                                    let mapItem = MKMapItem(placemark: placemark)
                                    mapItem.name = location
                                    mapItem.openInMaps(launchOptions: [
                                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                                    ])
                                }
                            } label: {
                                Label("Get Directions", systemImage: "map")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.blue)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Get directions to \(location)")
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

    /// Stable identifier derived from payload fields (EventPayload has no explicit id field).
    static func payloadKey(_ payload: AdaptiveComposerEventPayload) -> String {
        "\(payload.title)-\(Int(payload.startDate.timeIntervalSince1970))"
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

                    // BTN-002 LANE-8: gated OFF — Selah deep-link navigation pending SelahNavigationService
                    if AMENFeatureFlags.shared.selahScriptureActionsEnabled {
                        Button {
                            NotificationCenter.default.post(
                                name: Notification.Name("selah.openNote"),
                                object: nil,
                                userInfo: ["churchId": payload.churchId, "title": payload.title]
                            )
                        } label: {
                            Label("Open in Selah", systemImage: "book.closed.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(_acAmenGold)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(payload.title) in Selah")
                        .accessibilityHint("Opens this church note in the Selah reader")
                    }
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
    /// Caller may inject the parent postId via the environment so votes reach Firestore.
    /// Falls back to nil — optimistic UI still works without the postId.
    @Environment(\.adaptiveComposerPostId) private var postId

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
                            // BTN-002 LANE-8: wire poll vote to PollService when postId is available
                            if let pid = postId {
                                Task { try? await PollService.shared.vote(postId: pid, optionId: option) }
                            }
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

// MARK: - Environment key: adaptiveComposerPostId
// Caller injects the parent post's Firestore document ID so attachment cards can write back.

private struct AC_PostIdKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var adaptiveComposerPostId: String? {
        get { self[AC_PostIdKey.self] }
        set { self[AC_PostIdKey.self] = newValue }
    }
}
