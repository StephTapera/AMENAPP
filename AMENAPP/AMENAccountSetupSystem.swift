//
//  AMENAccountSetupSystem.swift
//  AMENAPP
//
//  Role-based setup continuation system shown after account type selection.
//  Displays smart setup cards the user should complete per account type.
//
//  No Firebase. Pure SwiftUI.
//

import SwiftUI

// MARK: - 1. AccountSetupProgress

struct AccountSetupProgress {
    let accountType: AMENAccountType
    var completedItems: Set<String>

    var progressFraction: Double {
        let total = requiredItems.count + suggestedItems.count
        guard total > 0 else { return 1.0 }
        let done = completedItems.intersection(allItemKeys).count
        return Double(done) / Double(total)
    }

    var isComplete: Bool { progressFraction >= 1.0 }

    private var allItemKeys: Set<String> {
        Set(requiredItems.map(\.key) + suggestedItems.map(\.key))
    }

    var requiredItems: [(key: String, label: String)] {
        switch accountType {
        case .personal:
            return [
                (key: "profile_photo", label: "Add a profile photo"),
                (key: "bio", label: "Write your bio"),
                (key: "church_affiliation", label: "Add your church")
            ]
        case .church:
            return [
                (key: "church_name", label: "Confirm church name"),
                (key: "service_times", label: "Add service times"),
                (key: "location", label: "Add your address")
            ]
        case .business:
            return [
                (key: "org_name", label: "Confirm organization name"),
                (key: "category", label: "Choose your category"),
                (key: "mission", label: "Write your mission statement")
            ]
        }
    }

    var suggestedItems: [(key: String, label: String)] {
        switch accountType {
        case .personal:
            return [
                (key: "faith_journey", label: "Share your faith journey"),
                (key: "prayer_focus", label: "Add a prayer focus"),
                (key: "testimony", label: "Share your testimony")
            ]
        case .church:
            return [
                (key: "profile_photo", label: "Upload a church photo"),
                (key: "visit_info", label: "Add first-visit info"),
                (key: "social_links", label: "Connect social accounts")
            ]
        case .business:
            return [
                (key: "logo", label: "Upload your logo"),
                (key: "website", label: "Add website URL"),
                (key: "featured_offering", label: "Add a featured offering")
            ]
        }
    }

    // MARK: Persistence

    private static func defaultsKey(_ type: AMENAccountType) -> String {
        "amenSetupProgress_\(type.rawValue)"
    }

    static func load(for type: AMENAccountType) -> AccountSetupProgress {
        let key = defaultsKey(type)
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        return AccountSetupProgress(accountType: type, completedItems: Set(saved))
    }

    func save() {
        let key = AccountSetupProgress.defaultsKey(accountType)
        UserDefaults.standard.set(Array(completedItems), forKey: key)
    }

    mutating func markComplete(_ itemKey: String) {
        completedItems.insert(itemKey)
        save()
    }

    mutating func markIncomplete(_ itemKey: String) {
        completedItems.remove(itemKey)
        save()
    }
}

// MARK: - Setup Checklist Data

private struct SetupItem: Identifiable {
    let id: String
    let label: String
    let description: String
    let icon: String
    let isRequired: Bool
}

