import SwiftUI

// MARK: - Display Tab

enum WellnessDisplayTab: String, CaseIterable {
    case tools      = "Tools"
    case counseling = "Counseling"
    case groups     = "Groups"
    case faith      = "Faith"
    case crisis     = "Crisis"
}

// MARK: - Tab Row

struct WellnessTabRow: View {
    @Binding var selectedTab: WellnessDisplayTab
    @Namespace private var tabNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(WellnessDisplayTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.80)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(tab.rawValue)
                                .font(.custom(selectedTab == tab ? "OpenSans-Bold" : "OpenSans-Regular", size: 16))
                                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                                .padding(.horizontal, 4)

                            if selectedTab == tab {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(red: 0.10, green: 0.60, blue: 0.56), Color(red: 0.14, green: 0.68, blue: 0.62)],
                                            startPoint: .leading, endPoint: .trailing
                                        )
                                    )
                                    .frame(height: 3)
                                    .matchedGeometryEffect(id: "tabIndicator", in: tabNamespace)
                            } else {
                                Capsule()
                                    .fill(Color.clear)
                                    .frame(height: 3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.rawValue)
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    .padding(.horizontal, 8)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 1)
        }
    }
}

// MARK: - Tab Content

struct WellnessTabContent: View {
    let tab: WellnessDisplayTab

    var body: some View {
        switch tab {
        case .tools:      WellnessToolsTabContent()
        case .counseling: WellnessCounselingTabContent()
        case .groups:     WellnessGroupsTabContent()
        case .faith:      WellnessFaithTabContent()
        case .crisis:     WellnessCrisisTabContent()
        }
    }
}

// MARK: - Tools Tab

private struct WellnessToolsTabContent: View {
    private let cards: [(title: String, text: String, chip: String)] = [
        (
            "Tools that remember the person",
            "Each tool carries one line of remembered context — preferred breathing pattern, recent journal continuity, sleep window. Helpful, not creepy.",
            "Personal"
        ),
        (
            "No streaks, no dopamine loops",
            "Observational copy only: \"You returned to breathing a few times last week.\" No badges, counters, or streak-recovery guilt.",
            "Anti-addictive"
        ),
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(cards, id: \.title) { card in
                WellnessSupportCard(title: card.title, bodyText: card.text, chip: card.chip)
            }
        }
    }
}

// MARK: - Counseling Tab

private struct WellnessCounselingTabContent: View {
    private let cards: [(title: String, text: String, chip: String)] = [
        (
            "Telehealth-first Christian counseling",
            "Verified providers with filters for tradition, specialty, insurance, language, and sliding scale. Therapy, pastoral care, and warmline are kept separate.",
            "Verified"
        ),
        (
            "Care type clarity",
            "Licensed therapy, pastoral counseling, and warmline support are distinct. This surface never blurs them into one vague \"help\" bucket.",
            "Clinically clear"
        ),
        (
            "Integration with professional care",
            "Berean Care can help you prepare for your next session or find a counselor. It never positions itself as the replacement.",
            "Safe framing"
        ),
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(cards, id: \.title) { card in
                WellnessSupportCard(title: card.title, bodyText: card.text, chip: card.chip)
            }
        }
    }
}

// MARK: - Groups Tab

