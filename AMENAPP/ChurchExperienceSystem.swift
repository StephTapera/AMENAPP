// ChurchExperienceSystem.swift
// AMENAPP
//
// Structured, moderated Church Experience layer.
// NOT a review wall — structured fields first, context second,
// open text last. Anti-slander moderation enforced before publish.
//
// Key types:
//   ChurchExperienceEntry        — the core data model
//   ChurchExperienceComposer     — multi-step entry UI
//   ChurchReputationCard         — multi-dimensional summary card
//   ChurchExperienceListView     — scrollable published entry list
//   ChurchExperienceConcernFlow  — private safety/conduct path

import SwiftUI

// MARK: - Enums

enum ChurchExperienceSignal: String, CaseIterable, Codable {
    // Positive
    case welcoming              = "welcoming"
    case strongTeaching         = "strongTeaching"
    case greatForKids           = "greatForKids"
    case greatForYoungAdults    = "greatForYoungAdults"
    case authenticWorship       = "authenticWorship"
    case goodFollowUp           = "goodFollowUp"
    case strongCommunity        = "strongCommunity"
    case accessibleParking      = "accessibleParking"
    case multiCultural          = "multiCultural"
    case goodForNewcomers       = "goodForNewcomers"
    case recoveryFriendly       = "recoveryFriendly"
    case goodForSingles         = "goodForSingles"
    case deepBibleTeaching      = "deepBibleTeaching"
    // Challenges
    case hardParking            = "hardParking"
    case hardForNewcomers       = "hardForNewcomers"
    case limitedKidsMinistry    = "limitedKidsMinistry"
    case fastPaced              = "fastPaced"
    case slowPaced              = "slowPaced"
    case limitedAccessibility   = "limitedAccessibility"
    case crowded                = "crowded"
    case difficultToFollow      = "difficultToFollow"
    case limitedYoungAdults     = "limitedYoungAdults"

    var displayName: String {
        switch self {
        case .welcoming:            return "Very welcoming"
        case .strongTeaching:       return "Strong teaching"
        case .greatForKids:         return "Great for kids"
        case .greatForYoungAdults:  return "Great for young adults"
        case .authenticWorship:     return "Authentic worship"
        case .goodFollowUp:         return "Great follow-up"
        case .strongCommunity:      return "Strong community"
        case .accessibleParking:    return "Easy parking"
        case .multiCultural:        return "Multicultural"
        case .goodForNewcomers:     return "Easy for newcomers"
        case .recoveryFriendly:     return "Recovery-friendly"
        case .goodForSingles:       return "Great for singles"
        case .deepBibleTeaching:    return "Deep Bible teaching"
        case .hardParking:          return "Hard to park"
        case .hardForNewcomers:     return "Tricky for newcomers"
        case .limitedKidsMinistry:  return "Limited kids ministry"
        case .fastPaced:            return "Fast-paced service"
        case .slowPaced:            return "Slow-paced service"
        case .limitedAccessibility: return "Limited accessibility"
        case .crowded:              return "Gets crowded"
        case .difficultToFollow:    return "Hard to follow along"
        case .limitedYoungAdults:   return "Few young adults"
        }
    }

    var isPositive: Bool {
        switch self {
        case .welcoming, .strongTeaching, .greatForKids, .greatForYoungAdults,
             .authenticWorship, .goodFollowUp, .strongCommunity, .accessibleParking,
             .multiCultural, .goodForNewcomers, .recoveryFriendly, .goodForSingles,
             .deepBibleTeaching:
            return true
        default:
            return false
        }
    }

    var icon: String {
        switch self {
        case .welcoming:            return "hands.sparkles"
        case .strongTeaching:       return "book.closed"
        case .greatForKids:         return "figure.2.and.child.holdinghands"
        case .greatForYoungAdults:  return "person.3"
        case .authenticWorship:     return "music.note"
        case .goodFollowUp:         return "envelope"
        case .strongCommunity:      return "heart.circle"
        case .accessibleParking:    return "car"
        case .multiCultural:        return "globe"
        case .goodForNewcomers:     return "star"
        case .recoveryFriendly:     return "cross.circle"
        case .goodForSingles:       return "person.crop.circle"
        case .deepBibleTeaching:    return "text.book.closed"
        case .hardParking:          return "car.fill"
        case .hardForNewcomers:     return "questionmark.circle"
        case .limitedKidsMinistry:  return "figure.2.and.child.holdinghands"
        case .fastPaced:            return "hare"
        case .slowPaced:            return "tortoise"
        case .limitedAccessibility: return "figure.roll"
        case .crowded:              return "person.3.fill"
        case .difficultToFollow:    return "puzzlepiece"
        case .limitedYoungAdults:   return "person.crop.circle.badge.minus"
        }
    }
}

