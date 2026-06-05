import SwiftUI
import FirebaseFunctions
import FirebaseFirestore
import FirebaseAuth
import UserNotifications
import PhotosUI
import EventKit

struct BereanCommunicationHubView: View {
    @StateObject private var viewModel = BereanCommunicationHubViewModel()
    @StateObject private var commFlags = CommunicationOSFeatureFlags.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var selectedScope: CommunicationScope = .all
    @State private var searchText = ""
    @State private var selectedThreadID: String?
    @State private var showingAttachmentMenu = false

    // MARK: - Detection wiring
    @State private var hubDetectedItems: [DetectedMessageContext] = []
    @State private var detectionTask: Task<Void, Never>?

    // MARK: - Contact notes
    @State private var showingContactNotes = false
    @State private var selectedContactUID = ""

    // MARK: - Photo picker
    @State private var showingPhotosPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    // MARK: - Poll / send-later / share sheets
    @State private var showingPollComposer = false
    @State private var showingSendLaterSheet = false
    @State private var sendLaterDate = Date().addingTimeInterval(3600)
    @State private var showingShareSheet = false
    @State private var shareContent = ""

    // MARK: - Conversation memories
    @State private var conversationMemories: [ConversationMemoryItem] = []
    @State private var memoriesLoadTask: Task<Void, Never>?

    // MARK: - RAG Search
    @State private var ragResults: [RAGSearchResult] = []
    @State private var ragSearchTask: Task<Void, Never>?

    // MARK: - Resume session
    @AppStorage("bereanActiveSessionId") private var activeSessionId: String = UUID().uuidString
    @State private var isResumingSession = false

