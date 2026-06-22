// AmenSpacesHeroCardSection.swift
// AMEN Spiritual OS — Spaces Dashboard HeroCard Section
// Full parallax hero + stat row + study callout card + quick actions + activity feed.
// Updated 2026-06-03 — migrated to @Observable ViewModel; real Firestore data.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

// MARK: - Relative date formatter (file-private)

private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

// MARK: - Member avatar stack

private struct MemberAvatarStack: View {
    let memberPreviews: [MemberPreview]
    let totalMemberCount: Int

    private let size: CGFloat = 30
    private let overlap: CGFloat = 10

    var body: some View {
        HStack(spacing: -(overlap)) {
            ForEach(Array(memberPreviews.prefix(5).enumerated()), id: \.offset) { index, member in
                CachedAsyncImage(url: member.photoURL, size: CGSize(width: 60, height: 60)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.systemScaled(12))
                                .foregroundStyle(Color.white.opacity(0.6))
                        )
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
                .zIndex(Double(5 - index))
            }
        }
    }
}

// MARK: - Hero parallax image

private struct HeroParallaxImage: View {
    let bannerURL: String?
    let spaceName: String
    let scrollOffset: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Fallback background (always present)
                Color(.systemGroupedBackground)

                // Banner image with optional parallax offset
                if let urlString = bannerURL, let url = URL(string: urlString) {
                    CachedAsyncImage(url: url, size: CGSize(width: 800, height: 600)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: 300)
                            .clipped()
                            .offset(y: reduceMotion ? 0 : min(0, scrollOffset * 0.4))
                    } placeholder: {
                        Color.clear
                    }
                }

                // Bottom scrim for readability
                LinearGradient(
                    colors: [Color.clear, Color(.systemBackground).opacity(0.82)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
        }
        .accessibilityLabel("\(spaceName) banner photo")
        .accessibilityHidden(false)
    }
}

// MARK: - Space name frosted capsule (bottom-leading, NOT full-width)

private struct SpaceNameCapsule: View {
    let spaceName: String
    let tagline: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(spaceName)
                .font(.systemScaled(17, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let tagline {
                Text(tagline)
                    .font(.systemScaled(12))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Stat row (plain background — no glass)

private struct DashboardStatRow: View {
    let memberPreviews: [MemberPreview]
    let totalMemberCount: Int
    let activePrayerCount: Int
    let nextEvent: SpaceDashboardEvent?

    private var nextEventLabel: String {
        guard let event = nextEvent else { return "No events" }
        let f = DateFormatter()
        f.dateFormat = "EEE h a"
        return f.string(from: event.startTime)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Member avatars + overflow count
            HStack(spacing: 8) {
                MemberAvatarStack(
                    memberPreviews: memberPreviews,
                    totalMemberCount: totalMemberCount
                )
                if totalMemberCount > memberPreviews.count {
                    Text("+\(totalMemberCount - memberPreviews.count)")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.65))
                }
            }

            Spacer()

            // Active prayer count
            HStack(spacing: 5) {
                Image(systemName: "heart.fill")
                    .font(.systemScaled(13))
                    .foregroundStyle(Color.accentColor)
                Text("\(activePrayerCount) Prayer\(activePrayerCount == 1 ? "" : "s")")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
            }

            Spacer()

            // Next event
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.systemScaled(13))
                    .foregroundStyle(Color(hex: "245B8F"))
                Text(nextEventLabel)
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statRowA11yLabel)
    }

    private var statRowA11yLabel: String {
        let eventPart: String
        if let event = nextEvent {
            eventPart = event.startTime.formatted(.dateTime.weekday().hour().minute())
        } else {
            eventPart = "none"
        }
        return "\(totalMemberCount) members, \(activePrayerCount) active prayer requests, next event \(eventPart)"
    }
}

// MARK: - Study series card (LiquidGlassCard — one callout, per glass rules)

private struct StudySeriesCard: View {
    let series: StudySeries