enum ChurchFitTag: String, CaseIterable, Codable {
    case firstTimeVisitors    = "firstTimeVisitors"
    case families             = "families"
    case youngAdults          = "youngAdults"
    case singles              = "singles"
    case seekers              = "seekers"
    case deepTeachingLovers   = "deepTeachingLovers"
    case worshipFocused       = "worshipFocused"
    case recoveryHealing      = "recoveryHealing"
    case quietReflective      = "quietReflective"
    case communityOriented    = "communityOriented"
    case missionsFocused      = "missionsFocused"
    case multiGenerational    = "multiGenerational"

    var displayName: String {
        switch self {
        case .firstTimeVisitors:  return "First-time visitors"
        case .families:           return "Families"
        case .youngAdults:        return "Young adults"
        case .singles:            return "Singles"
        case .seekers:            return "Seekers & explorers"
        case .deepTeachingLovers: return "Deep teaching lovers"
        case .worshipFocused:     return "Worship-focused"
        case .recoveryHealing:    return "Recovery & healing"
        case .quietReflective:    return "Quiet & reflective"
        case .communityOriented:  return "Community-oriented"
        case .missionsFocused:    return "Missions-focused"
        case .multiGenerational:  return "Multi-generational"
        }
    }

    var icon: String {
        switch self {
        case .firstTimeVisitors:  return "door.left.hand.open"
        case .families:           return "house"
        case .youngAdults:        return "person.3"
        case .singles:            return "person.crop.circle"
        case .seekers:            return "magnifyingglass"
        case .deepTeachingLovers: return "text.book.closed"
        case .worshipFocused:     return "music.note"
        case .recoveryHealing:    return "cross.circle"
        case .quietReflective:    return "moon.stars"
        case .communityOriented:  return "heart.circle"
        case .missionsFocused:    return "globe.americas"
        case .multiGenerational:  return "person.3.sequence"
        }
    }
}

enum ExperienceVisibility: String, Codable {
    case publicPost      = "public"
    case followersOnly   = "followers"
    case privateEntry    = "private"
}

enum ExperienceStatus: String, Codable {
    case draft           = "draft"
    case pendingReview   = "pendingReview"
    case published       = "published"
    case flagged         = "flagged"
    case privateConcern  = "privateConcern"
}

enum PrivateConcernCategory: String, CaseIterable, Codable {
    case safety                  = "Safety concern"
    case inappropriateConduct    = "Inappropriate conduct"
    case financialPressure       = "Financial pressure"
    case childrensMinistryConcern = "Children's ministry concern"
    case harassment              = "Harassment"
    case doctrinalConcern        = "Doctrinal concern"
}

// MARK: - Core Model

struct ChurchExperienceEntry: Identifiable, Codable {
    var id: String = UUID().uuidString
    var churchId: String
    var authorId: String
    var authorName: String
    var visitDate: Date
    var isFirstTimeVisitor: Bool

    // Structured ratings (0–5 each)
    var welcomeScore: Int      = 0
    var teachingScore: Int     = 0
    var communityScore: Int    = 0
    var accessibilityScore: Int = 0
    var organizationScore: Int = 0
    var overallScore: Int      = 0

    // Structured signals
    var positiveSignals: [ChurchExperienceSignal]   = []
    var challengeSignals: [ChurchExperienceSignal]  = []

    // "Good fit for" tags
    var fitTags: [ChurchFitTag] = []

    // Optional open reflection
    var reflectionText: String?
    var practicalTip: String?

    // Metadata
    var wouldReturn: WouldReturn?
    var visibility: ExperienceVisibility  = .publicPost
    var status: ExperienceStatus          = .draft
    var createdAt: Date                   = Date()

    enum WouldReturn: String, Codable {
        case yes, maybe, no
    }
}

// MARK: - Glass Style Helpers (private)

private struct GlassCapsuleStyle: ViewModifier {
    var isSelected: Bool
    func body(content: Content) -> some View {
        content
            .background(
                Capsule()
                    .fill(isSelected ? Color.black : Color.white.opacity(0.55))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.clear : Color(white: 0.88).opacity(0.5),
                        lineWidth: 0.5
                    )
            )
    }
}

private extension View {
    func glassCapsule(selected: Bool = false) -> some View {
        modifier(GlassCapsuleStyle(isSelected: selected))
    }
}

private struct ChurchGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Color.white.opacity(0.55)
                    Color(white: 0.88).opacity(0.5)
                }.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
            )
    }
}

