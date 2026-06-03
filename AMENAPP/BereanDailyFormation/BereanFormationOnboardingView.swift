// BereanFormationOnboardingView.swift
// AMENAPP — Berean Daily Formation Companion — Onboarding
//
// 4-step flow: intro → topics → consents (×4) → preparing.
// After preparing delay, fires onComplete(BereanFormationPrefs).

import SwiftUI

// MARK: - Onboarding steps

private enum FormationOnboardingStep {
    case intro
    case topics
    case consents(integrationIndex: Int)
    case preparing
}

// MARK: - Topic option

private struct FormationTopicOption {
    let id: String
    let label: String
    let icon: String
    let desc: String
}

private let TOPIC_OPTIONS: [FormationTopicOption] = [
    FormationTopicOption(id: "verse",    label: "Daily Verse & Reflection",  icon: "✦",  desc: "One verse tied to where you are in Scripture, with a short invitation to reflect."),
    FormationTopicOption(id: "plan",     label: "Reading-Plan Momentum",     icon: "📖", desc: "Know where you are today and keep your pace."),
    FormationTopicOption(id: "prayer",   label: "Prayer Follow-ups",         icon: "🙏", desc: "Revisit who you've been praying for; celebrate answered prayer."),
    FormationTopicOption(id: "sanctuary",label: "Sanctuary Stirrings",       icon: "⛪", desc: "Open requests and threads from your communities worth revisiting."),
    FormationTopicOption(id: "study",    label: "Open Study Thread",         icon: "🔍", desc: "A passage you highlighted or a study left unfinished."),
    FormationTopicOption(id: "memory",   label: "Memory-Verse Practice",     icon: "🧠", desc: "Spaced repetition to help Scripture take root."),
    FormationTopicOption(id: "seasonal", label: "Seasonal Rhythm",           icon: "🌿", desc: "Invitations shaped by the liturgical calendar."),
]

private let INTEGRATIONS = ["youversion", "sanctuary", "prayerlist", "notifications"]

private struct IntegrationMeta {
    let icon: String; let name: String; let reads: String; let why: String; let ifDeclined: String
}

private let INTEGRATION_META: [String: IntegrationMeta] = [
    "youversion": IntegrationMeta(
        icon: "📖", name: "YouVersion Bible",
        reads: "Your reading plans, bookmarks, and highlighted verses.",
        why: "So Berean ties your daily reflection to where you actually are in Scripture — not a random verse.",
        ifDeclined: "Berean works without this. Your reading plan progress will be tracked manually."
    ),
    "sanctuary": IntegrationMeta(
        icon: "⛪", name: "Sanctuaries",
        reads: "Open prayer requests and active threads in Sanctuaries you belong to.",
        why: "So Berean can surface community moments worth revisiting and people you could encourage.",
        ifDeclined: "No Sanctuary content is read without this permission."
    ),
    "prayerlist": IntegrationMeta(
        icon: "🙏", name: "Prayer List",
        reads: "Your personal prayer list — who you're praying for, and when.",
        why: "So Berean can gently remind you to pray again and celebrate answered prayer.",
        ifDeclined: "No AI processes your prayer items without this permission."
    ),
    "notifications": IntegrationMeta(
        icon: "🌅", name: "Morning Notifications",
        reads: "Nothing — this only schedules a single morning push notification.",
        why: "So Berean arrives each morning without you having to remember to open it.",
        ifDeclined: "You can open Berean manually anytime without notifications."
    ),
]

// MARK: - Main view

struct BereanFormationOnboardingView: View {
    let onComplete: (BereanFormationPrefs) -> Void