private func setupItems(for type: AMENAccountType) -> [SetupItem] {
    switch type {
    case .personal:
        return [
            SetupItem(id: "profile_photo", label: "Add a profile photo", description: "Let your community put a face to your name.", icon: "person.crop.circle.fill", isRequired: true),
            SetupItem(id: "bio", label: "Write your bio", description: "Share a little about who you are in faith.", icon: "text.alignleft", isRequired: true),
            SetupItem(id: "church_affiliation", label: "Add your church", description: "Connect with your local congregation.", icon: "building.columns.fill", isRequired: true),
            SetupItem(id: "faith_journey", label: "Share your faith journey", description: "Tell others what season you're in.", icon: "leaf.fill", isRequired: false),
            SetupItem(id: "prayer_focus", label: "Add a prayer focus", description: "Let others pray alongside you.", icon: "hands.and.sparkles.fill", isRequired: false),
            SetupItem(id: "testimony", label: "Share your testimony", description: "Your story can encourage someone today.", icon: "text.book.closed.fill", isRequired: false)
        ]
    case .church:
        return [
            SetupItem(id: "church_name", label: "Confirm church name", description: "Make sure your congregation can find you.", icon: "building.columns.fill", isRequired: true),
            SetupItem(id: "service_times", label: "Add service times", description: "Help new visitors know when to come.", icon: "clock.fill", isRequired: true),
            SetupItem(id: "location", label: "Add your address", description: "Enable directions and local discovery.", icon: "mappin.circle.fill", isRequired: true),
            SetupItem(id: "profile_photo", label: "Upload a church photo", description: "A welcoming image goes a long way.", icon: "photo.fill", isRequired: false),
            SetupItem(id: "visit_info", label: "Add first-visit info", description: "Help first-timers feel prepared and welcomed.", icon: "person.wave.2.fill", isRequired: false),
            SetupItem(id: "social_links", label: "Connect social accounts", description: "Cross-link your presence across platforms.", icon: "link", isRequired: false)
        ]
    case .business:
        return [
            SetupItem(id: "org_name", label: "Confirm organization name", description: "Your public-facing display name.", icon: "building.2.fill", isRequired: true),
            SetupItem(id: "category", label: "Choose your category", description: "Help people discover the right account.", icon: "square.grid.2x2.fill", isRequired: true),
            SetupItem(id: "mission", label: "Write your mission statement", description: "Tell people what drives your work.", icon: "text.alignleft", isRequired: true),
            SetupItem(id: "logo", label: "Upload your logo", description: "A clear brand identity builds trust.", icon: "photo.fill", isRequired: false),
            SetupItem(id: "website", label: "Add website URL", description: "Drive traffic from your AMEN profile.", icon: "globe", isRequired: false),
            SetupItem(id: "featured_offering", label: "Add a featured offering", description: "Highlight your best resource or service.", icon: "star.fill", isRequired: false)
        ]
    }
}

// MARK: - 2. AccountSetupChecklistView

struct AccountSetupChecklistView: View {
    let accountType: AMENAccountType
    let onDismiss: () -> Void

    @State private var progress: AccountSetupProgress
    @State private var showCompletion = false

    init(accountType: AMENAccountType, onDismiss: @escaping () -> Void) {
        self.accountType = accountType
        self.onDismiss = onDismiss
        _progress = State(initialValue: AccountSetupProgress.load(for: accountType))
    }

    private var subtitle: String {
        switch accountType {
        case .personal: return "A few quick steps to make your profile shine."
        case .church:   return "Help your congregation and visitors find you."
        case .business: return "Set up your organization for discovery and impact."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Let's set up your \(accountType.rawValue) account")
                            .font(AMENFont.bold(22))
                            .foregroundStyle(.black)
                        Text(subtitle)
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.black.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Progress bar
                    SetupProgressBar(fraction: progress.progressFraction)
                        .padding(.horizontal, 20)

                    // Checklist rows
                    VStack(spacing: 10) {
                        ForEach(Array(setupItems(for: accountType).enumerated()), id: \.element.id) { index, item in
                            SetupChecklistRow(
                                itemNumber: index + 1,
                                label: item.label,
                                description: item.description,
                                icon: item.icon,
                                isComplete: progress.completedItems.contains(item.id),
                                isRequired: item.isRequired,
                                onTap: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                        if progress.completedItems.contains(item.id) {
                                            progress.markIncomplete(item.id)
                                        } else {
                                            progress.markComplete(item.id)
                                        }
                                    }
                                    if progress.isComplete {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82).delay(0.15)) {
                                            showCompletion = true
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)

                    // Completion card
                    if showCompletion || progress.isComplete {
                        SetupCompletionCard(accountType: accountType, onContinue: onDismiss)
                            .padding(.horizontal, 16)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.92).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    // Skip button
                    Button(action: onDismiss) {
                        Text("Skip for now")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.black.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 24)
                }
            }
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(22))
                            .foregroundStyle(Color(white: 0.80))
                    }
                }
            }
        }
    }
}

// MARK: Setup Progress Bar (private helper)

private struct SetupProgressBar: View {
    let fraction: Double
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                    )
                    .frame(height: 6)

                // Fill
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.black)
                    .frame(width: appeared ? geo.size.width * fraction : 0, height: 6)
                    .animation(.spring(response: 0.5, dampingFraction: 0.80), value: fraction)
            }
        }
        .frame(height: 6)
        .onAppear { appeared = true }
    }
}

// MARK: - 3. SetupChecklistRow