private extension View {
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(ChurchGlassCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Star Rating Row

private struct ChurchExperienceStarRatingRow: View {
    let label: String
    @Binding var score: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(AMENFont.regular(14))
                .foregroundStyle(Color(white: 0.2))
                .frame(maxWidth: 100, alignment: .leading)
            Spacer()
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= score ? "star.fill" : "star")
                        .font(.systemScaled(20))
                        .foregroundStyle(star <= score ? Color.black : Color(white: 0.75))
                        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: score)
                        .onTapGesture { score = star }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Signal Chip

private struct SignalChip: View {
    let signal: ChurchExperienceSignal
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: signal.icon)
                    .font(.systemScaled(11))
                Text(signal.displayName)
                    .font(AMENFont.semiBold(12))
            }
            .foregroundStyle(isSelected ? Color.white : Color(white: 0.25))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassCapsule(selected: isSelected)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isSelected)
    }
}

// MARK: - Fit Tag Chip

private struct FitTagChip: View {
    let tag: ChurchFitTag
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: tag.icon)
                    .font(.systemScaled(11))
                Text(tag.displayName)
                    .font(AMENFont.semiBold(12))
            }
            .foregroundStyle(isSelected ? Color.white : Color(white: 0.25))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassCapsule(selected: isSelected)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isSelected)
    }
}

// MARK: - ChurchExperienceComposer

struct ChurchExperienceComposer: View {
    let churchId: String
    let churchName: String
    let authorId: String
    let authorName: String

    @Environment(\.dismiss) private var dismiss

    @State private var step: Int = 1
    @State private var entry = ChurchExperienceEntry(churchId: "", authorId: "", authorName: "", visitDate: Date(), isFirstTimeVisitor: true)
    @State private var selectedSignals: Set<ChurchExperienceSignal> = []
    @State private var selectedFitTags: Set<ChurchFitTag> = []
    @State private var reflectionText: String = ""
    @State private var practicalTip: String = ""
    @State private var showModerationAlert: Bool = false
    @State private var moderationReason: String = ""
    @State private var showConcernFlow: Bool = false
    @State private var showSuccessToast: Bool = false

    private let riskPhrases = ["cult", "demonic", "fake", "fraud", "criminal", "predator"]
    private let coreModeration = ["abusive", "liar", "deceiving", "disgusting", "horrible people"]

    // MARK: Body

