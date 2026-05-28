import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Missing type stubs (ChurchDiscovery Phase 2/3 types not yet migrated to Swift)

enum ChurchLiveStateKind: String {
    case live, upcoming, closed, quiet, unknown
}

struct ChurchLiveState {
    let state: ChurchLiveStateKind
    let title: String?
    let description: String?
    let startsAt: Date?
    let endsAt: Date?
    let livestreamURL: String?
    let attendanceSignal: Int?
    let atmosphereTags: [String]
    let updatedAt: Date?
}

struct ChurchExperienceSummary {
    let parking: String?
    let bestArrivalTime: String?
    let entrance: String?
    let serviceLength: String?
    let worshipStyle: String?
    let kidsMinistry: String?
    let accessibility: String?
    let translation: String?
    let quietSpace: String?
    let firstTimeFlow: String?
    let confidence: Double?
    let updatedAt: Date?
}

struct ChurchMediaAsset: Identifiable {
    let id: String
    let imageURL: String
    let type: String
    let source: String?
    let approved: Bool
    let createdAt: Date?
}

struct ChurchDetailPayload {
    let entity: ChurchEntity?
    let heroImageURL: String?
    let logoURL: String?
    let about: String?
    let typeLabel: String?
    let city: String?
    let state: String?
    let verified: Bool
    let livestreamURL: String?
    let denomination: String?
    let accessibilityTags: [String]
    let media: [ChurchMediaAsset]
    let liveState: ChurchLiveState?
    let experienceSummary: ChurchExperienceSummary?
}

// MARK: -

@MainActor
final class ChurchDetailViewModel: ObservableObject {
    @Published private(set) var payload: ChurchDetailPayload?
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?

    let church: Church

    private let dataService = ChurchDataService.shared
    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    private var hasStarted = false

    init(church: Church) {
        self.church = church
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        attachListeners()

        Task {
            await loadInitialPayload()
        }
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        hasStarted = false
    }

    fileprivate func clearError() {
        errorMessage = nil
    }

    var heroImageURL: URL? {
        URL(string: payload?.heroImageURL ?? "")
    }

    var logoURL: URL? {
        URL(string: payload?.logoURL ?? "")
    }

    var displayName: String {
        payload?.entity?.name ?? church.name
    }

    var typeLine: String {
        let type = payload?.typeLabel ?? "Church"
        let location = cityStateText
        return location.isEmpty ? type : "\(type) • \(location)"
    }

