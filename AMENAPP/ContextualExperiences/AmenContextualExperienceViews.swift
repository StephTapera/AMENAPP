import SwiftUI

// MARK: - Liquid Glass Components

private struct ExperienceGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 22
    var interactive = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(.systemBackground))
                } else if #available(iOS 26.0, *), AMENFeatureFlags.shared.experienceLiquidGlassEnabled {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.clear)
                        .glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: .rect(cornerRadius: cornerRadius))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.thinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.18 : 0.08), lineWidth: contrast == .increased ? 1.1 : 0.7)
            }
            .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
    }
}

private extension View {
    func experienceGlass(cornerRadius: CGFloat = 22, interactive: Bool = false) -> some View {
        modifier(ExperienceGlassSurface(cornerRadius: cornerRadius, interactive: interactive))
    }
}

struct ContextualExperienceBanner: View {
    let resolution: AmenContextualExperienceStackResolution
    var openAction: (() -> Void)? = nil

    var body: some View {
        if let title = resolution.bannerTitle {
            if let openAction = openAction {
                Button(action: openAction) {
                    bannerContent(title: title, showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .experienceGlass(interactive: true)
                .accessibilityLabel(title)
                .accessibilityHint("Opens the active contextual experience")
            } else {
                bannerContent(title: title, showsDisclosure: false)
                    .experienceGlass(interactive: false)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(title)
            }
        }
    }

    private func bannerContent(title: String, showsDisclosure: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: resolution.theme.symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.primary.opacity(0.07)))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle = resolution.bannerSubtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct ExperienceActionPill: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 12)
                .frame(minHeight: 38)
        }
        .buttonStyle(.plain)
        .experienceGlass(cornerRadius: 19, interactive: true)
        .accessibilityLabel(title)
    }
}

struct ExperienceJoinButton: View {
    let isJoined: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isJoined ? "Leave" : "Join", systemImage: isJoined ? "person.crop.circle.badge.minus" : "person.crop.circle.badge.plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Capsule().fill(isJoined ? Color.primary.opacity(0.08) : Color.primary))
                .foregroundStyle(isJoined ? Color.primary : Color(.systemBackground))
        }
        .buttonStyle(.plain)
        .accessibilityHint(isJoined ? "Leaves this experience" : "Joins this experience")
    }
}

struct ExperienceSafetyBadge: View {
    let rules: AmenExperienceSafetyRules

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: rules.youthProtected ? "shield.lefthalf.filled" : "checkmark.shield")
            Text(rules.griefSensitive ? "Gentle mode" : rules.youthProtected ? "Youth protected" : "Standard safety")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