    var body: some View {
        NavigationView {
            ZStack {
                Color.white.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Progress bar
                    progressBar
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 16)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            switch step {
                            case 1: stepOneQuickSignals
                            case 2: stepTwoDimensionScores
                            case 3: stepThreeFitTags
                            case 4: stepFourReflection
                            default: EmptyView()
                            }
                            Spacer(minLength: 120)
                        }
                    }
                }

                // Bottom CTA
                VStack {
                    Spacer()
                    bottomCTA
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(AMENFont.regular(15))
                        .foregroundStyle(Color(white: 0.45))
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(churchName)
                            .font(AMENFont.semiBold(14))
                            .foregroundStyle(.primary)
                        Text("Share your experience")
                            .font(AMENFont.regular(11))
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
            }
        }
        .sheet(isPresented: $showConcernFlow) {
            ChurchExperienceConcernFlow(churchId: churchId, churchName: churchName)
        }
        .alert("A note before you share", isPresented: $showModerationAlert) {
            Button("Describe what happened") { /* keep editing */ }
            Button("Focus on my experience") { sanitizeReflection() }
            Button("Keep private") { submitPrivate() }
        } message: {
            Text(moderationReason)
        }
        .overlay(alignment: .bottom) {
            if showSuccessToast {
                Text("Experience shared. Thank you.")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black, in: Capsule())
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            entry.churchId   = churchId
            entry.authorId   = authorId
            entry.authorName = authorName
        }
    }

    // MARK: Progress Bar

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(1...4, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Color.black : Color(white: 0.88))
                    .frame(height: 3)
                    .animation(.spring(response: 0.38, dampingFraction: 0.82), value: step)
            }
        }
    }

    // MARK: Step 1 — Quick Signals

    private var stepOneQuickSignals: some View {
        VStack(alignment: .leading, spacing: 24) {

            // Overall star score
            VStack(alignment: .leading, spacing: 12) {
                Text("How was your visit overall?")
                    .font(AMENFont.bold(20))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 24)

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= entry.overallScore ? "star.fill" : "star")
                            .font(.systemScaled(36))
                            .foregroundStyle(star <= entry.overallScore ? Color.black : Color(white: 0.82))
                            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: entry.overallScore)
                            .onTapGesture { entry.overallScore = star }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 8)

            // Would you return
            VStack(alignment: .leading, spacing: 10) {
                Text("Would you return?")
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 24)

                HStack(spacing: 10) {
                    ForEach(ChurchExperienceEntry.WouldReturn.allCases, id: \.self) { choice in
                        Button {
                            entry.wouldReturn = choice
                        } label: {
                            Text(choice.label)
                                .font(AMENFont.semiBold(13))
                                .foregroundStyle(entry.wouldReturn == choice ? Color.white : Color(white: 0.25))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 9)
                                .glassCapsule(selected: entry.wouldReturn == choice)
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: entry.wouldReturn)
                    }
                }
                .padding(.horizontal, 24)
            }

            // First-time visitor toggle
            HStack {
                Text("First-time visitor?")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(Color(white: 0.45))
                Spacer()
                Toggle("", isOn: $entry.isFirstTimeVisitor)
                    .labelsHidden()
                    .tint(Color.black)
            }
            .padding(.horizontal, 24)

            Divider().padding(.horizontal, 24)

            // Positive signals
            VStack(alignment: .leading, spacing: 12) {
                Text("What stood out?")
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 24)

                signalChipsGrid(signals: ChurchExperienceSignal.allCases.filter { $0.isPositive })
            }

            // Challenge signals
            VStack(alignment: .leading, spacing: 12) {
                Text("Anything to note? (optional)")
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 24)

                signalChipsGrid(signals: ChurchExperienceSignal.allCases.filter { !$0.isPositive })
            }
        }
    }

    @ViewBuilder
    private func signalChipsGrid(signals: [ChurchExperienceSignal]) -> some View {
        // Wrap chips
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 120), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(signals, id: \.self) { signal in
                SignalChip(signal: signal, isSelected: selectedSignals.contains(signal)) {
                    if selectedSignals.contains(signal) {
                        selectedSignals.remove(signal)
                    } else {
                        selectedSignals.insert(signal)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: Step 2 — Dimension Scores

    private var stepTwoDimensionScores: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rate the experience")
                    .font(AMENFont.bold(20))
                    .foregroundStyle(.primary)
                Text("Optional — helps future visitors know what to expect.")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(Color(white: 0.55))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                ChurchExperienceStarRatingRow(label: "Welcome",       score: $entry.welcomeScore)
                Divider().padding(.leading, 16)
                ChurchExperienceStarRatingRow(label: "Teaching",      score: $entry.teachingScore)
                Divider().padding(.leading, 16)
                ChurchExperienceStarRatingRow(label: "Community",     score: $entry.communityScore)
                Divider().padding(.leading, 16)
                ChurchExperienceStarRatingRow(label: "Accessibility", score: $entry.accessibilityScore)
                Divider().padding(.leading, 16)
                ChurchExperienceStarRatingRow(label: "Organisation",  score: $entry.organizationScore)
            }
            .glassCard(cornerRadius: 16)
            .padding(.horizontal, 16)
        }
    }

    // MARK: Step 3 — Fit Tags

    private var stepThreeFitTags: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Who would you recommend this church for?")
                    .font(AMENFont.bold(20))
                    .foregroundStyle(.primary)
                Text("Select all that apply.")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(Color(white: 0.55))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(ChurchFitTag.allCases, id: \.self) { tag in
                    FitTagChip(tag: tag, isSelected: selectedFitTags.contains(tag)) {
                        if selectedFitTags.contains(tag) {
                            selectedFitTags.remove(tag)
                        } else {
                            selectedFitTags.insert(tag)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: Step 4 — Reflection

    private var stepFourReflection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Anything future visitors should know?")
                    .font(AMENFont.bold(20))
                    .foregroundStyle(.primary)
                Text("Optional — your own experience, your own words.")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(Color(white: 0.55))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 12) {
                textAreaField(
                    placeholder: "Share your experience... (optional)",
                    text: $reflectionText,
                    minHeight: 100
                )
                .padding(.horizontal, 16)

                textAreaField(
                    placeholder: "A practical tip for first-timers? (optional)",
                    text: $practicalTip,
                    minHeight: 60
                )
                .padding(.horizontal, 16)
            }

            // Visibility picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Who can see this?")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(Color(white: 0.4))
                    .padding(.horizontal, 24)

                HStack(spacing: 8) {
                    visibilityButton(.publicPost,    label: "Everyone",   icon: "globe")
                    visibilityButton(.followersOnly, label: "Followers",  icon: "person.2")
                    visibilityButton(.privateEntry,  label: "Just me",    icon: "lock")
                }
                .padding(.horizontal, 24)
            }

            // Safety concern link
            Button {
                showConcernFlow = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.shield")
                        .font(.systemScaled(12))
                    Text("Report a serious safety or conduct concern")
                        .font(AMENFont.regular(13))
                }
                .foregroundStyle(Color(white: 0.55))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
        }
    }

    private func visibilityButton(_ vis: ExperienceVisibility, label: String, icon: String) -> some View {
        Button {
            entry.visibility = vis
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.systemScaled(11))
                Text(label)
                    .font(AMENFont.semiBold(12))
            }
            .foregroundStyle(entry.visibility == vis ? Color.white : Color(white: 0.3))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassCapsule(selected: entry.visibility == vis)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: entry.visibility)
    }

    @ViewBuilder
    private func textAreaField(placeholder: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(Color(white: 0.7))
                    .padding(12)
            }
            TextEditor(text: text)
                .font(AMENFont.regular(14))
                .foregroundStyle(.primary)
                .frame(minHeight: minHeight)
                .padding(8)
                .scrollContentBackground(.hidden)
        }
        .glassCard(cornerRadius: 14)
    }

    // MARK: Bottom CTA

    private var bottomCTA: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if step > 1 {
                    Button("Back") { withAnimation { step -= 1 } }
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(Color(white: 0.45))
                        .frame(width: 70)
                }
                Button(step < 4 ? "Continue" : "Share experience") {
                    handleCTA()
                }
                .font(AMENFont.bold(15))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(ctaEnabled ? Color.black : Color(white: 0.82), in: Capsule())
                .disabled(!ctaEnabled)
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: ctaEnabled)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .background(Color(.systemBackground))
        }
    }

    private var ctaEnabled: Bool {
        switch step {
        case 1: return entry.overallScore > 0
        case 2: return true  // optional step
        case 3: return true  // optional step
        case 4: return true
        default: return false
        }
    }

    // MARK: Actions

    private func handleCTA() {
        if step < 4 {
            withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.82))) { step += 1 }
            return
        }
        // Final step — moderate then submit
        moderateAndSubmit()
    }

    private func moderateAndSubmit() {
        // Check for hard-blocked phrases → private concern path
        let combined = (reflectionText + " " + practicalTip).lowercased()
        for phrase in riskPhrases {
            if combined.contains(phrase) {
                showConcernFlow = true
                return
            }
        }

        // Check for low score + soft moderation phrases
        if entry.overallScore <= 2 {
            for phrase in coreModeration {
                if combined.contains(phrase) {
                    moderationReason = "Help future visitors by being specific about what you experienced, not assumptions about people's motives. You can describe what happened, focus on your experience, or keep this private."
                    showModerationAlert = true
                    return
                }
            }
            // Low score without problematic text — still show constructive prompt
            if !reflectionText.isEmpty {
                moderationReason = "Your experience matters. Help future visitors by being specific — what did you experience? Specific, honest reflections are the most helpful."
                showModerationAlert = true
                return
            }
        }

        commitEntry()
    }

    private func sanitizeReflection() {
        // User chose "Focus on my experience" — clear the text, let them rewrite
        reflectionText = ""
        practicalTip   = ""
    }

    private func submitPrivate() {
        entry.visibility = .privateEntry
        commitEntry()
    }

    private func commitEntry() {
        // Assemble final entry
        entry.positiveSignals   = selectedSignals.filter { $0.isPositive }
        entry.challengeSignals  = selectedSignals.filter { !$0.isPositive }
        entry.fitTags           = Array(selectedFitTags)
        entry.reflectionText    = reflectionText.isEmpty ? nil : reflectionText
        entry.practicalTip      = practicalTip.isEmpty ? nil : practicalTip
        entry.status            = entry.visibility == .privateEntry ? .draft : .pendingReview
        entry.createdAt         = Date()

        // In production: persist to local store / queue for Firestore write
        // ChurchExperienceStore.shared.submit(entry)

        withAnimation {
            showSuccessToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            dismiss()
        }
    }
}