    var cityStateText: String {
        let city = payload?.city ?? payload?.entity?.city ?? ""
        let state = payload?.state ?? payload?.entity?.state ?? ""
        return [city, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var denominationText: String? {
        payload?.denomination ?? payload?.entity?.denomination ?? church.denomination
    }

    var aboutText: String {
        let candidates = [
            payload?.about,
            payload?.entity?.address.isEmpty == false ? "Located at \(payload?.entity?.address ?? church.address)." : nil
        ]
        return candidates.compactMap { $0 }.first ?? "This church has not added an about summary yet."
    }

    var websiteURL: URL? {
        let raw = payload?.entity?.website ?? church.website
        guard let raw, !raw.isEmpty else { return nil }
        let normalized = raw.hasPrefix("http://") || raw.hasPrefix("https://") ? raw : "https://\(raw)"
        return URL(string: normalized)
    }

    var phoneNumber: String {
        let raw = payload?.entity?.phoneNumber ?? church.phone
        return raw.isEmpty ? "No phone listed" : raw
    }

    var addressText: String {
        payload?.entity?.address ?? church.address
    }

    var serviceTimes: [ChurchEntity.ServiceTime] {
        payload?.entity?.serviceTimes ?? []
    }

    var serviceTimesText: String {
        guard !serviceTimes.isEmpty else { return church.serviceTime }
        return serviceTimes
            .sorted { $0.dayOfWeek == $1.dayOfWeek ? $0.time < $1.time : $0.dayOfWeek < $1.dayOfWeek }
            .map { "\(weekdayName(for: $0.dayOfWeek)) \($0.time)" }
            .joined(separator: "\n")
    }

    var mediaPreview: [ChurchMediaAsset] {
        Array((payload?.media ?? []).prefix(4))
    }

    fileprivate var quickFacts: [ChurchQuickFact] {
        var facts: [ChurchQuickFact] = []

        if let liveState = payload?.liveState {
            facts.append(
                ChurchQuickFact(
                    title: "Service Status",
                    value: liveState.title ?? liveState.state.displayText,
                    systemImage: liveState.state.symbolName
                )
            )
        }

        facts.append(
            ChurchQuickFact(
                title: "Distance",
                value: church.distance,
                systemImage: "location.fill"
            )
        )

        if let next = nextServiceText {
            facts.append(
                ChurchQuickFact(
                    title: "Next Service",
                    value: next,
                    systemImage: "calendar"
                )
            )
        }

        if let summary = payload?.experienceSummary?.serviceLength, !summary.isEmpty {
            facts.append(
                ChurchQuickFact(
                    title: "Typical Length",
                    value: summary,
                    systemImage: "clock"
                )
            )
        }

        return facts
    }

    var liveStateSummary: String? {
        payload?.liveState?.description
    }

    var nextServiceText: String? {
        if let start = payload?.liveState?.startsAt {
            return start.formatted(date: .abbreviated, time: .shortened)
        }
        guard let first = serviceTimes.first else { return nil }
        return "\(weekdayName(for: first.dayOfWeek)) \(first.time)"
    }

    fileprivate var primarySmartAction: ChurchSmartAction {
        if let liveState = payload?.liveState {
            switch liveState.state {
            case .live:
                return ChurchSmartAction(
                    title: payload?.livestreamURL == nil ? "Live Now" : "Join Live",
                    subtitle: liveState.title ?? "Worship is happening now",
                    systemImage: "dot.radiowaves.left.and.right",
                    tint: Color(red: 0.96, green: 0.68, blue: 0.32)
                )
            case .upcoming:
                return ChurchSmartAction(
                    title: "Plan Visit",
                    subtitle: liveState.title ?? "Service starts soon",
                    systemImage: "calendar.badge.plus",
                    tint: .blue
                )
            case .closed, .quiet, .unknown:
                break
            }
        }

        if church.distanceValue <= 5 {
            return ChurchSmartAction(
                title: "Check In",
                subtitle: "You are nearby",
                systemImage: "location.circle",
                tint: .blue
            )
        }

        return ChurchSmartAction(
            title: "Ask Berean",
            subtitle: "Get first-visit context",
            systemImage: "sparkles",
            tint: Color(red: 0.18, green: 0.18, blue: 0.18)
        )
    }

    fileprivate var secondarySmartActions: [ChurchSmartAction] {
        [
            ChurchSmartAction(
                title: "Plan Visit",
                subtitle: nextServiceText ?? "Prepare your first visit",
                systemImage: "figure.walk.arrival",
                tint: .blue
            ),
            ChurchSmartAction(
                title: "Ask Berean",
                subtitle: "Summaries and questions",
                systemImage: "sparkles",
                tint: Color(red: 0.18, green: 0.18, blue: 0.18)
            )
        ]
    }

    fileprivate var goodToKnowItems: [ChurchGoodToKnowItem] {
        var items: [ChurchGoodToKnowItem] = []

        if let kids = payload?.experienceSummary?.kidsMinistry, !kids.isEmpty {
            items.append(.init(title: "Kids Ministry", value: kids, systemImage: "figure.and.child.holdinghands"))
        }

        if let parking = payload?.experienceSummary?.parking, !parking.isEmpty {
            items.append(.init(title: "Parking", value: parking, systemImage: "car.fill"))
        }

        if let accessibility = payload?.experienceSummary?.accessibility, !accessibility.isEmpty {
            items.append(.init(title: "Accessibility", value: accessibility, systemImage: "figure.roll"))
        } else if let firstAccess = payload?.accessibilityTags.first {
            items.append(.init(title: "Accessibility", value: firstAccess, systemImage: "figure.roll"))
        }

        if let translation = payload?.experienceSummary?.translation, !translation.isEmpty {
            items.append(.init(title: "Translation", value: translation, systemImage: "captions.bubble"))
        }

        if let quietSpace = payload?.experienceSummary?.quietSpace, !quietSpace.isEmpty {
            items.append(.init(title: "Quiet Space", value: quietSpace, systemImage: "moon.stars"))
        }

        if payload?.livestreamURL != nil {
            items.append(.init(title: "Livestream", value: "Available when services are live", systemImage: "play.tv"))
        }

        return items
    }

    private func loadInitialPayload() async {
        // Seed an initial payload from the locally-known Church object so the
        // UI can render immediately; real-time listeners will update it shortly.
        payload = ChurchDetailPayload(
            entity: nil,
            heroImageURL: nil,
            logoURL: nil,
            about: nil,
            typeLabel: "Church",
            city: nil,
            state: nil,
            verified: false,
            livestreamURL: nil,
            denomination: church.denomination,
            accessibilityTags: [],
            media: [],
            liveState: nil,
            experienceSummary: nil
        )
        isLoading = false
    }

    private func attachListeners() {
        let churchRef = db.collection("churches").document(church.canonicalChurchId)

        listeners.append(
            churchRef.addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let data = snapshot?.data() else { return }
                Task { @MainActor in
                    self.mergeDocument(data)
                }
            }
        )

        listeners.append(
            churchRef.collection("media")
                .whereField("approved", isEqualTo: true)
                .limit(to: 8)
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let self, let documents = snapshot?.documents else { return }
                    Task { @MainActor in
                        self.mergeMedia(documents)
                    }
                }
        )

        listeners.append(
            churchRef.collection("live_state")
                .document("current")
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let self else { return }
                    Task { @MainActor in
                        self.mergeLiveState(snapshot?.data())
                    }
                }
        )