struct SetupChecklistRow: View {
    let itemNumber: Int
    let label: String
    let description: String
    let icon: String
    let isComplete: Bool
    let isRequired: Bool
    let onTap: () -> Void

    @State private var tapped = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.70)) {
                tapped = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.70)) {
                    tapped = false
                }
            }
            onTap()
        }) {
            HStack(spacing: 14) {
                // Circle indicator
                ZStack {
                    Circle()
                        .fill(isComplete ? .black : Color(white: 0.93))
                        .frame(width: 32, height: 32)

                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.systemScaled(13, weight: .bold))
                            .foregroundStyle(.white)
                            .scaleEffect(isComplete ? 1 : 0.1)
                            .animation(.spring(response: 0.22, dampingFraction: 0.70), value: isComplete)
                    } else {
                        Text("\(itemNumber)")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.black.opacity(0.5))
                    }
                }

                // Center text
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(isComplete ? .black.opacity(0.45) : .black)
                        .strikethrough(isComplete, color: .black.opacity(0.3))

                    Text(description)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.black.opacity(0.4))
                        .lineLimit(1)
                }

                Spacer()

                // Right: pill + chevron
                VStack(alignment: .trailing, spacing: 4) {
                    Text(isRequired ? "Required" : "Suggested")
                        .font(AMENFont.regular(10))
                        .foregroundStyle(isRequired ? .black.opacity(0.7) : .black.opacity(0.4))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(isRequired ? Color(white: 0.90) : Color(white: 0.95))
                        )

                    Image(systemName: isComplete ? "checkmark.circle.fill" : "chevron.right")
                        .font(.systemScaled(12, weight: isComplete ? .medium : .semibold))
                        .foregroundStyle(.black.opacity(isComplete ? 0.4 : 0.3))
                }
            }
            .padding(14)
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
                    .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 3)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(tapped ? 0.97 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.70), value: tapped)
    }
}

// MARK: - 4. SetupCompletionCard

struct SetupCompletionCard: View {
    let accountType: AMENAccountType
    let onContinue: () -> Void

    @State private var appeared = false

    private var completionCopy: String {
        switch accountType {
        case .personal:
            return "Your profile is ready to inspire and connect with others on their faith journey."
        case .church:
            return "Your church is set up and ready to welcome your community on AMEN."
        case .business:
            return "Your organization is ready to reach and serve the faith community."
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 4)
            .overlay(
                VStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.systemScaled(32, weight: .medium))
                        .foregroundStyle(.black.opacity(0.75))
                        .scaleEffect(appeared ? 1 : 0.5)
                        .animation(.spring(response: 0.45, dampingFraction: 0.65), value: appeared)

                    VStack(spacing: 5) {
                        Text("Your account is ready")
                            .font(AMENFont.bold(18))
                            .foregroundStyle(.black)

                        Text(completionCopy)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.black.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 8)
                    }

                    Button(action: onContinue) {
                        Text("Continue to AMEN")
                            .font(AMENFont.semiBold(14))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(.black))
                    }
                    .buttonStyle(.plain)
                }
                .padding(22)
            )
            .frame(minHeight: 200)
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75).delay(0.1)) {
                    appeared = true
                }
            }
    }
}

// MARK: - 5. AccountSetupContinuationCard

struct AccountSetupContinuationCard: View {
    let accountType: AMENAccountType
    let progress: AccountSetupProgress
    let onTap: () -> Void
    let onDismiss: () -> Void

    private var completedCount: Int { progress.completedItems.count }
    private var totalCount: Int {
        let items = setupItems(for: accountType)
        return items.count
    }

    @State private var visible = true

    var body: some View {
        if visible {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 3)
                .overlay(
                    VStack(spacing: 10) {
                        HStack {
                            Text("\(completedCount) of \(totalCount) setup items complete")
                                .font(AMENFont.semiBold(13))
                                .foregroundStyle(.black)
                            Spacer()
                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    visible = false
                                }
                                onDismiss()
                            }) {
                                Image(systemName: "xmark")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.black.opacity(0.35))
                                    .padding(6)
                                    .background(Circle().fill(Color(white: 0.93)))
                            }
                            .buttonStyle(.plain)
                        }

                        // Inline progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color(white: 0.90))
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(.black)
                                    .frame(width: geo.size.width * progress.progressFraction, height: 4)
                            }
                        }
                        .frame(height: 4)

                        Button(action: onTap) {
                            HStack {
                                Text("Continue setup")
                                    .font(AMENFont.semiBold(13))
                                    .foregroundStyle(.black)
                                Image(systemName: "arrow.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.black.opacity(0.6))
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(14)
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96)),
                    removal: .opacity.combined(with: .scale(scale: 0.96))
                ))
        }
    }
}

