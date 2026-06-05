import SwiftUI
import FirebaseFunctions

// MARK: - Integration Types

enum IntegrationCategory: String, CaseIterable, Identifiable {
    case calendar = "Calendar"
    case communication = "Communication"
    case churchManagement = "Church Management"
    case crm = "CRM"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .calendar: return "calendar"
        case .communication: return "video.fill"
        case .churchManagement: return "cross.fill"
        case .crm: return "person.crop.circle.badge.checkmark"
        }
    }
}

struct ExternalIntegration: Identifiable {
    let id: String
    let name: String
    let category: IntegrationCategory
    let icon: String
    let description: String
    let isConnected: Bool
    let capabilities: [IntegrationCapability]
    let crossPostRequiresGate: Bool

    static let all: [ExternalIntegration] = [
        ExternalIntegration(
            id: "apple-calendar",
            name: "Apple Calendar",
            category: .calendar,
            icon: "calendar.badge.checkmark",
            description: "Sync church events and meeting times to Apple Calendar.",
            isConnected: false,
            capabilities: [.syncEvents, .readAvailability],
            crossPostRequiresGate: true
        ),
        ExternalIntegration(
            id: "google-calendar",
            name: "Google Calendar",
            category: .calendar,
            icon: "calendar",
            description: "Two-way sync with Google Calendar for scheduling.",
            isConnected: false,
            capabilities: [.syncEvents, .readAvailability, .createMeetLinks],
            crossPostRequiresGate: true
        ),
        ExternalIntegration(
            id: "outlook",
            name: "Outlook Calendar",
            category: .calendar,
            icon: "envelope.badge.shield.half.filled",
            description: "Sync events with Microsoft Outlook or Exchange.",
            isConnected: false,
            capabilities: [.syncEvents, .readAvailability],
            crossPostRequiresGate: true
        ),
        ExternalIntegration(
            id: "zoom",
            name: "Zoom",
            category: .communication,
            icon: "video.circle.fill",
            description: "Auto-generate Zoom links for virtual services and meetings.",
            isConnected: false,
            capabilities: [.createMeetLinks, .syncEvents],
            crossPostRequiresGate: true
        ),
        ExternalIntegration(
            id: "teams",
            name: "Microsoft Teams",
            category: .communication,
            icon: "video.fill",
            description: "Connect Teams meetings to church space events.",
            isConnected: false,
            capabilities: [.createMeetLinks],
            crossPostRequiresGate: true
        ),
        ExternalIntegration(
            id: "planning-center",
            name: "Planning Center",
            category: .churchManagement,
            icon: "list.clipboard.fill",
            description: "Sync volunteer schedules and service plans from Planning Center.",
            isConnected: false,
            capabilities: [.syncVolunteers, .syncEvents, .memberDirectory],
            crossPostRequiresGate: true
        ),
        ExternalIntegration(
            id: "pushpay",
            name: "Pushpay",
            category: .churchManagement,
            icon: "dollarsign.circle.fill",
            description: "Link giving campaigns and donation drives.",
            isConnected: false,
            capabilities: [.donationLink],
            crossPostRequiresGate: true
        ),
        ExternalIntegration(
            id: "realm",
            name: "Realm / ACS",
            category: .churchManagement,
            icon: "building.2.fill",
            description: "Pull member directory and group rosters from Realm.",
            isConnected: false,
            capabilities: [.memberDirectory, .syncVolunteers],
            crossPostRequiresGate: true
        ),
        ExternalIntegration(
            id: "salesforce",
            name: "Salesforce NPSP",
            category: .crm,
            icon: "cloud.fill",
            description: "Push ministry contacts and follow-up tasks to Salesforce Nonprofit.",
            isConnected: false,
            capabilities: [.contactSync, .taskExport],
            crossPostRequiresGate: true
        ),
        ExternalIntegration(
            id: "hubspot",
            name: "HubSpot",
            category: .crm,
            icon: "megaphone.fill",
            description: "Manage visitor follow-ups and outreach pipelines.",
            isConnected: false,
            capabilities: [.contactSync, .emailCampaign],
            crossPostRequiresGate: true
        )
    ]
}

enum IntegrationCapability: String, CaseIterable {
    case syncEvents = "Event Sync"
    case readAvailability = "Availability"
    case createMeetLinks = "Meeting Links"
    case syncVolunteers = "Volunteer Sync"
    case memberDirectory = "Member Directory"
    case donationLink = "Donation Link"
    case contactSync = "Contact Sync"
    case taskExport = "Task Export"
    case emailCampaign = "Email Campaigns"