        listeners.append(
            churchRef.collection("experience_summary")
                .document("current")
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let self else { return }
                    Task { @MainActor in
                        self.mergeExperienceSummary(snapshot?.data())
                    }
                }
        )
    }

    private func mergeDocument(_ data: [String: Any]) {
        let current = payload
        let entity = (try? Firestore.Decoder().decode(ChurchEntity.self, from: data)) ?? current?.entity
        payload = ChurchDetailPayload(
            entity: entity,
            heroImageURL: firstString(data, keys: ["heroImageUrl", "heroImageURL", "photoURL"]) ?? current?.heroImageURL,
            logoURL: firstString(data, keys: ["logoUrl", "logoURL"]) ?? entity?.logoURL ?? current?.logoURL,
            about: firstString(data, keys: ["about", "description", "bio"]) ?? current?.about,
            typeLabel: firstString(data, keys: ["type", "category"]) ?? current?.typeLabel ?? "Church",
            city: entity?.city ?? firstString(data, keys: ["city"]) ?? current?.city,
            state: entity?.state ?? firstString(data, keys: ["state"]) ?? current?.state,
            verified: (data["verified"] as? Bool) ?? current?.verified ?? false,
            livestreamURL: firstString(data, keys: ["livestreamUrl", "livestreamURL"]) ?? current?.livestreamURL,
            denomination: entity?.denomination ?? firstString(data, keys: ["denomination"]) ?? current?.denomination,
            accessibilityTags: stringList(data["accessibility"]).isEmpty ? (current?.accessibilityTags ?? []) : stringList(data["accessibility"]),
            media: current?.media ?? [],
            liveState: current?.liveState,
            experienceSummary: current?.experienceSummary
        )
    }

    private func mergeMedia(_ documents: [QueryDocumentSnapshot]) {
        let media = documents.compactMap { document -> ChurchMediaAsset? in
            let data = document.data()
            guard let imageURL = firstString(data, keys: ["imageUrl", "imageURL", "url"]) else { return nil }
            return ChurchMediaAsset(
                id: document.documentID,
                imageURL: imageURL,
                type: firstString(data, keys: ["type"])?.lowercased() ?? "community",
                source: firstString(data, keys: ["source"]),
                approved: (data["approved"] as? Bool) ?? true,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
            )
        }

        guard let current = payload else { return }
        payload = ChurchDetailPayload(
            entity: current.entity,
            heroImageURL: current.heroImageURL ?? media.first(where: { $0.type == "hero" })?.imageURL ?? media.first?.imageURL,
            logoURL: current.logoURL,
            about: current.about,
            typeLabel: current.typeLabel,
            city: current.city,
            state: current.state,
            verified: current.verified,
            livestreamURL: current.livestreamURL,
            denomination: current.denomination,
            accessibilityTags: current.accessibilityTags,
            media: media,
            liveState: current.liveState,
            experienceSummary: current.experienceSummary
        )
    }

    private func mergeLiveState(_ data: [String: Any]?) {
        guard let current = payload else { return }
        let liveState = data.flatMap { value -> ChurchLiveState? in
            let state = ChurchLiveStateKind(rawValue: firstString(value, keys: ["state"])?.lowercased() ?? "") ?? .unknown
            return ChurchLiveState(
                state: state,
                title: firstString(value, keys: ["title"]),
                description: firstString(value, keys: ["description"]),
                startsAt: (value["startsAt"] as? Timestamp)?.dateValue(),
                endsAt: (value["endsAt"] as? Timestamp)?.dateValue(),
                livestreamURL: firstString(value, keys: ["livestreamUrl", "livestreamURL"]),
                attendanceSignal: value["attendanceSignal"] as? Int,
                atmosphereTags: stringList(value["atmosphereTags"]),
                updatedAt: (value["updatedAt"] as? Timestamp)?.dateValue()
            )
        }

        payload = ChurchDetailPayload(
            entity: current.entity,
            heroImageURL: current.heroImageURL,
            logoURL: current.logoURL,
            about: current.about,
            typeLabel: current.typeLabel,
            city: current.city,
            state: current.state,
            verified: current.verified,
            livestreamURL: current.livestreamURL ?? liveState?.livestreamURL,
            denomination: current.denomination,
            accessibilityTags: current.accessibilityTags,
            media: current.media,
            liveState: liveState,
            experienceSummary: current.experienceSummary
        )
    }

    private func mergeExperienceSummary(_ data: [String: Any]?) {
        guard let current = payload else { return }
        let summary = data.map {
            ChurchExperienceSummary(
                parking: firstString($0, keys: ["parking"]),
                bestArrivalTime: firstString($0, keys: ["bestArrivalTime"]),
                entrance: firstString($0, keys: ["entrance"]),
                serviceLength: firstString($0, keys: ["serviceLength"]),
                worshipStyle: firstString($0, keys: ["worshipStyle"]),
                kidsMinistry: firstString($0, keys: ["kidsMinistry"]),
                accessibility: firstString($0, keys: ["accessibility"]),
                translation: firstString($0, keys: ["translation"]),
                quietSpace: firstString($0, keys: ["quietSpace"]),
                firstTimeFlow: firstString($0, keys: ["firstTimeFlow"]),
                confidence: $0["confidence"] as? Double,
                updatedAt: ($0["updatedAt"] as? Timestamp)?.dateValue()
            )
        }

        payload = ChurchDetailPayload(
            entity: current.entity,
            heroImageURL: current.heroImageURL,
            logoURL: current.logoURL,
            about: current.about,
            typeLabel: current.typeLabel,
            city: current.city,
            state: current.state,
            verified: current.verified,
            livestreamURL: current.livestreamURL,
            denomination: current.denomination,
            accessibilityTags: current.accessibilityTags,
            media: current.media,
            liveState: current.liveState,
            experienceSummary: summary
        )
    }

    private func firstString(_ data: [String: Any], keys: [String]) -> String? {
        for key in keys {
            let value = String(describing: data[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, value != "nil" {
                return value
            }
        }
        return nil
    }

    private func stringList(_ raw: Any?) -> [String] {
        guard let values = raw as? [Any] else { return [] }
        return values.compactMap {
            let value = String(describing: $0).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }

    private func weekdayName(for day: Int) -> String {
        switch day {
        case 1: return "Sunday"
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        case 7: return "Saturday"
        default: return "Sunday"
        }
    }
}

private struct ChurchQuickFact: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let systemImage: String
}

private struct ChurchSmartAction: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
}