struct ExperienceStackDebugView: View {
    let resolution: AmenContextualExperienceStackResolution

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Resolver Stack", systemImage: "square.stack.3d.up")
                .font(.headline)
            Text("Primary: \(resolution.activeExperienceId ?? "Default Amen UI")")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(resolution.debugRows, id: \.self) { row in
                Text(row)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - Dashboard

struct AmenContextualExperienceDashboardView: View {
    let organizationId: String
    @StateObject private var vm: AmenContextualExperienceDashboardViewModel
    @State private var route: Route?
    @State private var showCreate = false

    enum Route: Identifiable {
        case detail(AmenContextualExperience)
        case preview(AmenContextualExperience)
        case roles(AmenContextualExperience)
        case safety(AmenContextualExperience)
        case notifications(AmenContextualExperience)
        case accessibility(AmenContextualExperience)
        case memories(AmenContextualExperience)
        case analytics(AmenContextualExperience)

        var id: String {
            switch self {
            case .detail(let exp): return "detail-\(exp.id)"
            case .preview(let exp): return "preview-\(exp.id)"
            case .roles(let exp): return "roles-\(exp.id)"
            case .safety(let exp): return "safety-\(exp.id)"
            case .notifications(let exp): return "notifications-\(exp.id)"
            case .accessibility(let exp): return "accessibility-\(exp.id)"
            case .memories(let exp): return "memories-\(exp.id)"
            case .analytics(let exp): return "analytics-\(exp.id)"
            }
        }
    }

    init(organizationId: String) {
        self.organizationId = organizationId
        _vm = StateObject(wrappedValue: AmenContextualExperienceDashboardViewModel(organizationId: organizationId))
    }

    var body: some View {
        NavigationStack {
            Group {
                if !AMENFeatureFlags.shared.contextualExperiencesEnabled {
                    ContentUnavailableView("Contextual Experiences", systemImage: "sparkles.rectangle.stack", description: Text("This system is behind a rollout flag."))
                } else if vm.isLoading && vm.experiences.isEmpty {
                    ExperienceSkeletonList()
                } else if vm.experiences.isEmpty {
                    emptyState
                } else {
                    experienceList
                }
            }
            .navigationTitle("Experiences")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!AMENFeatureFlags.shared.experienceAdminToolsEnabled)
                    .accessibilityLabel("Create experience")
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .sheet(isPresented: $showCreate) {
                AmenExperienceFormView(mode: .create, draft: initialDraft) { draft in
                    await vm.create(draft)
                }
            }
            .sheet(item: $route) { route in
                sheet(for: route)
            }
            .alert("Experience Error", isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })) {
                Button("OK", role: .cancel) { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    private var initialDraft: AmenExperienceDraft {
        var draft = AmenExperienceDraft()
        draft.organizationId = organizationId
        return draft
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 44))
            Text("No Experiences Yet")
                .font(.title3.weight(.semibold))
            Text("Create a seasonal, event, prayer, or tradition layer for this organization.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            ExperienceActionPill(title: "Create", systemImage: "plus") { showCreate = true }
                .disabled(!AMENFeatureFlags.shared.experienceAdminToolsEnabled)
        }
        .padding(24)
    }

    private var experienceList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ContextualExperienceBanner(resolution: vm.resolution) {
                    if let id = vm.resolution.activeExperienceId, let exp = vm.experiences.first(where: { $0.id == id }) {
                        route = .detail(exp)
                    }
                }
                .padding(.horizontal)

                if !vm.resolution.secondaryExperiences.isEmpty {
                    ExperienceModuleRail(title: "More happening now", experiences: vm.resolution.secondaryExperiences) { exp in
                        route = .detail(exp)
                    }
                }

                ExperienceStackDebugView(resolution: vm.resolution)
                    .padding(.horizontal)

                ForEach(vm.experiences) { experience in
                    ExperienceGlassCard(experience: experience) {
                        route = .detail(experience)
                    } preview: {
                        route = .preview(experience)
                    } join: {
                        Task { await vm.join(experience) }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    @ViewBuilder
    private func sheet(for route: Route) -> some View {
        switch route {
        case .detail(let experience):
            AmenExperienceDetailView(experience: experience, vm: vm, route: $route)
        case .preview(let experience):
            AmenExperiencePreviewView(experience: experience)
        case .roles(let experience):
            AmenExperienceRoleManagementView(experience: experience, vm: vm)
        case .safety(let experience):
            AmenExperienceSafetySettingsView(experience: experience)
        case .notifications(let experience):
            AmenExperienceNotificationSettingsView(experience: experience, vm: vm)
        case .accessibility(let experience):
            AmenExperienceAccessibilityPreviewView(experience: experience)
        case .memories(let experience):
            AmenExperienceMemoryHistoryView(experience: experience, vm: vm)
        case .analytics(let experience):
            AmenExperienceAnalyticsView(experience: experience, vm: vm)
        }
    }
}

struct ExperienceGlassCard: View {
    let experience: AmenContextualExperience
    let open: () -> Void
    let preview: () -> Void
    let join: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: experience.experienceType.symbolName)
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(experience.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(experience.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    ExperienceSafetyBadge(rules: experience.safetyRules)
                }

                HStack(spacing: 8) {
                    Text(experience.experienceType.displayName)
                    Text(experience.visibility.displayName)
                    Text(experience.status.rawValue.capitalized)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ExperienceActionPill(title: "Preview", systemImage: "eye", action: preview)
                    ExperienceActionPill(title: "Join", systemImage: "person.badge.plus", action: join)
                    Spacer()
                    ShareLink(item: "amen://experience/\(experience.id)") {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.footnote.weight(.semibold))
                    }
                    .accessibilityLabel("Share")
                }
            }
            .padding(16)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .experienceGlass(interactive: true)
    }
}