    var body: some View {
        LiquidGlassCard(contextTint: Color.amenPurple, elevated: false) {
            HStack(spacing: 14) {
                Image(systemName: "book.fill")
                    .font(.systemScaled(22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(series.seriesTitle)
                        .font(.systemScaled(15, weight: .bold))
                        .foregroundStyle(Color(.label))
                        .lineLimit(1)

                    Text("Week \(series.currentWeek) of \(series.totalWeeks)")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(Color(.secondaryLabel))

                    if let reading = series.suggestedReading, !reading.isEmpty {
                        Text(reading)
                            .font(.systemScaled(12))
                            .foregroundStyle(Color.accentColor.opacity(0.90))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Current study: \(series.seriesTitle), week \(series.currentWeek) of \(series.totalWeeks)"
            + (series.suggestedReading.map { ". Reading: \($0)" } ?? "")
        )
    }
}

// MARK: - Quick action button (.bordered style — NOT glass)

private struct SpaceDashboardQuickActionButton: View {
    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.systemScaled(13, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .tint(Color.accentColor)
        .accessibilityLabel(label)
    }
}

// MARK: - Activity row (plain — no glass)

private struct SpaceDashboardActivityRow: View {
    let item: ActivityItem

    private var iconName: String {
        switch item.actionType {
        case "prayer": return "hands.sparkles.fill"
        case "note":   return "doc.text.fill"
        case "event":  return "calendar.circle.fill"
        default:       return "text.bubble.fill"
        }
    }

    private var iconTint: Color {
        switch item.actionType {
        case "prayer": return Color.accentColor
        case "note":   return Color.amenBlue
        case "event":  return Color.accentColor
        default:       return Color.amenPurple
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CachedAsyncImage(url: item.actorPhotoURL, size: CGSize(width: 72, height: 72)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.systemScaled(12))
                            .foregroundStyle(Color.white.opacity(0.5))
                    )
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(iconTint)

                    Text(item.actorName)
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Text(item.summary)
                    .font(.systemScaled(13))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Text(relativeFormatter.localizedString(for: item.timestamp, relativeTo: Date()))
                .font(.systemScaled(11))
                .foregroundStyle(Color.white.opacity(0.40))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.actorName): \(item.summary), "
            + relativeFormatter.localizedString(for: item.timestamp, relativeTo: Date())
        )
    }
}

// MARK: - Loading placeholder

private struct HeroLoadingPlaceholder: View {
    var body: some View {
        VStack {
            Spacer()
            ProgressView()
                .tint(Color.accentColor)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .background(Color(.secondarySystemBackground).opacity(0.6))
        .accessibilityHidden(true)
    }
}

// MARK: - Section header (plain label — no glass)

private func dashboardSectionHeader(title: String) -> some View {
    Text(title.uppercased())
        .font(.systemScaled(11, weight: .bold))
        .kerning(1.2)
        .foregroundStyle(Color.white.opacity(0.50))
        .padding(.horizontal, 16)
}

// MARK: - AmenSpacesHeroCardSection

/// Drop this view at the top of any Space detail view.
/// Self-contained: owns its ViewModel, fires .task { await vm.load() }.
struct AmenSpacesHeroCardSection: View {

    // MARK: Props

    let spaceId: String
    let bannerURL: String?
    let spaceName: String

    // Legacy support for callers using (spaceId:, userId:) signature
    var userId: String = ""

    // MARK: Feature flag

    @AppStorage("spiritualOS_enabled") private var masterEnabled = false
    @AppStorage("spiritualOS_spaces_dashboard_enabled") private var globalEnabled = false

    // MARK: ViewModel (@Observable — use @State, not @StateObject)

    @State private var viewModel: AmenSpacesDashboardViewModel

    // MARK: Sheet state

    @State private var showPrayTogether = false
    @State private var showSchedule = false
    @State private var showNotes = false
    @State private var showAskBerean = false
    @State private var showDiscussion = false

    // MARK: Scroll offset (provided by parent via preference key)

    @State private var scrollOffset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Primary init

    init(spaceId: String, bannerURL: String?, spaceName: String) {
        self.spaceId = spaceId
        self.bannerURL = bannerURL
        self.spaceName = spaceName
        _viewModel = State(wrappedValue: AmenSpacesDashboardViewModel(spaceId: spaceId))
    }

    // MARK: Legacy init for existing callers

    init(spaceId: String, userId: String) {
        self.spaceId = spaceId
        self.bannerURL = nil
        self.spaceName = ""
        self.userId = userId
        _viewModel = State(wrappedValue: AmenSpacesDashboardViewModel(spaceId: spaceId))
    }

    // MARK: Body

    var body: some View {
        Group {
            if !(masterEnabled && globalEnabled) {
                EmptyView()
            } else if viewModel.isLoading {
                HeroLoadingPlaceholder()
            } else {
                heroContent
            }
        }
        .task {
            guard masterEnabled && globalEnabled else { return }
            await viewModel.load()
        }
        .sheet(isPresented: $showPrayTogether) {
            PrayTogetherPlaceholderSheet(spaceId: spaceId)
        }
        .sheet(isPresented: $showSchedule) {
            SchedulePlaceholderSheet(spaceId: spaceId)
        }
        .sheet(isPresented: $showNotes) {
            OpenNotesPlaceholderSheet(spaceId: spaceId)
        }
        .sheet(isPresented: $showAskBerean) {
            AskBereanPlaceholderSheet(spaceId: spaceId)
        }
        .sheet(isPresented: $showDiscussion) {
            SpaceDiscussionSheet(spaceId: spaceId)
        }
    }

    // MARK: - Hero content

    @ViewBuilder
    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Hero image (260 pt) with frosted name capsule ─────────────────
            ZStack(alignment: .bottomLeading) {
                HeroParallaxImage(
                    bannerURL: bannerURL,
                    spaceName: spaceName,
                    scrollOffset: scrollOffset
                )
                .frame(height: 260)
                .clipped()

                // Frosted name capsule — bottom-leading, NOT full-width
                SpaceNameCapsule(
                    spaceName: spaceName.isEmpty
                        ? (viewModel.memberPreviews.first?.displayName ?? "Space")
                        : spaceName,
                    tagline: viewModel.nextEvent.map { "Next: \($0.title)" }
                )
                .padding(.leading, 16)
                .padding(.bottom, 16)
            }
            .frame(height: 260)

            // ── Stat row (plain background — no glass) ────────────────────────
            DashboardStatRow(
                memberPreviews: viewModel.memberPreviews,
                totalMemberCount: viewModel.totalMemberCount,
                activePrayerCount: viewModel.activePrayerCount,
                nextEvent: viewModel.nextEvent
            )
            .background(Color(.systemGroupedBackground))

            // ── Current study card (single LiquidGlassCard callout — per glass rules) ──
            if let series = viewModel.currentStudySeries {
                StudySeriesCard(series: series)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
            }

            // ── Quick action buttons (.bordered — NOT glass) ──────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    SpaceDashboardQuickActionButton(
                        label: "Pray Together",
                        icon: "hands.sparkles"
                    ) { showPrayTogether = true }

                    SpaceDashboardQuickActionButton(
                        label: "Start Discussion",
                        icon: "bubble.left.and.bubble.right"
                    ) { showDiscussion = true }

                    SpaceDashboardQuickActionButton(
                        label: "Open Notes",
                        icon: "doc.text"
                    ) { showNotes = true }

                    SpaceDashboardQuickActionButton(
                        label: "Ask Berean",
                        icon: "sparkles"
                    ) { showAskBerean = true }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))