private struct ChurchGoodToKnowItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let systemImage: String
}

private extension ChurchLiveStateKind {
    var displayText: String {
        switch self {
        case .live: return "Live worship in progress"
        case .upcoming: return "Service starts soon"
        case .closed: return "Closed now"
        case .quiet: return "Quiet right now"
        case .unknown: return "Live state unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .live: return "dot.radiowaves.left.and.right"
        case .upcoming: return "calendar.badge.clock"
        case .closed: return "moon.stars.fill"
        case .quiet: return "wind"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct ChurchDetailView: View {
    let church: Church
    let isSaved: Bool
    let isVisited: Bool
    let visitInsights: ChurchVisitInsights?
    var onSave: () -> Void
    var onGetDirections: () -> Void
    var onCall: () -> Void
    var onShare: () -> Void
    var onCheckIn: () -> Void
    var onAddToSchedule: () -> Void
    var onStartChurchNotes: () -> Void
    var onPlanFirstVisit: () -> Void

    @StateObject private var viewModel: ChurchDetailViewModel
    @StateObject private var enhancementStore = ChurchEnhancementStore.shared
    @StateObject private var rankingService = ChurchRankingService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var headerScrollOffset: CGFloat = 0
    @State private var showBereanSheet = false

    init(
        church: Church,
        isSaved: Bool,
        isVisited: Bool,
        visitInsights: ChurchVisitInsights?,
        onSave: @escaping () -> Void,
        onGetDirections: @escaping () -> Void,
        onCall: @escaping () -> Void,
        onShare: @escaping () -> Void,
        onCheckIn: @escaping () -> Void,
        onAddToSchedule: @escaping () -> Void,
        onStartChurchNotes: @escaping () -> Void,
        onPlanFirstVisit: @escaping () -> Void
    ) {
        self.church = church
        self.isSaved = isSaved
        self.isVisited = isVisited
        self.visitInsights = visitInsights
        self.onSave = onSave
        self.onGetDirections = onGetDirections
        self.onCall = onCall
        self.onShare = onShare
        self.onCheckIn = onCheckIn
        self.onAddToSchedule = onAddToSchedule
        self.onStartChurchNotes = onStartChurchNotes
        self.onPlanFirstVisit = onPlanFirstVisit
        _viewModel = StateObject(wrappedValue: ChurchDetailViewModel(church: church))
    }

    private var headerCompressionProgress: CGFloat {
        AdaptiveHeaderMetrics.progress(offset: headerScrollOffset, collapseDistance: 180)
    }

    private var intelligence: ChurchRankingSnapshot? {
        rankingService.snapshot(for: church)
    }

    private var firstVisitGuide: FirstVisitGuideData? {
        enhancementStore.data(for: church.canonicalChurchId)?.firstVisitGuide
    }

    private var shouldShowVisitMemory: Bool {
        guard let visitInsights else { return false }
        return visitInsights.lastVisitedChurchId == church.canonicalChurchId ||
            visitInsights.favoriteChurchIds.contains(church.canonicalChurchId)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
                    AdaptiveHeaderScrollTracker(coordinateSpace: "churchDetailScroll")

                    if viewModel.isLoading && viewModel.payload == nil {
                        ChurchDetailSkeletonView()
                            .padding(.bottom, 120)
                    } else {
                        VStack(alignment: .leading, spacing: 22) {
                            heroSection
                            contentSections
                        }
                        .padding(.bottom, 120)
                    }
                }
                .background(Color(white: 0.97).ignoresSafeArea())
                .coordinateSpace(name: "churchDetailScroll")
                .onPreferenceChange(AdaptiveHeaderScrollOffsetKey.self) { headerScrollOffset = $0 }

                ChurchFloatingActionBar(
                    isSaved: isSaved,
                    onSuggestEdit: onShare,
                    onAdd: onPlanFirstVisit,
                    onSave: onSave,
                    onMore: onStartChurchNotes
                )
                .padding(.bottom, 12)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showBereanSheet) {
                BereanChurchContextSheet(church: church, payload: viewModel.payload)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(30)
            }
            .onAppear {
                viewModel.start()
                enhancementStore.observe(churchId: church.canonicalChurchId)
                rankingService.observe(church: church)
            }
            .onDisappear {
                viewModel.stop()
                enhancementStore.stopObserving(churchId: church.canonicalChurchId)
            }
        }
    }

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            ChurchHeroGlassHeader(
                imageURL: viewModel.heroImageURL,
                title: viewModel.displayName,
                liveState: viewModel.payload?.liveState,
                compressionProgress: headerCompressionProgress,
                onClose: { dismiss() },
                onShare: onShare
            )

