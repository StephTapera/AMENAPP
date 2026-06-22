// SpiritualMemoryView.swift
// AMENAPP
// Browse the user's spiritual memory graph — church visits, saved content,
// study topics, prayer habits, and spiritual goals.

import SwiftUI

struct SpiritualMemoryView: View {
    @ObservedObject private var service = SpiritualGraphService.shared
    @State private var selectedType: SpiritualMemoryType? = nil
    @State private var isLoading = false

    private var filtered: [SpiritualMemoryRecord] {
        guard let type = selectedType else { return service.recentMemories }
        return service.recentMemories.filter { $0.type == type }
    }

    var body: some View {
        Group {
            if isLoading && service.recentMemories.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    selectedType == nil ? "No Spiritual Memories" : "No \(selectedType!.displayName) Entries",
                    systemImage: "brain.head.profile",
                    description: Text("As you engage with content, church visits, and study, Selah builds a private spiritual memory.")
                )
            } else {
                List {
                    ForEach(filtered, id: \.id) { record in
                        SpiritualMemoryRow(record: record)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Spiritual Memory")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("All") { selectedType = nil }
                    Divider()
                    ForEach(SpiritualMemoryType.allCases, id: \.self) { type in
                        Button(type.displayName) { selectedType = type }
                    }
                } label: {
                    Image(systemName: selectedType == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .task {
            isLoading = true
            try? await service.loadRecentMemory(limit: 50)
            isLoading = false
        }
    }
}

// MARK: - Row

private struct SpiritualMemoryRow: View {
    let record: SpiritualMemoryRecord

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 40, height: 40)
                Image(systemName: record.type.icon)
                    .font(.systemScaled(16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(record.source)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(record.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !record.tags.isEmpty {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(record.tags.prefix(2).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if let date = record.createdAt {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Display helpers

private extension SpiritualMemoryType {
    var displayName: String {
        switch self {
        case .churchVisit:          return "Church Visit"
        case .savedSermon:          return "Saved Sermon"
        case .studyTopic:           return "Study Topic"
        case .prayerHabit:          return "Prayer Habit"
        case .volunteerInterest:    return "Volunteer Interest"
        case .serviceAttendance:    return "Service Attendance"
        case .recurringMinistry:    return "Recurring Ministry"
        case .spiritualGoal:        return "Spiritual Goal"
        case .savedScriptureTheme:  return "Scripture Theme"
        }
    }

    var icon: String {
        switch self {
        case .churchVisit:          return "building.columns"
        case .savedSermon:          return "play.circle"
        case .studyTopic:           return "book.pages"
        case .prayerHabit:          return "hands.sparkles"
        case .volunteerInterest:    return "hand.raised"
        case .serviceAttendance:    return "person.3"
        case .recurringMinistry:    return "arrow.clockwise"
        case .spiritualGoal:        return "flag"
        case .savedScriptureTheme:  return "text.book.closed"
        }
    }
}
