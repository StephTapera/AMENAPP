import SwiftUI

// MARK: - Covenant Start Here View
// Member onboarding surface shown on first join. Guides the user through
// creator welcome, rules, best rooms, top teachings, intro prompt, and settings.

struct AmenCovenantStartHereView: View {
    let covenant: Covenant
    @Environment(\.dismiss) private var dismiss
    @State private var onboarding: CovenantOnboarding?
    @State private var loading = true
    @State private var currentStep = 0
    @State private var notificationPrefs: NotificationPrefs = .init()
    @State private var sundayModeEnabled = false

    struct NotificationPrefs {
        var announcements = true
        var prayerUpdates = true
        var events = true
        var newPosts = true
        var mentions = true
    }

    private let totalSteps = 4

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                if loading {
                    ProgressView()
                } else {
                    VStack(spacing: 0) {
                        progressBar
                        TabView(selection: $currentStep) {
                            welcomeStep.tag(0)
                            rulesStep.tag(1)
                            roomsAndContentStep.tag(2)
                            preferencesStep.tag(3)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentStep)

                        navigationButtons
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { dismiss() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .task { await loadOnboarding() }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? Color.purple : Color.secondary.opacity(0.25))
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                AsyncImage(url: URL(string: covenant.avatarURL ?? "")) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.purple.opacity(0.2)
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .shadow(color: .purple.opacity(0.2), radius: 12, y: 4)

                VStack(spacing: 8) {
                    Text(onboarding?.welcomeTitle ?? "Welcome to \(covenant.name)")
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(onboarding?.welcomeBody ?? covenant.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                AmenTrustBadgeRow(badges: covenant.trustBadges)

                HStack(spacing: 20) {
                    statCard(value: "\(covenant.memberCount)", label: "Members")
                    statCard(value: "\(covenant.tiers.count)", label: "Tiers")
                }
            }
            .padding(24)
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.purple)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    // MARK: - Step 1: Rules

    private var rulesStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                stepHeader(icon: "shield.fill", title: "Community Guidelines", subtitle: "How we treat each other here.")

                let rules = onboarding?.rules ?? [
                    "Treat every member with dignity.",
                    "No spam, self-promotion without permission.",
                    "Keep discussions spiritually constructive.",
                    "Respect theological diversity within Christian faith.",
                    "No harassment, hate speech, or abusive content.",
                    "Financial pressure or manipulation is not allowed."
                ]

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(rules.enumerated()), id: \.offset) { i, rule in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.purple))
                            Text(rule)
                                .font(.subheadline)
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }
            .padding(24)
        }
    }

    // MARK: - Step 2: Rooms + Content

    private var roomsAndContentStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                stepHeader(icon: "bubble.left.and.bubble.right.fill", title: "Get Started", subtitle: "Your first stops in the community.")

                if let intro = onboarding?.introPrompt, !intro.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Introduce Yourself", systemImage: "hand.wave.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.purple)
                        Text(intro)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Write Introduction") {}
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.purple)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.purple.opacity(0.06))
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Recommended Rooms")
                        .font(.subheadline.weight(.semibold))
                    VStack(spacing: 0) {
                        ForEach(CovenantRoom.RoomType.allCases.prefix(4), id: \.self) { type in
                            HStack(spacing: 12) {
                                Image(systemName: type.icon)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.purple)
                                    .frame(width: 32)
                                Text(type.displayName)
                                    .font(.subheadline)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            Divider().padding(.leading, 58)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                }
            }
            .padding(24)
        }
    }

    // MARK: - Step 3: Preferences

    private var preferencesStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                stepHeader(icon: "bell.badge.fill", title: "Your Preferences", subtitle: "Personalise your experience. Change anytime.")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notifications")
                        .font(.subheadline.weight(.semibold))
                    VStack(spacing: 0) {
                        prefToggle("Announcements", icon: "megaphone.fill", binding: $notificationPrefs.announcements)
                        prefToggle("Prayer Updates", icon: "hands.sparkles.fill", binding: $notificationPrefs.prayerUpdates)
                        prefToggle("Events", icon: "calendar", binding: $notificationPrefs.events)
                        prefToggle("New Posts", icon: "doc.richtext.fill", binding: $notificationPrefs.newPosts)
                        prefToggle("Mentions", icon: "at", binding: $notificationPrefs.mentions)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Sunday Mode")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 14) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Sunday Mode")
                                .font(.subheadline.weight(.medium))
                            Text("Quieter experience for Sundays. Fewer interruptions.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $sundayModeEnabled).labelsHidden()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                }
            }
            .padding(24)
        }
    }

    private func prefToggle(_ label: String, icon: String, binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 28)
            Text(label).font(.subheadline)
            Spacer()
            Toggle("", isOn: binding).labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 14) {
            if currentStep > 0 {
                Button("Back") {
                    withAnimation { currentStep -= 1 }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 80)
            }

            Button {
                if currentStep < totalSteps - 1 {
                    withAnimation { currentStep += 1 }
                } else {
                    dismiss()
                }
            } label: {
                Text(currentStep == totalSteps - 1 ? "Enter Community" : "Next")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.purple))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    // MARK: - Helpers

    private func stepHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.purple)
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func loadOnboarding() async {
        loading = true
        onboarding = try? await CovenantService.shared.loadOnboarding(covenantId: covenant.id ?? "")
        loading = false
    }
}