            VStack(spacing: 16) {
                Spacer()

                ChurchIdentityGlassCard(
                    logoURL: viewModel.logoURL,
                    churchName: viewModel.displayName,
                    subtitle: viewModel.typeLine,
                    isVerified: viewModel.payload?.verified ?? false,
                    denomination: viewModel.denominationText,
                    isVisited: isVisited,
                    compressionProgress: headerCompressionProgress
                )
                .padding(.horizontal, 20)
                .offset(y: 74)

                if headerCompressionProgress > 0.55 {
                    Text(viewModel.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.82))
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .adaptiveLiquidGlassHeaderSurface(progress: headerCompressionProgress, cornerRadius: 999)
                        .transition(.opacity)
                }
            }
        }
        .frame(height: 390)
        .padding(.bottom, 76)
    }

    @ViewBuilder
    private var contentSections: some View {
        VStack(alignment: .leading, spacing: 18) {
            ChurchPrimaryActionsRow(
                etaText: church.distance,
                hasWebsite: viewModel.websiteURL != nil,
                onDirections: onGetDirections,
                onCall: onCall,
                onWebsite: {
                    if let websiteURL = viewModel.websiteURL {
                        openURL(websiteURL)
                    }
                }
            )

            ChurchSmartActionPanel(
                primaryAction: viewModel.primarySmartAction,
                secondaryActions: viewModel.secondarySmartActions,
                onTap: handleSmartAction
            )

            if let liveState = viewModel.payload?.liveState {
                ChurchLiveStateCard(liveState: liveState, nextServiceText: viewModel.nextServiceText)
            }

            if let intelligence {
                ChurchFitScoreCard(snapshot: intelligence)
            }

            if !viewModel.quickFacts.isEmpty {
                ChurchQuickFactsRow(facts: viewModel.quickFacts)
            }

            if let firstVisitGuide, !firstVisitGuide.isStale {
                FirstVisitCompanionCard(
                    churchName: viewModel.displayName,
                    parkingInfo: firstVisitGuide.parking,
                    entranceInfo: firstVisitGuide.arrivalTip,
                    kidsCheckIn: false,
                    expectedDurationMinutes: nil,
                    serviceStyle: firstVisitGuide.whatToWear,
                    accessibilityFeatures: []
                )
            }

            if let summary = viewModel.payload?.experienceSummary {
                ChurchExperienceSummarySection(summary: summary)
            }

            ChurchPhotoPreviewGrid(media: viewModel.mediaPreview)

            ChurchSectionCard(title: "About") {
                Text(viewModel.aboutText)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ChurchGoodToKnowSection(items: viewModel.goodToKnowItems)

            if let socialProof = intelligence?.socialProof, !socialProof.isEmpty {
                ChurchSocialProofCard(lines: socialProof)
            }

            if let sermon = intelligence?.sermon {
                ChurchSermonIntelligenceCard(sermon: sermon)
            }

            if shouldShowVisitMemory, let visitInsights {
                VisitMemoryCard(
                    insights: visitInsights,
                    lastReflectionSnippet: visitInsights.topReflectionThemes.first,
                    isSaved: isSaved
                )
            }

            ChurchSectionCard(title: "Details") {
                VStack(alignment: .leading, spacing: 16) {
                    ChurchDetailRow(title: "Phone", value: viewModel.phoneNumber)
                    ChurchDetailRow(title: "Website", value: viewModel.websiteURL?.absoluteString ?? "Not listed")
                    ChurchDetailRow(title: "Address", value: viewModel.addressText)
                    ChurchDetailRow(title: "Service Times", value: viewModel.serviceTimesText)

                    if let denomination = viewModel.denominationText, !denomination.isEmpty {
                        ChurchDetailRow(title: "Denomination", value: denomination)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .alert("Church detail unavailable", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func handleSmartAction(_ action: ChurchSmartAction) {
        switch action.title {
        case "Join Live":
            if let livestreamURL = viewModel.payload?.livestreamURL, let url = URL(string: livestreamURL) {
                openURL(url)
            } else {
                showBereanSheet = true
            }
        case "Check In":
            onCheckIn()
        case "Plan Visit":
            onPlanFirstVisit()
        default:
            showBereanSheet = true
        }
    }
}

private struct ChurchHeroGlassHeader: View {
    let imageURL: URL?
    let title: String
    let liveState: ChurchLiveState?
    let compressionProgress: CGFloat
    let onClose: () -> Void
    let onShare: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named("churchDetailScroll")).minY
            let stretch = max(minY, 0)
            let collapse = min(max(-minY / 220, 0), 1)

            ZStack(alignment: .top) {
                Group {
                    if let imageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                LinearGradient(
                                    colors: [Color.white, Color(white: 0.9)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                        }
                    } else {
                        LinearGradient(
                            colors: [Color.white, Color(white: 0.9)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height + stretch)
                .clipped()
                .offset(y: stretch > 0 ? -stretch : minY * 0.22)
                .scaleEffect(reduceMotion ? 1 : 1 + (stretch / 900))

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.32 + (collapse * 0.18)),
                        Color.clear,
                        Color.white.opacity(0.52 + (collapse * 0.22))
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack {
                    ChurchHeroIconButton(systemImage: "square.and.arrow.up", action: onShare)
                    Spacer()
                    ChurchHeroIconButton(systemImage: "xmark", action: onClose)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)

                if let liveState, liveState.state == .live {
                    VStack {
                        Spacer()
                        HStack {
                            Label(liveState.title ?? "Live now", systemImage: "dot.radiowaves.left.and.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.8))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .adaptiveLiquidGlassHeaderSurface(progress: compressionProgress, cornerRadius: 999)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 118)
                    }
                }
            }
        }
    }
}

private struct ChurchHeroIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.8))
                .frame(width: 44, height: 44)
                .adaptiveLiquidGlassHeaderSurface(progress: 0.55, cornerRadius: 22)
        }
        .buttonStyle(ChurchTactileButtonStyle())
    }
}

private struct ChurchIdentityGlassCard: View {
    let logoURL: URL?
    let churchName: String
    let subtitle: String
    let isVerified: Bool
    let denomination: String?
    let isVisited: Bool
    let compressionProgress: CGFloat

    var body: some View {
        VStack(spacing: 14) {
            Group {
                if let logoURL {
                    AsyncImage(url: logoURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            fallbackAvatar
                        }
                    }
                } else {
                    fallbackAvatar
                }
            }
            .frame(width: 76, height: 76)
            .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.82), lineWidth: 1)
            )

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(churchName)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.92))
                        .multilineTextAlignment(.center)

                    if isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                }

                Text(subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.52))
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    if let denomination, !denomination.isEmpty {
                        Text(denomination)
                    }
                    if isVisited {
                        Text("Visited")
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.55))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .adaptiveLiquidGlassHeaderSurface(progress: max(compressionProgress, 0.35), cornerRadius: 32)
    }

    private var fallbackAvatar: some View {
        ZStack {
            Color(white: 0.9)
            Image(systemName: "building.columns.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.68))
        }
    }
}