            // ── Recent activity (plain rows — no glass) ──────────────────────
            if !viewModel.recentActivity.isEmpty {
                dashboardSectionHeader(title: "Recent Activity")
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                VStack(spacing: 0) {
                    ForEach(viewModel.recentActivity) { item in
                        SpaceDashboardActivityRow(item: item)

                        if item.id != viewModel.recentActivity.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.07))
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .background(Color(.systemGroupedBackground))
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Placeholder Sheets (intentional — each replaced by dedicated OS in a later phase)

private struct PrayTogetherPlaceholderSheet: View {
    let spaceId: String
    @Environment(\.dismiss) private var dismiss
    @State private var prayerText = ""
    @State private var isSubmitting = false
    @State private var submitted = false
    @ObservationIgnored private let db = Firestore.firestore()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                if submitted {
                    VStack(spacing: 16) {
                        Image(systemName: "hands.sparkles.fill")
                            .font(.systemScaled(44))
                            .foregroundStyle(Color.accentColor)
                        Text("Prayer Submitted")
                            .font(.title2.weight(.bold))
                        Text("Your prayer has been added for this space.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Done") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Share a prayer for this space community.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    TextEditor(text: $prayerText)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)

                    Spacer()

                    Button(action: submitPrayer) {
                        Group {
                            if isSubmitting { ProgressView() } else { Text("Submit Prayer") }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(prayerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                    .padding()
                }
            }
            .navigationTitle("Pray Together")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func submitPrayer() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSubmitting = true
        db.collection("spaces").document(spaceId).collection("prayerRequests").addDocument(data: [
            "uid": uid,
            "prayerText": prayerText.trimmingCharacters(in: .whitespacesAndNewlines),
            "createdAt": Timestamp(date: Date())
        ]) { _ in
            isSubmitting = false
            submitted = true
        }
    }
}

private struct SchedulePlaceholderSheet: View {
    let spaceId: String
    @Environment(\.dismiss) private var dismiss
    @State private var eventTitle = ""
    @State private var eventDate = Date().addingTimeInterval(86400)
    @State private var eventNote = ""
    @State private var isSubmitting = false
    @State private var submitted = false
    @ObservationIgnored private let db = Firestore.firestore()

    var body: some View {
        NavigationStack {
            Form {
                if submitted {
                    Section {
                        Label("Event scheduled!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    Section("Event Details") {
                        TextField("Event title", text: $eventTitle)
                        DatePicker("Date & Time", selection: $eventDate, displayedComponents: [.date, .hourAndMinute])
                    }
                    Section("Notes (optional)") {
                        TextEditor(text: $eventNote)
                            .frame(minHeight: 60)
                    }
                }
            }
            .navigationTitle("Schedule Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !submitted {
                        Button(isSubmitting ? "Saving…" : "Save") { scheduleEvent() }
                            .disabled(eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func scheduleEvent() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSubmitting = true
        var data: [String: Any] = [
            "title": eventTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            "scheduledAt": Timestamp(date: eventDate),
            "createdBy": uid,
            "spaceId": spaceId,
            "createdAt": Timestamp(date: Date())
        ]
        if !eventNote.isEmpty { data["note"] = eventNote }
        db.collection("spaces").document(spaceId).collection("events").addDocument(data: data) { _ in
            isSubmitting = false
            submitted = true
        }
    }
}

private struct SpaceNoteEntry: Identifiable {
    let id: String
    let text: String
    let authorUID: String
    let createdAt: Date
}

private struct OpenNotesPlaceholderSheet: View {
    let spaceId: String
    @Environment(\.dismiss) private var dismiss
    @State private var notes: [SpaceNoteEntry] = []
    @State private var newNoteText = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @ObservationIgnored private let db = Firestore.firestore()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView().padding(.top, 40)
                    Spacer()
                } else if notes.isEmpty {
                    ContentUnavailableView("No notes yet", systemImage: "doc.text", description: Text("Be the first to add a note for this space."))
                    Spacer()
                } else {
                    List(notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.text)
                                .font(.subheadline)
                            Text(note.createdAt.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listStyle(.plain)
                }

                HStack(spacing: 10) {
                    TextField("Add a note…", text: $newNoteText)
                        .textFieldStyle(.roundedBorder)
                    Button(action: saveNote) {
                        if isSaving { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    }
                    .disabled(newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
                .padding()
                .background(.regularMaterial)
            }
            .navigationTitle("Space Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await loadNotes() }
        .presentationDetents([.medium, .large])
    }

    private func loadNotes() async {
        isLoading = true
        let snap = try? await db.collection("spaces").document(spaceId).collection("notes")
            .order(by: "createdAt", descending: true).limit(to: 40).getDocuments()
        notes = snap?.documents.compactMap { doc -> SpaceNoteEntry? in
            let d = doc.data()
            guard let text = d["text"] as? String,
                  let uid = d["authorUID"] as? String,
                  let ts = d["createdAt"] as? Timestamp else { return nil }
            return SpaceNoteEntry(id: doc.documentID, text: text, authorUID: uid, createdAt: ts.dateValue())
        } ?? []
        isLoading = false
    }

    private func saveNote() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let text = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSaving = true
        db.collection("spaces").document(spaceId).collection("notes").addDocument(data: [
            "text": text, "authorUID": uid, "createdAt": Timestamp(date: Date())
        ]) { _ in
            newNoteText = ""
            isSaving = false
            Task { await loadNotes() }
        }
    }
}

private struct AskBereanPlaceholderSheet: View {
    let spaceId: String
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var answer = ""
    @State private var isAsking = false
    private let functions = Functions.functions()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.amenPurple)
                    Text("Ask a Bible study question about this space's topic.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                TextField("Your question…", text: $question, axis: .vertical)
                    .lineLimit(3...5)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                Button(action: askBerean) {
                    Group {
                        if isAsking { ProgressView() } else { Text("Ask Berean") }
                    }
                    .frame(maxWidth: .infinity).frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.amenPurple)
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAsking)
                .padding(.horizontal)

                if !answer.isEmpty {
                    ScrollView {
                        Text(answer)
                            .font(.subheadline)
                            .padding()
                    }
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top, 16)
            .navigationTitle("Ask Berean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func askBerean() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isAsking = true
        answer = ""
        Task {
            do {
                let callable = functions.httpsCallable("bereanQuestion")
                let result = try await callable.call(["question": q, "spaceId": spaceId])
                let data = result.data as? [String: Any] ?? [:]
                answer = (data["answer"] as? String) ?? "No answer returned."
            } catch {
                answer = "Could not reach Berean AI. Please try again."
            }
            isAsking = false
        }
    }
}

private struct SpaceDiscussionSheet: View {
    let spaceId: String
    @Environment(\.dismiss) private var dismiss
    @State private var topic = ""
    @State private var body_ = ""
    @State private var isSubmitting = false
    @State private var submitted = false
    @ObservationIgnored private let db = Firestore.firestore()

    var body: some View {
        NavigationStack {
            Form {
                if submitted {
                    Section {
                        Label("Discussion started!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    Section("Topic") {
                        TextField("What would you like to discuss?", text: $topic)
                    }
                    Section("Opening post") {
                        TextEditor(text: $body_)
                            .frame(minHeight: 80)
                    }
                }
            }
            .navigationTitle("Start Discussion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !submitted {
                        Button(isSubmitting ? "Posting…" : "Post") { startDiscussion() }
                            .disabled(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                    } else {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func startDiscussion() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSubmitting = true
        db.collection("spaces").document(spaceId).collection("discussions").addDocument(data: [
            "title": topic.trimmingCharacters(in: .whitespacesAndNewlines),
            "body": body_.trimmingCharacters(in: .whitespacesAndNewlines),
            "authorUid": uid,
            "createdAt": Timestamp(date: Date()),
            "spaceId": spaceId
        ]) { _ in
            isSubmitting = false
            submitted = true
        }
    }
}
