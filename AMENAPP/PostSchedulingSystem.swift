// PostSchedulingSystem.swift
// AMENAPP
//
// Comprehensive smart post scheduling system.
// Purely additive — does not modify any existing file.
// No Firebase imports; pure SwiftUI + Foundation.

import Foundation
import SwiftUI
import Combine

// MARK: - State Machine

enum PostPublishingState: Equatable {
    case draft
    case uploadingMedia(progress: Double)
    case processingMedia
    case readyToSchedule
    case scheduled(for: Date)
    case publishing
    case published
    case failed(reason: String)
}

// MARK: - Content Type

enum SmartContentType: String {
    case text, photo, video, testimony, prayer, sermon, announcement, event
}

// MARK: - Quiet Publish Mode

enum QuietPublishMode: String {
    case normal, silent, boost
}

// MARK: - Smart Time Suggestion

struct SmartTimeSuggestion: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let suggestedDate: Date
    let reasoning: String
    let contentTypes: [SmartContentType]
}

// MARK: - Scheduled Post Status

enum ScheduledPostStatus: Equatable {
    case upcoming
    case processingMedia
    case pendingMedia
    case ready
    case failed(reason: String)
    case published
}

// MARK: - Scheduled Post Entry

struct ScheduledPostEntry: Identifiable {
    let id: String
    var content: String
    var scheduledFor: Date
    var status: ScheduledPostStatus
    var mediaType: SmartContentType
}

// MARK: - PostSchedulingService

@MainActor
final class PostSchedulingService: ObservableObject {

    @Published var suggestions: [SmartTimeSuggestion] = []
    @Published var detectedContentType: SmartContentType = .text

    // MARK: Content type detection

    func detectContentType(from text: String, hasImages: Bool, hasVideo: Bool) -> SmartContentType {
        if hasVideo { return .video }
        let lower = text.lowercased()
        if lower.contains("testimony") || lower.contains("testify") || lower.contains("witness") {
            return .testimony
        }
        if lower.contains("prayer") || lower.contains("pray") || lower.contains("intercede") {
            return .prayer
        }
        if lower.contains("sermon") || lower.contains("message") || lower.contains("preach") {
            return .sermon
        }
        if lower.contains("event") || lower.contains("announce") || lower.contains("join us") {
            return .announcement
        }
        if hasImages { return .photo }
        return .text
    }

    // MARK: Smart time suggestions

    func suggestTimes(for contentType: SmartContentType, postText: String) -> [SmartTimeSuggestion] {
        var result: [SmartTimeSuggestion] = []
        let now = Date()
        let cal = Calendar.current
        let lower = postText.lowercased()

        // Sunday morning
        let nextSunday: Date = {
            var comps = DateComponents()
            comps.weekday = 1 // Sunday
            comps.hour = 7
            comps.minute = 45
            comps.second = 0
            return cal.nextDate(
                after: now,
                matching: comps,
                matchingPolicy: .nextTime
            ) ?? now.addingTimeInterval(86400)
        }()

        result.append(SmartTimeSuggestion(
            label: "Sunday morning devotional",
            icon: "sun.max.fill",
            suggestedDate: nextSunday,
            reasoning: "Best engagement for faith content",
            contentTypes: [.text, .photo, .video, .testimony, .prayer, .sermon]
        ))

        // Wednesday evening
        let nextWednesday: Date = {
            var comps = DateComponents()
            comps.weekday = 4 // Wednesday
            comps.hour = 18
            comps.minute = 30
            comps.second = 0
            return cal.nextDate(
                after: now,
                matching: comps,
                matchingPolicy: .nextTime
            ) ?? now.addingTimeInterval(86400 * 3)
        }()

        result.append(SmartTimeSuggestion(
            label: "Wednesday evening study",
            icon: "book.closed.fill",
            suggestedDate: nextWednesday,
            reasoning: "Midweek Bible study window",
            contentTypes: [.text, .testimony, .prayer, .sermon]
        ))

        // Tomorrow morning
        let tomorrowMorning: Date = {
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
            return cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }()

        result.append(SmartTimeSuggestion(
            label: "Tomorrow morning",
            icon: "sunrise.fill",
            suggestedDate: tomorrowMorning,
            reasoning: "Morning devotional slot",
            contentTypes: [.text, .photo, .prayer]
        ))

        // Context-sensitive overrides
        if lower.contains("prayer") || lower.contains("pray") {
            let tonightNine: Date = {
                let tonight = cal.date(bySettingHour: 21, minute: 0, second: 0, of: now) ?? now
                return tonight > now ? tonight : cal.date(byAdding: .day, value: 1, to: tonight) ?? tonight
            }()
            result.append(SmartTimeSuggestion(
                label: "Tonight — evening prayer",
                icon: "moon.stars.fill",
                suggestedDate: tonightNine,
                reasoning: "Evening prayer window",
                contentTypes: [.prayer]
            ))
        }

        if lower.contains("sermon") || lower.contains("message") {
            let sundayAfterService: Date = {
                var comps = DateComponents()
                comps.weekday = 1
                comps.hour = 12
                comps.minute = 30
                comps.second = 0
                return cal.nextDate(
                    after: now,
                    matching: comps,
                    matchingPolicy: .nextTime
                ) ?? now.addingTimeInterval(86400)
            }()
            result.append(SmartTimeSuggestion(
                label: "After service — Sunday",
                icon: "person.3.fill",
                suggestedDate: sundayAfterService,
                reasoning: "After service: Sunday 12:30 PM",
                contentTypes: [.sermon]
            ))
        }

        if lower.contains("event") || lower.contains("announce") {
            let threeDays: Date = cal.date(byAdding: .day, value: 3, to: tomorrowMorning) ?? tomorrowMorning
            result.append(SmartTimeSuggestion(
                label: "3 days out — prime window",
                icon: "megaphone.fill",
                suggestedDate: threeDays,
                reasoning: "3 days before: prime announcement window",
                contentTypes: [.announcement, .event]
            ))
        }

        // Return at most the first 3 general + any special suggestions
        return Array(result.prefix(6))
    }

