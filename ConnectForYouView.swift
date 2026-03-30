// ConnectForYouView.swift
// AMENAPP
//
// Personalized hub for AMEN Connect — quick links to Jobs, Events,
// Mentorship, plus recent activity highlights.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ConnectForYouView: View {
    @State private var recentEvents: [FaithEvent] = []
    @State private var isLoading = true
    @State private var appeared = false

    private let accentBlue = Color(red: 0.15, green: 0.45, blue: 0.82)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                heroHeader

                // Quick-access grid
                quickAccessGrid
                    .padding(.horizontal, 16)

                Divider().opacity(0.3).padding(.horizontal, 20)

                // Upcoming events preview
                upcomingEventsSection

                // Mentorship CTA
                mentorshipCTA
                    .padding(.horizontal, 16)

                Color.clear.frame(height: 80)
            }
        }
        .task {
            await loadRecentEvents()
            withAnimation(.easeOut(duration: 0.4)) { appeared = true }
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.35, blue: 0.75),
                    Color(red: 0.20, green: 0.50, blue: 0.90),
                    Color(red: 0.08, green: 0.25, blue: 0.55)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            Circle().fill(Color.white.opacity(0.06)).frame(width: 120).offset(x: -20, y: 30)
            Circle().fill(Color.white.opacity(0.04)).frame(width: 70)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 20).offset(y: -10)

            VStack(alignment: .leading, spacing: 6) {
                Text("FOR YOU")
                    .font(.system(size: 10, weight: .semibold)).kerning(3)
                    .foregroundStyle(Color.white.opacity(0.55))

                Text("Your Connect Hub")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.white)

                Text("Jobs, events, mentorship, and community — curated for you.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .padding(.top, 56)
        }
        .frame(minHeight: 180)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: - Quick Access Grid

    private var quickAccessGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            NavigationLink(destination: JobSearchView()) {
                quickCard(icon: "briefcase.fill", title: "Browse Jobs", color: .blue)
            }
            NavigationLink(destination: EventsView()) {
                quickCard(icon: "calendar", title: "Events", color: Color(red: 0.42, green: 0.24, blue: 0.82))
            }
            NavigationLink(destination: MentorshipView()) {
                quickCard(icon: "person.2.fill", title: "Mentorship", color: Color(red: 0.18, green: 0.62, blue: 0.36))
            }
            NavigationLink(destination: PrayerView()) {
                quickCard(icon: "hands.sparkles.fill", title: "Prayer", color: Color(red: 0.62, green: 0.28, blue: 0.82))
            }
        }
    }

    private func quickCard(icon: String, title: String, color: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Upcoming Events

    private var upcomingEventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Upcoming Events")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                NavigationLink("See All") {
                    EventsView()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accentBlue)
            }
            .padding(.horizontal, 20)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if recentEvents.isEmpty {
                Text("No upcoming events yet. Check back soon!")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recentEvents.prefix(5)) { event in
                            compactEventCard(event)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private func compactEventCard(_ event: FaithEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: event.category.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(event.category.color)
                Text(event.category.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold)).kerning(1)
                    .foregroundStyle(event.category.color)
            }
            Text(event.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(shortDate(event.startDate))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 180, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Mentorship CTA

    private var mentorshipCTA: some View {
        NavigationLink(destination: MentorshipView()) {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 28))
                    .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.36))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Find a Mentor")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Get matched with experienced believers for guidance and growth.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    // MARK: - Data Loading

    private func loadRecentEvents() async {
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("faithEvents")
                .whereField("isPublic", isEqualTo: true)
                .whereField("startDate", isGreaterThan: Timestamp(date: Date()))
                .order(by: "startDate", descending: false)
                .limit(to: 5)
                .getDocuments()

            recentEvents = snap.documents.compactMap {
                try? Firestore.Decoder().decode(FaithEvent.self, from: $0.data())
            }
        } catch {
            dlog("ConnectForYouView: Failed to load events — \(error.localizedDescription)")
        }
        isLoading = false
    }
}

private func shortDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "MMM d, h:mm a"
    return f.string(from: date)
}
