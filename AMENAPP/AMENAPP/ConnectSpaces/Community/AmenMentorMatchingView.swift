// AmenMentorMatchingView.swift
// AMEN ConnectSpaces — AI-powered mentor matching + active mentorship tracking
// Built: 2026-06-04

import SwiftUI
import FirebaseAuth
import FirebaseFunctions

// MARK: - Inline Models

struct MentorMatch: Identifiable, Codable {
    let id: String
    let userId: String
    let displayName: String
    let sharedInterests: [String]
    let matchScore: Double
    let availabilityNote: String

    var matchLabel: String {
        if matchScore >= 0.80 { return "Strong Match" }
        if matchScore >= 0.60 { return "Good Match" }
        return "Potential Match"
    }

    var matchColor: Color {
        if matchScore >= 0.80 { return Color(hex: "D9A441") }
        if matchScore >= 0.60 { return Color(hex: "6E4BB5") }
        return Color.white.opacity(0.55)
    }
}

struct ActiveMentorship: Identifiable, Codable {
    let id: String
    let partnerUserId: String
    let partnerName: String
    let startDate: Date
    let goals: [String]
    let milestonesCompleted: Int
    let totalMilestones: Int
    let nextCheckIn: Date?

    var progressFraction: Double {
        guard totalMilestones > 0 else { return 0 }
        return Double(milestonesCompleted) / Double(totalMilestones)
    }
}

// MARK: - Constants

private let mentorInterestOptions = [
    "Faith", "Marriage", "Parenting", "Career",
    "Mental Health", "Business", "Leadership", "Addiction Recovery",
    "Grief", "Spiritual Formation", "Prayer Life", "Bible Study"
]

private let mentorTypeOptions = [
    "1-on-1 Mentorship", "Accountability Partner",
    "Prayer Partner", "Life Coach", "Spiritual Director"
]

private let commitmentOptions = [
    "15 min/week", "30 min/week", "1 hr/week", "Flexible"
]

// MARK: - Main View

struct AmenMentorMatchingView: View {
    let spaceId: String
    let currentUserId: String
    let onDismiss: () -> Void