struct ExperienceModuleRail: View {
    let title: String
    let experiences: [AmenContextualExperience]
    let open: (AmenContextualExperience) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(experiences) { experience in
                        Button { open(experience) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: experience.experienceType.symbolName)
                                Text(experience.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                Text(experience.organizationType.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 180, alignment: .leading)
                            .padding(14)
                        }
                        .buttonStyle(.plain)
                        .experienceGlass(cornerRadius: 18, interactive: true)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Detail / Preview

struct AmenExperienceDetailView: View {
    let experience: AmenContextualExperience
    @ObservedObject var vm: AmenContextualExperienceDashboardViewModel
    @Binding var route: AmenContextualExperienceDashboardView.Route?
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var showAddModule = false
    @State private var addModuleKind: AmenExperienceModuleKind = .event
    @State private var showSpaces = false
    @State private var showOrganizationProfile = false
    @State private var reportReason = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CelebrationHeroCard(experience: experience)
                    ExperienceJoinButton(isJoined: false) { Task { await vm.join(experience) } }
                }

                Section("Actions") {
                    actionButton("Preview", "eye") { route = .preview(experience) }
                    actionButton("Open in Amen Spaces", "square.grid.2x2") {
                        showSpaces = true
                    }
                    actionButton("Open Organization Profile", "building.2") {
                        showOrganizationProfile = true
                    }
                    actionButton("Save", "bookmark") { Task { await vm.join(experience) } }
                    ShareLink(item: "amen://experience/\(experience.id)") { Label("Share", systemImage: "square.and.arrow.up") }
                    ShareLink(item: "amen://experience/\(experience.id)") { Label("Invite", systemImage: "person.badge.plus") }
                    actionButton("Toggle Notifications", "bell") { route = .notifications(experience) }
                    actionButton("Toggle Accessibility Preview", "accessibility") { route = .accessibility(experience) }
                    actionButton("Report", "exclamationmark.bubble") { Task { await vm.report(experience, reason: reportReason.isEmpty ? "User report" : reportReason) } }
                }

                if experience.canManage || AMENFeatureFlags.shared.experienceAdminToolsEnabled {
                    Section("Admin") {
                        actionButton("Edit", "pencil") { showEdit = true }
                        actionButton("Publish", "paperplane") { Task { await vm.publish(experience) } }
                        actionButton("Unpublish", "tray.and.arrow.down") { Task { await vm.unpublish(experience) } }
                        actionButton("Archive", "archivebox") { Task { await vm.archive(experience) } }
                        actionButton("Delete", "trash") { Task { await vm.delete(experience); dismiss() } }
                        actionButton("Add Event", "calendar.badge.plus") { presentAddModule(.event) }
                        actionButton("Add Prayer Prompt", "hands.sparkles") { presentAddModule(.prayer) }
                        actionButton("Add Discussion", "bubble.left.and.bubble.right") { presentAddModule(.discussion) }
                        actionButton("Add Memory", "memories") { route = .memories(experience) }
                        actionButton("Add Tradition", "clock.arrow.circlepath") { route = .memories(experience) }
                        actionButton("Start Campaign", "play.circle") { Task { await vm.publish(experience) } }
                        actionButton("End Campaign", "stop.circle") { Task { await vm.archive(experience) } }
                        actionButton("Moderate", "shield") { route = .safety(experience) }
                        actionButton("Manage Roles", "person.2.badge.gearshape") { route = .roles(experience) }
                        actionButton("View Analytics", "chart.bar") { route = .analytics(experience) }
                        actionButton("Safety / Moderation", "shield.lefthalf.filled") { route = .safety(experience) }
                    }
                }
            }
            .navigationTitle(experience.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showEdit) {
                AmenExperienceFormView(mode: .edit(experience), draft: AmenExperienceDraft(experience: experience)) { draft in
                    await vm.update(id: experience.id, draft: draft)
                    return experience.id
                }
            }
            .sheet(isPresented: $showAddModule) {
                AmenExperienceAddModuleView(experience: experience, vm: vm, initialKind: addModuleKind)
            }
            .sheet(isPresented: $showSpaces) {
                NavigationStack {
                    SpacesDiscoveryView()
                        .navigationTitle("Amen Spaces")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .sheet(isPresented: $showOrganizationProfile) {
                AmenExperienceOrganizationProfileIntegrationView(experience: experience)
            }
        }
    }

    private func actionButton(_ title: String, _ image: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: image) }
            .accessibilityLabel(title)
    }

    private func presentAddModule(_ kind: AmenExperienceModuleKind) {
        addModuleKind = kind
        showAddModule = true
    }
}

