import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class BereanPulseActionRouter: ObservableObject {
    enum Destination: Identifiable {
        case chat(initialMode: BereanPersonalityMode, query: String, context: BereanPulseChatContext)
        case post(postId: String, commentId: String?)
        case church(churchId: String)
        case conversation(conversationId: String)
        case prayerJournal(entryId: String)
        case readingPlan(planId: String)
        case projectBrief(projectId: String)
        case wellnessCheckIn(checkInId: String)
        case findChurch
        case notifications
        case messages
        case createPost
        case profile

        var id: String {
            switch self {
            case .chat(_, let query, let context):
                return "chat_\(query)_\(context.sourceCardId)"
            case .post(let postId, let commentId):
                return "post_\(postId)_\(commentId ?? "none")"
            case .church(let churchId):
                return "church_\(churchId)"
            case .conversation(let conversationId):
                return "conversation_\(conversationId)"
            case .prayerJournal(let entryId):
                return "prayerJournal_\(entryId)"
            case .readingPlan(let planId):
                return "readingPlan_\(planId)"
            case .projectBrief(let projectId):
                return "projectBrief_\(projectId)"
            case .wellnessCheckIn(let checkInId):
                return "wellnessCheckIn_\(checkInId)"
            case .findChurch:
                return "findChurch"
            case .notifications:
                return "notifications"
            case .messages:
                return "messages"
            case .createPost:
                return "createPost"
            case .profile:
                return "profile"
            }
        }
    }

    @Published var destination: Destination?
    @Published var shareText: String?
    @Published var unsupportedMessage: String?

    func route(
        action: BereanPulseAction,
        card: BereanPulseCard
    ) {
        let chatContext = BereanPulseChatContext(
            sourceCardId: card.id,
            sourceSignalsSummary: card.sourceSignals.filter(\.isUserVisible).map(\.summary),
            privacyContext: card.privacyLevel
        )

        switch action.type {
        case .askBerean, .continueChat:
            let mode = BereanPersonalityMode(rawValue: action.payload["mode"] ?? "") ?? .strategist
            let query = action.payload["prompt"] ?? card.expandedBody
            destination = .chat(initialMode: mode, query: query, context: chatContext)
        case .startReflection, .createPrayer:
            destination = .chat(
                initialMode: .shepherd,
                query: action.payload["prompt"] ?? card.expandedBody,
                context: chatContext
            )
        case .openPost, .openSavedPost:
            guard let postId = nonEmptyValue("postId", in: action.payload) else {
                unsupportedMessage = card.unavailableActionExplanation
                return
            }
            destination = .post(postId: postId, commentId: nonEmptyValue("commentId", in: action.payload))
        case .openChurch:
            guard let churchId = nonEmptyValue("churchId", in: action.payload) else {
                unsupportedMessage = card.unavailableActionExplanation
                return
            }
            destination = .church(churchId: churchId)
        case .openGroup:
            if let conversationId = nonEmptyValue("conversationId", in: action.payload) {
                destination = .conversation(conversationId: conversationId)
            } else {
                unsupportedMessage = card.unavailableActionExplanation ?? String(localized: "This group card is missing a supported group payload.")
            }
        case .openPrayerJournal:
            guard let entryId = nonEmptyValue("entryId", in: action.payload) else {
                unsupportedMessage = card.unavailableActionExplanation
                return
            }
            destination = .prayerJournal(entryId: entryId)
        case .draftMessage:
            if let conversationId = nonEmptyValue("conversationId", in: action.payload) {
                destination = .conversation(conversationId: conversationId)
            } else {
                unsupportedMessage = card.unavailableActionExplanation
            }
        case .openFindChurch:
            destination = .findChurch
        case .openDiscoverSearch:
            if let prompt = nonEmptyValue("prompt", in: action.payload) {
                destination = .chat(initialMode: .strategist, query: prompt, context: chatContext)
            } else {
                unsupportedMessage = String(localized: "This card needs search context before it can continue.")
            }
        case .openReadingPlan:
            guard let planId = nonEmptyValue("planId", in: action.payload) else {
                unsupportedMessage = card.unavailableActionExplanation
                return
            }
            destination = .readingPlan(planId: planId)
        case .openProjectBrief:
            guard let projectId = nonEmptyValue("projectId", in: action.payload) else {
                unsupportedMessage = card.unavailableActionExplanation
                return
            }
            destination = .projectBrief(projectId: projectId)
        case .openWellnessCheckIn:
            guard let checkInId = nonEmptyValue("checkInId", in: action.payload) else {
                unsupportedMessage = card.unavailableActionExplanation
                return
            }
            destination = .wellnessCheckIn(checkInId: checkInId)
        case .openMessages:
            destination = .messages
        case .openNotifications:
            destination = .notifications
        case .createPost:
            destination = .createPost
        case .openProfile:
            destination = .profile
        case .shareCard:
            shareText = "\(card.title)\n\n\(card.whyNow)\n\n\(card.expandedBody)"
        case .saveCard, .hideCard, .requestPermission, .curatePreferences:
            break
        }
    }

    private func nonEmptyValue(_ key: String, in payload: [String: String]) -> String? {
        guard let value = payload[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}

struct BereanPulseDestinationView: View {
    let destination: BereanPulseActionRouter.Destination

    var body: some View {
        switch destination {
        case .chat(let initialMode, let query, let context):
            BereanChatRouteView(
                entryPoint: .bereanHome,
                initialMode: initialMode,
                initialQuery: "\(context.promptPrefix())\n\n\(query)"
            )
        case .post(let postId, let commentId):
            PulsePostRouteView(postId: postId, commentId: commentId)
        case .church(let churchId):
            ChurchProfileView(churchId: churchId)
        case .conversation(let conversationId):
            PulseConversationRouteView(conversationId: conversationId)
        case .prayerJournal(let entryId):
            PulsePrayerJournalRouteView(entryId: entryId)
        case .readingPlan(let planId):
            PulseReadingPlanRouteView(planId: planId)
        case .projectBrief(let projectId):
            PulseProjectBriefRouteView(projectId: projectId)
        case .wellnessCheckIn(let checkInId):
            PulseWellnessCheckInRouteView(checkInId: checkInId)
        case .findChurch:
            FindChurchView()
        case .notifications:
            NotificationsView()
        case .messages:
            MessagesView()
        case .createPost:
            CreatePostView()
        case .profile:
            ProfileView()
        }
    }
}

private struct PulsePostRouteView: View {
    let postId: String
    let commentId: String?
    @State private var post: Post?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let post {
                PostDetailView(post: post)
            } else if let errorMessage {
                PulseUnavailableStateView(title: String(localized: "Post unavailable"), message: errorMessage)
            } else {
                ProgressView()
                    .task { await loadPost() }
            }
        }
    }

    private func loadPost() async {
        do {
            post = try await FirebasePostService.shared.fetchPostById(postId: postId)
            if post == nil {
                errorMessage = String(localized: "The referenced post could not be found.")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PulseConversationRouteView: View {
    let conversationId: String
    @State private var conversation: ChatConversation?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let conversation {
                ModernConversationDetailView(conversation: conversation)
            } else if let errorMessage {
                PulseUnavailableStateView(title: String(localized: "Conversation unavailable"), message: errorMessage)
            } else {
                ProgressView()
                    .task { await loadConversation() }
            }
        }
    }

    private func loadConversation() async {
        let fetched = await FirebaseMessagingService.shared.fetchConversation(conversationId: conversationId)
        if let fetched {
            conversation = fetched
        } else {
            errorMessage = String(localized: "The referenced conversation could not be loaded.")
        }
    }
}

private struct PulsePrayerJournalRouteView: View {
    let entryId: String
    @State private var entryTitle = ""
    @State private var entryBody = ""
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                PulseUnavailableStateView(title: String(localized: "Prayer journal unavailable"), message: errorMessage)
            } else if !entryTitle.isEmpty || !entryBody.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(entryTitle.isEmpty ? String(localized: "Prayer Reflection") : entryTitle)
                            .font(.title2.weight(.bold))
                        Text(entryBody.isEmpty ? String(localized: "This reflection entry does not have readable text yet.") : entryBody)
                            .font(.body)
                    }
                    .padding(24)
                }
                .navigationTitle(String(localized: "Prayer Journal"))
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ProgressView()
                    .task { await loadEntry() }
            }
        }
    }

    private func loadEntry() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = String(localized: "A signed-in user is required to open this reflection.")
            return
        }
        do {
            let doc = try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .collection("reflectionEntries")
                .document(entryId)
                .getDocument()
            guard let data = doc.data() else {
                errorMessage = String(localized: "The referenced reflection entry could not be found.")
                return
            }
            entryTitle = data["title"] as? String ?? data["passageReference"] as? String ?? ""
            entryBody = data["text"] as? String ?? data["content"] as? String ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PulseReadingPlanRouteView: View {
    let planId: String
    @State private var title = ""
    @State private var summary = ""
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                PulseUnavailableStateView(title: String(localized: "Reading plan unavailable"), message: errorMessage)
            } else if !title.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(title)
                            .font(.title2.weight(.bold))
                        Text(summary.isEmpty ? String(localized: "This reading plan is ready to continue.") : summary)
                            .font(.body)
                    }
                    .padding(24)
                }
                .navigationTitle(String(localized: "Reading Plan"))
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ProgressView()
                    .task { await loadPlan() }
            }
        }
    }

    private func loadPlan() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = String(localized: "A signed-in user is required to open this reading plan.")
            return
        }
        do {
            let userScoped = try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .collection("readingPlans")
                .document(planId)
                .getDocument()
            let globalScoped = try await Firestore.firestore()
                .collection("readingPlans")
                .document(planId)
                .getDocument()
            let data = userScoped.data() ?? globalScoped.data()
            guard let data else {
                errorMessage = String(localized: "The referenced reading plan could not be found.")
                return
            }
            title = data["title"] as? String ?? String(localized: "Reading Plan")
            summary = data["summary"] as? String ?? data["description"] as? String ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PulseProjectBriefRouteView: View {
    let projectId: String
    @State private var title = ""
    @State private var status = ""
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                PulseUnavailableStateView(title: String(localized: "Project unavailable"), message: errorMessage)
            } else if !title.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(title)
                            .font(.title2.weight(.bold))
                        if !status.isEmpty {
                            Text(status)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(24)
                }
                .navigationTitle(String(localized: "Project Brief"))
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ProgressView()
                    .task { await loadProject() }
            }
        }
    }

    private func loadProject() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = String(localized: "A signed-in user is required to open this project.")
            return
        }
        do {
            let doc = try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .collection("creatorProjects")
                .document(projectId)
                .getDocument()
            guard let data = doc.data() else {
                errorMessage = String(localized: "The referenced project could not be found.")
                return
            }
            title = data["title"] as? String ?? String(localized: "Untitled Project")
            status = data["status"] as? String ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PulseWellnessCheckInRouteView: View {
    let checkInId: String
    @State private var title = ""
    @State private var prompt = ""
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                PulseUnavailableStateView(title: String(localized: "Wellness check-in unavailable"), message: errorMessage)
            } else if !title.isEmpty || !prompt.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(title.isEmpty ? String(localized: "Wellness Check-In") : title)
                            .font(.title2.weight(.bold))
                        Text(prompt.isEmpty ? String(localized: "This wellness check-in is ready to continue.") : prompt)
                            .font(.body)
                    }
                    .padding(24)
                }
                .navigationTitle(String(localized: "Check-In"))
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ProgressView()
                    .task { await loadCheckIn() }
            }
        }
    }

    private func loadCheckIn() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = String(localized: "A signed-in user is required to open this check-in.")
            return
        }
        let firestore = Firestore.firestore()
        let candidatePaths: [DocumentReference] = [
            firestore.collection("users").document(uid).collection("wellnessCheckIns").document(checkInId),
            firestore.collection("users").document(uid).collection("koraCheckIns").document(checkInId),
            firestore.collection("users").document(uid).collection("mentorshipCheckIns").document(checkInId)
        ]

        do {
            for reference in candidatePaths {
                let doc = try await reference.getDocument()
                if let data = doc.data() {
                    title = data["title"] as? String ?? data["question"] as? String ?? String(localized: "Wellness Check-In")
                    prompt = data["prompt"] as? String ?? data["summary"] as? String ?? ""
                    return
                }
            }
            errorMessage = String(localized: "The referenced wellness check-in could not be found.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PulseUnavailableStateView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(40, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
