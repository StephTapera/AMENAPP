import SwiftUI
import FirebaseFunctions

@MainActor
final class ThreadSummaryPanelViewModel: ObservableObject {
    @Published private(set) var state: AmenThreadSummaryState = .idle

    private let functions = Functions.functions()
    private var loadTask: Task<Void, Never>?
    private var lastLoadedSummary: AmenThreadSummary?

    func load(threadId: String, sinceMessageId: String? = nil, forceRefresh: Bool = false) {
        guard AMENFeatureFlags.shared.threadSummaryEnabled else {
            state = .empty
            return
        }
        loadTask?.cancel()
        state = forceRefresh ? .generating : .loading
        loadTask = Task {
            do {
                let summary = try await fetchSummary(threadId: threadId, sinceMessageId: sinceMessageId, forceRefresh: forceRefresh)
                guard !Task.isCancelled else { return }
                lastLoadedSummary = summary
                state = summary.summary.isEmpty && summary.changedSinceLastVisit.isEmpty ? .empty : (summary.isStale ? .stale(summary) : .loaded(summary))
                AmenMessagingAnalytics.track(.threadSummaryGenerated, parameters: ["hasSummary": !summary.summary.isEmpty])
            } catch let error as NSError where error.domain == NSURLErrorDomain {
                guard !Task.isCancelled else { return }
                state = .offline(lastLoadedSummary)
            } catch {
                guard !Task.isCancelled else { return }
                let nsError = error as NSError
                if nsError.localizedDescription.lowercased().contains("permission") {
                    state = .permissionDenied
                } else {
                    state = .error("Summary unavailable. Try again shortly.")
                }
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
    }

    private func fetchSummary(threadId: String, sinceMessageId: String?, forceRefresh: Bool) async throws -> AmenThreadSummary {
        let payload: [String: Any] = [
            "threadId": threadId,
            "conversationId": threadId,
            "sinceMessageId": sinceMessageId as Any,
            "forceRefresh": forceRefresh
        ]
        do {
            let result = try await functions.httpsCallable("generateThreadSummary").call(payload)
            if let data = result.data as? [String: Any] {
                return parseSummary(data, threadId: threadId)
            }
        } catch {
            let fallback = try await functions.httpsCallable("generateDMCatchUp").call([
                "conversationId": threadId,
                "since": Date().addingTimeInterval(-86400).timeIntervalSince1970 * 1000
            ])
            if let data = fallback.data as? [String: Any] {
                return parseCatchUpFallback(data, threadId: threadId)
            }
            throw error
        }
        return .empty(threadId: threadId)
    }

    private func parseSummary(_ data: [String: Any], threadId: String) -> AmenThreadSummary {
        let decisions = (data["decisions"] as? [[String: Any]] ?? []).compactMap(parseDecision)
        let questions = (data["openQuestions"] as? [[String: Any]] ?? data["questions"] as? [[String: Any]] ?? []).compactMap(parseQuestion)
        let actions = (data["followUps"] as? [[String: Any]] ?? data["actions"] as? [[String: Any]] ?? []).compactMap(parseAction)
        let media = (data["mediaRefs"] as? [[String: Any]] ?? data["media"] as? [[String: Any]] ?? []).compactMap(parseMediaRef)
        let importantDates = (data["importantDates"] as? [[String: Any]] ?? []).compactMap(parseImportantDate)
        let sourceIds = data["sourceMessageIds"] as? [String] ?? []
        return AmenThreadSummary(
            id: data["id"] as? String ?? UUID().uuidString,
            threadId: threadId,
            summary: data["summary"] as? String ?? "",
            topic: data["topic"] as? String ?? "Current thread",
            changedSinceLastVisit: data["changedSinceLastVisit"] as? [String] ?? data["keyUpdates"] as? [String] ?? [],
            decisions: decisions,
            openQuestions: questions,
            followUps: actions,
            importantDates: importantDates,
            mediaRefs: media,
            suggestedActions: [],
            generatedAt: Date(),
            staleAfter: Date().addingTimeInterval(15 * 60),
            sourceMessageIds: sourceIds
        )
    }

    private func parseCatchUpFallback(_ data: [String: Any], threadId: String) -> AmenThreadSummary {
        let summaryText = data["summary"] as? String ?? ""
        let decisions = (data["decisions"] as? [String] ?? []).enumerated().map { index, text in
            AmenThreadDecision(id: "fallback_decision_\(index)", title: "Potential decision", summary: text, sourceMessageIds: [], decidedByUid: nil, confirmedByUids: [], status: .proposed, decidedAt: nil, confidence: nil)
        }
        let questions = (data["unansweredQuestions"] as? [String] ?? []).enumerated().map { index, text in
            AmenThreadQuestion(id: "fallback_question_\(index)", question: text, askedByUid: nil, sourceMessageId: "", answeredByMessageId: nil, status: .open, confidence: nil)
        }
        let actions = (data["suggestedActions"] as? [String] ?? []).enumerated().map { index, text in
            AmenThreadAction(id: "fallback_action_\(index)", title: text, description: nil, sourceMessageIds: [], assignedToUid: nil, dueDate: nil, confidence: nil, status: .suggested)
        }
        return AmenThreadSummary(
            id: UUID().uuidString,
            threadId: threadId,
            summary: summaryText,
            topic: "Catch up",
            changedSinceLastVisit: summaryText.isEmpty ? [] : [summaryText],
            decisions: decisions,
            openQuestions: questions,
            followUps: actions,
            importantDates: [],
            mediaRefs: [],
            suggestedActions: [],
            generatedAt: Date(),
            staleAfter: Date().addingTimeInterval(15 * 60),
            sourceMessageIds: []
        )
    }

    private func parseDecision(_ dict: [String: Any]) -> AmenThreadDecision? {
        guard let summary = dict["summary"] as? String, !summary.isEmpty else { return nil }
        let rawStatus = dict["status"] as? String ?? AmenThreadDecisionStatus.proposed.rawValue
        return AmenThreadDecision(
            id: dict["id"] as? String ?? UUID().uuidString,
            title: dict["title"] as? String ?? "Potential decision",
            summary: summary,
            sourceMessageIds: dict["sourceMessageIds"] as? [String] ?? [],
            decidedByUid: dict["decidedByUid"] as? String,
            confirmedByUids: dict["confirmedByUids"] as? [String] ?? [],
            status: AmenThreadDecisionStatus(rawValue: rawStatus) ?? .proposed,
            decidedAt: nil,
            confidence: dict["confidence"] as? Double
        )
    }

    private func parseQuestion(_ dict: [String: Any]) -> AmenThreadQuestion? {
        guard let question = dict["question"] as? String, !question.isEmpty else { return nil }
        let rawStatus = dict["status"] as? String ?? AmenThreadQuestionStatus.open.rawValue
        return AmenThreadQuestion(
            id: dict["id"] as? String ?? UUID().uuidString,
            question: question,
            askedByUid: dict["askedByUid"] as? String,
            sourceMessageId: dict["sourceMessageId"] as? String ?? "",
            answeredByMessageId: dict["answeredByMessageId"] as? String,
            status: AmenThreadQuestionStatus(rawValue: rawStatus) ?? .open,
            confidence: dict["confidence"] as? Double
        )
    }

    private func parseAction(_ dict: [String: Any]) -> AmenThreadAction? {
        let title = dict["title"] as? String ?? dict["action"] as? String ?? ""
        guard !title.isEmpty else { return nil }
        let rawStatus = dict["status"] as? String ?? AmenThreadActionStatus.suggested.rawValue
        return AmenThreadAction(
            id: dict["id"] as? String ?? UUID().uuidString,
            title: title,
            description: dict["description"] as? String,
            sourceMessageIds: dict["sourceMessageIds"] as? [String] ?? [],
            assignedToUid: dict["assignedToUid"] as? String,
            dueDate: nil,
            confidence: dict["confidence"] as? Double,
            status: AmenThreadActionStatus(rawValue: rawStatus) ?? .suggested
        )
    }

    private func parseMediaRef(_ dict: [String: Any]) -> AmenThreadMediaRef? {
        let id = dict["id"] as? String ?? dict["mediaId"] as? String ?? UUID().uuidString
        return AmenThreadMediaRef(
            id: id,
            title: dict["title"] as? String ?? dict["name"] as? String ?? "Shared media",
            mediaType: dict["mediaType"] as? String ?? dict["type"] as? String ?? "media",
            sourceMessageId: dict["sourceMessageId"] as? String,
            sourcePath: dict["sourcePath"] as? String
        )
    }

    private func parseImportantDate(_ dict: [String: Any]) -> AmenThreadImportantDate? {
        guard let title = dict["title"] as? String else { return nil }
        return AmenThreadImportantDate(
            id: dict["id"] as? String ?? UUID().uuidString,
            title: title,
            date: Date(),
            sourceMessageIds: dict["sourceMessageIds"] as? [String] ?? [],
            confidence: dict["confidence"] as? Double
        )
    }
}

struct ThreadSummaryPanel: View {
    let threadId: String
    var sinceMessageId: String?
    var onOpenSourceMessage: (String) -> Void = { _ in }
    var onCreateTask: (AmenThreadAction) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    @StateObject private var viewModel = ThreadSummaryPanelViewModel()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Thread Summary")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done", action: onDismiss)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.load(threadId: threadId, sinceMessageId: sinceMessageId, forceRefresh: true)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh summary")
                    }
                }
        }
        .background(Color(.systemBackground))
        .onAppear {
            AmenMessagingAnalytics.track(.threadSummaryOpened)
            viewModel.load(threadId: threadId, sinceMessageId: sinceMessageId)
        }
        .onDisappear { viewModel.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            stateView(title: "Loading summary", systemImage: "text.quote", showsProgress: true)
        case .generating:
            stateView(title: "Generating summary", systemImage: "sparkles", showsProgress: true)
        case .empty:
            stateView(title: "Nothing to summarize yet", systemImage: "bubble.left.and.bubble.right", message: "Thread context will appear after there is enough accessible conversation history.")
        case .permissionDenied:
            stateView(title: "Summary unavailable", systemImage: "lock.fill", message: "You do not have access to this thread context.")
        case .offline(let cached):
            if let cached {
                summaryScroll(cached, banner: "Offline. Showing last known summary.")
            } else {
                stateView(title: "Offline", systemImage: "wifi.slash", message: "Connect to refresh thread intelligence.")
            }
        case .error(let message):
            stateView(title: "Could not load summary", systemImage: "exclamationmark.triangle", message: message)
        case .stale(let summary):
            summaryScroll(summary, banner: "This summary may be stale.")
        case .loaded(let summary):
            summaryScroll(summary, banner: nil)
        }
    }

    private func summaryScroll(_ summary: AmenThreadSummary, banner: String?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let banner {
                    labelRow(banner, systemImage: "clock.badge.exclamationmark", tint: .orange)
                }
                section("Current Topic", systemImage: "target", tint: .blue) {
                    Text(summary.topic)
                        .font(.headline)
                    if !summary.summary.isEmpty {
                        Text(summary.summary)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Last updated \(summary.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                listSection("What Changed", items: summary.changedSinceLastVisit, systemImage: "arrow.triangle.2.circlepath", tint: .indigo)
                decisionsSection(summary.decisions)
                questionsSection(summary.openQuestions)
                actionsSection(summary.followUps)
                datesSection(summary.importantDates)
                mediaSection(summary.mediaRefs)
            }
            .padding(16)
        }
    }

    private func listSection(_ title: String, items: [String], systemImage: String, tint: Color) -> some View {
        section(title, systemImage: systemImage, tint: tint) {
            if items.isEmpty {
                emptyLine("No updates found")
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    labelRow(item, systemImage: "circle.fill", tint: tint)
                }
            }
        }
    }

    private func decisionsSection(_ decisions: [AmenThreadDecision]) -> some View {
        section("Key Decisions", systemImage: "checkmark.seal", tint: .green) {
            if decisions.isEmpty {
                emptyLine("No decisions found")
            } else {
                ForEach(decisions) { decision in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(decision.summary).font(.subheadline.weight(.semibold))
                        Text(decision.status == .confirmed ? "Confirmed" : "Potential decision")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        sourceButtons(decision.sourceMessageIds)
                    }
                }
            }
        }
    }

    private func questionsSection(_ questions: [AmenThreadQuestion]) -> some View {
        section("Unresolved Questions", systemImage: "questionmark.bubble", tint: .orange) {
            if questions.isEmpty {
                emptyLine("No unresolved questions found")
            } else {
                ForEach(questions) { question in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(question.question).font(.subheadline.weight(.semibold))
                        if !question.sourceMessageId.isEmpty { sourceButtons([question.sourceMessageId]) }
                    }
                }
            }
        }
    }

    private func actionsSection(_ actions: [AmenThreadAction]) -> some View {
        section("Follow-ups", systemImage: "bolt", tint: .purple) {
            if actions.isEmpty {
                emptyLine("No follow-ups found")
            } else {
                ForEach(actions) { action in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(action.title).font(.subheadline.weight(.semibold))
                            if let description = action.description {
                                Text(description).font(.caption).foregroundStyle(.secondary)
                            }
                            sourceButtons(action.sourceMessageIds)
                        }
                        Spacer()
                        Button("Create") { onCreateTask(action) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .accessibilityLabel("Create task from follow-up")
                    }
                }
            }
        }
    }

    private func datesSection(_ dates: [AmenThreadImportantDate]) -> some View {
        section("Important Dates", systemImage: "calendar", tint: .teal) {
            if dates.isEmpty {
                emptyLine("No important dates found")
            } else {
                ForEach(dates) { date in
                    labelRow("\(date.title) - \(date.date.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar", tint: .teal)
                }
            }
        }
    }

    private func mediaSection(_ media: [AmenThreadMediaRef]) -> some View {
        section("Files and Media", systemImage: "photo.stack", tint: .indigo) {
            if media.isEmpty {
                emptyLine("No referenced media found")
            } else {
                ForEach(media) { item in
                    labelRow(item.title, systemImage: "paperclip", tint: .indigo)
                }
            }
        }
    }

    private func sourceButtons(_ ids: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(ids.prefix(3), id: \.self) { id in
                Button("Source") { onOpenSourceMessage(id) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Open source message")
            }
        }
    }

    private func section<Content: View>(_ title: String, systemImage: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).foregroundStyle(tint)
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
            }
            content()
        }
        .padding(14)
        .background(reduceTransparency ? AnyShapeStyle(Color(.secondarySystemBackground)) : AnyShapeStyle(.ultraThinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.18), lineWidth: 0.75))
        .accessibilityElement(children: .contain)
    }

    private func labelRow(_ text: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage).font(.caption).foregroundStyle(tint)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func stateView(title: String, systemImage: String, message: String? = nil, showsProgress: Bool = false) -> some View {
        VStack(spacing: 14) {
            if showsProgress {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: systemImage).font(.title2).foregroundStyle(.secondary)
            }
            Text(title).font(.headline)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