struct AmenExperienceOrganizationProfileIntegrationView: View {
    let experience: AmenContextualExperience
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    OrganizationPulseHeader(experience: experience)
                    ContextualExperienceBanner(resolution: AmenContextualExperienceStackResolution(
                        activeExperienceId: experience.id,
                        sourceLayer: experience.sourceLayer,
                        theme: experience.theme,
                        bannerTitle: experience.title,
                        bannerSubtitle: experience.description,
                        secondaryExperiences: [],
                        debugRows: []
                    )) {}
                }

                if let bannerSurface {
                    Section {
                        AmenSpaceBannerRail(
                            surface: bannerSurface,
                            spaceId: experience.organizationId,
                            title: "Featured \(experience.organizationType.displayName)"
                        )
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }

                Section("Active Experiences") {
                    CelebrationHeroCard(experience: experience)
                }

                Section("Upcoming Events") {
                    EventModeCapsule(experience: experience)
                }

                Section("Prayer Campaigns") {
                    PrayerCampaignCard(experience: experience)
                }

                Section("Traditions & Memories") {
                    TraditionMemoryCard(
                        title: "Living tradition",
                        subtitle: "This organization can keep annual celebrations, testimonies, and memories attached to the experience."
                    )
                }

                Section("Discussions") {
                    Label("Experience-aware conversations open from Amen Spaces.", systemImage: "bubble.left.and.bubble.right")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Organization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var bannerSurface: AmenSpaceBannerSurface? {
        switch experience.organizationType {
        case .church, .ministry, .nonprofit, .prayerGroup, .creatorCommunity, .bibleStudy, .communityGroup:
            return .churchProfile
        case .school, .university, .campusGroup:
            return .schoolProfile
        case .business, .enterprise:
            return .businessProfile
        }
    }
}

struct OrganizationPulseHeader: View {
    let experience: AmenContextualExperience

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: organizationSymbolName)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.primary.opacity(0.07)))

            VStack(alignment: .leading, spacing: 4) {
                Text(experience.organizationType.displayName)
                    .font(.headline)
                Text(experience.organizationId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            ExperienceSafetyBadge(rules: experience.safetyRules)
        }
        .padding(14)
        .experienceGlass(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(experience.organizationType.displayName) organization profile")
    }

    private var organizationSymbolName: String {
        switch experience.organizationType {
        case .church: return "building.columns"
        case .school: return "graduationcap"
        case .university: return "building.2"
        case .ministry: return "hands.sparkles"
        case .business: return "briefcase"
        case .enterprise: return "building"
        case .nonprofit: return "heart"
        case .prayerGroup: return "person.3"
        case .creatorCommunity: return "sparkles"
        case .campusGroup: return "map"
        case .bibleStudy: return "book.closed"
        case .communityGroup: return "person.3.sequence"
        }
    }
}

struct CelebrationHeroCard: View {
    let experience: AmenContextualExperience

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: experience.experienceType.symbolName)
                    .font(.title2)
                Spacer()
                ExperienceSafetyBadge(rules: experience.safetyRules)
            }
            Text(experience.title)
                .font(.title2.bold())
            Text(experience.description)
                .font(.body)
                .foregroundStyle(.secondary)
            EventModeCapsule(experience: experience)
        }
        .padding(18)
        .experienceGlass(cornerRadius: 24)
    }
}

struct EventModeCapsule: View {
    let experience: AmenContextualExperience

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
            Text("\(experience.startAt.formatted(date: .abbreviated, time: .omitted)) - \(experience.endAt.formatted(date: .abbreviated, time: .omitted))")
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }
}

struct AmenExperiencePreviewView: View {
    let experience: AmenContextualExperience

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ContextualExperienceBanner(resolution: AmenContextualExperienceStackResolution(
                        activeExperienceId: experience.id,
                        sourceLayer: experience.sourceLayer,
                        theme: experience.theme,
                        bannerTitle: experience.title,
                        bannerSubtitle: experience.description,
                        secondaryExperiences: [],
                        debugRows: []
                    )) {}
                    CelebrationHeroCard(experience: experience)
                    PrayerCampaignCard(experience: experience)
                    TraditionMemoryCard(title: "Tradition history", subtitle: "Memories and annual moments stay attached to this organization.")
                }
                .padding()
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct PrayerCampaignCard: View {
    let experience: AmenContextualExperience
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hands.sparkles.fill")
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.primary.opacity(0.07)))
            VStack(alignment: .leading, spacing: 3) {
                Text("Prayer campaign")
                    .font(.subheadline.weight(.semibold))
                Text(experience.safetyRules.privatePrayerDefault ? "Private prayer is the default." : "Members can participate together.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .experienceGlass(cornerRadius: 18)
    }
}