    // MARK: Conflict detection

    func detectConflict(with existingScheduled: [Date], for newDate: Date) -> Bool {
        existingScheduled.contains { existing in
            abs(existing.timeIntervalSince(newDate)) < 7200 // 2 hours
        }
    }

    // MARK: Date validation

    func validateScheduledDate(_ date: Date) -> (isValid: Bool, error: String?) {
        let now = Date()
        if date < now.addingTimeInterval(300) {
            return (false, "Scheduled time must be at least 5 minutes from now.")
        }
        let sixMonths = Calendar.current.date(byAdding: .month, value: 6, to: now) ?? now
        if date > sixMonths {
            return (false, "Scheduled time cannot be more than 6 months away.")
        }
        return (true, nil)
    }

    // MARK: Update suggestions

    func refresh(postText: String, hasImages: Bool, hasVideo: Bool) {
        detectedContentType = detectContentType(from: postText, hasImages: hasImages, hasVideo: hasVideo)
        suggestions = suggestTimes(for: detectedContentType, postText: postText)
    }
}

// MARK: - Glass Background ViewModifier

private struct PostGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 4)
            )
    }
}

private extension View {
    func glassCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(PostGlassCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Date Formatting Helpers

private extension Date {
    func shortScheduleLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d · h:mm a"
        return formatter.string(from: self)
    }

    func pillLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter.string(from: self)
    }

    func chipLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter.string(from: self)
    }
}

// MARK: - SmartScheduleSheet

struct SmartScheduleSheet: View {
    @Binding var isPresented: Bool
    @Binding var scheduledDate: Date?

    var postText: String = ""
    var hasImages: Bool = false
    var hasVideo: Bool = false
    var onConfirm: ((Date) -> Void)? = nil

    @StateObject private var service = PostSchedulingService()

    private var minimumDate: Date { Date().addingTimeInterval(300) }

    @State private var selectedDateTime: Date = Date().addingTimeInterval(3600)
    @State private var selectedSuggestionID: UUID? = nil
    @State private var publishMode: QuietPublishMode = .normal
    @State private var existingScheduled: [Date] = []

    private var hasConflict: Bool {
        service.detectConflict(with: existingScheduled, for: selectedDateTime)
    }

    private var validation: (isValid: Bool, error: String?) {
        service.validateScheduledDate(selectedDateTime)
    }

