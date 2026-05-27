import SwiftUI

struct AmenCompanionView: View {
    @StateObject private var vm = AmenCompanionViewModel.shared
    @StateObject private var churchService = ChurchCompanionService.shared
    @StateObject private var visitService = VisitPlanningService.shared
    @StateObject private var privacy = CompanionPrivacyManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let prompt = vm.activePrompt {
                        CompanionPromptCard(prompt: prompt) { action in
                            vm.handlePromptAction(action)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if !churchService.savedChurches.isEmpty {
                        savedChurchesSection
                    }

                    if !visitService.activePlans.isEmpty {
                        visitPlansSection
                    }

                    churchDiscoverySection

                    safeConnectionSection
                }
                .padding()
            }
            .navigationTitle("Amen Companion")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm.showAskAmen = true
                    } label: {
                        Image(systemName: "sparkles")
                    }
                }
            }
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
            .sheet(isPresented: $vm.showAskAmen) {
                CompanionAskSheet()
            }
            .task { await vm.initialize() }
        }
    }

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

// MARK: - Stub Sheets (full implementations below)

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
                    ContentUnavailableView("Describe what you're looking for", systemImage: "building.columns", description: Text("Try: \"Baptist church with Sunday evening service\""))
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

struct VisitPlanningSheet: View {
    let church: SmartChurchSummary
    @StateObject private var visitService = VisitPlanningService.shared
    @State private var selectedServiceTime: SmartChurchSummaryServiceTime?
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
                            .background(selectedIntent == intent ? .blue.opacity(0.1) : .ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
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
                                requestedConnection = try await service.requestConnection(intent: selectedIntent, broadArea: broadArea)
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

struct CompanionAskSheet: View {
    @StateObject private var ai = AskAmenCompanionRouter.shared
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private let suggestedQueries = [
        "Find me a church near me",
        "Help me compare churches",
        "Give me a prayer for this new city",
        "What should I know before visiting a new church?"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let response = ai.lastResponse {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(response.text)
                                .font(.body)
                                .padding()

                            if let prayer = response.prayerText {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Prayer", systemImage: "hands.sparkles")
                                        .font(.headline)
                                    Text(prayer)
                                        .font(.body)
                                        .italic()
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                            }

                            if !response.suggestions.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Suggestions", systemImage: "lightbulb")
                                        .font(.headline)
                                    ForEach(response.suggestions, id: \.self) { s in
                                        Text("• \(s)").font(.subheadline)
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Try asking...")
                                .font(.headline)
                                .padding(.horizontal)
                            ForEach(suggestedQueries, id: \.self) { q in
                                Button { query = q } label: {
                                    Text(q)
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal)
                            }
                        }
                        .padding(.top)
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    TextField("Ask Amen Companion...", text: $query)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    Button {
                        let q = query
                        query = ""
                        Task { await ai.ask(q) }
                    } label: {
                        Image(systemName: ai.isProcessing ? "circle.dotted" : "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .disabled(query.isEmpty || ai.isProcessing)
                }
                .padding()
            }
            .navigationTitle("Ask Amen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
