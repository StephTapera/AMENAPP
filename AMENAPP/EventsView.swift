// EventsView.swift
// AMENAPP
//
// Faith-based events and gatherings platform.
// Create, discover, RSVP, and share events — church services, conferences,
// mission trips, worship nights, small group gatherings, and community service events.

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Data Models

struct FaithEvent: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String = ""
    var description: String = ""
    var category: EventCategory = .worship
    var hostUID: String = ""
    var hostName: String = ""
    var hostPhotoURL: String = ""
    var churchName: String = ""             // optional organizer church
    var location: String = ""              // address or "Online"
    var isOnline: Bool = false
    var startDate: Date = Date()
    var endDate: Date = Date().addingTimeInterval(3600)
    var imageURL: String = ""
    var capacity: Int = 0                  // 0 = unlimited
    var rsvpCount: Int = 0
    var rsvpUIDs: [String] = []
    var isPublic: Bool = true
    var requiresApproval: Bool = false
    var registrationLink: String = ""      // external link if needed
    var tags: [String] = []
    var createdAt: Date = Date()
    var isFeatured: Bool = false
}

enum EventCategory: String, Codable, CaseIterable {
    case worship     = "Worship"
    case conference  = "Conference"
    case serve       = "Serve"
    case smallGroup  = "Small Group"
    case retreat     = "Retreat"
    case prayer      = "Prayer"
    case youth       = "Youth"
    case family      = "Family"
    case mission     = "Mission"
    case community   = "Community"

    var icon: String {
        switch self {
        case .worship:    return "music.note"
        case .conference: return "mic.fill"
        case .serve:      return "hands.sparkles.fill"
        case .smallGroup: return "person.3.fill"
        case .retreat:    return "mountain.2.fill"
        case .prayer:     return "hands.sparkles"
        case .youth:      return "figure.run"
        case .family:     return "house.fill"
        case .mission:    return "airplane"
        case .community:  return "building.2.fill"
        }
    }

    var color: Color {
        switch self {
        case .worship:    return Color(red: 0.42, green: 0.24, blue: 0.82)
        case .conference: return Color(red: 0.15, green: 0.45, blue: 0.82)
        case .serve:      return Color(red: 0.18, green: 0.62, blue: 0.36)
        case .smallGroup: return Color(red: 0.90, green: 0.47, blue: 0.10)
        case .retreat:    return Color(red: 0.18, green: 0.55, blue: 0.45)
        case .prayer:     return Color(red: 0.62, green: 0.28, blue: 0.82)
        case .youth:      return Color(red: 0.85, green: 0.32, blue: 0.32)
        case .family:     return Color(red: 0.90, green: 0.58, blue: 0.10)
        case .mission:    return Color(red: 0.15, green: 0.35, blue: 0.80)
        case .community:  return Color(red: 0.38, green: 0.38, blue: 0.40)
        }
    }
}

// MARK: - Events Store

@MainActor
final class EventsStore: ObservableObject {
    static let shared = EventsStore()

    @Published var upcomingEvents: [FaithEvent] = []
    @Published var myRSVPs: [String] = []           // event IDs
    @Published var myHostedEvents: [FaithEvent] = []
    @Published var isLoaded = false

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    func loadEvents() {
        listener?.remove()
        let now = Date()
        listener = db.collection("faithEvents")
            .whereField("isPublic", isEqualTo: true)
            .whereField("startDate", isGreaterThan: Timestamp(date: now))
            .order(by: "startDate", descending: false)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let docs = snap?.documents else { return }
                self.upcomingEvents = docs.compactMap {
                    try? Firestore.Decoder().decode(FaithEvent.self, from: $0.data())
                }
                self.isLoaded = true
            }