    private var formattedConfirmLabel: String {
        "Schedule for \(selectedDateTime.shortScheduleLabel())"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {

                        // Content preview mini-card
                        contentPreviewCard

                        // Smart suggestions
                        if !service.suggestions.isEmpty {
                            suggestionsSection
                        }

                        // Date & Time picker
                        dateTimeSection

                        // Audience row
                        audienceRow

                        // Conflict warning
                        if hasConflict {
                            conflictWarning
                        }

                        // Quiet publish options
                        quietPublishSection

                        // CTA
                        ctaSection

                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Schedule Post")
                        .font(AMENFont.bold(17))
                        .foregroundColor(.black)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isPresented = false
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Circle()
                                        .fill(Color.white.opacity(0.55))
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                                )
                                .frame(width: 30, height: 30)
                            Image(systemName: "xmark")
                                .font(.systemScaled(12, weight: .semibold))
                                .foregroundColor(.black)
                        }
                    }
                }
            }
        }
        .onAppear {
            service.refresh(postText: postText, hasImages: hasImages, hasVideo: hasVideo)
            if let existing = scheduledDate {
                selectedDateTime = existing
            }
        }
    }

    // MARK: Content Preview Card

    private var contentPreviewCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(white: 0.94))
                    .frame(width: 40, height: 40)
                Image(systemName: contentTypeIcon(service.detectedContentType))
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundColor(.black)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(previewText)
                    .font(AMENFont.regular(14))
                    .foregroundColor(.black)
                    .lineLimit(2)

                Text(contentTypeLabel(service.detectedContentType))
                    .font(AMENFont.regular(12))
                    .foregroundColor(Color(white: 0.45))
            }

            Spacer()
        }
        .padding(14)
        .glassCard(cornerRadius: 14)
    }

    private var previewText: String {
        let trimmed = postText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "No text content" }
        if trimmed.count > 60 {
            return String(trimmed.prefix(60)) + "…"
        }
        return trimmed
    }

    private func contentTypeIcon(_ type: SmartContentType) -> String {
        switch type {
        case .text:         return "text.alignleft"
        case .photo:        return "photo"
        case .video:        return "video.fill"
        case .testimony:    return "heart.text.square.fill"
        case .prayer:       return "hands.pray"
        case .sermon:       return "mic.fill"
        case .announcement: return "megaphone.fill"
        case .event:        return "calendar.badge.plus"
        }
    }

    private func contentTypeLabel(_ type: SmartContentType) -> String {
        switch type {
        case .text:         return "· Text post"
        case .photo:        return "· Photo"
        case .video:        return "· Video"
        case .testimony:    return "· Testimony"
        case .prayer:       return "· Prayer"
        case .sermon:       return "· Sermon"
        case .announcement: return "· Announcement"
        case .event:        return "· Event"
        }
    }

    // MARK: Suggestions Section

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Optimal Times")
                .font(AMENFont.semiBold(13))
                .foregroundColor(Color(white: 0.45))
                .padding(.leading, 2)

            VStack(spacing: 8) {
                ForEach(service.suggestions.prefix(3)) { suggestion in
                    suggestionRow(suggestion)
                }
            }
        }
    }

    private func suggestionRow(_ suggestion: SmartTimeSuggestion) -> some View {
        let isSelected = selectedSuggestionID == suggestion.id

        return SuggestionRowView(
            suggestion: suggestion,
            isSelected: isSelected
        ) {
            withAnimation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.80))) {
                selectedSuggestionID = suggestion.id
                selectedDateTime = suggestion.suggestedDate
            }
        }
    }

    // MARK: Date & Time Section

    private var dateTimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom Time")
                .font(AMENFont.semiBold(13))
                .foregroundColor(Color(white: 0.45))
                .padding(.leading, 2)

            VStack(spacing: 0) {
                DatePicker(
                    "",
                    selection: $selectedDateTime,
                    in: minimumDate...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .tint(.black)
                .padding(8)
                .onChange(of: selectedDateTime) {
                    selectedSuggestionID = nil
                }

                Divider()
                    .background(Color(white: 0.88))

                // Timezone row
                HStack(spacing: 10) {
                    Image(systemName: "clock.fill")
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundColor(Color(white: 0.45))
                    Text("Timezone: \(TimeZone.current.abbreviation() ?? "Local")")
                        .font(AMENFont.regular(14))
                        .foregroundColor(Color(white: 0.45))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .glassCard(cornerRadius: 14)
        }
    }

    // MARK: Audience Row

    private var audienceRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.fill")
                .font(.systemScaled(14, weight: .medium))
                .foregroundColor(Color(white: 0.45))
                .frame(width: 20)

            Text("Who can see this")
                .font(AMENFont.regular(14))
                .foregroundColor(.black)

            Spacer()

            Text("Everyone")
                .font(AMENFont.regular(14))
                .foregroundColor(Color(white: 0.45))

            Image(systemName: "chevron.right")
                .font(.systemScaled(11, weight: .semibold))
                .foregroundColor(Color(white: 0.65))
        }
        .padding(14)
        .glassCard(cornerRadius: 14)
    }

    // MARK: Conflict Warning

    private var conflictWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundColor(Color.orange)

            Text("You have another post scheduled within 2 hours. Consider spacing them out.")
                .font(AMENFont.regular(13))
                .foregroundColor(.black)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 3)
        )
    }

    // MARK: Quiet Publish Section

    private var quietPublishSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Publish Options")
                .font(AMENFont.semiBold(13))
                .foregroundColor(Color(white: 0.45))
                .padding(.leading, 2)

            VStack(spacing: 0) {
                quietPublishRow(
                    mode: .normal,
                    icon: "bell.fill",
                    title: "Publish normally",
                    subtitle: "Standard notification to followers"
                )
                Divider().background(Color(white: 0.88)).padding(.leading, 46)
                quietPublishRow(
                    mode: .silent,
                    icon: "bell.slash.fill",
                    title: "Publish silently",
                    subtitle: "No notification to followers"
                )
                Divider().background(Color(white: 0.88)).padding(.leading, 46)
                quietPublishRow(
                    mode: .boost,
                    icon: "bolt.fill",
                    title: "Boost notification",
                    subtitle: "Notify all followers"
                )
            }
            .glassCard(cornerRadius: 14)
        }
    }

    @State private var publishModeState: QuietPublishMode = .normal

    private func quietPublishRow(mode: QuietPublishMode, icon: String, title: String, subtitle: String) -> some View {
        Button {
            withAnimation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.80))) {
                publishModeState = mode
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundColor(Color(white: 0.45))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AMENFont.semiBold(14))
                        .foregroundColor(.black)
                    Text(subtitle)
                        .font(AMENFont.regular(12))
                        .foregroundColor(Color(white: 0.55))
                }

                Spacer()

                ZStack {
                    Circle()
                        .strokeBorder(Color(white: 0.75), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if publishModeState == mode {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: CTA Section

    private var ctaSection: some View {
        VStack(spacing: 12) {
            // Validation error
            if let error = validation.error {
                Text(error)
                    .font(AMENFont.regular(13))
                    .foregroundColor(Color.red.opacity(0.75))
                    .padding(.horizontal, 2)
            }

            // Primary CTA
            Button {
                confirmSchedule()
            } label: {
                Text(formattedConfirmLabel)
                    .font(AMENFont.bold(16))
                    .foregroundColor(validation.isValid ? .white : Color(white: 0.55))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        Capsule()
                            .fill(validation.isValid ? Color.black : Color(white: 0.88))
                    )
            }
            .disabled(!validation.isValid)

            // Remove schedule (only if already scheduled)
            if scheduledDate != nil {
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.85))) {
                        scheduledDate = nil
                        isPresented = false
                    }
                } label: {
                    Text("Remove schedule")
                        .font(AMENFont.semiBold(15))
                        .foregroundColor(Color(white: 0.45))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule()
                                        .fill(Color.white.opacity(0.55))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                                )
                        )
                }
            }
        }
        .padding(.top, 4)
    }

    private func confirmSchedule() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        scheduledDate = selectedDateTime
        onConfirm?(selectedDateTime)
        isPresented = false
    }
}

