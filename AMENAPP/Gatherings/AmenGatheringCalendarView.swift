// AmenGatheringCalendarView.swift
// AMENAPP — Gathering Calendar / List Toggle
//
// Calendar mode: month strip + event dots + day panel.
// List mode: tabbed sections (Upcoming/Past/Invited/Hosting).

import SwiftUI

struct AmenGatheringCalendarView: View {
    @StateObject private var vm = GatheringCalendarViewModel()
    @State private var showCreateFlow = false
    @State private var selectedCard: AmenGatheringFeedCard?

    private let flags = AMENFeatureFlags.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modeSwitcher
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                Divider()

                if vm.calendarMode {
                    calendarContent
                } else {
                    listContent
                }
            }
            .navigationTitle("My Gatherings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if flags.gatheringCreationEnabled {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showCreateFlow = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .accessibilityLabel("Create a gathering")
                    }
                }
            }
            .sheet(isPresented: $showCreateFlow) {
                AmenGatheringCreateFlow()
            }
            .sheet(item: $selectedCard) { card in
                AmenGatheringDetailSheetWrapper(gatheringId: card.gatheringId)
            }
            .task { await vm.load() }
        }
    }

    // MARK: - Mode Switcher

    private var modeSwitcher: some View {
        HStack(spacing: 8) {
            modeButton(label: "Calendar", icon: "calendar", active: vm.calendarMode) {
                vm.calendarMode = true
            }
            modeButton(label: "List", icon: "list.bullet", active: !vm.calendarMode) {
                vm.calendarMode = false
            }
        }
    }

    private func modeButton(label: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(active ? .white : .primary)
                .padding(.horizontal, 16)
                .frame(minHeight: 36)
                .frame(maxWidth: .infinity)
                .background(active ? Color.primary : Color(.systemGray6))
                .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) view")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: - Calendar Content

    private var calendarContent: some View {
        VStack(spacing: 0) {
            monthStripHeader
            Divider()
            selectedDayPanel
        }
    }

    private var monthStripHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    vm.previousMonth()
                } label: {
                    Image(systemName: "chevron.left")
                        .accessibilityLabel("Previous month")
                }

                Spacer()

                Text(vm.displayMonth)
                    .font(.headline.weight(.bold))

                Spacer()

                Button {
                    vm.nextMonth()
                } label: {
                    Image(systemName: "chevron.right")
                        .accessibilityLabel("Next month")
                }
            }

            dayOfWeekRow

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(vm.calendarDays, id: \.self) { date in
                    if let date {
                        calendarDay(date)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var dayOfWeekRow: some View {
        HStack(spacing: 0) {
            ForEach(["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"], id: \.self) { day in
                Text(day)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func calendarDay(_ date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: vm.selectedDate)
        let isToday = Calendar.current.isDateInToday(date)
        let hasEvent = vm.hasGathering(on: date)

        return Button {
            vm.selectedDate = date
        } label: {
            VStack(spacing: 3) {
                Text(Calendar.current.component(.day, from: date).description)
                    .font(.subheadline.weight(isToday || isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : (isToday ? .primary : .primary))
                    .frame(width: 32, height: 32)
                    .background {
                        if isSelected {
                            Circle().fill(Color.primary)
                        } else if isToday {
                            Circle().strokeBorder(Color.primary, lineWidth: 1.5)
                        }
                    }

                if hasEvent {
                    Circle()
                        .fill(isSelected ? Color.white : Color.primary)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .abbreviated, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(hasEvent ? "Has gatherings" : "")
    }

    private var selectedDayPanel: some View {
        let events = vm.gatherings(on: vm.selectedDate)
        return Group {
            if events.isEmpty {
                emptyDayState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(events) { card in
                            AmenGatheringCompactCard(card: card) { selectedCard = card }
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private var emptyDayState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Wide Open Today")
                .font(.headline.weight(.semibold))
            Text("Start a prayer walk, small group, or gathering.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if flags.gatheringCreationEnabled {
                Button {
                    showCreateFlow = true
                } label: {
                    Label("Create Gathering", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .background(Color.primary)
                        .clipShape(Capsule(style: .continuous))
                }
                .accessibilityLabel("Create a gathering")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - List Content

    private var listContent: some View {
        VStack(spacing: 0) {
            listTabBar
            Divider()
            listForCurrentTab
        }
    }

    private let listTabs = ["Upcoming", "Hosting", "Invited", "Past", "Saved"]

    private var listTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(listTabs, id: \.self) { tab in
                    Button(tab) {
                        vm.selectedListTab = tab
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(vm.selectedListTab == tab ? .white : .primary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 32)
                    .background(vm.selectedListTab == tab ? Color.primary : Color(.systemGray6))
                    .clipShape(Capsule(style: .continuous))
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tab) gatherings")
                    .accessibilityAddTraits(vm.selectedListTab == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var listForCurrentTab: some View {
        let cards = vm.cardsForTab(vm.selectedListTab)
        return Group {
            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cards.isEmpty {
                emptyListState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(cards) { card in
                            AmenGatheringCompactCard(card: card) { selectedCard = card }
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private var emptyListState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Nothing Here Yet")
                .font(.headline)
            Text("Your gatherings will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - View Model

@MainActor
final class GatheringCalendarViewModel: ObservableObject {
    @Published var allCards: [AmenGatheringFeedCard] = []
    @Published var selectedDate = Date()
    @Published var selectedMonth = Date()
    @Published var calendarMode = true
    @Published var selectedListTab = "Upcoming"
    @Published var isLoading = false

    var displayMonth: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: selectedMonth)
    }

    var calendarDays: [Date?] {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: selectedMonth),
              let firstDay = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth))
        else { return [] }

        let weekday = cal.component(.weekday, from: firstDay) - 1
        var days: [Date?] = Array(repeating: nil, count: weekday)
        for day in range {
            days.append(cal.date(byAdding: .day, value: day - 1, to: firstDay))
        }
        return days
    }

    func hasGathering(on date: Date) -> Bool {
        allCards.contains { Calendar.current.isDate($0.startAt, inSameDayAs: date) }
    }

    func gatherings(on date: Date) -> [AmenGatheringFeedCard] {
        allCards.filter { Calendar.current.isDate($0.startAt, inSameDayAs: date) }
    }

    func cardsForTab(_ tab: String) -> [AmenGatheringFeedCard] {
        let now = Date()
        switch tab {
        case "Upcoming": return allCards.filter { $0.startAt > now }.sorted { $0.startAt < $1.startAt }
        case "Past":     return allCards.filter { $0.startAt < now }.sorted { $0.startAt > $1.startAt }
        case "Hosting":  return allCards.filter { _ in false } // filter by host uid when available
        case "Invited":  return allCards.filter { $0.userRsvpStatus != nil }
        case "Saved":    return allCards.filter { $0.isSaved }
        default:         return allCards
        }
    }

    func previousMonth() {
        selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
    }

    func nextMonth() {
        selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            allCards = try await AmenGatheringService.shared.listGatheringsFeed(limitCount: 100)
        } catch {
            // Non-fatal
        }
    }
}