private struct ChurchPrimaryActionsRow: View {
    let etaText: String
    let hasWebsite: Bool
    let onDirections: () -> Void
    let onCall: () -> Void
    let onWebsite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ChurchPrimaryActionButton(
                title: etaText,
                subtitle: "Directions",
                systemImage: "car.fill",
                isPrimary: true,
                action: onDirections
            )

            ChurchPrimaryActionButton(
                title: "Call",
                subtitle: nil,
                systemImage: "phone.fill",
                isPrimary: false,
                action: onCall
            )

            ChurchPrimaryActionButton(
                title: "Website",
                subtitle: nil,
                systemImage: "safari.fill",
                isPrimary: false,
                action: onWebsite
            )
            .disabled(!hasWebsite)
            .opacity(hasWebsite ? 1 : 0.45)
        }
    }
}

private struct ChurchPrimaryActionButton: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundStyle(isPrimary ? Color.white : Color.blue)
            .frame(maxWidth: .infinity, minHeight: 74)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isPrimary ? Color.blue : Color.white.opacity(0.76))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(isPrimary ? 0.18 : 0.82), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(isPrimary ? 0.12 : 0.05), radius: 14, y: 5)
            }
        }
        .buttonStyle(ChurchTactileButtonStyle())
        .frame(minHeight: 44)
    }
}

