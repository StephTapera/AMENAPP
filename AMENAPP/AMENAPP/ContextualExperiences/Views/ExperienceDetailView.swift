import SwiftUI

// MARK: - ExperienceDetailView

/// Full detail screen for a single ContextualExperience.
struct ExperienceDetailView: View {

    let experience: ContextualExperience
    let userRole: OrgMemberRole

    @StateObject private var viewModel = ContextualExperienceViewModel()
    @State private var selectedModule: ExperienceModuleType?
    @State private var showAnalytics = false
    @State private var showSafetyConsole = false
    @State private var prayerPrompts: [ExperiencePrayerPrompt] = []
    @State private var discussions: [ExperienceDiscussion] = []
    @State private var events: [ExperienceEvent] = []
    @State private var memories: [ExperienceMemory] = []
    @State private var traditions: [ExperienceTradition] = []
    @State private var isLoadingModule = false
    @State private var joinConfirmation = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let service = ContextualExperienceService.shared

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        heroBanner
                        joinLeaveBar
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        if !experience.enabledModules.isEmpty {
                            ContextualExperienceModuleRail(
                                modules: experience.enabledModules,
                                selectedModule: $selectedModule
                            )
                            .padding(.top, 14)

                            moduleContent
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                        }

                        metaChips
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, userRole.isAdmin ? 100 : 32)
                    }
                }
                .background(AmenTheme.Colors.backgroundPrimary)

                if userRole.isAdmin {
                    ExperienceAdminToolbar(
                        experience: viewModel.selectedExperience ?? experience,
                        onPublish: {
                            Task { await viewModel.publish(experienceId: experience.id ?? "") }
                        },
                        onUnpublish: {
                            Task { await viewModel.unpublish(experienceId: experience.id ?? "") }
                        },
                        onArchive: {
                            Task { await viewModel.archive(experienceId: experience.id ?? "") }
                        },
                        onEdit: {
                            // Edit sheet handled by parent
                        },
                        onViewAnalytics: {
                            HapticManager.impact(style: .light)
                            showAnalytics = true
                        }
                    )
                }
            }
            .navigationTitle(experience.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        HapticManager.impact(style: .light)
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                    .accessibilityLabel("Close")
                }
                if userRole.canModerate {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            HapticManager.impact(style: .light)
                            showSafetyConsole = true
                        } label: {
                            Image(systemName: "shield.checkered")
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                        }
                        .accessibilityLabel("Safety Console")
                        .accessibilityHint("Opens the moderation console")
                    }
                }
            }
        }
        .task {
            await viewModel.loadExperience(id: experience.id ?? "")
            if let first = experience.enabledModules.first {
                selectedModule = first
            }
        }
        .onChange(of: selectedModule) { _, mod in
            guard let mod else { return }
            Task { await loadModuleContent(mod) }
        }
        .sheet(isPresented: $showAnalytics) {
            ExperienceAnalyticsView(
                experience: experience,
                userRole: userRole
            )
        }
        .sheet(isPresented: $showSafetyConsole) {
            ExperienceSafetyConsole(
                experience: experience,
                userRole: userRole
            )
        }
    }

    // MARK: - Hero banner

    private var heroBanner: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: experience.theme.accentColorHex).opacity(0.22),
                            AmenTheme.Colors.backgroundPrimary
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 140)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: experience.type.icon)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                    Text(experience.type.displayName)
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                Text(experience.title)
                    .font(AMENFont.bold(22))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(2)
                Text(experience.description)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Join/Leave bar

    @ViewBuilder
    private var joinLeaveBar: some View {
        HStack(spacing: 10) {
            if experience.isKillSwitched {
                pausedBadge
            } else if viewModel.hasJoined {
                leaveButton
            } else {
                joinButton
            }
            Spacer()
            participantBadge
            if experience.daysRemaining > 0 && experience.isActive {
                daysRemainingBadge
            }
        }
    }

    private var joinButton: some View {
        Button {
            HapticManager.impact(style: .light)
            Task { await viewModel.join(experienceId: experience.id ?? "") }
        } label: {
            Text("Join Experience")
                .font(AMENFont.semiBold(15))
                .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(
                    Capsule().fill(AmenTheme.Colors.buttonPrimary)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Join \(experience.title)")
        .accessibilityHint("Joins this experience")
    }

    private var leaveButton: some View {
        Button {
            HapticManager.impact(style: .light)
            Task { await viewModel.leave(experienceId: experience.id ?? "") }
        } label: {
            Text("Leave")
                .font(AMENFont.semiBold(15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(
                    Capsule().fill(AmenTheme.Colors.surfaceChip)
                        .overlay(
                            Capsule()
                                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Leave \(experience.title)")
        .accessibilityHint("Leaves this experience")
    }

    private var pausedBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(AmenTheme.Colors.statusWarning)
            Text("Paused")
                .font(AMENFont.semiBold(14))
                .foregroundStyle(AmenTheme.Colors.statusWarning)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule().fill(AmenTheme.Colors.statusWarning.opacity(0.12))
        )
        .accessibilityLabel("Experience is paused")
    }

    private var participantBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.2.fill")
                .imageScale(.small)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text("\(experience.participantCount)")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .accessibilityLabel("\(experience.participantCount) participants")
    }

    private var daysRemainingBadge: some View {
        Text("\(experience.daysRemaining)d left")
            .font(AMENFont.regular(12))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(AmenTheme.Colors.surfaceChip)
            )
            .accessibilityLabel("\(experience.daysRemaining) days remaining")
    }

    // MARK: - Module content

    @ViewBuilder
    private var moduleContent: some View {
        if isLoadingModule {
            moduleLoadingSkeleton
        } else {
            switch selectedModule {
            case .prayer:
                prayerSection
            case .discussion:
                discussionSection
            case .event:
                eventSection
            case .memory:
                memorySection
            case .tradition:
                traditionSection
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Prayer

    private var prayerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if prayerPrompts.isEmpty {
                emptyModuleState(
                    icon: "hands.and.sparkles.fill",
                    message: "No prayer prompts yet."
                )
            } else {
                ForEach(prayerPrompts) { prompt in
                    prayerPromptCard(prompt)
                }
            }
        }
    }

    private func prayerPromptCard(_ prompt: ExperiencePrayerPrompt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt.prompt)
                .font(AMENFont.regular(15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            if let scripture = prompt.scriptureReference {
                Text(scripture)
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            Button {
                HapticManager.impact(style: .light)
            } label: {
                Text("Pray")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(AmenTheme.Colors.buttonPrimary)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pray for this prompt")
        }
        .padding(14)
        .background(glassCardBackground)
        .overlay(glassCardStroke)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(prompt.prompt)
    }

    // MARK: - Discussion

    private var discussionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if discussions.isEmpty {
                emptyModuleState(
                    icon: "bubble.left.and.bubble.right.fill",
                    message: "No discussions yet."
                )
            } else {
                ForEach(discussions) { discussion in
                    discussionCard(discussion)
                }
            }
        }
    }

    private func discussionCard(_ discussion: ExperienceDiscussion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(discussion.title)
                .font(AMENFont.semiBold(15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text(discussion.body)
                .font(AMENFont.regular(13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(3)
            HStack {
                Image(systemName: "bubble.right")
                    .imageScale(.small)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                Text("\(discussion.replyCount) replies")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                Spacer()
                Text(discussion.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(AMENFont.regular(11))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
        }
        .padding(14)
        .background(glassCardBackground)
        .overlay(glassCardStroke)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(discussion.title). \(discussion.replyCount) replies.")
    }

    // MARK: - Events

    private var eventSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if events.isEmpty {
                emptyModuleState(icon: "calendar.badge.plus", message: "No events scheduled.")
            } else {
                ForEach(events) { event in
                    eventCard(event)
                }
            }
        }
    }

    private func eventCard(_ event: ExperienceEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.title)
                .font(AMENFont.semiBold(15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .imageScale(.small)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                Text(event.startDate.formatted(date: .abbreviated, time: .omitted))
                    .font(AMENFont.regular(12))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                if let location = event.location {
                    Image(systemName: "mappin")
                        .imageScale(.small)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                    Text(location)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
            }
            Text(event.description)
                .font(AMENFont.regular(13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(2)
        }
        .padding(14)
        .background(glassCardBackground)
        .overlay(glassCardStroke)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(event.startDate.formatted(date: .abbreviated, time: .omitted))")
    }

    // MARK: - Memories

    private var memorySection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if memories.isEmpty {
                emptyModuleState(icon: "photo.fill", message: "No memories shared yet.")
                    .gridCellColumns(2)
            } else {
                ForEach(memories) { memory in
                    memoryCell(memory)
                }
            }
        }
    }

    private func memoryCell(_ memory: ExperienceMemory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let imageURL = memory.imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: 100)
                            .clipped()
                    default:
                        Rectangle()
                            .fill(AmenTheme.Colors.shimmerBase)
                            .frame(height: 100)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceChip)
                    .frame(height: 100)
                    .overlay(
                        Image(systemName: "book.closed.fill")
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    )
            }
            Text(memory.title)
                .font(AMENFont.semiBold(13))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(1)
            Text(memory.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(AMENFont.regular(11))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .padding(10)
        .background(glassCardBackground)
        .overlay(glassCardStroke)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .accessibilityLabel("\(memory.title), \(memory.createdAt.formatted(date: .abbreviated, time: .omitted))")
    }

    // MARK: - Traditions

    private var traditionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if traditions.isEmpty {
                emptyModuleState(icon: "star.fill", message: "No traditions documented yet.")
            } else {
                ForEach(traditions) { tradition in
                    traditionCard(tradition)
                }
            }
        }
    }

    private func traditionCard(_ tradition: ExperienceTradition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tradition.title)
                .font(AMENFont.semiBold(15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text(tradition.description)
                .font(AMENFont.regular(13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(3)
            HStack {
                Image(systemName: "arrow.clockwise")
                    .imageScale(.small)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                Text(tradition.recurrencePattern.capitalized)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
        }
        .padding(14)
        .background(glassCardBackground)
        .overlay(glassCardStroke)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tradition.title)
    }

    // MARK: - Meta chips

    private var metaChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 8) {
                metaChip(
                    icon: "calendar",
                    text: "\(experience.startDate.formatted(date: .abbreviated, time: .omitted)) – \(experience.endDate.formatted(date: .abbreviated, time: .omitted))"
                )
                metaChip(
                    icon: "eye",
                    text: experience.visibility.displayName
                )
            }
            .flexibleGrid()
        }
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .imageScale(.small)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text(text)
                .font(AMENFont.regular(12))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(AmenTheme.Colors.surfaceChip)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(icon): \(text)")
    }

    // MARK: - Module loading skeleton

    private var moduleLoadingSkeleton: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: 80)
            }
        }
    }

    // MARK: - Empty module state

    private func emptyModuleState(icon: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text(message)
                .font(AMENFont.regular(14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityLabel(message)
    }

    // MARK: - Glass card backgrounds (reused in cards)

    private var glassCardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.3))
        }
    }

    private var glassCardStroke: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
    }

    // MARK: - Load module content

    private func loadModuleContent(_ module: ExperienceModuleType) async {
        guard let expId = experience.id else { return }
        isLoadingModule = true
        do {
            switch module {
            case .prayer:
                prayerPrompts = try await service.fetchPrayerPrompts(experienceId: expId)
            case .discussion:
                discussions = try await service.fetchDiscussions(experienceId: expId)
            case .event:
                events = try await service.fetchEvents(experienceId: expId)
            case .memory:
                memories = try await service.fetchMemories(experienceId: expId)
            case .tradition:
                traditions = try await service.fetchTraditions(experienceId: expId)
            default:
                break
            }
        } catch {
            // non-critical — module content silently fails, empty state shown
        }
        isLoadingModule = false
    }
}

// MARK: - View layout helper

private extension View {
    func flexibleGrid() -> some View {
        self
    }
}
