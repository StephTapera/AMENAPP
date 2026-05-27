import SwiftUI

struct GivingCalendarView: View {
    @State private var currentMonth = Date()
    @State private var donationDates: Set<String> = []

    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                monthNavigator
                calendarGrid
                legendSection
            }
            .padding(16)
        }
    }

    private var monthNavigator: some View {
        HStack {
            Button {
                currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
            } label: { Image(systemName: "chevron.left").foregroundStyle(AmenTheme.Colors.textSecondary) }
            .accessibilityLabel("Previous month")
            Spacer()
            Text(currentMonth.formatted(.dateTime.month(.wide).year()))
                .font(.custom("OpenSans-Bold", size: 17)).foregroundStyle(AmenTheme.Colors.textPrimary)
            Spacer()
            Button {
                currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
            } label: { Image(systemName: "chevron.right").foregroundStyle(AmenTheme.Colors.textSecondary) }
            .accessibilityLabel("Next month")
        }
    }

    private var calendarGrid: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(["Su","Mo","Tu","We","Th","Fr","Sa"], id: \.self) { day in
                    Text(day).font(.custom("OpenSans-Bold", size: 11)).foregroundStyle(AmenTheme.Colors.textTertiary).frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 8)
            let days = daysInMonth()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day = day {
                        let key = dateFormatter.string(from: day)
                        let hasDonation = donationDates.contains(key)
                        let isToday = calendar.isDateInToday(day)
                        ZStack {
                            Circle()
                                .fill(hasDonation ? Color(red: 0.83, green: 0.69, blue: 0.22) : isToday ? Color(red: 0.10, green: 0.60, blue: 0.56).opacity(0.2) : Color.clear)
                                .frame(width: 34, height: 34)
                            Text("\(calendar.component(.day, from: day))")
                                .font(.custom(hasDonation ? "OpenSans-Bold" : "OpenSans-Regular", size: 14))
                                .foregroundStyle(hasDonation ? .white : isToday ? Color(red: 0.10, green: 0.60, blue: 0.56) : AmenTheme.Colors.textPrimary)
                        }
                        .accessibilityLabel("\(calendar.component(.day, from: day))\(hasDonation ? ", donation day" : "")")
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }
        }
        .padding(14).background(AmenTheme.Colors.surfaceCard).cornerRadius(14)
    }

    private var legendSection: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle().fill(Color(red: 0.83, green: 0.69, blue: 0.22)).frame(width: 12, height: 12)
                Text("Donation Day").font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            HStack(spacing: 6) {
                Circle().fill(Color(red: 0.10, green: 0.60, blue: 0.56).opacity(0.2)).frame(width: 12, height: 12)
                Text("Today").font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textSecondary)
            }
        }
    }

    private func daysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let firstWeekday = calendar.dateComponents([.weekday], from: monthInterval.start).weekday
        else { return [] }
        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        var current = monthInterval.start
        while current < monthInterval.end {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }
}