    private var filteredThreads: [CommunicationThreadItem] {
        viewModel.threads.filter { thread in
            (selectedScope == .all || thread.scope == selectedScope) &&
            (searchText.isEmpty || thread.title.localizedCaseInsensitiveContains(searchText) || thread.preview.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                background

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        presenceRail
                        digestCard
                        commandPalettePreview
                        if commFlags.conversationMemoryEnabled && !conversationMemories.isEmpty {
                            ConversationMemoryCard(
                                memories: conversationMemories,
                                onDelete: { item in conversationMemories.removeAll { $0.id == item.id } }
                            )
                        }
                        if !ragResults.isEmpty {
                            ragResultsSection
                        }
                        threadsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 130)
                }

                VStack(spacing: 0) {
                    if commFlags.smartMessageContextEnabled {
                        SmartMessageInsightCard(
                            detectedItems: hubDetectedItems,
                            onAction: { item in handleInsightAction(item) },
                            onDismiss: { item in hubDetectedItems.removeAll { $0.id == item.id } }
                        )
                        .padding(.bottom, 4)
                    }
                    composerBar
                }
            }
            .navigationTitle("Communion")
            .onChange(of: searchText) { _, newValue in
                if CommunicationOSFeatureFlags.shared.smartMessageContextEnabled {
                    detectionTask?.cancel()
                    detectionTask = Task {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        guard !Task.isCancelled else { return }
                        let result = await AmenSmartContextDetectionEngine.shared.detect(in: newValue)
                        let converted = AmenContextDetectionBridge.toMessageContextItems(from: result)
                        await MainActor.run {
                            hubDetectedItems = converted
                            if !converted.isEmpty {
                                AMENAnalyticsService.shared.track(.commOSActionTapped(actionKey: "context_detected"))
                            }
                        }
                    }
                }

                if CommunicationOSFeatureFlags.shared.ragSearchEnabled && newValue.count >= 3 {
                    ragSearchTask?.cancel()
                    ragSearchTask = Task {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        guard !Task.isCancelled else { return }
                        let response = try? await AmenAIFeaturesService.shared.ragSearch(query: newValue, scope: .all)
                        await MainActor.run {
                            ragResults = response?.results ?? []
                        }
                    }
                } else if newValue.isEmpty {
                    ragResults = []
                }
            }
            .sheet(isPresented: $showingAttachmentMenu) {
                SmartMessageActionMenu(
                    onAction: { action in handleAttachmentAction(action) },
                    onDismiss: { showingAttachmentMenu = false }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $showingContactNotes) {
                ContactPrivateNotesView(
                    contactUID: viewModel.threads.first?.id ?? "",
                    contactDisplayName: "This Contact",
                    onSave: { note, tags in
                        await savePrivateContactNote(
                            note: note,
                            tags: tags,
                            contactUID: viewModel.threads.first?.id ?? ""
                        )
                    },
                    onDismiss: { showingContactNotes = false }
                )
            }
            .photosPicker(isPresented: $showingPhotosPicker, selection: $selectedPhotoItems, maxSelectionCount: 1, matching: .images)
            .sheet(isPresented: $showingSendLaterSheet) {
                NavigationStack {
                    VStack(spacing: 24) {
                        Text("Send Later")
                            .font(.headline)
                        DatePicker("Schedule time", selection: $sendLaterDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.graphical)
                            .padding(.horizontal)
                        Button("Set Reminder") {
                            Task { await scheduleLocalReminderAt(sendLaterDate) }
                            showingSendLaterSheet = false
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom)
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingSendLaterSheet = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingShareSheet) {
                if !shareContent.isEmpty {
                    ShareSheet(items: [shareContent as Any])
                        .presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: $showingPollComposer) {
                NavigationStack {
                    VStack(spacing: 16) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Poll Composer")
                            .font(.headline)
                        Text("Ask your thread a question and let everyone vote.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingPollComposer = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.load()
                memoriesLoadTask = Task { await loadRecentMemories() }
            }
            .onDisappear {
                viewModel.cleanup()
                memoriesLoadTask?.cancel()
                detectionTask?.cancel()
                ragSearchTask?.cancel()
            }
        }
    }

    // MARK: - Insight action handler

    private func handleInsightAction(_ item: DetectedMessageContext) {
        switch item.type {
        case .date:
            sendLaterDate = Date().addingTimeInterval(3600)
            showingSendLaterSheet = true
            hubDetectedItems.removeAll { $0.id == item.id }
        case .link:
            if let url = URL(string: item.actionLabel), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
            hubDetectedItems.removeAll { $0.id == item.id }
        case .music, .task, .memory:
            hubDetectedItems.removeAll { $0.id == item.id }
        }
    }

    // MARK: - Attachment action handler

    private func handleAttachmentAction(_ action: MessageAttachmentAction) {
        showingAttachmentMenu = false
        switch action {
        case .camera:
            showingPhotosPicker = true
        case .photoLibrary:
            showingPhotosPicker = true
        case .polls:
            showingPollComposer = true
        case .sendLater:
            showingSendLaterSheet = true
        case .createReminder:
            Task { await scheduleLocalReminder() }
        case .saveMemory:
            guard !searchText.isEmpty else { return }
            Task { await saveMemoryFromText(searchText) }
        case .addContactNote:
            showingContactNotes = true
        case .shareLink:
            shareContent = searchText.isEmpty ? "Check out Amen — faith-first community." : searchText
            showingShareSheet = true
        case .createEvent:
            if let url = URL(string: "calshow://") {
                UIApplication.shared.open(url)
            }
        case .createTask:
            Task { await scheduleLocalReminder() }
        }
    }

    // MARK: - Firebase helpers

    private func scheduleLocalReminder() async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings()
        if status.authorizationStatus != .authorized {
            let granted = try? await center.requestAuthorization(options: [.alert, .sound])
            guard granted == true else { return }
        }
        let content = UNMutableNotificationContent()
        content.title = "Amen Reminder"
        content.body = searchText.isEmpty ? "Follow up on your thread" : String(searchText.prefix(100))
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func scheduleLocalReminderAt(_ date: Date) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus != .authorized {
            let granted = try? await center.requestAuthorization(options: [.alert, .sound])
            guard granted == true else { return }
        }
        let content = UNMutableNotificationContent()
        content.title = "Amen Reminder"
        content.body = searchText.isEmpty ? "Follow up on your thread" : String(searchText.prefix(100))
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func saveMemoryFromText(_ text: String) async {
        guard let threadId = viewModel.threads.first?.id else { return }
        do {
            _ = try await Functions.functions(region: "us-central1")
                .httpsCallable("saveConversationMemory")
                .call(["threadId": threadId, "type": "memory", "title": String(text.prefix(200))] as [String: Any])
        } catch {
            // Fail silently — memory save is non-critical
        }
    }

    private func savePrivateContactNote(note: String, tags: [String], contactUID: String) async {
        guard !contactUID.isEmpty else { return }
        do {
            _ = try await Functions.functions(region: "us-central1")
                .httpsCallable("savePrivateContactNote")
                .call(["contactUid": contactUID, "note": note, "tags": tags] as [String: Any])
        } catch {
            // Fail silently — note save is non-critical
        }
    }

    private func loadRecentMemories() async {
        guard let uid = Auth.auth().currentUser?.uid,
              let threadId = viewModel.threads.first?.id else { return }
        do {
            let snapshot = try await Firestore.firestore()
                .collection("threads").document(threadId)
                .collection("memories")
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
                .getDocuments()
            let items = snapshot.documents.compactMap { doc -> ConversationMemoryItem? in
                let data = doc.data()
                guard let typeRaw = data["type"] as? String,
                      let title = data["title"] as? String else { return nil }
                let type: ConversationMemoryType = {
                    switch typeRaw {
                    case "link": return .link
                    case "date": return .date
                    case "music": return .music
                    case "note": return .note
                    case "task": return .task
                    case "event": return .event
                    default: return .memory
                    }
                }()
                let body = data["body"] as? String
                let ts = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                return ConversationMemoryItem(id: UUID(), type: type, title: title, body: body, timestamp: ts)
            }
            _ = uid
            await MainActor.run { conversationMemories = items }
        } catch {
            // No-op — memory display is best-effort
        }
    }

    // MARK: - Background

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.98, blue: 0.96),
                Color(red: 0.94, green: 0.95, blue: 0.92),
                Color(red: 0.90, green: 0.93, blue: 0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.white.opacity(0.38))
                .frame(width: 220, height: 220)
                .blur(radius: 50)
                .offset(x: 70, y: -20)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Communication that remembers where prayer, study, and care left off.")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text("A calm operating layer for threads, prayer follow-up, retrieval, and sacred collaboration.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Find that prayer from last month…", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 0.8)
            }
        }
    }