    var icon: String {
        switch self {
        case .syncEvents: return "calendar.badge.plus"
        case .readAvailability: return "clock"
        case .createMeetLinks: return "link"
        case .syncVolunteers: return "person.2.badge.gearshape"
        case .memberDirectory: return "person.crop.square.fill.and.at.rectangle"
        case .donationLink: return "dollarsign.circle"
        case .contactSync: return "person.crop.circle.badge.plus"
        case .taskExport: return "checklist"
        case .emailCampaign: return "envelope.open"
        }
    }
}

// MARK: - Cross-Post Request

struct CrossPostRequest: Identifiable {
    let id: String
    let integration: ExternalIntegration
    let contentPreview: String
    let contentCard: ContentCard
    let destination: String
    var status: CrossPostStatus = .pending

    enum CrossPostStatus {
        case pending, approved, denied
    }
}

// MARK: - Main View

struct ExternalIntegrationView: View {
    @State private var integrations: [ExternalIntegration] = ExternalIntegration.all
    @State private var selectedCategory: IntegrationCategory? = nil
    @State private var pendingCrossPost: CrossPostRequest? = nil
    @State private var showApprovalSheet = false
    @State private var showConnectSheet: ExternalIntegration? = nil
    @State private var searchText = ""
    @Environment(\.colorScheme) private var colorScheme