        // Load user's RSVPs
        if let uid = Auth.auth().currentUser?.uid {
            db.collection("faithEvents")
                .whereField("rsvpUIDs", arrayContains: uid)
                .getDocuments { [weak self] snap, _ in
                    guard let self else { return }
                    self.myRSVPs = snap?.documents.compactMap { $0.documentID } ?? []
                }
        }
    }

    func createEvent(_ event: FaithEvent) async throws {
        let encoded = try Firestore.Encoder().encode(event)
        try await db.collection("faithEvents").document(event.id).setData(encoded)
    }

    func rsvp(to eventID: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("faithEvents").document(eventID).updateData([
            "rsvpUIDs": FieldValue.arrayUnion([uid]),
            "rsvpCount": FieldValue.increment(Int64(1))
        ])
        myRSVPs.append(eventID)
    }

    func cancelRSVP(for eventID: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("faithEvents").document(eventID).updateData([
            "rsvpUIDs": FieldValue.arrayRemove([uid]),
            "rsvpCount": FieldValue.increment(Int64(-1))
        ])
        myRSVPs.removeAll { $0 == eventID }
    }

    func isRSVPed(to eventID: String) -> Bool {
        myRSVPs.contains(eventID)
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }
}

// MARK: - Main View

struct EventsView: View {
    @StateObject private var store = EventsStore.shared
    @State private var selectedCategory: EventCategory? = nil
    @State private var showCreateEvent = false
    @State private var selectedEvent: FaithEvent?
    @State private var appeared = false

    private var filteredEvents: [FaithEvent] {
        guard let cat = selectedCategory else { return store.upcomingEvents }
        return store.upcomingEvents.filter { $0.category == cat }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroHeader

                    // Category filter
                    categoryPills
                        .padding(.top, 16)

                    Divider().opacity(0.3).padding(.horizontal, 20).padding(.top, 8)

                    // Featured events
                    if selectedCategory == nil {
                        featuredSection
                    }

                    // All events list
                    eventsListSection

                    Color.clear.frame(height: 100)
                }
            }
            .background(Color(.systemBackground))
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showCreateEvent) {
            CreateEventSheet()
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailSheet(event: event)
        }
        .onAppear {
            store.loadEvents()
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    // MARK: Hero Header

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.35, green: 0.12, blue: 0.65),
                    Color(red: 0.55, green: 0.25, blue: 0.88),
                    Color(red: 0.20, green: 0.10, blue: 0.45)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            // Decorative shapes
            Circle().fill(Color.white.opacity(0.06)).frame(width: 140).offset(x: -30, y: 40)
            Circle().fill(Color.white.opacity(0.04)).frame(width: 80)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 20).offset(y: -15)

            // Content
            VStack(alignment: .leading, spacing: 8) {
                Text("EVENTS")
                    .font(.system(size: 10, weight: .semibold)).kerning(3)
                    .foregroundStyle(Color.white.opacity(0.55))

                HStack(alignment: .top, spacing: 0) {
                    Text("Gather")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(.white)
                    Text(" Together")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(
                            LinearGradient(colors: [Color(red: 0.78, green: 0.65, blue: 1.0), .white],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                    Circle().fill(Color(red: 0.78, green: 0.65, blue: 1.0)).frame(width: 7, height: 7)
                        .offset(x: 3, y: 4)
                }

                Text("Worship nights · Conferences · Serve · Retreats · Mission")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1).minimumScaleFactor(0.85)

                // Create event button
                Button { showCreateEvent = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Host an Event")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 0.35, green: 0.12, blue: 0.65))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(Color.white.opacity(0.92)))
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .padding(.top, 56)
        }
        .frame(minHeight: 220)
        .scaleEffect(appeared ? 1 : 0.97)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: Category Pills

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All pill
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) { selectedCategory = nil }
                } label: {
                    Text("All")
                        .font(.custom(selectedCategory == nil ? "OpenSans-Bold" : "OpenSans-Regular", size: 13))
                        .foregroundStyle(selectedCategory == nil ? .white : Color(.label).opacity(0.65))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Capsule().fill(selectedCategory == nil
                                                   ? Color(red: 0.35, green: 0.12, blue: 0.65)
                                                   : Color(.secondarySystemBackground)))
                }

                ForEach(EventCategory.allCases, id: \.self) { cat in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            selectedCategory = selectedCategory == cat ? nil : cat
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 11, weight: .medium))
                            Text(cat.rawValue)
                                .font(.custom(selectedCategory == cat ? "OpenSans-Bold" : "OpenSans-Regular", size: 13))
                        }
                        .foregroundStyle(selectedCategory == cat ? .white : Color(.label).opacity(0.65))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(selectedCategory == cat ? cat.color : Color(.secondarySystemBackground)))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    // MARK: Featured Section

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Upcoming")
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            if store.upcomingEvents.filter({ $0.isFeatured }).isEmpty {
                // Show static demo events
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(demoEvents.prefix(3)) { event in
                            FeaturedEventCard(event: event, isFeatured: true) {
                                selectedEvent = event
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(store.upcomingEvents.filter { $0.isFeatured }) { event in
                            FeaturedEventCard(event: event, isFeatured: true) {
                                selectedEvent = event
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: Events List

    private var eventsListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(selectedCategory == nil ? "All Events" : (selectedCategory?.rawValue ?? ""))
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundStyle(.primary)
                Spacer()
                if !filteredEvents.isEmpty {
                    Text("\(filteredEvents.count) event\(filteredEvents.count == 1 ? "" : "s")")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 12)

            let displayEvents = filteredEvents.isEmpty ? demoEvents : filteredEvents
            LazyVStack(spacing: 12) {
                ForEach(displayEvents) { event in
                    EventListCard(event: event, isRSVPed: store.isRSVPed(to: event.id)) {
                        selectedEvent = event
                    }
                    .padding(.horizontal, 20)
                }
            }

            if displayEvents.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 44)).foregroundStyle(.secondary.opacity(0.4))
                        .padding(.top, 40)
                    Text("No events found")
                        .font(.custom("OpenSans-Bold", size: 18)).foregroundStyle(.primary)
                    Text("Be the first to host an event in this category.")
                        .font(.custom("OpenSans-Regular", size: 14)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                }
            }
        }
    }
}

