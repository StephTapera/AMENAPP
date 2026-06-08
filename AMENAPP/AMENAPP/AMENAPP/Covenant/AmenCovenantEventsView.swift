import SwiftUI
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

// MARK: - Amen Covenant Events View

struct AmenCovenantEventsView: View {
    let covenantId: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var vm = AmenCovenantEventsViewModel()
    @State private var expandedDescriptions: Set<String> = []
    @State private var toastMessage: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 20) {
                    if vm.isLoading {
                        loadingSection
                    } else {
                        upcomingSection
                        pastEventsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }

            if let toast = toastMessage {
                toastBanner(message: toast)
                    .transition(
                        reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                    )
                    .padding(.bottom, 24)
            }
        }
        .task { await vm.load(covenantId: covenantId) }
    }

    // MARK: - Upcoming Section

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Upcoming Events", icon: "calendar")
            if vm.upcomingEvents.isEmpty {
                emptyState(
                    icon: "calendar.badge.plus",
                    message: "No upcoming events.\nCheck back later."
                )
            } else {
                ForEach(vm.upcomingEvents) { event in
                    eventCard(event)
                }
            }
        }
    }

    // MARK: - Past Events Section

    private var pastEventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.75)) {
                    vm.showPastEvents.toggle()
                }
            } label: {
                HStack {
                    sectionHeader(title: "Past Events", icon: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    Spacer()
                    Image(systemName: vm.showPastEvents ? "chevron.up" : "chevron.down")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if vm.showPastEvents {
                if vm.pastEvents.isEmpty {
                    emptyState(icon: "calendar", message: "No past events yet.")
                } else {
                    ForEach(vm.pastEvents) { event in
                        eventCard(event)
                            .opacity(0.65)
                    }
                }
            }
        }
    }

    // MARK: - Event Card

    private func eventCard(_ event: AmenCovenantEventsViewModel.EventItem) -> some View {
        let isExpanded = expandedDescriptions.contains(event.id)

        return VStack(alignment: .leading, spacing: 0) {
            // Header strip: location type badge + visibility
            HStack(spacing: 8) {
                locationBadge(event.locationType)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)

            // Title
            Text(event.title)
                .font(.systemScaled(18, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)
                .padding(.bottom, 4)

            // Date / time
            Text(formattedDate(event.startAt))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            // Meeting URL domain (online/hybrid)
            if let url = event.meetingUrl, !url.isEmpty,
               event.locationType == "online" || event.locationType == "hybrid",
               let host = URL(string: url)?.host {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                    Text(host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            }

            // Description — 2-line truncated, expandable
            if !event.description.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    if event.description.count > 80 {
                        Button {
                            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.2)) {
                                if isExpanded {
                                    expandedDescriptions.remove(event.id)
                                } else {
                                    expandedDescriptions.insert(event.id)
                                }
                            }
                        } label: {
                            Text(isExpanded ? "Show less" : "Read more")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.purple)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            }

            Divider()
                .padding(.horizontal, 18)

            // RSVP counts strip
            HStack(spacing: 16) {
                rsvpCountLabel(count: event.goingCount, label: "Going", color: .green)
                rsvpCountLabel(count: event.maybeCount, label: "Maybe", color: .orange)
                rsvpCountLabel(count: event.notGoingCount, label: "Not going", color: .secondary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            Divider()
                .padding(.horizontal, 18)

            // Action row: RSVP + Add to Calendar
            HStack(spacing: 10) {
                rsvpButton(event)
                addToCalendarButton(event)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: - RSVP Button

    private func rsvpButton(_ event: AmenCovenantEventsViewModel.EventItem) -> some View {
        let isGoing = event.userRsvpStatus == "going"
        let inProgress = vm.rsvpInProgress.contains(event.id)

        return Button {
            Task {
                let newStatus = isGoing ? "not_going" : "going"
                await vm.rsvp(covenantId: covenantId, eventId: event.id, status: newStatus)
            }
        } label: {
            HStack(spacing: 6) {
                if inProgress {
                    ProgressView()
                        .tint(isGoing ? .white : .purple)
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: isGoing ? "checkmark.circle.fill" : "person.badge.plus")
                        .font(.systemScaled(13))
                }
                Text(isGoing ? "Cancel RSVP" : "RSVP")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isGoing ? Color.white : Color.purple)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(isGoing ? Color.purple : Color.purple.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
        .disabled(inProgress)
        .accessibilityLabel(isGoing ? "Cancel RSVP" : "RSVP to event")
    }

    // MARK: - Add to Calendar Button

    private func addToCalendarButton(_ event: AmenCovenantEventsViewModel.EventItem) -> some View {
        Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.75)) {
                toastMessage = "Calendar export coming soon"
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation { toastMessage = nil }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.plus")
                    .font(.systemScaled(13))
                Text("Add to Calendar")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Color(uiColor: .secondarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to Calendar")
    }

    // MARK: - Location Badge

    private func locationBadge(_ locationType: String) -> some View {
        let (label, color): (String, Color) = {
            switch locationType {
            case "online":   return ("Online", .blue)
            case "inPerson": return ("In Person", .green)
            case "hybrid":   return ("Hybrid", .purple)
            default:         return (locationType.capitalized, .gray)
            }
        }()

        return Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: - RSVP Count Label

    private func rsvpCountLabel(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) \(label)")
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(.purple)
            Text(title)
                .font(.headline)
        }
    }

    // MARK: - Empty State

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.systemScaled(38))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(36)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
        )
    }

    // MARK: - Loading Section

    private var loadingSection: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Loading events…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Toast Banner

    private func toastBanner(message: String) -> some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
            )
    }

    // MARK: - Date Formatter

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d · h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Events ViewModel

@MainActor
final class AmenCovenantEventsViewModel: ObservableObject {

    struct EventItem: Identifiable {
        let id: String
        let title: String
        let description: String
        let startAt: Date
        let endAt: Date?
        let locationType: String
        let locationLabel: String?
        let meetingUrl: String?
        let goingCount: Int
        let maybeCount: Int
        let notGoingCount: Int
        var userRsvpStatus: String?
    }

    @Published var upcomingEvents: [EventItem] = []
    @Published var pastEvents: [EventItem] = []
    @Published var showPastEvents: Bool = false
    @Published var isLoading: Bool = false
    @Published var rsvpInProgress: Set<String> = []

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    // MARK: Load events

    func load(covenantId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snap = try await db
                .collection("covenants").document(covenantId)
                .collection("events")
                .order(by: "startAt", descending: false)
                .getDocuments()

            let uid = Auth.auth().currentUser?.uid
            let now = Date()

            let allEvents: [EventItem] = snap.documents.compactMap { doc -> EventItem? in
                let data = doc.data()
                guard
                    let title = data["title"] as? String,
                    let startTimestamp = data["startAt"] as? Timestamp
                else { return nil }

                let startAt = startTimestamp.dateValue()
                let endAt = (data["endAt"] as? Timestamp)?.dateValue()

                // Resolve userRsvpStatus from nested rsvps map or separate field
                var rsvpStatus: String?
                if let uid, let rsvps = data["rsvps"] as? [String: String] {
                    rsvpStatus = rsvps[uid]
                } else if let uid, let status = data["rsvpStatus_\(uid)"] as? String {
                    rsvpStatus = status
                }

                return EventItem(
                    id: doc.documentID,
                    title: title,
                    description: data["description"] as? String ?? "",
                    startAt: startAt,
                    endAt: endAt,
                    locationType: data["locationType"] as? String ?? "online",
                    locationLabel: data["locationLabel"] as? String,
                    meetingUrl: data["meetingUrl"] as? String,
                    goingCount: data["goingCount"] as? Int ?? 0,
                    maybeCount: data["maybeCount"] as? Int ?? 0,
                    notGoingCount: data["notGoingCount"] as? Int ?? 0,
                    userRsvpStatus: rsvpStatus
                )
            }

            upcomingEvents = allEvents.filter { $0.startAt >= now }
            pastEvents = allEvents.filter { $0.startAt < now }.reversed()
        } catch {
            // Leave arrays empty — emptyState handles the UI
        }
    }

    // MARK: RSVP

    func rsvp(covenantId: String, eventId: String, status: String) async {
        rsvpInProgress.insert(eventId)
        defer { rsvpInProgress.remove(eventId) }

        // Optimistic local update
        applyOptimisticRsvp(eventId: eventId, status: status)

        do {
            let params: [String: Any] = [
                "covenantId": covenantId,
                "eventId": eventId,
                "status": status
            ]
            _ = try await functions.httpsCallable("rsvpCovenantEvent").call(params)
        } catch {
            // Revert optimistic update on failure
            applyOptimisticRsvp(eventId: eventId, status: status == "going" ? "not_going" : "going")
        }
    }

    private func applyOptimisticRsvp(eventId: String, status: String) {
        func update(_ list: inout [EventItem]) {
            guard let idx = list.firstIndex(where: { $0.id == eventId }) else { return }
            let old = list[idx]
            let wasGoing = old.userRsvpStatus == "going"
            let wasMaybe = old.userRsvpStatus == "maybe"
            let wasNotGoing = old.userRsvpStatus == "not_going"

            var goingDelta = 0
            var maybeDelta = 0
            var notGoingDelta = 0

            // Decrement old bucket
            if wasGoing { goingDelta -= 1 }
            if wasMaybe { maybeDelta -= 1 }
            if wasNotGoing { notGoingDelta -= 1 }

            // Increment new bucket
            switch status {
            case "going":     goingDelta += 1
            case "maybe":     maybeDelta += 1
            case "not_going": notGoingDelta += 1
            default: break
            }

            list[idx] = EventItem(
                id: old.id,
                title: old.title,
                description: old.description,
                startAt: old.startAt,
                endAt: old.endAt,
                locationType: old.locationType,
                locationLabel: old.locationLabel,
                meetingUrl: old.meetingUrl,
                goingCount: max(0, old.goingCount + goingDelta),
                maybeCount: max(0, old.maybeCount + maybeDelta),
                notGoingCount: max(0, old.notGoingCount + notGoingDelta),
                userRsvpStatus: status
            )
        }
        update(&upcomingEvents)
        update(&pastEvents)
    }
}
