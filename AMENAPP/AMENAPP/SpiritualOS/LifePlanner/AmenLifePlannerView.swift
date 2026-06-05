import SwiftUI
import FirebaseAuth

// MARK: - AmenLifePlannerView

struct AmenLifePlannerView: View {

    var userId: String

    @State private var viewModel = AmenLifePlannerViewModel()

    // ── Calendar helpers ─────────────────────────────────────────────────────
    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    // ── Week days for strip ───────────────────────────────────────────────────
    private var weekDays: [Date] {
        let cal = Calendar.current
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: viewModel.selectedDate) else {
            return []
        }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekInterval.start) }
    }

    // ── Month grid days ───────────────────────────────────────────────────────
    private var monthGridDays: [Date?] {
        let cal = Calendar.current
        guard let monthInterval = cal.dateInterval(of: .month, for: viewModel.selectedDate) else { return [] }
        let firstWeekday = cal.component(.weekday, from: monthInterval.start)
        let leadingBlanks = (firstWeekday - cal.firstWeekday + 7) % 7
        let daysInMonth = cal.range(of: .day, in: .month, for: monthInterval.start)?.count ?? 30
        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for d in 0..<daysInMonth {
            days.append(cal.date(byAdding: .day, value: d, to: monthInterval.start))
        }
        // Pad to full grid
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthHeaderRow
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                if viewModel.isExpanded {
                    monthGridView
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    weekStripRow
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Divider()

                if let suggestion = viewModel.todaySuggestion {
                    suggestionCard(text: suggestion)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        let dayEvents = viewModel.events(for: viewModel.selectedDate)
                        if dayEvents.isEmpty && !viewModel.isLoading {
                            emptyDayState
                                .padding(.top, 40)
                        } else {
                            ForEach(dayEvents) { event in
                                EventRow(event: event, timeFormatter: Self.timeFormatter) {
                                    Task { await rsvp(event: event) }
                                }
                                Divider()
                                    .padding(.leading, 16 + 4 + 12) // align to title
                            }
                        }
                    }
                    .padding(.bottom, 100)
                }

                if viewModel.isLoading {
                    ProgressView()
                        .padding()
                }
            }
            .navigationTitle("Life Planner")
            .navigationBarTitleDisplayMode(.inline)
            .animation(.spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82), value: viewModel.isExpanded)
            .animation(.spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82), value: viewModel.selectedDate)
        }
        .task {
            let uid = userId.isEmpty ? (Auth.auth().currentUser?.uid ?? "") : userId
            await viewModel.load(userId: uid)
        }
    }

    // MARK: - Month Header Row

    private var monthHeaderRow: some View {
        HStack {
            Text(Self.monthYearFormatter.string(from: viewModel.selectedDate))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                withAnimation(.spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82)) {
                    viewModel.isExpanded.toggle()
                }
            } label: {
                Image(systemName: viewModel.isExpanded ? "chevron.up" : "chevron.down")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(viewModel.isExpanded ? "Collapse to week view" : "Expand to month view")
        }
    }

    // MARK: - Week Strip Row

    private var weekStripRow: some View {
        HStack(spacing: 4) {
            ForEach(weekDays, id: \.self) { day in
                weekDayChip(day: day)
            }
        }
    }

    @ViewBuilder
    private func weekDayChip(day: Date) -> some View {
        let cal = Calendar.current
        let isSelected = cal.isDate(day, inSameDayAs: viewModel.selectedDate)
        let isToday = cal.isDateInToday(day)
        let hasEvents = !(viewModel.allEvents[cal.startOfDay(for: day)] ?? []).isEmpty
        let dayLetter = day.formatted(.dateTime.weekday(.narrow))
        let dayNumber = cal.component(.day, from: day)
        let eventCount = (viewModel.allEvents[cal.startOfDay(for: day)] ?? []).count

        Button {
            withAnimation(.spring(response: LiquidGlassTokens.motionFast, dampingFraction: 0.75)) {
                viewModel.selectedDate = cal.startOfDay(for: day)
                if viewModel.isExpanded { viewModel.isExpanded = false }
            }
        } label: {
            VStack(spacing: 2) {
                Text(dayLetter)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isSelected ? Color(hex: "D9A441") : .secondary)

                Text("\(dayNumber)")
                    .font(.callout.weight(isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)

                Circle()
                    .fill(hasEvents ? Color(hex: "D9A441") : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color(hex: "D9A441").opacity(0.5), lineWidth: 1)
                        )
                } else if isToday {
                    Capsule()
                        .fill(Color(hex: "D9A441").opacity(0.12))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(weekChipAccessibilityLabel(day: day, eventCount: eventCount))
    }

    private func weekChipAccessibilityLabel(day: Date, eventCount: Int) -> String {
        let fullDate = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let countPart = eventCount == 0 ? "no events" : "\(eventCount) event\(eventCount == 1 ? "" : "s")"
        return "\(fullDate), \(countPart)"
    }

    // MARK: - Month Grid

    private var monthGridView: some View {
        VStack(spacing: 0) {
            // Weekday header
            HStack(spacing: 0) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { letter in
                    Text(letter)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(monthGridDays.enumerated()), id: \.offset) { _, dayOpt in
                    if let day = dayOpt {
                        monthDayCell(day: day)
                    } else {
                        Color.clear
                            .frame(height: 38)
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func monthDayCell(day: Date) -> some View {
        let cal = Calendar.current
        let isSelected = cal.isDate(day, inSameDayAs: viewModel.selectedDate)
        let isToday = cal.isDateInToday(day)
        let hasEvents = !(viewModel.allEvents[cal.startOfDay(for: day)] ?? []).isEmpty
        let dayNumber = cal.component(.day, from: day)

        Button {
            withAnimation(.spring(response: LiquidGlassTokens.motionFast, dampingFraction: 0.75)) {
                viewModel.selectedDate = cal.startOfDay(for: day)
                viewModel.isExpanded = false
            }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color(hex: "D9A441"))
                            .frame(width: 28, height: 28)
                    } else if isToday {
                        Circle()
                            .strokeBorder(Color(hex: "D9A441"), lineWidth: 1.5)
                            .frame(width: 28, height: 28)
                    }

                    Text("\(dayNumber)")
                        .font(.callout.weight(isSelected || isToday ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.black : .primary)
                }
                .frame(height: 28)

                Circle()
                    .fill(hasEvents ? Color(hex: "D9A441") : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Suggestion Card

    private func suggestionCard(text: String) -> some View {
        LiquidGlassCard(contextTint: Color(hex: "D9A441")) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .font(.body)
                    .foregroundStyle(Color(hex: "D9A441"))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Open Notes") {
                        NotificationCenter.default.post(
                            name: Notification.Name("AmenNavigateTo"),
                            object: "notes"
                        )
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .accessibilityLabel("Open Notes")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Suggestion: \(text)")
    }

    // MARK: - Empty State

    private var emptyDayState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.largeTitle)
                .foregroundStyle(Color.secondary.opacity(0.4))
            Text("No events scheduled")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("No events scheduled for this day")
    }

    // MARK: - RSVP

    private func rsvp(event: PlannerEvent) async {
        guard let spaceId = event.spaceId,
              let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        do {
            try await db
                .collection("spaces").document(spaceId)
                .collection("events").document(event.id)
                .updateData(["rsvpUserIds": FieldValue.arrayUnion([uid])])
            // Reload to reflect the RSVP
            await viewModel.load(userId: uid)
        } catch {
            // Silent — user can retry
        }
    }
}

// MARK: - EventRow

private struct EventRow: View {
    let event: PlannerEvent
    let timeFormatter: DateFormatter
    let onRSVP: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Leading color bar
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(barColor(for: event.type))
                .frame(width: 4)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                if let subtitle = event.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(timeFormatter.string(from: event.startTime))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                if event.rsvpRequired && !event.userHasRSVPd {
                    Button(action: onRSVP) {
                        Text("RSVP")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(hex: "D9A441"), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Double-tap to RSVP to this event")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemBackground))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private var rowAccessibilityLabel: String {
        "\(event.type.label) at \(DateFormatter.localizedString(from: event.startTime, dateStyle: .none, timeStyle: .short)), \(event.title)"
    }

    private func barColor(for type: PlannerEventType) -> Color {
        switch type {
        case .church:    return Color(hex: "D9A441")
        case .prayer:    return Color.indigo
        case .birthday:  return Color.pink
        case .volunteer: return Color.green
        case .reading:   return Color.teal
        }
    }
}

// MARK: - Preview

#Preview {
    AmenLifePlannerView(userId: "preview_user")
}