// MARK: - Featured Event Card

struct FeaturedEventCard: View {
    let event: FaithEvent
    let isFeatured: Bool
    let onTap: () -> Void
    @State private var appeared = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Background gradient
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(
                        colors: [event.category.color, event.category.color.opacity(0.7)],
                        startPoint: .topTrailing, endPoint: .bottomLeading
                    ))
                    .frame(width: 220, height: 160)

                // Icon watermark
                Image(systemName: event.category.icon)
                    .font(.system(size: 70, weight: .ultraLight))
                    .foregroundStyle(Color.white.opacity(0.08))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 12).padding(.trailing, 16)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.category.rawValue.uppercased())
                        .font(.system(size: 9, weight: .semibold)).kerning(1.5)
                        .foregroundStyle(Color.white.opacity(0.7))
                    Text(event.title)
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(shortDate(event.startDate))
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(Color.white.opacity(0.8))
                    if !event.location.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: event.isOnline ? "video.fill" : "mappin")
                                .font(.system(size: 10))
                            Text(event.location)
                                .font(.custom("OpenSans-Regular", size: 11))
                        }
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(1)
                    }
                }
                .padding(14)
            }
        }
        .buttonStyle(ResourceCardPressStyle())
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(Double.random(in: 0...0.12))) {
                appeared = true
            }
        }
    }
}

// MARK: - Event List Card

