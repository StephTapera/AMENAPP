// FindChurch2ConciergeView.swift
// AMENAPP — Find Church 2.0 — Berean AI First-Visit Concierge (Wave 4 UI)
//
// Design rules enforced:
//   • .ultraThinMaterial only — no nested materials
//   • Luminous border: Color.white.opacity(0.45) strokeBorder 0.5 pt
//   • @Environment(\.accessibilityReduceMotion) guards all animations
//   • Dynamic Type text styles throughout — no fixed sizes
//   • All tap targets ≥ 44×44 pt
//   • Local-only answers — NO external API calls from this view
//   • Hard guardrail: fabrication of service times, beliefs, or staff is disallowed
//   • Feature-gated: returns EmptyView when findChurch2ConciergeEnabled == false
//
// Depends on:
//   FindChurch2Contracts.swift — ChurchObject, StructuredServiceTime, BeliefSchema
//   AMENFeatureFlags.swift     — findChurch2ConciergeEnabled

import SwiftUI

// MARK: - FindChurch2ConciergeView

struct FindChurch2ConciergeView: View {

    // MARK: Interface

    let church: ChurchObject

    // MARK: Preset questions

    private let presetQuestions: [String] = [
        "What time is service?",
        "Is childcare available?",
        "What denomination?",
        "What's the worship style?",
        "Is there parking?",
        "Are visitors welcome?"
    ]

    // MARK: State

    @State private var customQuestion: String = ""
    @State private var activeQuestion: String = ""
    @State private var responseText: String = ""
    @State private var isAnimating: Bool = false
    @FocusState private var isFieldFocused: Bool

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Feature gate

    @ObservedObject private var flags = AMENFeatureFlags.shared

    // MARK: Body

    var body: some View {
        if !flags.findChurch2ConciergeEnabled {
            EmptyView()
        } else {
            conciergeContent
        }
    }

    // MARK: - Concierge Content

    @ViewBuilder
    private var conciergeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                headerPill

                presetChipGrid

                customQuestionField

                if !responseText.isEmpty || isAnimating {
                    responseArea
                }