private struct SuggestionRowView: View {
    let suggestion: SmartTimeSuggestion
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: suggestion.icon)
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundColor(isSelected ? .black : Color(white: 0.45))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.label)
                        .font(AMENFont.semiBold(14))
                        .foregroundColor(.black)
                    Text(suggestion.reasoning)
                        .font(AMENFont.regular(12))
                        .foregroundColor(Color(white: 0.45))
                }

                Spacer()

                Text(suggestion.suggestedDate.shortScheduleLabel())
                    .font(AMENFont.regular(11))
                    .foregroundColor(Color(white: 0.55))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            .padding(12)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.black : Color(white: 0.88).opacity(0.5),
                        lineWidth: isSelected ? 1 : 0.5
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 3)
    }
}

// MARK: - PublishMode

enum PublishMode: Equatable {
    case postNow, schedule, draft
}

// MARK: - PublishPillView

struct PublishPillView: View {
    @Binding var mode: PublishMode
    var isEnabled: Bool
    var isLoading: Bool
    var scheduledDate: Date?
    var onPublishNow: () -> Void
    var onSchedule: () -> Void
    var onSaveDraft: () -> Void

    @State private var isExpanded: Bool = false
    @State private var isPulsing: Bool = false

    private var pillLabel: String {
        if isLoading { return "Publishing…" }
        switch mode {
        case .postNow: return "Post now"
        case .schedule:
            if let date = scheduledDate {
                return "Scheduled · \(date.pillLabel())"
            }
            return "Schedule post"
        case .draft: return "Save draft"
        }
    }