struct EventListCard: View {
    let event: FaithEvent
    let isRSVPed: Bool
    let onTap: () -> Void
    @State private var isTogglingRSVP = false

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: event.startDate)
    }
    private var monthAbbrev: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: event.startDate).uppercased()
    }
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: event.startDate)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Date block
                VStack(spacing: 1) {
                    Text(monthAbbrev)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(event.category.color)
                    Text(dayNumber)
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(.primary)
                }
                .frame(width: 44)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(event.category.color.opacity(0.1))
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        // Time
                        HStack(spacing: 4) {
                            Image(systemName: "clock").font(.system(size: 11))
                            Text(timeString).font(.custom("OpenSans-Regular", size: 12))
                        }
                        .foregroundStyle(.secondary)

                        if !event.location.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: event.isOnline ? "video" : "mappin")
                                    .font(.system(size: 11))
                                Text(event.location)
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }

                    if event.rsvpCount > 0 {
                        Text("\(event.rsvpCount) going")
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(event.category.color)
                    }
                }

                Spacer(minLength: 0)

                // RSVP button
                VStack {
                    Button {
                        toggleRSVP()
                    } label: {
                        Group {
                            if isTogglingRSVP {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: isRSVPed ? "checkmark.circle.fill" : "plus.circle")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(isRSVPed ? event.category.color : Color(.secondaryLabel))
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isRSVPed ? event.category.color.opacity(0.3) : Color(.separator).opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(ResourceCardPressStyle())
    }

    private func toggleRSVP() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isTogglingRSVP = true
        Task {
            if isRSVPed {
                try? await EventsStore.shared.cancelRSVP(for: event.id)
            } else {
                try? await EventsStore.shared.rsvp(to: event.id)
            }
            await MainActor.run { isTogglingRSVP = false }
        }
    }
}

// MARK: - Event Detail Sheet

struct EventDetailSheet: View {
    let event: FaithEvent
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = EventsStore.shared
    @State private var isTogglingRSVP = false

