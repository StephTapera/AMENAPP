// AttachmentCardsC.swift
// AMEN — Smart Attachment Cards Set C
// DonationCard, VolunteerCard, AnnouncementCard, RSVPCard, DirectionsCard,
// VoiceCard, VideoCard, TaskCard, ReminderCard, LinkCard,
// BibleStudyCard, DiscussionThreadCard
import SwiftUI
import MapKit

// MARK: - Module-local gold constant

private let _accGold = Color(red: 198 / 255, green: 151 / 255, blue: 63 / 255)

// MARK: - AdaptiveCardContainer
// Defined in AttachmentCardsB.swift (same module — no import needed).
// Used directly here; no redeclaration.

// MARK: - AC_DonationCard

struct AC_DonationCard: View {
    let payload: DonationPayload
    let onRemove: () -> Void

    private let stripeEnabled: Bool = false

    private var progress: Double {
        guard payload.goalAmount > 0 else { return 0 }
        return min(payload.raisedAmount / payload.goalAmount, 1.0)
    }

    private var progressPercent: Int {
        Int((progress * 100).rounded())
    }

    var body: some View {
        AdaptiveCardContainer(onRemove: onRemove) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(_accGold)
                        .accessibilityHidden(true)
                    Text(payload.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 44)
                }
                .frame(minHeight: 44)