    private var pillIcon: String {
        switch mode {
        case .postNow: return "arrow.up"
        case .schedule: return "calendar.badge.clock"
        case .draft: return "tray.and.arrow.down"
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Dropdown overlay
            if isExpanded {
                dropdownMenu
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity
                        )
                    )
                    .zIndex(1)
            }

            // Main pill
            mainPill
                .scaleEffect(mode == .schedule && isPulsing ? 1.03 : 1.0)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isPulsing)
                .onAppear {
                    if mode == .schedule {
                        triggerPulse()
                    }
                }
                .onChange(of: mode) { _, newMode in
                    if newMode == .schedule {
                        triggerPulse()
                    }
                }
        }
    }

    private var mainPill: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.75)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: pillIcon)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundColor(isEnabled ? .black : Color(white: 0.55))
            }

            Text(pillLabel)
                .font(AMENFont.semiBold(15))
                .foregroundColor(isEnabled ? .black : Color(white: 0.55))

            // Chevron for dropdown
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.80))) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.systemScaled(10, weight: .bold))
                    .foregroundColor(Color(white: 0.45))
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.55)))
                .overlay(
                    Capsule()
                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 4)
        )
        .onLongPressGesture {
            withAnimation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.80))) {
                isExpanded = true
            }
        }
        .onTapGesture {
            guard isEnabled, !isLoading else { return }
            if mode == .postNow {
                onPublishNow()
            } else if mode == .schedule {
                onSchedule()
            }
        }
        .disabled(!isEnabled || isLoading)
    }

    private var dropdownMenu: some View {
        VStack(spacing: 0) {
            dropdownOption(
                icon: "arrow.up",
                label: "Post now",
                action: {
                    withAnimation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.80))) {
                        mode = .postNow
                        isExpanded = false
                    }
                    onPublishNow()
                }
            )
            Divider().background(Color(white: 0.88))
            dropdownOption(
                icon: "calendar.badge.clock",
                label: "Schedule",
                action: {
                    withAnimation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.80))) {
                        mode = .schedule
                        isExpanded = false
                    }
                    onSchedule()
                }
            )
            Divider().background(Color(white: 0.88))
            dropdownOption(
                icon: "tray.and.arrow.down",
                label: "Save draft",
                action: {
                    withAnimation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.80))) {
                        mode = .draft
                        isExpanded = false
                    }
                    onSaveDraft()
                }
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 20, x: 0, y: 6)
        )
        .padding(.bottom, 56)
    }

    private func dropdownOption(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundColor(Color(white: 0.45))
                    .frame(width: 20)
                Text(label)
                    .font(AMENFont.semiBold(15))
                    .foregroundColor(.black)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    private func triggerPulse() {
        isPulsing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            isPulsing = false
        }
    }
}

// MARK: - ScheduledStatusChip

struct ScheduledStatusChip: View {
    var scheduledDate: Date
    var onEdit: () -> Void
    var onClear: () -> Void

    @State private var appeared: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundColor(Color(white: 0.45))

            Text("Scheduled · \(scheduledDate.chipLabel())")
                .font(AMENFont.semiBold(13))
                .foregroundColor(Color(white: 0.45))