struct TraditionMemoryCard: View {
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - Forms and Settings

enum AmenExperienceFormMode {
    case create
    case edit(AmenContextualExperience)

    var title: String {
        switch self {
        case .create: return "Create Experience"
        case .edit: return "Edit Experience"
        }
    }
}

struct AmenExperienceFormView: View {
    let mode: AmenExperienceFormMode
    @State var draft: AmenExperienceDraft
    let save: (AmenExperienceDraft) async -> String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Title", text: $draft.title)
                    TextField("Description", text: $draft.description, axis: .vertical)
                    TextField("Organization ID", text: $draft.organizationId)
                    TextField("Region", text: $draft.region)
                    Picker("Organization Type", selection: $draft.organizationType) { ForEach(AmenContextualOrganizationType.allCases) { Text($0.displayName).tag($0) } }
                    Picker("Experience Type", selection: $draft.experienceType) { ForEach(AmenContextualExperienceType.allCases) { Text($0.displayName).tag($0) } }
                    Picker("Visibility", selection: $draft.visibility) { ForEach(AmenContextualExperienceVisibility.allCases) { Text($0.displayName).tag($0) } }
                }
                Section("Dates") {
                    DatePicker("Start", selection: $draft.startAt)
                    DatePicker("End", selection: $draft.endAt)
                }
                Section("Theme") {
                    TextField("Accent", text: $draft.theme.accentName)
                    TextField("SF Symbol", text: $draft.theme.symbolName)
                    Toggle("Quiet visuals", isOn: $draft.theme.prefersQuietVisuals)
                }
                Section("Safety") {
                    Toggle("Grief-sensitive", isOn: $draft.safetyRules.griefSensitive)
                    Toggle("Youth protected", isOn: $draft.safetyRules.youthProtected)
                    Toggle("Private prayer default", isOn: $draft.safetyRules.privatePrayerDefault)
                    Toggle("Require moderation", isOn: $draft.safetyRules.requireModeration)
                    Toggle("Kill switch", isOn: $draft.safetyRules.killSwitch)
                }
                Section("Notifications") {
                    Toggle("Enabled", isOn: $draft.notificationRules.enabled)
                    Toggle("Quiet hours", isOn: $draft.notificationRules.quietHoursEnabled)
                    Stepper("Max per day: \(draft.notificationRules.maxPerDay)", value: $draft.notificationRules.maxPerDay, in: 0...6)
                    Toggle("Allow urgent", isOn: $draft.notificationRules.allowUrgent)
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            _ = await save(draft)
                            dismiss()
                        }
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.organizationId.isEmpty)
                }
            }
        }
    }
}

struct AmenExperienceAddModuleView: View {
    let experience: AmenContextualExperience
    @ObservedObject var vm: AmenContextualExperienceDashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind: AmenExperienceModuleKind = .event
    @State private var title = ""
    @State private var bodyText = ""

    init(
        experience: AmenContextualExperience,
        vm: AmenContextualExperienceDashboardViewModel,
        initialKind: AmenExperienceModuleKind = .event
    ) {
        self.experience = experience
        self.vm = vm
        _kind = State(initialValue: initialKind)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) { ForEach(AmenExperienceModuleKind.allCases) { Text($0.label).tag($0) } }
                TextField("Title", text: $title)
                TextField("Body", text: $bodyText, axis: .vertical)
            }
            .navigationTitle("Add Module")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await vm.addModule(kind, experience: experience, title: title, body: bodyText)
                            dismiss()
                        }
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

struct AmenExperienceRoleManagementView: View {
    let experience: AmenContextualExperience
    @ObservedObject var vm: AmenContextualExperienceDashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set(["owner", "admin", "pastor", "teacher", "moderator"])
    private let roles = ["owner", "admin", "pastor", "teacher", "moderator", "communicationsLead", "prayerLead"]