// MARK: - WouldReturn all cases

extension ChurchExperienceEntry.WouldReturn: CaseIterable {
    static var allCases: [ChurchExperienceEntry.WouldReturn] { [.yes, .maybe, .no] }

    var label: String {
        switch self {
        case .yes:   return "Yes"
        case .maybe: return "Maybe"
        case .no:    return "Not for me"
        }
    }
}

// MARK: - Private Concern Flow

struct ChurchExperienceConcernFlow: View {
    let churchId: String
    let churchName: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: PrivateConcernCategory? = nil
    @State private var concernText: String = ""
    @State private var submitted = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.white.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Report a concern")
                                .font(AMENFont.bold(22))
                                .foregroundStyle(.primary)
                            Text("This will be sent privately to the AMEN moderation team. It will not be published.")
                                .font(AMENFont.regular(14))
                                .foregroundStyle(Color(white: 0.5))
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                        VStack(spacing: 8) {
                            ForEach(PrivateConcernCategory.allCases, id: \.self) { cat in
                                Button {
                                    selectedCategory = cat
                                } label: {
                                    HStack {
                                        Text(cat.rawValue)
                                            .font(AMENFont.regular(15))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if selectedCategory == cat {
                                            Image(systemName: "checkmark")
                                                .font(.systemScaled(13, weight: .semibold))
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 14)
                                    .glassCard(cornerRadius: 14)
                                }
                                .buttonStyle(.plain)
                                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: selectedCategory)
                                .padding(.horizontal, 16)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Describe what happened")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(Color(white: 0.4))
                                .padding(.horizontal, 24)

                            ZStack(alignment: .topLeading) {
                                if concernText.isEmpty {
                                    Text("Please be as specific as possible about what you experienced...")
                                        .font(AMENFont.regular(14))
                                        .foregroundStyle(Color(white: 0.7))
                                        .padding(12)
                                }
                                TextEditor(text: $concernText)
                                    .font(AMENFont.regular(14))
                                    .foregroundStyle(.primary)
                                    .frame(minHeight: 120)
                                    .padding(8)
                                    .scrollContentBackground(.hidden)
                            }
                            .glassCard(cornerRadius: 14)
                            .padding(.horizontal, 16)
                        }

                        Button {
                            submitted = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                dismiss()
                            }
                        } label: {
                            Text(submitted ? "Sent to moderation" : "Submit privately")
                                .font(AMENFont.bold(15))
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    (selectedCategory != nil && !concernText.isEmpty) || submitted
                                        ? Color.black : Color(white: 0.82),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedCategory == nil || concernText.isEmpty || submitted)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(AMENFont.regular(15))
                        .foregroundStyle(Color(white: 0.45))
                }
                ToolbarItem(placement: .principal) {
                    Text(churchName)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

// MARK: - ChurchReputationCard

struct ChurchReputationCard: View {
    let entries: [ChurchExperienceEntry]
    let onShareExperience: () -> Void

    private var publishedEntries: [ChurchExperienceEntry] {
        entries.filter { $0.status == .published }
    }

    private var avgWelcome: Double      { avg(publishedEntries.map { Double($0.welcomeScore) }) }
    private var avgTeaching: Double     { avg(publishedEntries.map { Double($0.teachingScore) }) }
    private var avgCommunity: Double    { avg(publishedEntries.map { Double($0.communityScore) }) }
    private var avgAccessibility: Double { avg(publishedEntries.map { Double($0.accessibilityScore) }) }
    private var avgOrganization: Double { avg(publishedEntries.map { Double($0.organizationScore) }) }

    private var topPositiveSignals: [ChurchExperienceSignal] {
        let all = publishedEntries.flatMap { $0.positiveSignals }
        let counts = Dictionary(grouping: all, by: { $0 }).mapValues { $0.count }
        return counts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
    }

    private var topFitTags: [ChurchFitTag] {
        let all = publishedEntries.flatMap { $0.fitTags }
        let counts = Dictionary(grouping: all, by: { $0 }).mapValues { $0.count }
        return counts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
    }

    private var wouldReturnCount: Int {
        publishedEntries.filter { $0.wouldReturn == .yes }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header
            HStack {
                Text("Visitor insights")
                    .font(AMENFont.bold(16))
                    .foregroundStyle(.primary)
                Spacer()
                if !publishedEntries.isEmpty {
                    Text("\(publishedEntries.count) visit\(publishedEntries.count == 1 ? "" : "s")")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(Color(white: 0.55))
                }
            }

            if publishedEntries.isEmpty {
                Text("No visitor insights yet. Be the first to share.")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(Color(white: 0.55))
            } else {
                // Dimension bars
                VStack(spacing: 10) {
                    dimensionBar(label: "Welcome",       score: avgWelcome)
                    dimensionBar(label: "Teaching",      score: avgTeaching)
                    dimensionBar(label: "Community",     score: avgCommunity)
                    dimensionBar(label: "Accessibility", score: avgAccessibility)
                    dimensionBar(label: "Organisation",  score: avgOrganization)
                }

                // Best known for
                if !topPositiveSignals.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Best known for")
                            .font(AMENFont.semiBold(12))
                            .foregroundStyle(Color(white: 0.55))

                        HStack(spacing: 8) {
                            ForEach(topPositiveSignals, id: \.self) { signal in
                                HStack(spacing: 4) {
                                    Image(systemName: signal.icon)
                                        .font(.systemScaled(10))
                                    Text(signal.displayName)
                                        .font(AMENFont.semiBold(11))
                                }
                                .foregroundStyle(Color(white: 0.25))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .glassCapsule()
                            }
                        }
                    }
                }

                // Good fit for
                if !topFitTags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Good fit for")
                            .font(AMENFont.semiBold(12))
                            .foregroundStyle(Color(white: 0.55))

                        HStack(spacing: 8) {
                            ForEach(topFitTags, id: \.self) { tag in
                                HStack(spacing: 4) {
                                    Image(systemName: tag.icon)
                                        .font(.systemScaled(10))
                                    Text(tag.displayName)
                                        .font(AMENFont.semiBold(11))
                                }
                                .foregroundStyle(Color(white: 0.25))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .glassCapsule()
                            }
                        }
                    }
                }

                // Footer stats
                Text("\(publishedEntries.count) visitor insight\(publishedEntries.count == 1 ? "" : "s") · \(wouldReturnCount) would return")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(Color(white: 0.55))
            }

            // Share CTA
            Button(action: onShareExperience) {
                Text("Share your experience")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .glassCard(cornerRadius: 12)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .glassCard(cornerRadius: 18)
    }

    @ViewBuilder
    private func dimensionBar(label: String, score: Double) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(AMENFont.regular(13))
                .foregroundStyle(Color(white: 0.35))
                .frame(width: 88, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(white: 0.9))
                        .frame(height: 5)
                    Capsule()
                        .fill(Color.black)
                        .frame(width: geo.size.width * CGFloat(score / 5.0), height: 5)
                }
            }
            .frame(height: 5)

            Text(score > 0 ? String(format: "%.1f", score) : "–")
                .font(AMENFont.semiBold(12))
                .foregroundStyle(score > 0 ? Color.black : Color(white: 0.7))
                .frame(width: 28, alignment: .trailing)
        }
    }

    private func avg(_ values: [Double]) -> Double {
        let valid = values.filter { $0 > 0 }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0, +) / Double(valid.count)
    }
}