    var isRSVPed: Bool { store.isRSVPed(to: event.id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [event.category.color, event.category.color.opacity(0.75)],
                            startPoint: .topTrailing, endPoint: .bottomLeading
                        )
                        .frame(height: 180)

                        Image(systemName: event.category.icon)
                            .font(.system(size: 90, weight: .ultraLight))
                            .foregroundStyle(Color.white.opacity(0.07))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.top, 20).padding(.trailing, 20)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.category.rawValue.uppercased())
                                .font(.system(size: 10, weight: .semibold)).kerning(2)
                                .foregroundStyle(Color.white.opacity(0.6))
                            Text(event.title)
                                .font(.system(size: 22, weight: .black))
                                .foregroundStyle(.white)
                            Text("Hosted by \(event.hostName.isEmpty ? event.churchName : event.hostName)")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(Color.white.opacity(0.75))
                        }
                        .padding(.horizontal, 20).padding(.bottom, 24)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        // Date/Time/Location info cards
                        HStack(spacing: 12) {
                            infoBlock(icon: "calendar", label: "Date", value: fullDate(event.startDate), color: event.category.color)
                            infoBlock(icon: "clock.fill", label: "Time", value: timeRange(event.startDate, event.endDate), color: event.category.color)
                        }

                        if !event.location.isEmpty {
                            infoBlock(icon: event.isOnline ? "video.fill" : "mappin.circle.fill",
                                      label: event.isOnline ? "Online" : "Location",
                                      value: event.location, color: event.category.color)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !event.description.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("About This Event")
                                    .font(.custom("OpenSans-Bold", size: 16))
                                    .foregroundStyle(.primary)
                                Text(event.description)
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.primary.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if event.rsvpCount > 0 {
                            HStack(spacing: 8) {
                                Image(systemName: "person.2.fill")
                                    .foregroundStyle(event.category.color)
                                Text("\(event.rsvpCount) people going")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.secondary)
                                if event.capacity > 0 {
                                    Text("· \(max(0, event.capacity - event.rsvpCount)) spots left")
                                        .font(.custom("OpenSans-Regular", size: 14))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        // Tags
                        if !event.tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(event.tags, id: \.self) { tag in
                                        Text(tag)
                                            .font(.custom("OpenSans-Regular", size: 12))
                                            .foregroundStyle(event.category.color)
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(Capsule().fill(event.category.color.opacity(0.1)))
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        isTogglingRSVP = true
                        Task {
                            if isRSVPed {
                                try? await EventsStore.shared.cancelRSVP(for: event.id)
                            } else {
                                try? await EventsStore.shared.rsvp(to: event.id)
                            }
                            await MainActor.run { isTogglingRSVP = false }
                        }
                    } label: {
                        Group {
                            if isTogglingRSVP {
                                ProgressView().tint(.white)
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: isRSVPed ? "checkmark.circle.fill" : "calendar.badge.plus")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text(isRSVPed ? "You're Going!" : "RSVP to Attend")
                                        .font(.custom("OpenSans-Bold", size: 16))
                                }
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isRSVPed
                                      ? Color(red: 0.18, green: 0.62, blue: 0.36)
                                      : event.category.color)
                        )
                    }
                    .buttonStyle(ResourceCardPressStyle())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color(.systemBackground))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func infoBlock(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.primary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - Create Event Sheet

struct CreateEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var category: EventCategory = .worship
    @State private var location = ""
    @State private var isOnline = false
    @State private var startDate = Date().addingTimeInterval(86400)
    @State private var endDate = Date().addingTimeInterval(86400 + 7200)
    @State private var capacity = 0
    @State private var isPublic = true
    @State private var isCreating = false
    @State private var showSuccess = false
    @State private var tags = ""
    @State private var showSafetyBlock = false
    @State private var safetyBlockMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Event Details") {
                    TextField("Event Title", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(EventCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(4)
                }

                Section("Date & Time") {
                    DatePicker("Start", selection: $startDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
                }

                Section("Location") {
                    Toggle("Online Event", isOn: $isOnline)
                    if !isOnline {
                        TextField("Address or Venue", text: $location)
                    }
                }

                Section("Settings") {
                    Toggle("Public Event", isOn: $isPublic)
                    Stepper(capacity == 0 ? "Unlimited Capacity" : "Capacity: \(capacity)", value: $capacity, in: 0...10000, step: 10)
                    TextField("Tags (comma-separated)", text: $tags)
                        .font(.custom("OpenSans-Regular", size: 15))
                }

                Section {
                    Button {
                        createEvent()
                    } label: {
                        HStack {
                            Spacer()
                            Group {
                                if isCreating { ProgressView() }
                                else { Text("Create Event").font(.custom("OpenSans-Bold", size: 16)) }
                            }
                            .foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(title.count >= 3 ? category.color : Color(.tertiaryLabel)))
                    }
                    .disabled(title.count < 3 || isCreating)
                }
            }
            .navigationTitle("Host an Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .alert("Event Created!", isPresented: $showSuccess) {
            Button("Done") { dismiss() }
        } message: {
            Text("Your event is now listed and visible to the community.")
        }
        .alert("Can't Create Event", isPresented: $showSafetyBlock) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(safetyBlockMessage.isEmpty
                 ? "This event description violates AMEN community guidelines. Please revise it before posting."
                 : safetyBlockMessage)
        }
    }

    private func createEvent() {
        guard let uid = Auth.auth().currentUser?.uid,
              let user = Auth.auth().currentUser else { return }
        isCreating = true
        Task {
            // Screen title + description through UnifiedSafetyGate before writing
            // to Firestore. Events are public-facing so they must meet content policy.
            let combinedText = "\(title) \(description)"
            let safetyDecision = await UnifiedSafetyGate.shared.evaluate(
                text: combinedText,
                surface: .eventDescription,
                authorId: uid
            )

            switch safetyDecision {
            case .block(let reason, _), .escalate(let reason, _):
                await MainActor.run {
                    isCreating = false
                    safetyBlockMessage = reason
                    showSafetyBlock = true
                }
                return
            case .requireEdit(let violation, _):
                await MainActor.run {
                    isCreating = false
                    safetyBlockMessage = violation
                    showSafetyBlock = true
                }
                return
            case .softPrompt, .allow:
                break  // Allow with optional nudge (nudge shown via ContentGuardrailView if wired)
            }

            var event = FaithEvent()
            event.title = title
            event.description = description
            event.category = category
            event.hostUID = uid
            event.hostName = user.displayName ?? ""
            event.location = isOnline ? "Online" : location
            event.isOnline = isOnline
            event.startDate = startDate
            event.endDate = endDate
            event.capacity = capacity
            event.isPublic = isPublic
            event.tags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            event.rsvpUIDs = [uid]
            event.rsvpCount = 1
            try? await EventsStore.shared.createEvent(event)
            await MainActor.run {
                isCreating = false
                showSuccess = true
            }
        }
    }
}

