import SwiftUI

struct AmenCompanionView: View {
    @StateObject private var vm = AmenCompanionViewModel.shared
    @StateObject private var churchService = ChurchCompanionService.shared
    @StateObject private var visitService = VisitPlanningService.shared
    @StateObject private var privacy = CompanionPrivacyManager.shared
    @StateObject private var spatial = SpatialSocialViewModel.shared
    @StateObject private var ai = AskAmenCompanionRouter.shared
    @State private var askQuery = ""
    @FocusState private var askFocused: Bool

    private let suggestedQueries = [
        "Find me a church near me",
        "Help me compare churches",
        "Give me a prayer for this new city",
        "What should I know before visiting a new church?"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Ask Amen — always-visible hero at the top
                    askAmenSection

                    // Contextual prompt card (location-aware nudge)
                    if let prompt = vm.activePrompt {
                        CompanionPromptCard(prompt: prompt) { action in
                            vm.handlePromptAction(action)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Empty state — shown only when nothing has been saved yet
                    if churchService.savedChurches.isEmpty &&
                       visitService.activePlans.isEmpty &&
                       vm.activePrompt == nil &&
                       ai.lastResponse == nil {
                        companionEmptyState
                    }

                    if !churchService.savedChurches.isEmpty {
                        savedChurchesSection
                    }

                    if !visitService.activePlans.isEmpty {
                        visitPlansSection
                    }

                    churchDiscoverySection

                    safeConnectionSection

                    // Nearby — absorbed from SpatialSocialView
                    nearbySection
                }
                .padding()
            }
            .navigationTitle("Amen Companion")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $vm.showChurchDiscovery) {
                ChurchDiscoverySheet()
            }
            .sheet(isPresented: $vm.showVisitPlanning) {
                if let church = vm.selectedChurchForVisit {
                    VisitPlanningSheet(church: church)
                }
            }
            .sheet(isPresented: $vm.showSafeConnection) {
                SafeConnectionSheet()
            }
            .task {
                await vm.initialize()
                await spatial.initialize()
            }
        }
    }

    // MARK: - Ask Amen Inline

    private var askAmenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ask Amen", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.primary)

            if let response = ai.lastResponse {
                VStack(alignment: .leading, spacing: 12) {
                    Text(response.text)
                        .font(.body)

                    if let prayer = response.prayerText {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Prayer", systemImage: "hands.sparkles")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(prayer)
                                .font(.subheadline)
                                .italic()
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }

                    if !response.suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Suggestions", systemImage: "lightbulb")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(response.suggestions, id: \.self) { s in
                                Text("• \(s)").font(.subheadline)
                            }
                        }
                    }

                    if let error = ai.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }

                    Button("Ask another question") {
                        ai.clearResponse()
                        askFocused = true
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            } else if ai.isProcessing {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.85)
                    Text("Amen is thinking...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else {
                // Tappable suggestion chips
                VStack(spacing: 8) {
                    ForEach(suggestedQueries, id: \.self) { q in
                        Button {
                            Task { await ai.ask(q) }
                        } label: {
                            Text(q)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error = ai.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            // Input bar — always visible
            HStack(spacing: 10) {
                TextField("Ask Amen Companion...", text: $askQuery)
                    .focused($askFocused)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .onSubmit { Task { await submitAsk() } }
                Button {
                    Task { await submitAsk() }
                } label: {
                    Image(systemName: ai.isProcessing ? "circle.dotted" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle((askQuery.isEmpty || ai.isProcessing ? Color.primary.opacity(0.3) : Color.blue))
                        .animation(.easeInOut(duration: 0.15), value: ai.isProcessing)
                }
                .disabled(askQuery.isEmpty || ai.isProcessing)
            }
        }
    }

    private func submitAsk() async {
        let q = askQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        askQuery = ""
        await ai.ask(q)
    }

    // MARK: - Empty State

    private var companionEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "building.columns.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.blue.opacity(0.7))
            Text("Find Your Church Home")
                .font(.title3.weight(.semibold))
            Text("Ask Amen above to discover churches near you, plan visits, and connect with your faith community.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Saved Churches

    private var savedChurchesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Saved Churches", systemImage: "bookmark.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(churchService.savedChurches.prefix(3)) { church in
                SavedChurchRow(church: church) {
                    vm.startVisitPlan(for: church)
                }
            }
        }
    }

    // MARK: - Visit Plans

    private var visitPlansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Visit Plans", systemImage: "calendar.badge.checkmark")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(visitService.activePlans.prefix(3)) { plan in
                VisitPlanRow(plan: plan)
            }
        }
    }

    // MARK: - Church Discovery

    private var churchDiscoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Find a Church", systemImage: "building.columns.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            Button {
                vm.showChurchDiscovery = true
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Search churches near me")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Safe Connections

    private var safeConnectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Faith Connections", systemImage: "person.2.circle.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            if privacy.preferences.safeConnectionEnabled {
                Button {
                    vm.showSafeConnection = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.badge.plus")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Someone nearby is open to faith-centered connection.")
                                .font(.subheadline)
                            Text("Mutual consent required · No exact location shared")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task { try? await privacy.setSafeConnection(true) }
                } label: {
                    HStack {
                        Image(systemName: "lock.shield")
                        Text("Enable safe connections")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Nearby (absorbed from SpatialSocialView)

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Nearby", systemImage: "location.circle.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            if spatial.isInitializing {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.8)
                    Text("Looking for nearby activity...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else if spatial.currentEnvironment.type == .unknown &&
                      spatial.nearbyGatherings.isEmpty &&
                      spatial.activeEphemeralSpaces.isEmpty &&
                      spatial.smartIntroductions.isEmpty {
                Button {
                    Task { await spatial.initialize() }
                } label: {
                    HStack {
                        Image(systemName: "location")
                            .foregroundStyle(.secondary)
                        Text("Enable location for nearby gatherings")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            } else {
                if let signal = spatial.topAmbientSignal {
                    AmbientSignalBanner(signal: signal) {
                        spatial.dismissAmbientSignal(signal)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if spatial.currentEnvironment.type != .unknown {
                    EnvironmentContextCard(environment: spatial.currentEnvironment)
                }

                if !spatial.activeEphemeralSpaces.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Live Spaces", systemImage: "dot.radiowaves.left.and.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(spatial.activeEphemeralSpaces) { space in
                            EphemeralSpaceCard(space: space)
                        }
                    }
                }

                if !spatial.nearbyGatherings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Gatherings Nearby", systemImage: "person.3.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(spatial.nearbyGatherings) { gathering in
                            NearbyGatheringCard(gathering: gathering) {
                                Task { await spatial.createEphemeralSpace(for: gathering) }
                            }
                        }
                    }
                }

                if !spatial.smartIntroductions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("People You Might Know", systemImage: "sparkle.magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Based on shared contexts — not location tracking.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(spatial.smartIntroductions.prefix(2)) { intro in
                            SmartIntroductionCard(intro: intro) {
                                spatial.dismissIntroduction(intro)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Companion Prompt Card

struct CompanionPromptCard: View {
    let prompt: CompanionPrompt
    let onAction: (CompanionAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "location.circle.fill")
                    .foregroundStyle(.blue)
                Text(prompt.headline)
                    .font(.headline)
                Spacer()
                if prompt.dismissible {
                    Button {
                        onAction(CompanionAction(label: "Dismiss", destination: .dismiss))
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(prompt.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    onAction(prompt.primaryAction)
                } label: {
                    Text(prompt.primaryAction.label)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if let secondary = prompt.secondaryAction {
                    Button {
                        onAction(secondary)
                    } label: {
                        Text(secondary.label)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Saved Church Row

struct SavedChurchRow: View {
    let church: SmartChurchSummary
    let onPlanVisit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.columns.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 36, height: 36)
                .background(.orange.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(church.name)
                    .font(.subheadline.weight(.semibold))
                Text(church.shortLocation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Plan Visit", action: onPlanVisit)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Visit Plan Row

struct VisitPlanRow: View {
    let plan: ChurchVisitPlan

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 36, height: 36)
                .background(.green.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.churchName)
                    .font(.subheadline.weight(.semibold))
                Text("\(plan.serviceDay) · \(plan.serviceTime)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let visitDate = plan.visitDate {
                Text(visitDate, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Church Discovery Sheet

struct ChurchDiscoverySheet: View {
    @StateObject private var vm = ChurchCompanionService.shared
    @StateObject private var locationService = LocationContextService.shared
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Bible-teaching church with young adults...", text: $query)
                        .onSubmit { Task { await vm.search(query: query, context: locationService.currentContext) } }
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding()

                if vm.isSearching {
                    ProgressView("Searching...").padding()
                } else if vm.nearbyResults.isEmpty {
                    ContentUnavailableView(
                        "Describe what you're looking for",
                        systemImage: "building.columns",
                        description: Text("Try: \"Baptist church with Sunday evening service\"")
                    )
                    .padding()
                } else {
                    List(vm.nearbyResults) { result in
                        ChurchSearchResultRow(result: result)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Find a Church")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct ChurchSearchResultRow: View {
    let result: SmartChurchSearchItem
    @StateObject private var churchService = ChurchCompanionService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.church.name)
                        .font(.headline)
                    Text(result.church.shortLocation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%.1f mi", result.distanceMiles))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(result.matchReason)
                .font(.caption)
                .foregroundStyle(.blue)
                .lineLimit(2)

            HStack(spacing: 8) {
                if !result.church.denomination.isEmpty {
                    ChurchTagPill(text: result.church.denomination)
                }
                if let style = result.church.worshipStyles.first {
                    ChurchTagPill(text: style)
                }
                Spacer()
                Button {
                    Task { try? await churchService.saveChurch(result.church) }
                } label: {
                    Image(systemName: churchService.isSaved(result.church.id) ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(churchService.isSaved(result.church.id) ? .blue : .secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct ChurchTagPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Visit Planning Sheet

struct VisitPlanningSheet: View {
    let church: SmartChurchSummary
    @StateObject private var visitService = VisitPlanningService.shared
    @State private var selectedServiceTime: SmartChurchServiceTime?
    @State private var prayerNote = ""
    @State private var isCreating = false
    @State private var created = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Church") {
                    Label(church.name, systemImage: "building.columns.fill")
                    Label(church.shortLocation, systemImage: "mappin")
                }

                Section("Service Time") {
                    if church.serviceTimes.isEmpty {
                        Text("No service times listed").foregroundStyle(.secondary)
                    } else {
                        ForEach(church.serviceTimes) { time in
                            Button {
                                selectedServiceTime = time
                            } label: {
                                HStack {
                                    Text(time.displayText)
                                    Spacer()
                                    if selectedServiceTime?.id == time.id {
                                        Image(systemName: "checkmark").foregroundStyle(.blue)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                Section("Prayer Before Your Visit") {
                    TextEditor(text: $prayerNote)
                        .frame(minHeight: 80)
                }

                Section {
                    if created {
                        Label("Visit Planned!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            guard let time = selectedServiceTime else { return }
                            isCreating = true
                            Task {
                                _ = try? await visitService.createPlan(church: church, serviceTime: time)
                                created = true
                                isCreating = false
                            }
                        } label: {
                            if isCreating {
                                ProgressView()
                            } else {
                                Label("Plan This Visit", systemImage: "calendar.badge.plus")
                            }
                        }
                        .disabled(selectedServiceTime == nil || isCreating)
                    }
                }
            }
            .navigationTitle("Plan a Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Safe Connection Sheet

struct SafeConnectionSheet: View {
    @StateObject private var service = SafeConnectionService.shared
    @StateObject private var location = LocationContextService.shared
    @State private var selectedIntent: SafeConnectionIntent = .prayer
    @State private var isRequesting = false
    @State private var requestedConnection: SafeConnection?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                    Text("Faith-Centered Connection")
                        .font(.title3.weight(.semibold))
                    Text("Someone nearby is also open to connection.\nBoth of you must consent before any details are shared.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)

                VStack(alignment: .leading, spacing: 12) {
                    Text("What brings you together?")
                        .font(.headline)
                    ForEach(SafeConnectionIntent.allCases, id: \.self) { intent in
                        Button {
                            selectedIntent = intent
                        } label: {
                            HStack {
                                Image(systemName: intent.systemImage)
                                    .frame(width: 24)
                                Text(intent.displayName)
                                Spacer()
                                if selectedIntent == intent {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedIntent == intent ? Color.blue.opacity(0.1) : Color.clear)
                            )
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal)

                if let error = errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                if let connection = requestedConnection {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.badge.checkmark").font(.largeTitle).foregroundStyle(.green)
                        Text("Request sent to your broad area.")
                            .font(.subheadline.weight(.semibold))
                        Text("If someone nearby also opts in, you'll be connected.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text("Area: \(connection.broadArea)")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                } else {
                    Button {
                        isRequesting = true
                        Task {
                            do {
                                let broadArea = location.currentContext.broadAreaLabel
                                requestedConnection = try await service.requestConnection(
                                    intent: selectedIntent,
                                    broadArea: broadArea
                                )
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            isRequesting = false
                        }
                    } label: {
                        Group {
                            if isRequesting {
                                ProgressView()
                            } else {
                                Label("Connect Anonymously", systemImage: "person.badge.plus")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                    .disabled(isRequesting)
                }

                Spacer()
            }
            .navigationTitle("Safe Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