// MARK: - ChurchExperienceListView

struct ChurchExperienceListView: View {
    let churchId: String
    let churchName: String
    @Binding var entries: [ChurchExperienceEntry]

    @State private var showComposer = false
    @State private var expandedEntryIds: Set<String> = []

    private var publishedEntries: [ChurchExperienceEntry] {
        entries
            .filter { $0.status == .published && $0.churchId == churchId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Reputation summary card
            ChurchReputationCard(entries: entries) {
                showComposer = true
            }

            if !publishedEntries.isEmpty {
                Text("Visitor experiences")
                    .font(AMENFont.bold(16))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 2)

                ForEach(publishedEntries) { entry in
                    experienceCard(entry)
                }
            }
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $showComposer) {
            ChurchExperienceComposer(
                churchId: churchId,
                churchName: churchName,
                authorId: "current_user",
                authorName: "You"
            )
        }
    }

    @ViewBuilder
    private func experienceCard(_ entry: ChurchExperienceEntry) -> some View {
        let isExpanded = expandedEntryIds.contains(entry.id)

        VStack(alignment: .leading, spacing: 12) {
            // Author row
            HStack(spacing: 10) {
                // Initials avatar
                ZStack {
                    Circle()
                        .fill(Color(white: 0.92))
                        .frame(width: 36, height: 36)
                    Text(initials(entry.authorName))
                        .font(AMENFont.bold(13))
                        .foregroundStyle(Color(white: 0.4))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.authorName)
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.primary)
                    Text(entry.isFirstTimeVisitor ? "First-time visitor" : "Returning visitor")
                        .font(AMENFont.regular(11))
                        .foregroundStyle(Color(white: 0.55))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    starRow(entry.overallScore)
                    Text(relativeDate(entry.visitDate))
                        .font(AMENFont.regular(11))
                        .foregroundStyle(Color(white: 0.65))
                }
            }

            // Top 2 signal chips
            let topSignals = Array((entry.positiveSignals + entry.challengeSignals).prefix(2))
            if !topSignals.isEmpty {
                HStack(spacing: 6) {
                    ForEach(topSignals, id: \.self) { signal in
                        HStack(spacing: 4) {
                            Image(systemName: signal.icon).font(.systemScaled(10))
                            Text(signal.displayName).font(AMENFont.semiBold(11))
                        }
                        .foregroundStyle(signal.isPositive ? Color.black : Color(white: 0.45))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .glassCapsule(selected: false)
                    }
                }
            }

            // Reflection snippet
            if let text = entry.reflectionText, !text.isEmpty {
                Text(text)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(Color(white: 0.25))
                    .lineLimit(isExpanded ? nil : 2)
                    .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isExpanded)

                if text.count > 100 {
                    Button(isExpanded ? "Show less" : "Read more") {
                        withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.82))) {
                            if isExpanded { expandedEntryIds.remove(entry.id) }
                            else          { expandedEntryIds.insert(entry.id) }
                        }
                    }
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(Color(white: 0.55))
                }
            }

            // Fit tags
            if !entry.fitTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(entry.fitTags.prefix(3), id: \.self) { tag in
                        Text(tag.displayName)
                            .font(AMENFont.regular(11))
                            .foregroundStyle(Color(white: 0.45))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(white: 0.95), in: Capsule())
                    }
                }
            }

            Divider()

            // Response row
            HStack(spacing: 0) {
                responseButton(label: "Similar",   icon: "plus.circle")
                Spacer()
                responseButton(label: "Different", icon: "minus.circle")
                Spacer()
                responseButton(label: "Helpful",   icon: "hand.thumbsup")
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 16)
    }

    private func responseButton(label: String, icon: String) -> some View {
        Button {
            // Reaction handling — future integration
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.systemScaled(12))
                Text(label).font(AMENFont.regular(13))
            }
            .foregroundStyle(Color(white: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func starRow(_ score: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= score ? "star.fill" : "star")
                    .font(.systemScaled(10))
                    .foregroundStyle(i <= score ? Color.black : Color(white: 0.8))
            }
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map { String($0) } ?? ""
        let last  = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return (first + last).uppercased()
    }

    private func relativeDate(_ date: Date) -> String {
        let diff = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if diff == 0 { return "Today" }
        if diff == 1 { return "Yesterday" }
        if diff < 7  { return "\(diff)d ago" }
        if diff < 30 { return "\(diff / 7)w ago" }
        return "\(diff / 30)mo ago"
    }
}