    @State private var selectedTab = 0
    @State private var selectedInterests: Set<String> = []
    @State private var selectedType = mentorTypeOptions.first ?? "1-on-1 Mentorship"
    @State private var selectedCommitment = commitmentOptions.last ?? "Flexible"
    @State private var isSearching = false
    @State private var matches: [MentorMatch] = []
    @State private var searchError: String?
    @State private var activeMentorships: [ActiveMentorship] = []
    @State private var loadingMentorships = false
    @State private var requestSentForId: String?
    @State private var showingDetailFor: ActiveMentorship?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let functions = Functions.functions()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "070607").ignoresSafeArea()

                VStack(spacing: 0) {
                    tabBar
                    Divider().opacity(0.12)

                    if selectedTab == 0 {
                        findMentorTab
                            .transition(.opacity)
                    } else {
                        myMentorshipsTab
                            .transition(.opacity)
                    }
                }
            }
            .navigationTitle("Mentorship")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                        .foregroundStyle(Color(hex: "D9A441"))
                }
            }
        }
    }

    // MARK: - Tab Bar

    private let tabLabels = ["Find a Mentor", "My Mentorships"]

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabLabels.indices, id: \.self) { idx in
                let label = tabLabels[idx]
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        selectedTab = idx
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(label)
                            .font(.system(size: 14, weight: selectedTab == idx ? .bold : .medium))
                            .foregroundStyle(selectedTab == idx ? Color(hex: "D9A441") : Color.white.opacity(0.50))
                        Rectangle()
                            .fill(selectedTab == idx ? Color(hex: "D9A441") : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .accessibilityLabel(label)
            }
        }
        .padding(.horizontal, 16)
        .background(Color(hex: "070607"))
    }

    // MARK: - Find Mentor Tab

    private var findMentorTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {

                filterSection(title: "Interests") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                        ForEach(mentorInterestOptions, id: \.self) { interest in
                            MentorInterestPill(
                                label: interest,
                                isSelected: selectedInterests.contains(interest)
                            ) {
                                if selectedInterests.contains(interest) {
                                    selectedInterests.remove(interest)
                                } else {
                                    selectedInterests.insert(interest)
                                }
                            }
                        }
                    }
                }

                filterSection(title: "Looking For") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(mentorTypeOptions, id: \.self) { type in
                                MentorSelectablePill(
                                    label: type,
                                    isSelected: selectedType == type
                                ) { selectedType = type }
                            }
                        }
                    }
                }

                filterSection(title: "Time Commitment") {
                    HStack(spacing: 8) {
                        ForEach(commitmentOptions, id: \.self) { opt in
                            MentorSelectablePill(
                                label: opt,
                                isSelected: selectedCommitment == opt
                            ) { selectedCommitment = opt }
                        }
                    }
                }

                Button(action: findMatches) {
                    HStack(spacing: 8) {
                        if isSearching {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Color(hex: "070607"))
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Find Matches")
                                .font(.system(size: 15, weight: .bold))
                        }
                    }
                    .foregroundStyle(Color(hex: "070607"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: "D9A441"))
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSearching || selectedInterests.isEmpty)
                .opacity(selectedInterests.isEmpty ? 0.45 : 1)
                .accessibilityLabel("Find mentor matches")
                .accessibilityHint(selectedInterests.isEmpty ? "Select at least one interest first" : "")

                if let error = searchError {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.red.opacity(0.80))
                        .padding(.horizontal, 4)
                }

                if !matches.isEmpty {
                    sectionLabel("Matches for You")
                    LazyVStack(spacing: 12) {
                        ForEach(matches) { match in
                            MentorMatchCard(
                                match: match,
                                requestSent: requestSentForId == match.id
                            ) {
                                Task { await sendRequest(to: match) }
                            }
                        }
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    // MARK: - My Mentorships Tab

    private var myMentorshipsTab: some View {
        Group {
            if loadingMentorships {
                VStack {
                    Spacer()
                    ProgressView().tint(Color(hex: "D9A441"))
                    Spacer()
                }
            } else if activeMentorships.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "person.2.circle")
                        .font(.system(size: 44, weight: .thin))
                        .foregroundStyle(Color.white.opacity(0.25))
                    Text("No active mentorships yet.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.45))
                    Spacer()
                }
                .padding(.horizontal, 32)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(activeMentorships) { mentorship in
                            ActiveMentorshipCard(mentorship: mentorship) {
                                showingDetailFor = mentorship
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    Spacer(minLength: 40)
                }
                .sheet(item: $showingDetailFor) { mentorship in
                    MentorshipDetailSheet(mentorship: mentorship)
                }
            }
        }
        .task { await loadMentorships() }
    }

    // MARK: - Helpers

    private func filterSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(title)
            content()
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .kerning(1.2)
            .foregroundStyle(Color.white.opacity(0.40))
    }

    private func findMatches() {
        isSearching = true
        searchError = nil
        matches = []
        Task {
            do {
                let result = try await functions.httpsCallable("findMentorMatches").call([
                    "spaceId": spaceId,
                    "interests": Array(selectedInterests),
                    "mentorType": selectedType,
                    "availability": selectedCommitment
                ])
                guard let data = result.data as? [[String: Any]] else {
                    await MainActor.run { isSearching = false }
                    return
                }
                let decoded = data.compactMap { dict -> MentorMatch? in
                    guard
                        let id = dict["id"] as? String,
                        let userId = dict["userId"] as? String,
                        let displayName = dict["displayName"] as? String,
                        let sharedInterests = dict["sharedInterests"] as? [String],
                        let matchScore = dict["matchScore"] as? Double,
                        let availabilityNote = dict["availabilityNote"] as? String
                    else { return nil }
                    return MentorMatch(id: id, userId: userId, displayName: displayName,
                                      sharedInterests: sharedInterests, matchScore: matchScore,
                                      availabilityNote: availabilityNote)
                }
                await MainActor.run {
                    isSearching = false
                    matches = decoded
                    if decoded.isEmpty {
                        searchError = "No mentors matched your filters. Try broadening your interests."
                    }
                }
            } catch {
                await MainActor.run {
                    isSearching = false
                    searchError = "Could not load matches. Please try again."
                }
            }
        }
    }

    private func sendRequest(to match: MentorMatch) async {
        do {
            _ = try await functions.httpsCallable("requestMentorship").call([
                "spaceId": spaceId,
                "mentorUserId": match.userId,
                "message": "Hi \(match.displayName), I'd love to connect for \(selectedType)."
            ])
            await MainActor.run { requestSentForId = match.id }
        } catch {
            // non-blocking
        }
    }

    private func loadMentorships() async {
        loadingMentorships = true
        try? await Task.sleep(nanoseconds: 300_000_000)
        await MainActor.run {
            activeMentorships = []
            loadingMentorships = false
        }
    }
}