    private var presenceRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Presence")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.presenceItems) { presence in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(presence.tint)
                                    .frame(width: 9, height: 9)
                                Text(presence.name)
                                    .font(.subheadline.weight(.semibold))
                            }

                            Text(presence.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(14)
                        .frame(width: 158, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
        }
    }

    private var digestCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("Today's Digest")
                Spacer()
                if viewModel.unresolvedCount > 0 {
                    Text("\(viewModel.unresolvedCount) unresolved")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
            }

            Text(viewModel.digestHeadline)
                .font(.headline)

            ForEach(viewModel.digestHighlights, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color(red: 0.86, green: 0.62, blue: 0.24))
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                digestAction("Catch up")
                digestAction("Summarize prayer rooms", emphasized: false)
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 0.8)
        }
    }

    private var commandPalettePreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Quick Actions")

            VStack(alignment: .leading, spacing: 10) {
                commandRow(icon: "command", title: "Jump to threads", subtitle: "Recent rooms, prayer chains, saved studies")
                commandRow(icon: "book.pages", title: "Search scripture", subtitle: "Query by passage, theme, or remembered wording")
                commandRow(icon: "brain.head.profile", title: "Ask Berean deeper", subtitle: "Context-aware study and recap actions")
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var ragResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Search Results")
            ForEach(ragResults) { result in
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.title)
                        .font(.subheadline.weight(.semibold))
                    Text(result.excerpt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(result.type.capitalized)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                        Spacer()
                        Text(String(format: "%.0f%%", result.score * 100))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.45), lineWidth: 0.8)
                }
            }
        }
    }

    private var threadsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("Threads")
                Spacer()
            }

            scopeRail

            switch viewModel.loadingState {
            case .loading:
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 32)
                    Spacer()
                }
            case .empty:
                Text("No threads yet. Start a prayer or study session with Berean.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            case .error(let message):
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 24)
            default:
                EmptyView()
            }

            ForEach(filteredThreads) { thread in
                Button {
                    withAnimation(animation) {
                        selectedThreadID = selectedThreadID == thread.id ? nil : thread.id
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(thread.tint.opacity(0.16))
                                .frame(width: 42, height: 42)
                                .overlay {
                                    Image(systemName: thread.icon)
                                        .foregroundStyle(thread.tint)
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(thread.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(thread.timeLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Text(thread.preview)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(selectedThreadID == thread.id ? 4 : 2)
                            }
                        }

                        HStack(spacing: 8) {
                            threadPill(thread.presenceLabel, tint: thread.tint)
                            threadPill("\(thread.replyCount) replies", tint: .gray)
                            if thread.needsFollowUp {
                                threadPill("Follow-up", tint: .orange)
                            }
                        }

                        if selectedThreadID == thread.id {
                            VStack(alignment: .leading, spacing: 10) {
                                Divider()
                                Text(thread.expandedSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    threadAction("Reply in thread")
                                    threadAction("Save to prayer")
                                    threadAction("Turn into journal")
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(16)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.48), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var scopeRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CommunicationScope.allCases) { scope in
                    Button {
                        withAnimation(animation) {
                            selectedScope = scope
                        }
                    } label: {
                        Text(scope.title)
                            .font(.subheadline.weight(selectedScope == scope ? .semibold : .regular))
                            .foregroundStyle(selectedScope == scope ? .primary : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule()
                                    .fill(selectedScope == scope ? Color.white.opacity(0.85) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var composerBar: some View {
        HStack(spacing: 12) {
            if commFlags.smartAttachmentMenuEnabled {
                Button {
                    showingAttachmentMenu = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Attachment menu")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Continue this study later")
                    .font(.subheadline.weight(.semibold))
                Text("Drafts, branches, and prayer follow-ups persist across devices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                guard !isResumingSession else { return }
                isResumingSession = true
                let sessionId = activeSessionId
                Task {
                    try? await Functions.functions(region: "us-central1")
                        .httpsCallable("resumeBereanSession")
                        .call([
                            "sessionId": sessionId,
                            "uid": Auth.auth().currentUser?.uid ?? ""
                        ])
                    await MainActor.run { isResumingSession = false }
                }
            } label: {
                if isResumingSession {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color(uiColor: .systemBackground))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                } else {
                    Text("Resume")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
            }
            .background(Color.primary, in: Capsule())
            .foregroundStyle(Color(uiColor: .systemBackground))
            .accessibilityLabel("Resume study session")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            if reduceTransparency {
                Capsule(style: .continuous)
                    .fill(Color(.systemBackground))
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        .glassEffect(reduceTransparency ? .identity : GlassEffectStyle.regular, in: Capsule(style: .continuous))
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
    }

    private func digestAction(_ title: String, emphasized: Bool = true) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(emphasized ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(emphasized ? Color.white.opacity(0.78) : Color.clear, in: Capsule())
    }

    private func commandRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func threadPill(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint == .gray ? .secondary : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(tint == .gray ? 0.08 : 0.12), in: Capsule())
    }

    private func threadAction(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.78), in: Capsule())
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private var animation: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.32, dampingFraction: 0.82)
    }
}

#Preview {
    BereanCommunicationHubView()
}