            Button {
                onClear()
            } label: {
                Image(systemName: "xmark")
                    .font(.systemScaled(10, weight: .bold))
                    .foregroundColor(Color(white: 0.55))
                    .padding(4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.55)))
                .overlay(
                    Capsule()
                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 3)
        )
        .scaleEffect(appeared ? 1.0 : 0.8)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.85))) {
                appeared = true
            }
        }
        .onTapGesture {
            onEdit()
        }
    }
}

// MARK: - ScheduledPostsHub

struct ScheduledPostsHub: View {
    @State private var selectedTab: ScheduledHubTab = .upcoming

    enum ScheduledHubTab: String, CaseIterable {
        case upcoming = "Upcoming"
        case processing = "Processing"
        case failed = "Failed"
        case published = "Published"
    }

    // Sample data — no Firebase
    @State private var entries: [ScheduledPostEntry] = ScheduledPostsHub.sampleEntries()
    @State private var entryToReschedule: ScheduledPostEntry? = nil
    @State private var rescheduleDate: Date = Date().addingTimeInterval(86400)

    private static func sampleEntries() -> [ScheduledPostEntry] {
        let cal = Calendar.current
        let base = Date()
        return [
            ScheduledPostEntry(
                id: "1",
                content: "Blessed is the one who does not walk in step with the wicked — Psalm 1:1",
                scheduledFor: cal.date(byAdding: .hour, value: 4, to: base) ?? base,
                status: .upcoming,
                mediaType: .text
            ),
            ScheduledPostEntry(
                id: "2",
                content: "Sunday sermon recap — God's grace in the valley seasons of life.",
                scheduledFor: cal.date(byAdding: .day, value: 1, to: base) ?? base,
                status: .ready,
                mediaType: .sermon
            ),
            ScheduledPostEntry(
                id: "3",
                content: "Join us this Friday for prayer night! 7 PM — doors open at 6:30.",
                scheduledFor: cal.date(byAdding: .day, value: 3, to: base) ?? base,
                status: .pendingMedia,
                mediaType: .announcement
            ),
            ScheduledPostEntry(
                id: "4",
                content: "Uploading testimony video from last week's service…",
                scheduledFor: cal.date(byAdding: .hour, value: 2, to: base) ?? base,
                status: .processingMedia,
                mediaType: .video
            ),
            ScheduledPostEntry(
                id: "5",
                content: "Morning devotional: The armor of God — Ephesians 6:10-18",
                scheduledFor: cal.date(byAdding: .day, value: -1, to: base) ?? base,
                status: .failed(reason: "Network error during upload"),
                mediaType: .text
            ),
            ScheduledPostEntry(
                id: "6",
                content: "Thank you for all your prayers this week. He is faithful.",
                scheduledFor: cal.date(byAdding: .day, value: -2, to: base) ?? base,
                status: .published,
                mediaType: .testimony
            )
        ]
    }

    private var upcomingEntries: [ScheduledPostEntry] {
        entries.filter {
            switch $0.status {
            case .upcoming, .ready, .pendingMedia: return true
            default: return false
            }
        }
    }

    private var processingEntries: [ScheduledPostEntry] {
        entries.filter { $0.status == .processingMedia }
    }

    private var failedEntries: [ScheduledPostEntry] {
        entries.filter {
            if case .failed = $0.status { return true }
            return false
        }
    }