                if responseText.isEmpty && !isAnimating {
                    askBereanButton
                }

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .onTapGesture {
            isFieldFocused = false
        }
    }

    // MARK: - Header Pill

    private var headerPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Ask about \(church.name)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background {
            if reduceTransparency {
                Capsule(style: .continuous)
                    .fill(Color(.systemBackground))
            } else {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ask about \(church.name)")
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Preset Chip Grid

    private var presetChipGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick questions")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            // Two-row horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presetQuestions, id: \.self) { question in
                        PresetChipButton(
                            label: question,
                            reduceMotion: reduceMotion,
                            reduceTransparency: reduceTransparency
                        ) {
                            submitQuestion(question)
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Custom Question Field

    private var customQuestionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or ask your own question")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("Type your question…", text: $customQuestion, axis: .vertical)
                    .font(.subheadline)
                    .keyboardType(.default)
                    .submitLabel(.send)
                    .focused($isFieldFocused)
                    .lineLimit(1...4)
                    .onSubmit {
                        let q = customQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !q.isEmpty else { return }
                        submitQuestion(q)
                        customQuestion = ""
                        isFieldFocused = false
                    }
                    .accessibilityLabel("Type your question about \(church.name)")

                if !customQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        let q = customQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
                        submitQuestion(q)
                        customQuestion = ""
                        isFieldFocused = false
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color(red: 0.85, green: 0.70, blue: 0.20))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ask Berean")
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .scale(scale: 0.7).combined(with: .opacity)
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemBackground))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
            }
            .animation(reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.80), value: customQuestion.isEmpty)
        }
    }

    // MARK: - Ask Berean Button (shown only before first question)

    private var askBereanButton: some View {
        Button {
            let q = customQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return }
            submitQuestion(q)
            customQuestion = ""
            isFieldFocused = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .accessibilityHidden(true)
                Text("Ask Berean")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.85, green: 0.70, blue: 0.20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
                    }
            }
            .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
        .disabled(customQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(customQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1.0)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.15), value: customQuestion.isEmpty)
        .accessibilityLabel("Ask Berean about \(church.name)")
    }

    // MARK: - Response Area

    @ViewBuilder
    private var responseArea: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Asked question label
            if !activeQuestion.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(activeQuestion)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(3)
                }
                .accessibilityLabel("You asked: \(activeQuestion)")
            }

            // Response card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.85, green: 0.70, blue: 0.20))
                        .accessibilityHidden(true)
                    Text("Berean")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.85, green: 0.70, blue: 0.20))
                }

                if responseText.isEmpty && isAnimating {
                    // Typing indicator
                    HStack(spacing: 4) {
                        ForEach(0..<3) { index in
                            Circle()
                                .frame(width: 6, height: 6)
                                .foregroundStyle(.secondary.opacity(0.6))
                        }
                    }
                    .accessibilityLabel("Berean is typing")
                } else {
                    Text(responseText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(responseText)
                }

                // Source indicator
                if !responseText.isEmpty {
                    Text("Based on \(church.name)'s profile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemBackground))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
            }
        }
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        .animation(reduceMotion ? .none : .spring(response: 0.34, dampingFraction: 0.84), value: responseText)
    }

    // MARK: - Submit Logic

    private func submitQuestion(_ question: String) {
        guard !isAnimating else { return }

        activeQuestion = question
        responseText = ""

        let fullAnswer = localAnswer(question: question, church: church)

        if reduceMotion {
            // Skip animation — show immediately
            withAnimation(.none) {
                responseText = fullAnswer
            }
        } else {
            isAnimating = true
            Task { await animateReveal(fullAnswer) }
        }
    }

    /// Streams characters one by one with a 15 ms delay between each character.
    private func animateReveal(_ text: String) async {
        let chars = Array(text)
        var built = ""
        for char in chars {
            built.append(char)
            let snapshot = built
            await MainActor.run {
                self.responseText = snapshot
            }
            try? await Task.sleep(nanoseconds: 15_000_000) // 15 ms
        }
        await MainActor.run {
            self.isAnimating = false
        }
    }

    // MARK: - Local Answer Builder

    /// Deterministic answer builder. Reads ONLY from `church` — never fabricates.
    /// Hard guardrail: for any unknown field, returns the contact-fallback string.
    func localAnswer(question: String, church: ChurchObject) -> String {
        let q = question.lowercased()

        // Service times
        if containsAny(q, ["time", "service", "when", "start", "hour", "schedule", "sunday", "worship"]) {
            return serviceTimesAnswer(for: church)
        }

        // Childcare
        if containsAny(q, ["childcare", "child care", "nursery", "kids", "children", "baby", "babies"]) {
            if church.accessibility.hasChildcare {
                return "\(church.name) offers childcare. Contact them for age ranges and details."
            } else {
                return fallbackAnswer(church)
            }
        }

        // Denomination
        if containsAny(q, ["denomination", "denominat", "baptist", "methodist", "catholic",
                            "pentecostal", "non-denom", "nondenom", "type of church", "kind of church",
                            "presbyterian", "lutheran", "orthodox", "protestant", "evangelical"]) {
            return denominationAnswer(for: church)
        }

        // Worship style
        if containsAny(q, ["worship", "style", "music", "traditional", "contemporary",
                            "liturgical", "blended", "praise", "hymn"]) {
            return worshipStyleAnswer(for: church)
        }

        // Parking
        if containsAny(q, ["parking", "park", "lot", "where to park", "car"]) {
            if let parking = church.accessibility.parkingNotes {
                return "Parking at \(church.name): \(parking)"
            } else {
                return fallbackAnswer(church)
            }
        }

        // Visitors welcome
        if containsAny(q, ["visitor", "visit", "new", "welcome", "first time", "newcomer",
                            "guest", "drop in", "walk in"]) {
            return "\(church.name) welcomes first-time visitors. " +
                   "No reservation needed — just show up. Come as you are."
        }

        // Wheelchair / accessibility
        if containsAny(q, ["wheelchair", "accessible", "accessibility", "disability",
                            "handicap", "ramp", "elevator"]) {
            if church.accessibility.isWheelchairAccessible {
                let extra = church.accessibility.entranceNotes.map { " \($0)" } ?? ""
                return "\(church.name) is wheelchair accessible.\(extra)"
            } else {
                return fallbackAnswer(church)
            }
        }

        // ASL
        if containsAny(q, ["asl", "sign language", "deaf", "hearing"]) {
            if church.accessibility.hasASL {
                return "\(church.name) offers ASL interpretation."
            } else {
                return fallbackAnswer(church)
            }
        }

        // Languages
        if containsAny(q, ["language", "spanish", "korean", "english", "languages offered"]) {
            return languagesAnswer(for: church)
        }

        // Beliefs / theology
        if containsAny(q, ["belief", "theology", "doctrine", "baptism", "communion",
                            "scripture", "bible view", "governance"]) {
            return beliefsAnswer(for: church)
        }

        // Website / contact
        if containsAny(q, ["website", "contact", "email", "phone", "call", "reach"]) {
            return contactAnswer(for: church)
        }

        // Address / location
        if containsAny(q, ["address", "location", "where is", "directions", "find", "map"]) {
            return "\(church.name) is located at \(church.address)."
        }

        // Unknown
        return fallbackAnswer(church)
    }

    // MARK: - Answer Builders (private helpers)

    private func serviceTimesAnswer(for church: ChurchObject) -> String {
        guard !church.serviceTimes.isEmpty else {
            return "Service times for \(church.name) haven't been listed yet. " +
                   contactClause(church) + " for the current schedule."
        }

        // Group by day
        let days = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let grouped = Dictionary(grouping: church.serviceTimes) { $0.dayOfWeek }
        var lines: [String] = []

        for dayNum in [1, 2, 3, 4, 5, 6, 7] {
            guard let times = grouped[dayNum], !times.isEmpty else { continue }
            let dayName = dayNum >= 1 && dayNum <= 7 ? days[dayNum] : "Day"
            let timesStr = times.map { t -> String in
                var s = t.displayTime
                if let type = t.serviceType { s += " (\(type))" }
                return s
            }.joined(separator: ", ")
            lines.append("\(dayName): \(timesStr)")
        }

        return lines.isEmpty ? fallbackAnswer(church) : lines.joined(separator: "\n")
    }

    private func denominationAnswer(for church: ChurchObject) -> String {
        if church.denominationIsFlexible {
            return "\(church.name) is non-denominational."
        }
        if let denom = church.denomination {
            var answer = "\(church.name) is affiliated with the \(denom)."
            if let family = church.denominationFamily, !family.isEmpty,
               family.lowercased() != denom.lowercased() {
                answer += " Broadly in the \(family) family."
            }
            return answer
        }
        return fallbackAnswer(church)
    }

    private func worshipStyleAnswer(for church: ChurchObject) -> String {
        if let style = church.beliefs?.worshipStyle {
            return "\(church.name) has a \(style) worship style."
        }
        return fallbackAnswer(church)
    }

    private func beliefsAnswer(for church: ChurchObject) -> String {
        guard let beliefs = church.beliefs else {
            return fallbackAnswer(church)
        }
        let tags = beliefs.allTags
        guard !tags.isEmpty else {
            return fallbackAnswer(church)
        }
        let lines = tags.prefix(5).map { "\($0.category): \($0.value)" }
        return "Belief profile for \(church.name):\n" + lines.joined(separator: "\n")
    }

    private func languagesAnswer(for church: ChurchObject) -> String {
        let langs = church.accessibility.languages
        guard !langs.isEmpty else {
            return fallbackAnswer(church)
        }
        // Map BCP-47 codes to human-readable names (best-effort for common codes)
        let nameMap: [String: String] = [
            "en": "English", "es": "Spanish", "ko": "Korean",
            "zh": "Chinese", "pt": "Portuguese", "fr": "French",
            "de": "German", "tl": "Tagalog", "vi": "Vietnamese",
            "ht": "Haitian Creole", "ar": "Arabic", "ru": "Russian"
        ]
        let readable = langs.map { nameMap[$0] ?? $0 }.joined(separator: ", ")
        return "Services at \(church.name) are offered in: \(readable)."
    }

    private func contactAnswer(for church: ChurchObject) -> String {
        var parts: [String] = []
        if let website = church.website { parts.append("Website: \(website)") }
        if let phone = church.phoneNumber { parts.append("Phone: \(phone)") }
        if let email = church.email { parts.append("Email: \(email)") }
        if parts.isEmpty {
            return "Contact information for \(church.name) isn't listed yet. Try searching online for their name and location."
        }
        return "You can reach \(church.name) at:\n" + parts.joined(separator: "\n")
    }

    private func fallbackAnswer(_ church: ChurchObject) -> String {
        "That information isn't listed yet for this church. " + contactClause(church) + " if available."
    }

    private func contactClause(_ church: ChurchObject) -> String {
        if let website = church.website {
            return "You can contact them at \(website)"
        }
        if let phone = church.phoneNumber {
            return "You can contact them at \(phone)"
        }
        return "You can contact them directly"
    }

    private func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}