private struct ChurchSmartActionPanel: View {
    let primaryAction: ChurchSmartAction
    let secondaryActions: [ChurchSmartAction]
    let onTap: (ChurchSmartAction) -> Void

    var body: some View {
        ChurchSectionCard(title: "Right Now") {
            VStack(spacing: 12) {
                Button {
                    onTap(primaryAction)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: primaryAction.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(primaryAction.tint)
                            .frame(width: 36, height: 36)
                            .background(primaryAction.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(primaryAction.title)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.86))
                            Text(primaryAction.subtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.55))
                        }

                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.45))
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(ChurchTactileButtonStyle())

                HStack(spacing: 10) {
                    ForEach(secondaryActions) { action in
                        Button {
                            onTap(action)
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: action.systemImage)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(action.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Color.black.opacity(0.78))
                            .frame(maxWidth: .infinity, minHeight: 66)
                            .background(Color.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(ChurchTactileButtonStyle())
                    }
                }
            }
        }
    }
}

private struct ChurchLiveStateCard: View {
    let liveState: ChurchLiveState
    let nextServiceText: String?

    var body: some View {
        ChurchSectionCard(title: "Service Status") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: liveState.state.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(liveState.state == .live ? Color(red: 0.83, green: 0.24, blue: 0.2) : .blue)
                    Text(liveState.title ?? liveState.state.displayText)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.86))
                }

                if let description = liveState.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.62))
                }

                if let nextServiceText {
                    Text("Next service: \(nextServiceText)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }
        }
    }
}

private struct ChurchFitScoreCard: View {
    let snapshot: ChurchRankingSnapshot

    var body: some View {
        ChurchSectionCard(title: "Your Fit") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(snapshot.score)% aligned")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.88))
                    Text("Preference alignment")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.5))
                }

                Text("May fit your preferences based on saved churches, interests, and service context. This is not a rating of spiritual quality.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.58))

                ForEach(snapshot.fitBreakdown.prefix(3)) { item in
                    HStack {
                        Text(item.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.58))
                        Spacer()
                        Text(item.verdict)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.84))
                    }
                }
            }
        }
    }
}

private struct ChurchQuickFactsRow: View {
    let facts: [ChurchQuickFact]

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(facts) { fact in
                VStack(spacing: 6) {
                    Text(fact.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.5))
                    Label(fact.value, systemImage: fact.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.82))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 6)
    }
}

private struct ChurchExperienceSummarySection: View {
    let summary: ChurchExperienceSummary

    var body: some View {
        ChurchSectionCard(title: "What You'll Experience") {
            VStack(alignment: .leading, spacing: 12) {
                summaryRow("Best arrival time", summary.bestArrivalTime, systemImage: "clock.badge.checkmark")
                summaryRow("Parking", summary.parking, systemImage: "car.fill")
                summaryRow("Entrance", summary.entrance, systemImage: "door.left.hand.open")
                summaryRow("Service length", summary.serviceLength, systemImage: "hourglass")
                summaryRow("Worship atmosphere", summary.worshipStyle, systemImage: "music.note")
                summaryRow("Kids ministry", summary.kidsMinistry, systemImage: "figure.and.child.holdinghands")
                summaryRow("First-time flow", summary.firstTimeFlow, systemImage: "person.crop.circle.badge.questionmark")
            }
        }
    }

    @ViewBuilder
    private func summaryRow(_ title: String, _ value: String?, systemImage: String) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .frame(width: 18, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.52))
                    Text(value)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
        }
    }
}

