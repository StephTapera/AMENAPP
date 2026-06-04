// BereanPrayerBriefingView.swift
// AMENAPP — Berean Prayer Intelligence OS — Today's prayer briefing

import SwiftUI
import FirebaseFunctions

// MARK: - Briefing View

struct BereanPrayerBriefingView: View {
    @StateObject private var service = BereanPrayerService.shared
    @AppStorage("bereanPrayerOS_enabled") private var isEnabled = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var showJournal = false
    @State private var showAddEntry = false
    @State private var sessionStart = Date()

    var body: some View {
        Group {
            if isEnabled {
                mainContent
            } else {
                comingSoonPlaceholder
            }
        }
        .sheet(isPresented: $showJournal) {
            BereanPrayerJournalView()
        }
        .sheet(isPresented: $showAddEntry) {
            AddPrayerEntrySheet(service: service)
        }
        .onAppear {
            sessionStart = Date()
            Task {
                service.loadEntries()
                try? await service.fetchBriefing()
                try? await service.fetchStreak()
            }
        }
        .onDisappear {
            let duration = Int(Date().timeIntervalSince(sessionStart))
            if duration > 0 {
                Task {
                    await service.logSession(
                        durationSeconds: duration,
                        visited: service.todaysBriefing?.todaysFocus.map(\.id) ?? []
                    )
                }
            }
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        ZStack {
            Color(hex: "#0A0A0F")
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // 1. Header
                    headerSection

                    // 2. Streak indicator (private — shown only to user)
                    if let streak = service.streak {
                        streakIndicator(streak: streak)
                    }

                    // 3. Scripture banner
                    if let briefing = service.todaysBriefing {
                        scriptureBanner(scripture: briefing.suggestedScripture)
                    }

                    // 4. Today's Focus or loading/empty state
                    if service.isLoading {
                        ProgressView()
                            .tint(Color(hex: "#C9A84C"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    } else if service.entries.isEmpty {
                        emptyState
                    } else {
                        todaysFocusSection
                    }

                    // 5. Pray Now button
                    if !service.entries.isEmpty {
                        prayNowButton
                    }

                    // 6. Answered This Week
                    if let briefing = service.todaysBriefing,
                       !briefing.answeredThisWeek.isEmpty {
                        answeredThisWeekSection(entries: briefing.answeredThisWeek)
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prayer")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Text(Date(), style: .date)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }

    // MARK: - Streak indicator
    // Shown only to the user — never published or compared to others.

    private func streakIndicator(streak: BereanPrayerStreak) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .foregroundStyle(Color(hex: "#C9A84C"))
                .accessibilityHidden(true)

            if streak.currentStreak > 0 {
                Text("\(streak.currentStreak) day streak")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(hex: "#C9A84C"))
            } else {
                Text("Start your prayer streak today")
                    .font(.subheadline)
                    .foregroundStyle(Color(hex: "#C9A84C"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(hex: "#C9A84C").opacity(0.12))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            streak.currentStreak > 0
                ? "\(streak.currentStreak) day prayer streak"
                : "Start your prayer streak today"
        )
    }

    // MARK: - Scripture banner

    private func scriptureBanner(scripture: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Scripture")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color(hex: "#C9A84C"))
                .textCase(.uppercase)
                .tracking(0.8)

            Text(scripture)
                .font(.body)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#111118"))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's scripture: \(scripture)")
    }

    // MARK: - Today's Focus section

    private var todaysFocusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Focus")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            let focusEntries = service.todaysBriefing?.todaysFocus
                ?? Array(service.entries.filter { $0.status == .active }.prefix(5))

            ForEach(focusEntries) { entry in
                BereanPrayerEntryCard(entry: entry)
            }

            Button {
                showJournal = true
            } label: {
                HStack {
                    Text("See All Prayer Requests")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color(hex: "#C9A84C"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#C9A84C").opacity(0.7))
                        .accessibilityHidden(true)
                }
                .padding(.top, 4)
            }
            .accessibilityLabel("See all prayer requests")
        }
    }

    // MARK: - Pray Now button

    private var prayNowButton: some View {
        Button {
            let visited = service.todaysBriefing?.todaysFocus.map(\.id)
                ?? Array(service.entries.prefix(5).map(\.id))
            let duration = Int(Date().timeIntervalSince(sessionStart))

            Task {
                await service.logSession(
                    durationSeconds: max(duration, 1),
                    visited: visited
                )
            }

            if !reduceMotion {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    sessionStart = Date()
                }
            } else {
                sessionStart = Date()
            }
        } label: {
            Text("Pray Now")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(Color(hex: "#0A0A0F"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(hex: "#C9A84C"))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel("Pray now")
        .accessibilityHint("Logs your prayer session")
    }

    // MARK: - Answered This Week

    private func answeredThisWeekSection(entries: [BereanPrayerEntry]) -> some View {
        DisclosureGroup {
            VStack(spacing: 10) {
                ForEach(entries) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(hex: "#C9A84C"))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.subject)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Color(hex: "#111118"))

                            if !entry.forWhom.isEmpty {
                                Text("For \(entry.forWhom)")
                                    .font(.caption)
                                    .foregroundStyle(Color(hex: "#111118").opacity(0.6))
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(entry.subject), answered prayer for \(entry.forWhom)")
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Answered This Week (\(entries.count))")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .tint(.white)
        .padding(16)
        .background(Color(hex: "#111118"))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "hands.clap")
                .font(.system(size: 40))
                .foregroundStyle(Color(hex: "#C9A84C").opacity(0.6))
                .accessibilityHidden(true)

            Text("Add your first prayer request")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text("Your prayer list is private and only visible to you.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)

            Button {
                showAddEntry = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .accessibilityHidden(true)
                    Text("Add Prayer Request")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundStyle(Color(hex: "#0A0A0F"))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color(hex: "#C9A84C"))
                .clipShape(Capsule())
            }
            .accessibilityLabel("Add prayer request")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Coming Soon placeholder

    private var comingSoonPlaceholder: some View {
        ZStack {
            Color(hex: "#0A0A0F").ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "hands.clap")
                    .font(.system(size: 48))
                    .foregroundStyle(Color(hex: "#C9A84C").opacity(0.5))
                    .accessibilityHidden(true)

                Text("Prayer")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Coming Soon")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prayer feature coming soon")
    }
}

// MARK: - Entry Card

struct BereanPrayerEntryCard: View {
    let entry: BereanPrayerEntry

    @StateObject private var service = BereanPrayerService.shared

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: entry.category.systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(categoryColor)
            }
            .accessibilityHidden(true)

            // Subject + forWhom
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.subject)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(hex: "#111118"))
                    .lineLimit(2)

                if !entry.forWhom.isEmpty {
                    Text("For \(entry.forWhom)")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#111118").opacity(0.55))
                }
            }