struct WellnessGroupsTabContent: View {
    @State private var selectedNeed: GroupsIntakeNeed = .grief
    @State private var selectedFormat: GroupsIntakeFormat = .inPerson
    @State private var selectedPacing: GroupsIntakePacing = .lowPressure
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var matchResult: GroupsIntakeResult {
        GroupsIntakeResult.match(need: selectedNeed, format: selectedFormat, pacing: selectedPacing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("3-QUESTION INTAKE")
                        .font(.custom("OpenSans-SemiBold", size: 10))
                        .tracking(2.2)
                        .foregroundStyle(.secondary)
                    Text("Match the right support")
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Text("Matched")
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .foregroundStyle(Color(red: 0.62, green: 0.10, blue: 0.38))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(red: 0.98, green: 0.90, blue: 0.95))
                    .clipShape(Capsule())
            }
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium)
                    .stroke(.white.opacity(0.32), lineWidth: 1)
            )

            WellnessIntakeRow(label: "What do you need support with?") {
                ForEach(GroupsIntakeNeed.allCases, id: \.self) { need in
                    WellnessIntakePill(label: need.rawValue, isSelected: selectedNeed == need) {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.80)) { selectedNeed = need }
                    }
                }
            }
            WellnessIntakeRow(label: "Preferred format?") {
                ForEach(GroupsIntakeFormat.allCases, id: \.self) { fmt in
                    WellnessIntakePill(label: fmt.rawValue, isSelected: selectedFormat == fmt) {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.80)) { selectedFormat = fmt }
                    }
                }
            }
            WellnessIntakeRow(label: "Pacing?") {
                ForEach(GroupsIntakePacing.allCases, id: \.self) { pace in
                    WellnessIntakePill(label: pace.rawValue, isSelected: selectedPacing == pace) {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.80)) { selectedPacing = pace }
                    }
                }
            }

            // Match result
            VStack(alignment: .leading, spacing: 8) {
                Text("BEST MATCH")
                    .font(.custom("OpenSans-SemiBold", size: 10))
                    .tracking(2.2)
                    .foregroundStyle(.secondary)
                Text(matchResult.groupName)
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
                Text(matchResult.description)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium)
                    .stroke(.white.opacity(0.32), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.07), radius: 10, y: 4)
            .id("match-\(matchResult.groupName)")
            .transition(.opacity)
            .animation(reduceMotion ? .none : .spring(response: 0.38, dampingFraction: 0.82), value: matchResult.groupName)
        }
    }
}

private struct WellnessIntakeRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.custom("OpenSans-SemiBold", size: 10))
                .tracking(1.8)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { content() }
                    .padding(.horizontal, 2)
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall)
                .stroke(.white.opacity(0.28), lineWidth: 1)
        )
    }
}

private struct WellnessIntakePill: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.custom(isSelected ? "OpenSans-SemiBold" : "OpenSans-Regular", size: 13))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color(red: 0.08, green: 0.08, blue: 0.08) : Color(.systemBackground))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color.primary.opacity(0.14), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Faith Tab

private struct WellnessFaithTabContent: View {
    private let cards: [(title: String, text: String, chip: String, icon: String)] = [
        (
            "Examen",
            "A nightly review of the day with God — where you noticed grace, where you fell short, what tomorrow holds. Calm and honest, not performative.",
            "Evening",
            "moon.stars.fill"
        ),
        (
            "Lectio Divina",
            "Slow scripture meditation in four movements: read, reflect, respond, rest. Theological rigor, not generic mindfulness with Bible verses.",
            "Grounded",
            "book.fill"
        ),
        (
            "Centering Prayer",
            "Silent prayer with a single sacred word as anchor. Timer-based stillness. Consent to God's presence, not concentration.",
            "Contemplative",
            "circle.dotted"
        ),
        (
            "Compline · Night Office",
            "The ancient prayer of the church before sleep. Closes the day with scripture, a psalm, and a canticle. Available after 8 PM.",
            "Night-ready",
            "moon.fill"
        ),
        (
            "Fasting — with safeguards only",
            "Fasting tools are hidden until a safety screening is passed. Can be fully disabled if eating-related risk is present. This is not a weight-loss feature.",
            "Safety gate",
            "shield.fill"
        ),
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(cards, id: \.title) { card in
                WellnessSupportCard(title: card.title, bodyText: card.text, chip: card.chip, icon: card.icon)
            }
        }
    }
}

// MARK: - Crisis Tab

private struct WellnessCrisisTabContent: View {
    private let cards: [(title: String, text: String, chip: String)] = [
        (
            "\"For a Friend\" is a first-class path",
            "What to say, what not to say, when to call 988 on someone's behalf, how to set your own limits, and what support looks like for the helper.",
            "Promoted"
        ),
        (
            "Crisis stays simple",
            "No adaptive complexity when someone needs help fast. Urgent actions are immediate, obvious, and always separate from wellness personalization.",
            "Collapsed"
        ),
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(cards, id: \.title) { card in
                WellnessSupportCard(title: card.title, bodyText: card.text, chip: card.chip)
            }
        }
    }
}

// MARK: - Shared Support Card

struct WellnessSupportCard: View {
    let title: String
    let bodyText: String
    let chip: String
    var icon: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 17))
                    .foregroundStyle(.primary)
                Text(bodyText)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Text(chip)
                .font(.custom("OpenSans-SemiBold", size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium)
                .stroke(.white.opacity(0.32), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}