// MARK: - 6. ComposerPresetChipRow

struct ComposerPresetChipRow: View {
    let accountType: AMENAccountType
    let onSelect: (String) -> Void

    @State private var selectedChip: String? = nil

    private var presets: [String] {
        switch accountType {
        case .personal:
            return ["Reflection", "Testimony", "Prayer Request", "Gratitude", "Scripture", "Question", "Encouragement"]
        case .church:
            return ["Announcement", "Sermon Recap", "Event", "Devotional", "Prayer Update", "Milestone", "Community"]
        case .business:
            return ["Resource Share", "Announcement", "Tip", "Behind the Scenes", "Collaboration", "Testimony", "Event"]
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { preset in
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.70)) {
                            selectedChip = selectedChip == preset ? nil : preset
                        }
                        onSelect(preset)
                    } label: {
                        Text(preset)
                            .font(AMENFont.semiBold(12))
                            .foregroundStyle(selectedChip == preset ? .black : .black.opacity(0.6))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(
                                Group {
                                    if selectedChip == preset {
                                        AnyView(
                                            Capsule()
                                                .fill(Color.white)
                                                .overlay(Capsule().strokeBorder(.black, lineWidth: 1))
                                        )
                                    } else {
                                        AnyView(
                                            Capsule()
                                                .fill(.ultraThinMaterial)
                                                .overlay(Capsule().fill(Color.white.opacity(0.55)))
                                                .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                                                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                                        )
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(selectedChip == preset ? 1.04 : 1.0)
                    .animation(.spring(response: 0.22, dampingFraction: 0.70), value: selectedChip)
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Previews

struct AccountSetupChecklistView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AccountSetupChecklistView(accountType: .personal, onDismiss: {})
                .previewDisplayName("Personal Setup")

            AccountSetupChecklistView(accountType: .church, onDismiss: {})
                .previewDisplayName("Church Setup")

            AccountSetupChecklistView(accountType: .business, onDismiss: {})
                .previewDisplayName("Business Setup")
        }
    }
}

struct SetupChecklistRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 10) {
            SetupChecklistRow(
                itemNumber: 1,
                label: "Add a profile photo",
                description: "Let your community put a face to your name.",
                icon: "person.crop.circle.fill",
                isComplete: false,
                isRequired: true,
                onTap: {}
            )
            SetupChecklistRow(
                itemNumber: 2,
                label: "Write your bio",
                description: "Share a little about who you are in faith.",
                icon: "text.alignleft",
                isComplete: true,
                isRequired: true,
                onTap: {}
            )
            SetupChecklistRow(
                itemNumber: 3,
                label: "Share your testimony",
                description: "Your story can encourage someone today.",
                icon: "text.book.closed.fill",
                isComplete: false,
                isRequired: false,
                onTap: {}
            )
        }
        .padding(16)
        .background(Color.white)
        .previewDisplayName("Checklist Rows")
    }
}

struct SetupCompletionCard_Previews: PreviewProvider {
    static var previews: some View {
        SetupCompletionCard(accountType: .personal, onContinue: {})
            .padding(20)
            .background(Color.white)
            .previewDisplayName("Completion Card")
    }
}

struct AccountSetupContinuationCard_Previews: PreviewProvider {
    static var previews: some View {
        AccountSetupContinuationCard(
            accountType: .personal,
            progress: AccountSetupProgress(
                accountType: .personal,
                completedItems: ["profile_photo", "bio"]
            ),
            onTap: {},
            onDismiss: {}
        )
        .padding(20)
        .background(Color.white)
        .previewDisplayName("Continuation Card")
    }
}

struct ComposerPresetChipRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ComposerPresetChipRow(accountType: .personal, onSelect: { _ in })
            ComposerPresetChipRow(accountType: .church, onSelect: { _ in })
            ComposerPresetChipRow(accountType: .business, onSelect: { _ in })
        }
        .padding(16)
        .background(Color.white)
        .previewDisplayName("Preset Chip Rows")
    }
}