// MARK: - Previews

struct ChurchExperienceSystem_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ChurchExperienceComposer(
                churchId: "church_1",
                churchName: "Grace City Church",
                authorId: "user_1",
                authorName: "Alex M."
            )
            .previewDisplayName("Composer")

            ScrollView {
                ChurchExperienceListView(
                    churchId: "church_1",
                    churchName: "Grace City Church",
                    entries: .constant(previewEntries)
                )
                .padding()
            }
            .background(Color.white)
            .previewDisplayName("List View")
        }
    }

    static var previewEntries: [ChurchExperienceEntry] {
        [
            {
                var e = ChurchExperienceEntry(
                    churchId: "church_1",
                    authorId: "u1",
                    authorName: "Marcus T.",
                    visitDate: Date().addingTimeInterval(-86400 * 3),
                    isFirstTimeVisitor: true
                )
                e.overallScore     = 5
                e.welcomeScore     = 5
                e.teachingScore    = 5
                e.communityScore   = 4
                e.accessibilityScore = 4
                e.organizationScore  = 4
                e.positiveSignals  = [.welcoming, .strongTeaching, .goodForNewcomers]
                e.fitTags          = [.firstTimeVisitors, .youngAdults]
                e.reflectionText   = "I walked in not knowing anyone and left with a group of people inviting me to their midweek group. Incredible welcome team."
                e.wouldReturn      = .yes
                e.status           = .published
                return e
            }(),
            {
                var e = ChurchExperienceEntry(
                    churchId: "church_1",
                    authorId: "u2",
                    authorName: "Dana R.",
                    visitDate: Date().addingTimeInterval(-86400 * 10),
                    isFirstTimeVisitor: false
                )
                e.overallScore    = 4
                e.welcomeScore    = 4
                e.teachingScore   = 5
                e.communityScore  = 3
                e.organizationScore = 4
                e.positiveSignals = [.deepBibleTeaching, .authenticWorship]
                e.challengeSignals = [.hardParking]
                e.fitTags         = [.deepTeachingLovers, .families]
                e.reflectionText  = "The teaching is exceptional — expository, verse-by-verse. Parking is the one thing to plan ahead for."
                e.practicalTip    = "Arrive 20 minutes early on Sunday if you want street parking."
                e.wouldReturn     = .yes
                e.status          = .published
                return e
            }()
        ]
    }
}