    var body: some View {
        NavigationStack {
            List(roles, id: \.self) { role in
                Toggle(role, isOn: Binding(get: { selected.contains(role) }, set: { enabled in
                    if enabled { selected.insert(role) } else { selected.remove(role) }
                }))
            }
            .navigationTitle("Manage Roles")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await vm.manageRoles(experience, roles: Array(selected)); dismiss() } } } }
            .onAppear { selected = Set(experience.rolesAllowedToManage) }
        }
    }
}

struct AmenExperienceSafetySettingsView: View {
    let experience: AmenContextualExperience
    var body: some View {
        List {
            Label(experience.safetyRules.griefSensitive ? "Grief-sensitive mode enabled" : "Standard emotional pacing", systemImage: "heart.text.square")
            Label(experience.safetyRules.youthProtected ? "Youth protection enabled" : "Standard age policy", systemImage: "shield")
            Label(experience.moderationConfiguration.discussionMode.capitalized, systemImage: "bubble.left.and.bubble.right")
            Label(experience.moderationConfiguration.prayerMode.capitalized, systemImage: "hands.sparkles")
        }
        .navigationTitle("Safety")
    }
}

struct AmenExperienceNotificationSettingsView: View {
    let experience: AmenContextualExperience
    @ObservedObject var vm: AmenContextualExperienceDashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool
    @State private var quietMode: Bool

    init(experience: AmenContextualExperience, vm: AmenContextualExperienceDashboardViewModel) {
        self.experience = experience
        self.vm = vm
        _enabled = State(initialValue: experience.notificationRules.enabled)
        _quietMode = State(initialValue: experience.notificationRules.quietHoursEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Notifications", isOn: $enabled)
                Toggle("Quiet delivery", isOn: $quietMode)
            }
            .navigationTitle("Notifications")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await vm.updateNotifications(experience, enabled: enabled, quietMode: quietMode); dismiss() } } } }
        }
    }
}

struct AmenExperienceAccessibilityPreviewView: View {
    let experience: AmenContextualExperience
    @State private var reduceMotion = false
    @State private var reduceTransparency = false
    @State private var highContrast = false

    var body: some View {
        Form {
            Toggle("Reduce Motion", isOn: $reduceMotion)
            Toggle("Reduce Transparency", isOn: $reduceTransparency)
            Toggle("High Contrast", isOn: $highContrast)
            Section("Preview") {
                Text(reduceMotion ? "Motion is reduced." : "Standard subtle motion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(reduceTransparency ? "Solid material fallback is active." : "Liquid Glass material can be used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(highContrast ? "High contrast-safe strokes are emphasized." : "Standard contrast preview.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CelebrationHeroCard(experience: experience)
            }
        }
        .navigationTitle("Accessibility Preview")
    }
}

struct AmenExperienceMemoryHistoryView: View {
    let experience: AmenContextualExperience
    @ObservedObject var vm: AmenContextualExperienceDashboardViewModel
    @State private var title = ""
    @State private var bodyText = ""

    var body: some View {
        Form {
            Section("Add Memory / Tradition") {
                TextField("Title", text: $title)
                TextField("Body", text: $bodyText, axis: .vertical)
                Button("Add Memory") { Task { await vm.addModule(.memory, experience: experience, title: title, body: bodyText) } }
                Button("Add Tradition") { Task { await vm.addModule(.tradition, experience: experience, title: title, body: bodyText) } }
            }
            TraditionMemoryCard(title: "Living tradition", subtitle: "Annual moments and memories are stored server-side under this experience.")
        }
        .navigationTitle("Memories")
    }
}

struct AmenExperienceAnalyticsView: View {
    let experience: AmenContextualExperience
    @ObservedObject var vm: AmenContextualExperienceDashboardViewModel

    var body: some View {
        List {
            ForEach(vm.analytics.keys.sorted(), id: \.self) { key in
                HStack { Text(key); Spacer(); Text(String(describing: vm.analytics[key] ?? "")) }
            }
        }
        .navigationTitle("Analytics")
        .task { await vm.loadAnalytics(for: experience) }
    }
}

struct ExperienceSkeletonList: View {
    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 120)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }
}

#Preview {
    AmenContextualExperienceDashboardView(organizationId: "preview-org")
}