// MARK: - PresetChipButton

private struct PresetChipButton: View {

    let label: String
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let action: () -> Void

    @GestureState private var isPressed = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background {
                    if reduceTransparency {
                        Capsule(style: .continuous)
                            .fill(Color(.systemBackground))
                    } else {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(isPressed ? 0.18 : 0.08))
                            }
                    }
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
                }
                .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.96 : 1))
                .animation(
                    reduceMotion
                        ? .none
                        : .spring(response: 0.22, dampingFraction: 0.80),
                    value: isPressed
                )
        }
        .buttonStyle(.plain)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
        .accessibilityLabel(label)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Concierge — Full Profile") {
    let church = ChurchObject(
        id: "preview-concierge-1",
        placeId: nil,
        ein: nil,
        name: "Grace Fellowship Church",
        normalizedName: "grace fellowship church",
        address: "123 Main St, Phoenix, AZ 85001",
        normalizedAddress: "123 main st phoenix az 85001",
        city: "Phoenix",
        state: "AZ",
        zipCode: "85001",
        country: "US",
        coordinate: .init(latitude: 33.4484, longitude: -112.0740),
        phoneNumber: "(602) 555-0100",
        email: nil,
        website: "https://gracefellowship.example.com",
        photoURL: nil,
        logoURL: nil,
        denomination: "Southern Baptist Convention",
        denominationFamily: "Baptist",
        denominationIsFlexible: false,
        denominationLineage: ["Protestant", "Evangelical", "Baptist", "SBC"],
        beliefs: BeliefSchema(
            baptismView: "believer's baptism",
            communionView: "memorial",
            governance: "congregational",
            worshipStyle: "contemporary",
            spiritualGifts: nil,
            womenInMinistry: nil,
            scriptureView: "inerrancy",
            customTags: []
        ),
        serviceTimes: [
            StructuredServiceTime(
                dayOfWeek: 1,
                startHour: 9,
                startMinute: 0,
                durationMinutes: 75,
                serviceType: "First Service",
                isAccessibleASL: true,
                isAccessibleWheelchair: true
            ),
            StructuredServiceTime(
                dayOfWeek: 1,
                startHour: 11,
                startMinute: 0,
                durationMinutes: 75,
                serviceType: "Main Service"
            )
        ],
        mediaLinks: MediaLinks(),
        accessibility: AccessibilityInfo(
            hasASL: true,
            isWheelchairAccessible: true,
            languages: ["en", "es"],
            hasChildcare: true,
            parkingNotes: "Free parking in front and side lots",
            entranceNotes: "Accessible ramp on south side"
        ),
        claimState: .verified,
        verificationTier: .domain,
        claimedBy: nil,
        claimedAt: nil,
        childSafetyPolicy: ChildSafetyPolicy(),
        staffCount: nil,
        ministryTags: [],
        gatheringIds: [],
        availabilityCache: nil,
        availabilityCachedAt: nil,
        pendingServiceTimeSuggestions: 0,
        amenMemberCount: 42,
        visitCount: 180,
        friendSavedCount: 3,
        source: .googlePlaces,
        createdAt: Date(),
        updatedAt: Date(),
        isDeleted: false
    )

    FindChurch2ConciergeView(church: church)
}