// MARK: - MentorInterestPill

private struct MentorInterestPill: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color(hex: "D9A441") : Color.white.opacity(0.70))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color(hex: "D9A441").opacity(0.14) : Color.white.opacity(0.06))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color(hex: "D9A441").opacity(0.55) : Color.white.opacity(0.12),
                                    lineWidth: isSelected ? 1 : 0.5
                                )
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - MentorSelectablePill

private struct MentorSelectablePill: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color(hex: "6E4BB5") : Color.white.opacity(0.70))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color(hex: "6E4BB5").opacity(0.14) : Color.white.opacity(0.06))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color(hex: "6E4BB5").opacity(0.55) : Color.white.opacity(0.12),
                                    lineWidth: isSelected ? 1 : 0.5
                                )
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - MentorMatchCard

private struct MentorMatchCard: View {
    let match: MentorMatch
    let requestSent: Bool
    let onConnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5) }
                        .frame(width: 44, height: 44)
                    Text(String(match.displayName.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(match.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text(match.matchLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(match.matchColor)
                }
                Spacer()

                if requestSent {
                    Label("Sent", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "D9A441"))
                } else {
                    Button(action: onConnect) {
                        Text("Connect")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: "070607"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background { Capsule().fill(Color(hex: "D9A441")) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Connect with \(match.displayName)")
                }
            }

            if !match.sharedInterests.isEmpty {
                HStack(spacing: 6) {
                    ForEach(match.sharedInterests.prefix(3), id: \.self) { interest in
                        Text(interest)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(hex: "6E4BB5"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background {
                                Capsule()
                                    .fill(Color(hex: "6E4BB5").opacity(0.12))
                                    .overlay { Capsule().strokeBorder(Color(hex: "6E4BB5").opacity(0.35), lineWidth: 0.5) }
                            }
                    }
                }
            }

            Text(match.availabilityNote)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(match.displayName), \(match.matchLabel)")
    }
}

// MARK: - ActiveMentorshipCard

private struct ActiveMentorshipCard: View {
    let mentorship: ActiveMentorship
    let onViewDetail: () -> Void

    var body: some View {
        Button(action: onViewDetail) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(mentorship.partnerName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Spacer()
                    Text("Started \(mentorship.startDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.40))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Milestones")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.45))
                        Spacer()
                        Text("\(mentorship.milestonesCompleted)/\(mentorship.totalMilestones)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "D9A441"))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.10))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: "D9A441"))
                                .frame(width: geo.size.width * mentorship.progressFraction)
                        }
                    }
                    .frame(height: 6)
                }

                if let nextCheckIn = mentorship.nextCheckIn {
                    Label(
                        "Next: \(nextCheckIn.formatted(date: .abbreviated, time: .shortened))",
                        systemImage: "calendar"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mentorship with \(mentorship.partnerName)")
    }
}

// MARK: - MentorshipDetailSheet

private struct MentorshipDetailSheet: View {
    let mentorship: ActiveMentorship
    @State private var sessionNotes = ""
    @State private var showEventComposer = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "070607").ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("Goals")
                            ForEach(mentorship.goals, id: \.self) { goal in
                                HStack(spacing: 10) {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(Color(hex: "D9A441").opacity(0.70))
                                    Text(goal)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.white.opacity(0.85))
                                }
                            }
                        }
                        .padding(16)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                                }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("Session Notes")
                            TextEditor(text: $sessionNotes)
                                .font(.system(size: 14))
                                .foregroundStyle(Color.white)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 100)
                                .padding(10)
                                .background {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                                        }
                                }
                        }

                        Button {
                            showEventComposer = true
                        } label: {
                            Label("Schedule Check-in", systemImage: "calendar.badge.plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: "D9A441"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(hex: "D9A441").opacity(0.10))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(Color(hex: "D9A441").opacity(0.35), lineWidth: 1)
                                        }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Schedule a check-in with \(mentorship.partnerName)")

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("with \(mentorship.partnerName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(hex: "D9A441"))
                }
            }
            .sheet(isPresented: $showEventComposer) {
                AmenSmartEventComposerView(
                    spaceId: "",
                    spaceName: "Check-in with \(mentorship.partnerName)",
                    onDismiss: { showEventComposer = false },
                    onEventCreated: { _ in showEventComposer = false }
                )
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .kerning(1.2)
            .foregroundStyle(Color.white.opacity(0.40))
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AmenMentorMatchingView(
        spaceId: "space-preview",
        currentUserId: "user-preview",
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}
#endif