    private var filteredIntegrations: [ExternalIntegration] {
        var list = integrations
        if let cat = selectedCategory {
            list = list.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchHeader
                categoryPicker
                Divider()
                integrationList
            }
            .background(Color(.systemBackground))
            .navigationTitle("Integrations")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $showConnectSheet) { integration in
                IntegrationConnectSheet(integration: integration) { connected in
                    // In production: persist connection state
                    showConnectSheet = nil
                }
            }
            .sheet(isPresented: $showApprovalSheet) {
                if let req = pendingCrossPost {
                    ApprovalSheetView(
                        card: req.contentCard,
                        proposedAction: .shareExternal,
                        requestorIsCreator: false,
                        requestorIsSpaceAdmin: false,
                        requestorIsChurchAdmin: false,
                        requestorIsTrustedMember: false,
                        targetSurface: .feed,
                        onApproved: { _, _ in
                            handleCrossPostDecision(request: req, approved: true)
                            showApprovalSheet = false
                            pendingCrossPost = nil
                        },
                        onDenied: { _ in
                            handleCrossPostDecision(request: req, approved: false)
                            showApprovalSheet = false
                            pendingCrossPost = nil
                        },
                        onDismiss: {
                            showApprovalSheet = false
                            pendingCrossPost = nil
                        }
                    )
                }
            }
        }
    }

    // MARK: - Search

    private var searchHeader: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search integrations", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding()
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryTab(nil, label: "All", icon: "square.grid.2x2")
                ForEach(IntegrationCategory.allCases) { cat in
                    categoryTab(cat, label: cat.rawValue, icon: cat.icon)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    private func categoryTab(_ cat: IntegrationCategory?, label: String, icon: String) -> some View {
        let isSelected = selectedCategory == cat
        return Button {
            withAnimation(.spring(response: 0.3)) { selectedCategory = cat }
        } label: {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.amenGold.opacity(0.15) : Color(.secondarySystemFill))
                .foregroundStyle(isSelected ? Color.amenGold : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    private var integrationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                crossPostGateNotice
                ForEach(IntegrationCategory.allCases) { category in
                    let items = filteredIntegrations.filter { $0.category == category }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { integration in
                                IntegrationRow(integration: integration) {
                                    showConnectSheet = integration
                                }
                                Divider().padding(.leading, 72)
                            }
                        } header: {
                            sectionHeader(category)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ category: IntegrationCategory) -> some View {
        HStack {
            Label(category.rawValue, systemImage: category.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    // MARK: - Cross-Post Gate Notice

    private var crossPostGateNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .foregroundStyle(Color.amenGold)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text("All cross-posting is approval-gated")
                    .font(.subheadline.weight(.semibold))
                Text("Any content sent to external platforms must pass through the AMEN Content Permission Engine. Nothing is auto-posted. Prayer requests and private content cannot be exported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.amenGold.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.amenGold.opacity(0.2), lineWidth: 1)
        )
        .padding()
    }

    // MARK: - Actions

    private func handleCrossPostDecision(request: CrossPostRequest, approved: Bool) {
        ContentAuditLogger.log(
            contentId: request.contentCard.id,
            contentType: request.contentCard.sourceType.rawValue,
            actorId: "current-user",
            action: approved ? "approved" : "denied",
            destination: request.integration.name,
            isExternal: true,
            wasAnonymous: false,
            approvalOutcome: approved ? "approved" : "denied"
        )
    }

    // MARK: - Cross-Post Trigger (callable from other screens)

    func requestCrossPost(card: ContentCard, to integration: ExternalIntegration, destination: String) {
        guard integration.crossPostRequiresGate else { return }
        let outcome = ContentPermissionEngine.evaluate(
            action: .shareExternal,
            card: card,
            requestorIsCreator: false,
            requestorIsSpaceAdmin: false,
            requestorIsChurchAdmin: false,
            requestorIsTrustedMember: false,
            targetSurface: .feed
        )
        guard outcome.canProceed || outcome.requiresApproval else { return }
        pendingCrossPost = CrossPostRequest(
            id: UUID().uuidString,
            integration: integration,
            contentPreview: String(card.body.prefix(120)),
            contentCard: card,
            destination: destination
        )
        showApprovalSheet = true
    }
}

// MARK: - Integration Row

private struct IntegrationRow: View {
    let integration: ExternalIntegration
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 48, height: 48)
                Image(systemName: integration.icon)
                    .font(.title3)
                    .foregroundStyle(Color.amenGold)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(integration.name)
                    .font(.subheadline.weight(.medium))
                Text(integration.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    ForEach(integration.capabilities.prefix(3), id: \.rawValue) { cap in
                        Text(cap.rawValue)
                            .font(.system(size: 9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            Button(action: onConnect) {
                Text(integration.isConnected ? "Manage" : "Connect")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(integration.isConnected ? Color(.secondarySystemFill) : Color.amenGold)
                    .foregroundStyle(integration.isConnected ? Color(.label) : Color.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

// MARK: - Connect Sheet

private struct IntegrationConnectSheet: View {
    let integration: ExternalIntegration
    let onComplete: (Bool) -> Void
    @State private var step: ConnectStep = .overview
    @State private var agreedToTerms = false
    @Environment(\.colorScheme) private var colorScheme

    enum ConnectStep { case overview, permissions, confirm }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch step {
                case .overview:
                    overviewStep
                case .permissions:
                    permissionsStep
                case .confirm:
                    confirmStep
                }
            }
            .navigationTitle("Connect \(integration.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onComplete(false) }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var overviewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: integration.icon)
                        .font(.system(size: 44))
                        .foregroundStyle(Color.amenGold)
                    VStack(alignment: .leading) {
                        Text(integration.name)
                            .font(.title2.weight(.semibold))
                        Text(integration.category.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(integration.description)
                    .font(.body)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Capabilities")
                        .font(.headline)
                    ForEach(integration.capabilities, id: \.rawValue) { cap in
                        Label(cap.rawValue, systemImage: cap.icon)
                            .font(.subheadline)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Privacy Guarantee", systemImage: "shield.fill")
                        .font(.headline)
                        .foregroundStyle(Color.amenGold)
                    Text("Prayer requests, private posts, and personal messages will never be sent to \(integration.name). All cross-posting requires your explicit approval through the AMEN Content Permission Engine.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.amenGold.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    withAnimation { step = .permissions }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.amenGold)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
    }

    private var permissionsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("What AMEN will access")
                    .font(.headline)

                ForEach(integration.capabilities, id: \.rawValue) { cap in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: cap.icon)
                            .foregroundStyle(Color.amenGold)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cap.rawValue)
                                .font(.subheadline.weight(.medium))
                            Text(permissionDescription(cap))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    Divider()
                }

                Toggle(isOn: $agreedToTerms) {
                    Text("I understand that all data sharing from AMEN to \(integration.name) requires my approval. AMEN will never auto-post.")
                        .font(.caption)
                }
                .tint(Color.amenGold)

                Button {
                    guard agreedToTerms else { return }
                    withAnimation { step = .confirm }
                } label: {
                    Text("Connect \(integration.name)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(agreedToTerms ? Color.amenGold : Color(.systemFill))
                        .foregroundStyle(agreedToTerms ? .white : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!agreedToTerms)
            }
            .padding()
        }
    }

    private var confirmStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            VStack(spacing: 8) {
                Text("\(integration.name) Connected")
                    .font(.title2.weight(.semibold))
                Text("In a production build, this would launch OAuth/SSO for \(integration.name). The integration is now configured. Remember: all outbound data requires approval.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                onComplete(true)
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.amenGold)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Spacer()
        }
        .padding()
    }

    private func permissionDescription(_ cap: IntegrationCapability) -> String {
        switch cap {
        case .syncEvents: return "Read and write church events to your external calendar."
        case .readAvailability: return "Check scheduling conflicts when planning events."
        case .createMeetLinks: return "Generate virtual meeting links for services."
        case .syncVolunteers: return "Import volunteer schedules from church management system."
        case .memberDirectory: return "Read group rosters (no private contact info exported)."
        case .donationLink: return "Link giving campaigns to space events."
        case .contactSync: return "Push approved ministry contacts for follow-up tracking."
        case .taskExport: return "Send approved pastoral follow-up tasks."
        case .emailCampaign: return "Create outreach campaigns (requires approval per send)."
        }
    }
}

// MARK: - Preview

#Preview {
    ExternalIntegrationView()
}