private struct ChurchPhotoPreviewGrid: View {
    let media: [ChurchMediaAsset]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Photos")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
                Spacer()
            }

            HStack(spacing: 12) {
                ForEach(media.prefix(2)) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        AsyncImage(url: URL(string: item.imageURL)) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                Color(white: 0.92)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 132)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                        Text(item.type == "hero" ? "From the Church" : item.type.capitalized)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.8))
                    }
                }

                if media.isEmpty {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.56))
                        .frame(height: 132)
                        .overlay(
                            Text("Church photos will appear here.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.45))
                                .padding(20)
                        )
                }
            }
        }
    }
}

private struct ChurchGoodToKnowSection: View {
    let items: [ChurchGoodToKnowItem]

    var body: some View {
        ChurchSectionCard(title: "Good to Know") {
            if items.isEmpty {
                Text("More visit notes have not been confirmed yet.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.52))
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.55))
                                .frame(width: 18, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.84))
                                Text(item.value)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(Color.black.opacity(0.58))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()
                        }
                    }
                }
            }
        }
    }
}

private struct ChurchFloatingActionBar: View {
    let isSaved: Bool
    let onSuggestEdit: () -> Void
    let onAdd: () -> Void
    let onSave: () -> Void
    let onMore: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            barButton(systemImage: "exclamationmark.bubble", action: onSuggestEdit)
            barButton(systemImage: "plus", action: onAdd)
            barButton(systemImage: isSaved ? "star.fill" : "star", action: onSave)
            barButton(systemImage: "ellipsis", action: onMore)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .adaptiveLiquidGlassHeaderSurface(progress: 0.7, cornerRadius: 999)
        .padding(.horizontal, 48)
    }

    private func barButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.82))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(ChurchTactileButtonStyle())
    }
}

struct BereanChurchContextSheet: View {
    let church: Church
    let payload: ChurchDetailPayload?

    @State private var prompt = ""
    @State private var response: BereanAIResponse?
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    private let core = BereanCoreService.shared

    private var suggestedPrompts: [String] {
        [
            "What should I know before visiting \(church.name)?",
            "What time should I arrive for \(church.name)?",
            "What does \(church.name) emphasize?",
            "Does this church have kids ministry?",
            "Summarize this church in 30 seconds."
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Ask Berean about this church")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.88))

                    Text("Berean answers using verified church profile data, live context, and visit guidance when available.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.58))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(suggestedPrompts, id: \.self) { item in
                            Button {
                                prompt = item
                            } label: {
                                Text(item)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.8))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                                    .padding(14)
                                    .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(ChurchTactileButtonStyle())
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Question")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.5))

                        TextEditor(text: $prompt)
                            .frame(minHeight: 110)
                            .padding(10)
                            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                        Button {
                            Task {
                                await askBerean()
                            }
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(isLoading ? "Thinking…" : "Ask Berean")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(ChurchTactileButtonStyle())
                        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    }

                    if let response {
                        ChurchSectionCard(title: "Berean Response") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(response.content)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(Color.black.opacity(0.82))

                                Text(response.isHighConfidence ? "High confidence" : "Use discernment")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.48))
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(white: 0.97).ignoresSafeArea())
            .navigationTitle("Ask Berean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func askBerean() async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        let retrievedContext = [
            payload?.about,
            payload?.experienceSummary?.firstTimeFlow,
            payload?.experienceSummary?.parking,
            payload?.experienceSummary?.kidsMinistry,
            payload?.experienceSummary?.accessibility,
            payload?.liveState?.title,
            payload?.liveState?.description
        ].compactMap { $0 }

        let request = BereanAIRequest(
            surface: .churchDiscovery,
            category: .assistantResponse,
            userInput: trimmed,
            context: [
                "churchId": church.canonicalChurchId,
                "churchName": church.name,
                "churchType": payload?.typeLabel ?? "Church",
                "cityState": [payload?.city, payload?.state].compactMap { $0 }.joined(separator: ", ")
            ],
            retrievedContext: retrievedContext,
            userId: Auth.auth().currentUser?.uid,
            allowCache: false,
            isPrivate: true
        )

        response = await core.process(request)
    }
}

private struct ChurchSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.5))

            content
        }
        .padding(18)
        .adaptiveLiquidGlassHeaderSurface(progress: 0.38, cornerRadius: 26)
    }
}

private struct ChurchDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.5))
            Text(value)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChurchDetailSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white.opacity(0.75))
                .frame(height: 320)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.75))
                .frame(height: 120)

            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.72))
                        .frame(height: 74)
                }
            }

            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.72))
                    .frame(height: 120)
            }
        }
        .padding(20)
        .redacted(reason: .placeholder)
    }
}

private struct ChurchTactileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