    private var publishedEntries: [ScheduledPostEntry] {
        entries.filter { $0.status == .published }
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Tab bar
                tabBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        switch selectedTab {
                        case .upcoming:
                            if upcomingEntries.isEmpty {
                                emptyState(message: "No upcoming posts scheduled.")
                            } else {
                                ForEach(upcomingEntries) { entry in
                                    ScheduledPostRow(
                                        entry: entry,
                                        onReschedule: {
                                            rescheduleDate = entry.scheduledFor.addingTimeInterval(86400)
                                            entryToReschedule = entry
                                        },
                                        onDuplicate: { duplicateEntry(entry) },
                                        onCancel: { removeEntry(id: entry.id) }
                                    )
                                }
                            }
                        case .processing:
                            if processingEntries.isEmpty {
                                emptyState(message: "No posts processing right now.")
                            } else {
                                ForEach(processingEntries) { entry in
                                    ScheduledPostRow(
                                        entry: entry,
                                        onReschedule: {
                                            rescheduleDate = entry.scheduledFor.addingTimeInterval(86400)
                                            entryToReschedule = entry
                                        },
                                        onDuplicate: { duplicateEntry(entry) },
                                        onCancel: { removeEntry(id: entry.id) }
                                    )
                                }
                            }
                        case .failed:
                            if failedEntries.isEmpty {
                                emptyState(message: "No failed posts.")
                            } else {
                                ForEach(failedEntries) { entry in
                                    ScheduledPostRow(
                                        entry: entry,
                                        onReschedule: {
                                            rescheduleDate = entry.scheduledFor.addingTimeInterval(86400)
                                            entryToReschedule = entry
                                        },
                                        onDuplicate: { duplicateEntry(entry) },
                                        onCancel: { removeEntry(id: entry.id) },
                                        onRetry: {
                                            if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                                                entries[idx].status = .upcoming
                                            }
                                        },
                                        onEdit: {
                                            NotificationCenter.default.post(name: Notification.Name("amenEditScheduledPost"), object: entry.id)
                                        }
                                    )
                                }
                            }
                        case .published:
                            if publishedEntries.isEmpty {
                                emptyState(message: "No published scheduled posts yet.")
                            } else {
                                ForEach(publishedEntries) { entry in
                                    ScheduledPostRow(
                                        entry: entry,
                                        onReschedule: {
                                            rescheduleDate = entry.scheduledFor.addingTimeInterval(86400)
                                            entryToReschedule = entry
                                        },
                                        onDuplicate: { duplicateEntry(entry) },
                                        onCancel: { removeEntry(id: entry.id) }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("Scheduled Posts")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $entryToReschedule) { entry in
            NavigationStack {
                Form {
                    Section("New schedule time") {
                        DatePicker("Date & time", selection: $rescheduleDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.graphical)
                    }
                }
                .navigationTitle("Reschedule Post")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { entryToReschedule = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            rescheduleEntry(entry, to: rescheduleDate)
                            entryToReschedule = nil
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(ScheduledHubTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.80))) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(AMENFont.semiBold(13))
                        .foregroundColor(selectedTab == tab ? .black : Color(white: 0.55))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(selectedTab == tab ? Color.white : Color.clear)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            selectedTab == tab ? Color(white: 0.88).opacity(0.5) : Color.clear,
                                            lineWidth: 0.5
                                        )
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.55)))
                .overlay(
                    Capsule()
                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 3)
        )
    }

    private func emptyState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.systemScaled(32, weight: .light))
                .foregroundColor(Color(white: 0.75))
            Text(message)
                .font(AMENFont.regular(15))
                .foregroundColor(Color(white: 0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func removeEntry(id: String) {
        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.85))) {
            entries.removeAll { $0.id == id }
        }
    }

    private func rescheduleEntry(_ entry: ScheduledPostEntry, to date: Date) {
        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.85))) {
            if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[idx].scheduledFor = date
                entries[idx].status = .upcoming
            }
        }
    }

    private func duplicateEntry(_ entry: ScheduledPostEntry) {
        let copy = ScheduledPostEntry(
            id: UUID().uuidString,
            content: entry.content,
            scheduledFor: entry.scheduledFor.addingTimeInterval(3600),
            status: .upcoming,
            mediaType: entry.mediaType
        )
        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.85))) {
            if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                entries.insert(copy, at: entries.index(after: idx))
            } else {
                entries.append(copy)
            }
        }
    }
}

// MARK: - ScheduledPostRow

struct ScheduledPostRow: View {
    var entry: ScheduledPostEntry
    var onReschedule: () -> Void
    var onDuplicate: () -> Void
    var onCancel: () -> Void
    var onRetry: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil

    @State private var showOverflow: Bool = false
    @State private var isRetrying: Bool = false

    private var statusBadgeLabel: String {
        switch entry.status {
        case .upcoming: return "Scheduled"
        case .processingMedia: return "Processing"
        case .pendingMedia: return "Pending media"
        case .ready: return "Ready"
        case .failed: return "Failed"
        case .published: return "Published"
        }
    }