                // Progress bar
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(.tertiarySystemFill))
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(_accGold)
                                .frame(width: geo.size.width * progress, height: 8)
                                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
                        }
                    }
                    .frame(height: 8)
                    .accessibilityLabel("Donation progress: \(progressPercent) percent of goal")

                    HStack {
                        Text("\(payload.currency)\(Int(payload.raisedAmount)) raised")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Goal: \(payload.currency)\(Int(payload.goalAmount))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    // TODO: Open Stripe donation flow when stripeEnabled = true
                } label: {
                    Text(stripeEnabled ? "Give Now" : "Payment Setup Required")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(stripeEnabled ? .white : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(
                            stripeEnabled ? _accGold : Color(.tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!stripeEnabled)
                .accessibilityLabel(stripeEnabled ? "Give to \(payload.title)" : "Payment Setup Required — giving unavailable")
                .accessibilityHint(stripeEnabled ? "Opens donation flow" : "Stripe payments have not been configured")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - AC_VolunteerCard

struct AC_VolunteerCard: View {
    let payload: VolunteerPayload
    let onRemove: () -> Void

    private var slotsRemaining: Int {
        max(payload.slotsTotal - payload.slotsFilled, 0)
    }

    private var isFull: Bool { slotsRemaining == 0 }

    var body: some View {
        AdaptiveCardContainer(onRemove: onRemove) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.teal)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payload.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(payload.slotsFilled)/\(payload.slotsTotal) slots filled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 44)
                }
                .frame(minHeight: 44)

                if !payload.description.isEmpty {
                    Text(payload.description)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(4)
                }

                Button {
                    // TODO: Open volunteer signup URL or sheet
                } label: {
                    Text(isFull ? "Slots Full" : "Sign Up to Volunteer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isFull ? Color.secondary : .white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(
                            isFull ? Color(.tertiarySystemFill) : Color.teal,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isFull)
                .accessibilityLabel(isFull ? "Volunteer slots are full" : "Sign up to volunteer for \(payload.title)")
                .accessibilityHint(isFull ? "" : "\(slotsRemaining) slot\(slotsRemaining == 1 ? "" : "s") remaining")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - AC_AnnouncementCard

struct AC_AnnouncementCard: View {
    let payload: AnnouncementPayload
    let onRemove: () -> Void

    @State private var isExpanded = true

    private var showPriorityBadge: Bool { payload.priority > 1 }

    private var priorityLabel: String {
        switch payload.priority {
        case 2: return "Important"
        case 3: return "Urgent"
        default: return "Priority \(payload.priority)"
        }
    }

    var body: some View {
        AdaptiveCardContainer(onRemove: onRemove) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(payload.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if showPriorityBadge {
                                Text(priorityLabel)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange, in: Capsule())
                                    .accessibilityLabel("\(priorityLabel) announcement")
                            }
                        }
                        Text("Announcement")
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
            .accessibilityLabel("Announcement: \(payload.title)\(showPriorityBadge ? ", \(priorityLabel)" : "")")
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")

            if isExpanded {
                Text(payload.body)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - AC_RSVPCard

struct AC_RSVPCard: View {
    let payload: RSVPPayload
    let onRemove: () -> Void

    @State private var userResponse: AC_C_RSVPResponse = .none

    var body: some View {
        AdaptiveCardContainer(onRemove: onRemove) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payload.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(payload.yesCount) going · \(payload.maybeCount) maybe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 44)
                }
                .frame(minHeight: 44)

                HStack(spacing: 8) {
                    AC_C_RSVPChip(label: "Going", icon: "checkmark", response: $userResponse, value: .going) {
                        // TODO: Firestore update RSVP yes for payload.eventId
                    }
                    AC_C_RSVPChip(label: "Maybe", icon: "questionmark", response: $userResponse, value: .maybe) {
                        // TODO: Firestore update RSVP maybe for payload.eventId
                    }
                    AC_C_RSVPChip(label: "Can't Go", icon: "xmark", response: $userResponse, value: .cantGo) {
                        // TODO: Firestore update RSVP no for payload.eventId
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }
}

private enum AC_C_RSVPResponse: Equatable { case going, maybe, cantGo, none }

private struct AC_C_RSVPChip: View {
    let label: String
    let icon: String
    @Binding var response: AC_C_RSVPResponse
    let value: AC_C_RSVPResponse
    let onSelect: () -> Void

    private var isSelected: Bool { response == value }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                response = isSelected ? .none : value
            }
            if !isSelected { onSelect() }
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
        .accessibilityHint("Tap to RSVP as \(label)")
    }
}

// MARK: - AC_DirectionsCard

struct AC_DirectionsCard: View {
    let payload: DirectionsPayload
    let onRemove: () -> Void

    @State private var snapshotImage: UIImage?
    @State private var snapshotError = false

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: payload.latitude, longitude: payload.longitude)
    }

    var body: some View {
        AdaptiveCardContainer(onRemove: onRemove) {
            VStack(alignment: .leading, spacing: 0) {
                // Map snapshot
                Group {
                    if let img = snapshotImage {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: 140)
                            .clipped()
                            .accessibilityLabel("Map showing \(payload.name)")
                    } else if snapshotError {
                        Rectangle()
                            .fill(Color(.tertiarySystemFill))
                            .frame(maxWidth: .infinity, minHeight: 140)
                            .overlay(
                                Label("Map unavailable", systemImage: "map.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            )
                            .accessibilityLabel("Map unavailable for \(payload.name)")
                    } else {
                        Rectangle()
                            .fill(Color(.tertiarySystemFill))
                            .frame(maxWidth: .infinity, minHeight: 140)
                            .overlay(ProgressView().accessibilityLabel("Loading map"))
                    }
                }
                .cornerRadius(12)
                .padding(.horizontal, 14)
                .padding(.top, 14)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(payload.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(payload.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 44)
                    }
                    .frame(minHeight: 44)

                    HStack(spacing: 12) {
                        Button {
                            openInMaps()
                        } label: {
                            Label("Open in Maps", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.blue)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(payload.name) in Maps")

                        Button {
                            UIPasteboard.general.string = payload.address
                        } label: {
                            Label("Copy Address", systemImage: "doc.on.doc")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Copy address for \(payload.name)")

                        Spacer()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .task {
            await loadSnapshot()
        }
    }

    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = payload.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    @MainActor
    private func loadSnapshot() async {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        options.size = CGSize(width: 600, height: 280)
        options.mapType = .standard
        options.showsBuildings = true
        do {
            let snapshotter = MKMapSnapshotter(options: options)
            let snapshot = try await snapshotter.start()
            snapshotImage = snapshot.image
        } catch {
            snapshotError = true
        }
    }
}

// MARK: - AC_VoiceCard

struct AC_VoiceCard: View {
    let payload: VoicePayload
    let onRemove: () -> Void

    @State private var isPlaying = false

    /// Waveform bars capped at 40 samples
    private var bars: [Float] {
        Array(payload.waveformData.prefix(40))
    }

    private var durationText: String {
        let secs = Int(payload.durationSeconds)
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    var body: some View {
        AdaptiveCardContainer(onRemove: onRemove) {
            HStack(spacing: 12) {
                Button {
                    // TODO: Wire AVPlayer for payload.downloadURL
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(_accGold)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause voice message" : "Play voice message")
                .accessibilityHint("Duration: \(durationText)")

                // Waveform
                HStack(alignment: .center, spacing: 2) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, amplitude in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(isPlaying ? _accGold : Color.secondary.opacity(0.5))
                            .frame(width: 3, height: max(4, CGFloat(amplitude) * 36))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .animation(.easeInOut(duration: 0.3), value: isPlaying)
                .accessibilityLabel("Audio waveform")

                Text(durationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Duration: \(durationText)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - AC_VideoCard

struct AC_VideoCard: View {
    let payload: VideoPayload
    let onRemove: () -> Void

    @State private var isPlaying = false

    private var durationText: String {
        let secs = Int(payload.durationSeconds)
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    var body: some View {
        AdaptiveCardContainer(onRemove: onRemove) {
            ZStack {
                // Thumbnail
                if let urlString = payload.thumbnailURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Rectangle().fill(Color(.tertiarySystemFill))
                        case .empty:
                            Rectangle().fill(Color(.tertiarySystemFill))
                                .overlay(ProgressView())
                        @unknown default:
                            Rectangle().fill(Color(.tertiarySystemFill))
                        }
                    }
                } else {
                    Rectangle()
                        .fill(Color(.tertiarySystemFill))
                        .overlay(
                            Image(systemName: "video.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary.opacity(0.5))
                        )
                }

                // Play button overlay
                Button {
                    // TODO: Open AVPlayer fullscreen for payload.downloadURL
                    isPlaying.toggle()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.45))
                            .frame(width: 56, height: 56)
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(x: isPlaying ? 0 : 2)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause video" : "Play video")

                // Duration badge
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(durationText)
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                            .padding(8)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()
            .cornerRadius(12)
            .padding(14)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Video attachment, duration \(durationText)")
        }
    }
}

// MARK: - AC_TaskCard

struct AC_TaskCard: View {
    let payload: TaskPayload
    let onRemove: () -> Void

    @State private var isCompleted: Bool

    init(payload: TaskPayload, onRemove: @escaping () -> Void) {
        self.payload = payload
        self.onRemove = onRemove
        _isCompleted = State(initialValue: payload.isCompleted)
    }

    var body: some View {
        AdaptiveCardContainer(onRemove: onRemove) {
            HStack(spacing: 12) {
                Toggle("", isOn: $isCompleted)
                    .labelsHidden()
                    .tint(_accGold)
                    .frame(minWidth: 44, minHeight: 44)
                    .onChange(of: isCompleted) { _, newValue in
                        // TODO: Firestore update isCompleted for payload.spaceId task
                        _ = newValue
                    }
                    .accessibilityLabel(isCompleted ? "Mark task incomplete" : "Mark task complete")

                VStack(alignment: .leading, spacing: 4) {
                    Text(payload.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                        .strikethrough(isCompleted, color: .secondary)
                        .lineLimit(2)
                        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isCompleted)
                        .accessibilityHidden(true)

                    if let due = payload.dueDate {
                        Text("Due \(AC_TaskCard.formattedDate(due))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    static func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f.string(from: date)
    }
}

// MARK: - AC_ReminderCard

struct AC_ReminderCard: View {
    let payload: AdaptiveComposerReminderPayload
    let onRemove: () -> Void

    var body: some View {
        AdaptiveCardContainer(onRemove: onRemove) {
            HStack(spacing: 12) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(_accGold)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(payload.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(AC_ReminderCard.formattedTrigger(payload.triggerDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let recurrence = payload.recurrence {
                        Text("Repeats: \(recurrence)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    // TODO: Add to Reminders via EventKit/UserNotifications
                } label: {
                    Text("Add")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(_accGold, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(payload.title) to Reminders")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    static func formattedTrigger(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - AC_LinkCard

struct AC_LinkCard: View {
    let payload: LinkPayload
    let onRemove: () -> Void

    var body: some View {
        AdaptiveCardContainer(onRemove: onRemove) {
            VStack(alignment: .leading, spacing: 0) {
                // Preview image
                if let imageURLString = payload.imageURL, let imageURL = URL(string: imageURLString) {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .frame(height: 120)
                                .clipped()
                        case .failure:
                            EmptyView()
                        case .empty:
                            Rectangle()
                                .fill(Color(.tertiarySystemFill))
                                .frame(maxWidth: .infinity)
                                .frame(height: 120)
                                .overlay(ProgressView())
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .cornerRadius(12)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .accessibilityLabel("Link preview image for \(payload.title ?? payload.domain)")
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "link")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        if let title = payload.title {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                        if let description = payload.description {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        Text(payload.domain)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }

                    Spacer()

                    Button {
                        if let url = URL(string: payload.url) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(.blue, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open link: \(payload.title ?? payload.domain)")
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }
}

// MARK: - AC_BibleStudyCard

struct AC_BibleStudyCard: View {
    let payload: BibleStudyPayload
    let onRemove: () -> Void

    @State private var isExpanded = true

    var body: some View {
        AdaptiveCardContainer(onRemove: onRemove) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(_accGold)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payload.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(payload.passages.count) passage\(payload.passages.count == 1 ? "" : "s")")
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
            .accessibilityLabel("Bible study: \(payload.title)")
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Passages list
                    ForEach(payload.passages, id: \.self) { passage in
                        HStack(spacing: 8) {
                            Image(systemName: "book.pages")
                                .font(.caption)
                                .foregroundStyle(_accGold)
                                .accessibilityHidden(true)
                            Text(passage)
                                .font(.callout)
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("Passage: \(passage)")
                    }

                    if !payload.studyNotes.isEmpty {
                        Text(payload.studyNotes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(4)
                    }

                    if payload.groupId != nil {
                        Button {
                            // TODO: Navigate to Bible study group for payload.groupId
                        } label: {
                            Label("Join Group", systemImage: "person.3.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                                .background(_accGold, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Join Bible study group for \(payload.title)")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - AC_DiscussionThreadCard

struct AC_DiscussionThreadCard: View {
    let payload: DiscussionThreadPayload
    let onRemove: () -> Void

    @State private var isExpanded = true

    var body: some View {
        AdaptiveCardContainer(onRemove: onRemove) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.indigo)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payload.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(payload.postCount) post\(payload.postCount == 1 ? "" : "s")")
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
            .accessibilityLabel("Discussion: \(payload.title), \(payload.postCount) posts")
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text(payload.prompt)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(5)

                    Button {
                        // TODO: Navigate to discussion for payload.communityId
                    } label: {
                        Label("Join Discussion", systemImage: "arrow.right.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(.indigo, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Join discussion: \(payload.title)")
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