            Spacer()

            // Status dot
            statusDot
        }
        .padding(14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                Task { try? await service.markAnswered(id: entry.id) }
            } label: {
                Label("Answered", systemImage: "checkmark.circle.fill")
            }
            .tint(Color(hex: "#C9A84C"))
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task {
                    await service.logSession(durationSeconds: 30, visited: [entry.id])
                }
            } label: {
                Label("Prayed", systemImage: "hands.clap.fill")
            }
            .tint(.green)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.subject), for \(entry.forWhom), \(entry.status.displayName)")
        .accessibilityAction(named: "Mark as Prayed") {
            Task { await service.logSession(durationSeconds: 30, visited: [entry.id]) }
        }
        .accessibilityAction(named: "Mark as Answered") {
            Task { try? await service.markAnswered(id: entry.id) }
        }
    }

    // MARK: - Helpers

    private var categoryColor: Color {
        switch entry.category {
        case .faith:      return Color(hex: "#C9A84C")
        case .healing:    return .red
        case .family:     return .orange
        case .career:     return .blue
        case .church:     return Color(hex: "#4A9ECC")
        case .community:  return .purple
        case .world:      return .green
        case .gratitude:  return Color(hex: "#C9A84C")
        case .other:      return .gray
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusDotColor)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var statusDotColor: Color {
        switch entry.status {
        case .active:   return .green
        case .answered: return Color(hex: "#C9A84C")
        case .archived: return .gray
        }
    }
}

// MARK: - Preview

#if DEBUG
struct BereanPrayerBriefingView_Previews: PreviewProvider {
    static var previews: some View {
        BereanPrayerBriefingView()
            .preferredColorScheme(.dark)
    }
}
#endif