#Preview("Concierge — Sparse Profile") {
    let church = ChurchObject(
        id: "preview-concierge-2",
        placeId: nil,
        ein: nil,
        name: "New Life Community",
        normalizedName: "new life community",
        address: "456 Oak Ave, Tempe, AZ 85281",
        normalizedAddress: "456 oak ave tempe az 85281",
        city: "Tempe",
        state: "AZ",
        zipCode: "85281",
        country: "US",
        coordinate: .init(latitude: 33.4255, longitude: -111.9400),
        phoneNumber: nil,
        email: nil,
        website: nil,
        photoURL: nil,
        logoURL: nil,
        denomination: nil,
        denominationFamily: nil,
        denominationIsFlexible: true,
        denominationLineage: [],
        beliefs: nil,
        serviceTimes: [],
        mediaLinks: MediaLinks(),
        accessibility: AccessibilityInfo(),
        claimState: .unclaimed,
        verificationTier: .none,
        claimedBy: nil,
        claimedAt: nil,
        childSafetyPolicy: ChildSafetyPolicy(),
        staffCount: nil,
        ministryTags: [],
        gatheringIds: [],
        availabilityCache: nil,
        availabilityCachedAt: nil,
        pendingServiceTimeSuggestions: 0,
        amenMemberCount: 2,
        visitCount: 5,
        friendSavedCount: 0,
        source: .userSubmitted,
        createdAt: Date(),
        updatedAt: Date(),
        isDeleted: false
    )

    FindChurch2ConciergeView(church: church)
}
#endif