// MARK: - Helpers

private func shortDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "MMM d, yyyy"
    return f.string(from: date)
}

private func fullDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateStyle = .long
    return f.string(from: date)
}

private func timeRange(_ start: Date, _ end: Date) -> String {
    let f = DateFormatter()
    f.timeStyle = .short
    return "\(f.string(from: start)) – \(f.string(from: end))"
}

// MARK: - Demo Events Data

private let demoEvents: [FaithEvent] = [
    FaithEvent(
        id: "demo_e1",
        title: "Sunday Night Worship",
        description: "An evening of worship, prayer, and community. All are welcome. Childcare available.",
        category: .worship,
        hostName: "Grace Community Church",
        churchName: "Grace Community Church",
        location: "Main Sanctuary — 400 Church St",
        isOnline: false,
        startDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date(),
        endDate: Calendar.current.date(byAdding: .day, value: 3, to: Date())?.addingTimeInterval(5400) ?? Date(),
        capacity: 200, rsvpCount: 47,
        isPublic: true, tags: ["Worship", "Prayer", "Community"],
        isFeatured: true
    ),
    FaithEvent(
        id: "demo_e2",
        title: "Faith & Work Conference",
        description: "A two-day conference for Christian professionals exploring how faith shapes work, leadership, and purpose.",
        category: .conference,
        hostName: "Kingdom Business Network",
        location: "Downtown Convention Center",
        isOnline: false,
        startDate: Calendar.current.date(byAdding: .day, value: 10, to: Date()) ?? Date(),
        endDate: Calendar.current.date(byAdding: .day, value: 11, to: Date())?.addingTimeInterval(28800) ?? Date(),
        capacity: 500, rsvpCount: 183,
        isPublic: true, tags: ["Business", "Leadership", "Faith"],
        isFeatured: true
    ),
    FaithEvent(
        id: "demo_e3",
        title: "Community Serve Day",
        description: "Join us as we serve our local community — feeding families, cleaning parks, and loving neighbors.",
        category: .serve,
        hostName: "City Light Church",
        location: "Community Center — 120 Hope Ave",
        isOnline: false,
        startDate: Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date(),
        endDate: Calendar.current.date(byAdding: .day, value: 5, to: Date())?.addingTimeInterval(14400) ?? Date(),
        capacity: 0, rsvpCount: 34,
        isPublic: true, tags: ["Serve", "Community", "Outreach"],
        isFeatured: true
    ),
    FaithEvent(
        id: "demo_e4",
        title: "Men's Accountability Retreat",
        description: "A weekend retreat for men to grow deeper in faith, brotherhood, and accountability.",
        category: .retreat,
        hostName: "Iron Sharpens Iron Ministry",
        location: "Cedar Ridge Camp — Mountain View",
        isOnline: false,
        startDate: Calendar.current.date(byAdding: .day, value: 21, to: Date()) ?? Date(),
        endDate: Calendar.current.date(byAdding: .day, value: 23, to: Date())?.addingTimeInterval(36000) ?? Date(),
        capacity: 60, rsvpCount: 22,
        isPublic: true, tags: ["Men", "Retreat", "Accountability"],
        isFeatured: false
    ),
    FaithEvent(
        id: "demo_e5",
        title: "Online Prayer Night",
        description: "Join believers from around the world for an hour of intercession and worship.",
        category: .prayer,
        hostName: "AMEN Prayer Network",
        location: "Online — Zoom Link in Bio",
        isOnline: true,
        startDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date(),
        endDate: Calendar.current.date(byAdding: .day, value: 2, to: Date())?.addingTimeInterval(3600) ?? Date(),
        capacity: 0, rsvpCount: 91,
        isPublic: true, tags: ["Prayer", "Online", "Intercession"],
        isFeatured: false
    )
]
