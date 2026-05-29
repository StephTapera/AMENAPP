import SwiftUI

// MARK: - OrganizationExperienceDashboard

/// Main dashboard showing all experiences for an organization.
/// Admin users see a floating "+ Create" button and an admin toolbar.
struct OrganizationExperienceDashboard: View {

    let organization: Organization
    let userRole: OrgMemberRole

    @StateObject private var viewModel = ContextualExperienceViewModel()
    @State private var showCreateSheet = false
    @State private var showArchivedSection = false
    @State private var experienceToOpen: ContextualExperience?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Computed sections

    private var activeExperiences: [ContextualExperience] {
        viewModel.experiences.filter { $0.isActive }
    }

    private var upcomingExperiences: [ContextualExperience] {
        viewModel.experiences.filter {
            $0.status == .published && !$0.isActive && $0.startDate > Date()
        }
    }

    private var pastExperiences: [ContextualExperience] {
        viewModel.experiences.filter {
            $0.status == .archived
                || $0.status == .deleted
                || ($0.status == .published && $0.endDate < Date())
        }
    }

    private var draftExperiences: [ContextualExperience] {
        viewModel.experiences.filter { $0.status == .draft }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if userRole.isAdmin {
                        adminToolbar
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                    }

                    if viewModel.isLoading {
                        skeletonSection
                    } else if let error = viewModel.error {
                        errorState(message: error)
                    } else {
                        contentSections
                    }
                }
                .padding(.bottom, 100)
            }
            .background(AmenTheme.Colors.backgroundPrimary)
            .navigationTitle(organization.name)
            .navigationBarTitleDisplayMode(.large)

            if userRole.isAdmin {
                createButton
            }
        }
        .task {
            viewModel.startListening(orgId: organization.id ?? "")
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateExperienceView(organization: organization, orgType: organization.type)
        }
        .sheet(item: $experienceToOpen) { exp in
            ExperienceDetailView(
                experience: exp,
                userRole: userRole
            )
        }
    }

    // MARK: - Content sections

    @ViewBuilder
    private var contentSections: some View {
        if activeExperiences.isEmpty && upcomingExperiences.isEmpty && draftExperiences.isEmpty {
            emptyState
                .padding(.top, 60)
        } else {
            if !activeExperiences.isEmpty {
                sectionHeader(title: "Active Now")
                experienceCards(activeExperiences)
            }

            if !upcomingExperiences.isEmpty {
                sectionHeader(title: "Upcoming")
                experienceCards(upcomingExperiences)
            }

            if userRole.isAdmin && !draftExperiences.isEmpty {
                sectionHeader(title: "Drafts")
                experienceCards(draftExperiences)
            }

            if !pastExperiences.isEmpty {
                archivedToggleRow
                if showArchivedSection {
                    experienceCards(pastExperiences)
                }
            }
        }
    }

    // MARK: - Section header

    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(AMENFont.semiBold(13))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Experience cards

    private func experienceCards(_ list: [ContextualExperience]) -> some View {
        VStack(spacing: 12) {
            ForEach(list) { exp in
                ContextualExperienceCard(
                    experience: exp,
                    userRole: userRole,
                    onJoin: {
                        Task { await viewModel.join(experienceId: exp.id ?? "") }
                    },
                    onViewDetail: {
                        HapticManager.impact(style: .light)
                        experienceToOpen = exp
                    }
                )
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Archived toggle

    private var archivedToggleRow: some View {
        Button {
            HapticManager.impact(style: .light)
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.15)
                    : .spring(response: 0.32, dampingFraction: 0.78)
            ) {
                showArchivedSection.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showArchivedSection
                      ? "chevron.down" : "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                Text("Past & Archived (\(pastExperiences.count))")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            showArchivedSection
                ? "Collapse past experiences"
                : "Expand past experiences, \(pastExperiences.count) items"
        )
    }

    // MARK: - Skeleton

    private var skeletonSection: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                ContextualExperienceCardSkeleton()
                    .padding(.horizontal, 16)
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text("No Experiences Yet")
                .font(AMENFont.bold(18))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("Create your first experience to bring your community together.")
                .font(AMENFont.regular(14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if userRole.isAdmin {
                Button {
                    HapticManager.impact(style: .light)
                    showCreateSheet = true
                } label: {
                    Text("Create Experience")
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(AmenTheme.Colors.buttonPrimary)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create Experience")
                .accessibilityHint("Opens the experience creation wizard")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    // MARK: - Error state

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(AmenTheme.Colors.statusError)
            Text("Something went wrong")
                .font(AMENFont.bold(16))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text(message)
                .font(AMENFont.regular(13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                HapticManager.impact(style: .light)
                Task {
                    await viewModel.loadOrgExperiences(orgId: organization.id ?? "")
                }
            } label: {
                Text("Retry")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(AmenTheme.Colors.buttonPrimary)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry loading experiences")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 16)
    }

    // MARK: - Admin toolbar

    private var adminToolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.checkered")
                .imageScale(.small)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text("Admin View")
                .font(AMENFont.semiBold(12))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Spacer()
            Text("\(viewModel.experiences.count) experiences")
                .font(AMENFont.regular(11))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AmenTheme.Colors.surfaceChip)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Admin view, \(viewModel.experiences.count) experiences")
    }

    // MARK: - Floating create button

    private var createButton: some View {
        Button {
            HapticManager.impact(style: .light)
            showCreateSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .imageScale(.medium)
                Text("Create")
                    .font(AMENFont.semiBold(15))
            }
            .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(AmenTheme.Colors.buttonPrimary)
                }
            )
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 24)
        .accessibilityLabel("Create new experience")
        .accessibilityHint("Opens the multi-step experience creation wizard")
    }
}