    private var statusBadgeTint: Color {
        switch entry.status {
        case .upcoming: return Color(white: 0.88)
        case .processingMedia, .pendingMedia: return Color.orange.opacity(0.15)
        case .ready: return Color(white: 0.88)
        case .failed: return Color.red.opacity(0.12)
        case .published: return Color(white: 0.88)
        }
    }

    private var statusBadgeTextColor: Color {
        switch entry.status {
        case .upcoming: return Color(white: 0.45)
        case .processingMedia, .pendingMedia: return Color.orange
        case .ready: return Color(white: 0.35)
        case .failed: return Color.red.opacity(0.75)
        case .published: return Color(white: 0.45)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                // Content preview
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.content)
                        .font(AMENFont.regular(14))
                        .foregroundColor(.black)
                        .lineLimit(1)

                    Text(entry.scheduledFor.shortScheduleLabel())
                        .font(AMENFont.regular(12))
                        .foregroundColor(Color(white: 0.55))
                }

                Spacer()

                // Status badge
                Text(statusBadgeLabel)
                    .font(AMENFont.semiBold(11))
                    .foregroundColor(statusBadgeTextColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(statusBadgeTint)
                    )

                // 3-dot overflow
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.80))) {
                        showOverflow.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundColor(Color(white: 0.45))
                        .padding(6)
                }
            }

            // Processing progress bar
            if entry.status == .processingMedia {
                ProgressView(value: 0.45)
                    .tint(.black)
                    .frame(maxWidth: .infinity)
            }

            // Failed retry button
            if case .failed(let reason) = entry.status {
                VStack(alignment: .leading, spacing: 8) {
                    Text(reason)
                        .font(AMENFont.regular(12))
                        .foregroundColor(Color.red.opacity(0.65))
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        guard !isRetrying else { return }
                        isRetrying = true
                        onRetry?()
                        NotificationCenter.default.post(
                            name: Notification.Name("amenRetryScheduledPost"),
                            object: entry.id
                        )
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            isRetrying = false
                        }
                    } label: {
                        Text(isRetrying ? "Retrying…" : "Retry publish")
                            .font(AMENFont.semiBold(13))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Capsule().fill(Color.white.opacity(0.55)))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                                    )
                            )
                    }
                }
            }

            // Overflow menu
            if showOverflow {
                HStack(spacing: 8) {
                    overflowButton(icon: "pencil", label: "Edit", action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showOverflow = false
                        onEdit?()
                        NotificationCenter.default.post(
                            name: Notification.Name("amenEditScheduledPost"),
                            object: entry
                        )
                    })
                    overflowButton(icon: "calendar.badge.clock", label: "Reschedule", action: onReschedule)
                    overflowButton(icon: "doc.on.doc", label: "Duplicate", action: onDuplicate)
                    overflowButton(icon: "xmark.circle", label: "Cancel", action: onCancel)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 14)
    }

    private func overflowButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundColor(Color(white: 0.45))
                Text(label)
                    .font(AMENFont.regular(11))
                    .foregroundColor(Color(white: 0.45))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview Provider

struct PostSchedulingSystem_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // SmartScheduleSheet preview
            SmartScheduleSheet(
                isPresented: .constant(true),
                scheduledDate: .constant(nil),
                postText: "Please join me in prayer for our community tonight.",
                hasImages: false,
                hasVideo: false
            )
            .previewDisplayName("Smart Schedule Sheet")

            // ScheduledStatusChip preview
            VStack {
                Spacer()
                ScheduledStatusChip(
                    scheduledDate: Calendar.current.date(byAdding: .hour, value: 3, to: Date()) ?? Date(),
                    onEdit: {},
                    onClear: {}
                )
                Spacer()
            }
            .background(Color.white)
            .previewDisplayName("Scheduled Status Chip")

            // PublishPillView preview
            VStack {
                Spacer()
                PublishPillView(
                    mode: .constant(.postNow),
                    isEnabled: true,
                    isLoading: false,
                    scheduledDate: nil,
                    onPublishNow: {},
                    onSchedule: {},
                    onSaveDraft: {}
                )
                Spacer()
            }
            .background(Color.white)
            .previewDisplayName("Publish Pill")

            // ScheduledPostsHub preview
            NavigationStack {
                ScheduledPostsHub()
            }
            .previewDisplayName("Scheduled Posts Hub")
        }
    }
}