    @State private var step: FormationOnboardingStep = .intro
    @State private var selectedTopics: Set<String> = ["verse", "prayer"]
    @State private var consents: [String: Bool] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#0A0A0F"), Color(hex: "#111118")],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            Group {
                switch step {
                case .intro:
                    introView
                        .transition(transition)
                case .topics:
                    topicsView
                        .transition(transition)
                case .consents(let idx):
                    consentView(for: idx)
                        .transition(transition)
                case .preparing:
                    preparingView
                        .transition(transition)
                }
            }
            .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.85), value: stepTag)
        }
    }

    private var stepTag: Int {
        switch step {
        case .intro:          return 0
        case .topics:         return 1
        case .consents(let i):return 2 + i
        case .preparing:      return 99
        }
    }

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 12)),
            removal: .opacity.combined(with: .offset(y: -8))
        )
    }

    // MARK: - Intro

    private var introView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer(minLength: 60)

                // Gold emblem
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "#E8CB7A"), Color(hex: "#8A6F2E")],
                                center: UnitPoint(x: 0.38, y: 0.38),
                                startRadius: 0, endRadius: 40
                            )
                        )
                        .frame(width: 80, height: 80)
                        .shadow(color: Color(hex: "#C9A84C").opacity(0.4), radius: 24)
                    Image(systemName: "sparkle")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(Color(hex: "#0A0A0F"))
                }
                .padding(.bottom, 40)

                Text("Berean")
                    .font(.custom("Georgia", size: 48).weight(.light))
                    .foregroundStyle(Color(hex: "#F5F0E8"))
                    .tracking(2)

                Text("EXAMINING THE SCRIPTURES DAILY")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: "#E8CB7A").opacity(0.85))
                    .tracking(3)
                    .padding(.bottom, 40)

                // Acts 17:11 card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Now these Jews were more noble than those in Thessalonica; they received the word with all eagerness, examining the Scriptures daily to see if these things were so.")
                        .font(.custom("Georgia", size: 18).italic())
                        .foregroundStyle(Color(hex: "#F5F0E8"))
                        .lineSpacing(4)
                    Text("Acts 17:11 (ESV)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotifGlassTokens.goldPrimary)
                        .tracking(0.5)
                    BereanMockLabel()
                    Text("Berean helps you stay rooted. Every morning, a personal arc of reflection — tied to where you actually are in your walk.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineSpacing(3)
                        .padding(.top, 8)
                }
                .padding(20)
                .glassSurface(cornerRadius: 20)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                // Bullet points
                VStack(alignment: .leading, spacing: 12) {
                    ForEach([
                        "Scripture tied to your reading plan, not random",
                        "Prayer follow-ups from your own list",
                        "Your community — not a feed of strangers",
                        "Formation over information. Faithfulness over productivity.",
                    ], id: \.self) { point in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 10)).foregroundStyle(NotifGlassTokens.goldPrimary)
                                .padding(.top, 3)
                            Text(point)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.55))
                                .lineSpacing(2)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)

                BereanFormationPrimaryButton("Begin") { step = .topics }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 60)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Topics

    private var topicsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 60)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle").font(.system(size: 10)).foregroundStyle(NotifGlassTokens.goldPrimary)
                        Text("Berean").font(.system(size: 11, weight: .semibold)).foregroundStyle(NotifGlassTokens.goldPrimary).tracking(1.5)
                    }
                    Text("What shapes your morning?")
                        .font(.custom("Georgia", size: 30).weight(.light))
                        .foregroundStyle(Color(hex: "#F5F0E8"))
                    Text("Select the kinds of formation you want each day.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.40))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                VStack(spacing: 10) {
                    ForEach(TOPIC_OPTIONS, id: \.id) { topic in
                        let active = selectedTopics.contains(topic.id)
                        Button {
                            if active { selectedTopics.remove(topic.id) } else { selectedTopics.insert(topic.id) }
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Text(topic.icon).font(.system(size: 22))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(topic.label)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(active ? Color(hex: "#E8CB7A") : Color(hex: "#F5F0E8"))
                                    Text(topic.desc)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.white.opacity(0.45))
                                        .lineSpacing(2)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                if active {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(NotifGlassTokens.goldPrimary)
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(active ? Color(hex: "#C9A84C").opacity(0.06) : Color.white.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(active ? Color(hex: "#C9A84C") : Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(active ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                BereanFormationPrimaryButton("Continue — connect sources", disabled: selectedTopics.isEmpty) {
                    step = .consents(integrationIndex: 0)
                }
                .padding(.horizontal, 24)

                Text("All integrations default OFF. You'll choose what to share next.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.25))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 60)
            }
        }
    }

    // MARK: - Consent

    private func consentView(for idx: Int) -> some View {
        let key  = INTEGRATIONS[idx]
        let meta = INTEGRATION_META[key]!

        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer(minLength: 80)

                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text(meta.icon).font(.system(size: 44))
                        Text("Connect \(meta.name)?")
                            .font(.custom("Georgia", size: 26).weight(.light))
                            .foregroundStyle(Color(hex: "#F5F0E8"))
                            .multilineTextAlignment(.center)
                        Text("All integrations default OFF. You decide what Berean sees.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.30))
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        consentRow(label: "What Berean reads", value: meta.reads)
                        consentRow(label: "Why it helps",      value: meta.why)
                        HStack(alignment: .top, spacing: 8) {
                            Text("If you decline:")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.45))
                                .frame(width: 90, alignment: .leading)
                            Text(meta.ifDeclined)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.35))
                                .lineSpacing(2)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color(hex: "#C9A84C").opacity(0.18), lineWidth: 0.5)
                        )
                    }
                    .padding(20)
                    .glassSurface(cornerRadius: 20)

                    HStack(spacing: 12) {
                        BereanFormationGhostButton("Not now") { advanceConsent(accepted: false) }
                        BereanFormationPrimaryButton("Connect")  { advanceConsent(accepted: true) }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 60)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func consentRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(NotifGlassTokens.goldPrimary).tracking(1.2).textCase(.uppercase)
            Text(value).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.55)).lineSpacing(2)
        }
    }

    private func advanceConsent(accepted: Bool) {
        guard case .consents(let idx) = step else { return }
        let key = INTEGRATIONS[idx]
        consents[key] = accepted
        let next = idx + 1
        if next < INTEGRATIONS.count {
            step = .consents(integrationIndex: next)
        } else {
            step = .preparing
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                onComplete(BereanFormationPrefs(selectedTopics: selectedTopics, consents: consents))
            }
        }
    }

    // MARK: - Preparing

    private var preparingView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "sparkle")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(NotifGlassTokens.goldLight)
                .symbolEffect(.breathe)
            Text("Your first Berean is being prepared.")
                .font(.custom("Georgia", size: 32).weight(.light))
                .foregroundStyle(NotifGlassTokens.goldLight)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Text("Overnight, Berean reads where you are in your walk and prepares a personal arc of reflection for morning.\n\nFormation over information. Faithfulness over productivity.")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared button styles

struct BereanFormationPrimaryButton: View {
    let title: String
    var disabled: Bool = false
    let action: () -> Void

    init(_ title: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.disabled = disabled; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(disabled ? Color.white.opacity(0.35) : Color(hex: "#0A0A0F"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(disabled ? Color.white.opacity(0.08) : NotifGlassTokens.primaryButtonGradient)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(title)
    }
}

struct BereanFormationGhostButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(hex: "#F5F0E8"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

#Preview { BereanFormationOnboardingView { _ in } }
