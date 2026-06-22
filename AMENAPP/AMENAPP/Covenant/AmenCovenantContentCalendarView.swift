import SwiftUI

// MARK: - Covenant Content Calendar View
// Creator tool for scheduling posts, stories, events, devotionals, study drops, and digest highlights.

struct AmenCovenantContentCalendarView: View {
    let covenantId: String
    @State private var scheduled: [CovenantScheduledContent] = []
    @State private var loading = false
    @State private var showScheduleSheet = false
    @State private var selectedDate = Date()
    @State private var viewMode: ViewMode = .list

    enum ViewMode: String, CaseIterable {
        case list = "List"
        case calendar = "Calendar"
    }

    // Items for the selected date (calendar mode)
    private var itemsForSelectedDate: [CovenantScheduledContent] {
        scheduled.filter { Calendar.current.isDate($0.scheduledAt.dateValue(), inSameDayAs: selectedDate) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View Mode", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(16)

                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if scheduled.isEmpty {
                    emptyState
                } else {
                    switch viewMode {
                    case .list: listView
                    case .calendar: calendarView
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Content Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showScheduleSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task { await loadContent() }
            .sheet(isPresented: $showScheduleSheet) {
                ScheduleContentSheet(covenantId: covenantId) {
                    Task { await loadContent() }
                }
            }
        }
    }

    // MARK: - List View

    private var listView: some View {
        List {
            let grouped = Dictionary(grouping: scheduled) { item -> String in
                let date = item.scheduledAt.dateValue()
                return DateFormatter.calendarGroupKey.string(from: date)
            }
            ForEach(grouped.keys.sorted(), id: \.self) { key in
                Section(key) {
                    ForEach(grouped[key] ?? []) { item in
                        ScheduledContentRow(item: item)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Calendar View

    private var calendarView: some View {
        VStack(spacing: 0) {
            DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(.horizontal, 16)

            Divider()

            if itemsForSelectedDate.isEmpty {
                VStack(spacing: 10) {
                    Text("Nothing scheduled")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Schedule Content") { showScheduleSheet = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.purple)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(itemsForSelectedDate) { item in
                    ScheduledContentRow(item: item)
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.systemScaled(48))
                .foregroundStyle(.tertiary)
            Text("No Scheduled Content")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Plan your posts, events, and devotionals ahead of time.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Schedule Something") { showScheduleSheet = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadContent() async {
        loading = true
        scheduled = (try? await CovenantService.shared.loadScheduledContent(covenantId: covenantId)) ?? []
        loading = false
    }
}

// MARK: - Scheduled Content Row

private struct ScheduledContentRow: View {
    let item: CovenantScheduledContent

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: typeIcon)
                .font(.systemScaled(16))
                .foregroundStyle(typeColor)
                .frame(width: 32, height: 32)
                .background(Circle().fill(typeColor.opacity(0.1)))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.targetType.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(typeColor)
                Text(item.payload["title"] ?? "Untitled")
                    .font(.subheadline)
                    .lineLimit(1)
                Text(item.scheduledAt.dateValue(), style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            statusBadge
        }
    }

    private var statusBadge: some View {
        let (label, color): (String, Color) = {
            switch item.status {
            case .scheduled:  return ("Scheduled", .blue)
            case .published:  return ("Published", .green)
            case .failed:     return ("Failed",    .red)
            case .canceled:   return ("Canceled",  .secondary)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.1)))
    }

    private var typeColor: Color {
        switch item.targetType {
        case .post:            return .blue
        case .event:           return .green
        case .devotional:      return .purple
        case .studyDrop:       return .indigo
        case .digestHighlight: return .teal
        }
    }

    private var typeIcon: String {
        switch item.targetType {
        case .post:            return "doc.richtext.fill"
        case .event:           return "calendar"
        case .devotional:      return "book.fill"
        case .studyDrop:       return "graduationcap.fill"
        case .digestHighlight: return "newspaper.fill"
        }
    }
}

// MARK: - Schedule Content Sheet

private struct ScheduleContentSheet: View {
    let covenantId: String
    let onScheduled: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var targetType: CovenantScheduledContent.TargetType = .post
    @State private var title = ""
    @State private var scheduledDate = Date().addingTimeInterval(3600)
    @State private var submitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Content Type") {
                    Picker("Type", selection: $targetType) {
                        ForEach(CovenantScheduledContent.TargetType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Details") {
                    TextField("Title", text: $title)
                    DatePicker("Schedule For", selection: $scheduledDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("Schedule Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schedule") {
                        Task { await schedule() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(title.isEmpty || submitting)
                }
            }
        }
    }

    private func schedule() async {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
        submitting = true
        let data: [String: Any] = [
            "covenantId": covenantId,
            "targetType": targetType.rawValue,
            "payload": ["title": title],
            "scheduledAt": Timestamp(date: scheduledDate),
            "status": "scheduled",
            "createdBy": uid,
            "createdAt": Timestamp(date: Date())
        ]
        do {
            try await Firestore.firestore()
                .collection("covenants").document(covenantId)
                .collection("scheduledContent").addDocument(data: data)
        } catch {}
        submitting = false
        onScheduled()
        dismiss()
    }
}

// MARK: - CaseIterable on TargetType

extension CovenantScheduledContent.TargetType: CaseIterable {
    public static var allCases: [CovenantScheduledContent.TargetType] {
        [.post, .event, .devotional, .studyDrop, .digestHighlight]
    }
}

// MARK: - DateFormatter Extension

private extension DateFormatter {
    static let calendarGroupKey: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        return f
    }()
}

// MARK: - Import shims for inline usage in ScheduleContentSheet

import FirebaseFirestore
import FirebaseAuth
