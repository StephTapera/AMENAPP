import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseAnalytics

enum AmenFeedContextType: String, Codable, CaseIterable {
    case inConversation
    case scriptureFocus
    case sharedInYourCircles
    case resonatingNearby
    case bereanInsight
    case churchPulse
    case gentleFollowUp
    case livePrayerMoment
    case communityQuestion
    case relevantNow

    enum SensitivityLevel: String, Codable {
        case low
        case pastoral
        case high
    }

    var displayPrefix: String {
        switch self {
        case .inConversation: return "In conversation"
        case .scriptureFocus: return "Scripture focus"
        case .sharedInYourCircles: return "Shared in your circles"
        case .resonatingNearby: return "Resonating nearby"
        case .bereanInsight: return "Berean insight"
        case .churchPulse: return "Church pulse"
        case .gentleFollowUp: return "Gentle follow-up"
        case .livePrayerMoment: return "Live prayer moment"
        case .communityQuestion: return "Community question"
        case .relevantNow: return "Relevant now"
        }
    }

    var sensitiveDisplayPrefix: String {
        switch self {
        case .inConversation: return "Current conversation"
        case .scriptureFocus: return "Scripture focus"
        case .churchPulse: return "Community reflection"
        case .gentleFollowUp, .livePrayerMoment: return "Prayer focus"
        case .sharedInYourCircles, .resonatingNearby, .bereanInsight, .communityQuestion, .relevantNow:
            return "Community reflection"
        }
    }

    var iconName: String {
        switch self {
        case .inConversation: return "text.bubble"
        case .scriptureFocus: return "book.closed"
        case .sharedInYourCircles: return "person.2"
        case .resonatingNearby: return "location"
        case .bereanInsight: return "sparkles"
        case .churchPulse: return "building.columns"
        case .gentleFollowUp: return "bookmark"
        case .livePrayerMoment: return "hands.sparkles"
        case .communityQuestion: return "bubble.left.and.bubble.right"
        case .relevantNow: return "circle.bottomhalf.filled"
        }
    }

    var priorityWeight: Int {
        switch self {
        case .livePrayerMoment: return 100
        case .scriptureFocus: return 96
        case .bereanInsight: return 92
        case .churchPulse: return 88
        case .sharedInYourCircles: return 84
        case .gentleFollowUp: return 80
        case .communityQuestion: return 78
        case .inConversation: return 74
        case .resonatingNearby: return 72
        case .relevantNow: return 68
        }
    }

    var sensitivityLevel: SensitivityLevel {
        switch self {
        case .livePrayerMoment, .scriptureFocus, .churchPulse, .gentleFollowUp:
            return .pastoral
        case .bereanInsight:
            return .low
        case .inConversation, .sharedInYourCircles, .resonatingNearby, .communityQuestion, .relevantNow:
            return .high
        }
    }

    var defaultDestination: AmenFeedContextDestinationType {
        switch self {
        case .inConversation: return .topicFeed
        case .scriptureFocus: return .scriptureCluster
        case .sharedInYourCircles: return .topicFeed
        case .resonatingNearby: return .topicFeed
        case .bereanInsight: return .bereanInsight
        case .churchPulse: return .churchPulse
        case .gentleFollowUp: return .whyThisAppeared
        case .livePrayerMoment: return .prayerMoment
        case .communityQuestion: return .postThread
        case .relevantNow: return .whyThisAppeared
        }
    }

    var fallbackCopy: String {
        switch self {
        case .inConversation: return "A thoughtful conversation is gathering around this topic."
        case .scriptureFocus: return "This connects with scripture themes people are reflecting on right now."
        case .sharedInYourCircles: return "People in your circles are sharing this topic with care."
        case .resonatingNearby: return "This is resonating in nearby faith communities."
        case .bereanInsight: return "This connects with scripture study themes you have explored recently."
        case .churchPulse: return "People in your church community are praying and reflecting around this."
        case .gentleFollowUp: return "This relates to something you chose to save or revisit."
        case .livePrayerMoment: return "There is an active prayer moment around this right now."
        case .communityQuestion: return "People are responding thoughtfully to this question."
        case .relevantNow: return "This connects with topics you have shown interest in."
        }
    }

    var minimumConfidence: Double {
        switch self {
        case .livePrayerMoment: return 0.80
        case .bereanInsight: return 0.78
        case .scriptureFocus: return 0.72
        default: return 0.72
        }
    }

    var expirationHours: Double {
        switch self {
        case .inConversation: return 24
        case .scriptureFocus: return 72
        case .sharedInYourCircles: return 48
        case .resonatingNearby: return 24
        case .bereanInsight: return 24 * 7
        case .churchPulse: return 48
        case .gentleFollowUp: return 24 * 14
        case .livePrayerMoment: return 2
        case .communityQuestion: return 48
        case .relevantNow: return 24
        }
    }
}

enum AmenFeedContextDestinationType: String, Codable {
    case topicFeed
    case scriptureCluster
    case churchPulse
    case prayerMoment
    case bereanInsight
    case postThread
    case whyThisAppeared
    case none
}

struct AmenFeedContextDestination: Codable, Equatable {
    let type: AmenFeedContextDestinationType
    let id: String?
}

struct AmenFeedContextLabel: Identifiable, Codable, Equatable {
    let id: String
    let type: AmenFeedContextType
    let title: String
    let reason: String
    let confidence: Double
    let priority: Int
    let destination: AmenFeedContextDestination
    let topicId: String?
    let verseRef: String?
    let churchId: String?
    let communityId: String?
    let expiresAt: Date?
    let isSensitive: Bool
    let isDismissible: Bool
    let analyticsId: String

    var displayPrefix: String {
        isSensitive ? type.sensitiveDisplayPrefix : type.displayPrefix
    }

    var effectiveDestination: AmenFeedContextDestination {
        if destination.type == .none {
            return AmenFeedContextDestination(type: .whyThisAppeared, id: nil)
        }
        return destination
    }

    var accessibilityText: String {
        "\(displayPrefix): \(title). Double tap to open topic."
    }
}

enum AmenFeedContextFeedbackAction: String {
    case impression
    case tap
    case dismiss
    case showLess = "show_less"
    case muteTopic = "mute_topic"
    case muteType = "mute_type"
    case hideAll = "hide_all"
    case reportIssue = "report_issue"
}

@MainActor
final class ContextLabelPreferenceStore: ObservableObject {
    static let shared = ContextLabelPreferenceStore()

    @Published private(set) var hiddenContextIds: Set<String>
    @Published private(set) var mutedContextTopicIds: Set<String>
    @Published private(set) var mutedContextTypes: Set<String>
    @Published private(set) var contextualLabelsDisabled: Bool

    private let db = Firestore.firestore()
    private let defaults = UserDefaults.standard
    private let hiddenKey = "amen.contextLabels.hiddenContextIds"
    private let mutedTopicsKey = "amen.contextLabels.mutedTopicIds"
    private let mutedTypesKey = "amen.contextLabels.mutedTypes"
    private let disabledKey = "amen.contextLabels.disabled"

    private init() {
        hiddenContextIds = Set(defaults.stringArray(forKey: hiddenKey) ?? [])
        mutedContextTopicIds = Set(defaults.stringArray(forKey: mutedTopicsKey) ?? [])
        mutedContextTypes = Set(defaults.stringArray(forKey: mutedTypesKey) ?? [])
        contextualLabelsDisabled = defaults.bool(forKey: disabledKey)
        Task { await syncFromRemote() }
    }

    func syncFromRemote() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let doc = try await db.collection("users")
                .document(uid)
                .collection("feedPreferences")
                .document("contextLabels")
                .getDocument()
            guard let data = doc.data() else { return }
            hiddenContextIds = Set(data["hiddenContextIds"] as? [String] ?? Array(hiddenContextIds))
            mutedContextTopicIds = Set(data["mutedTopicIds"] as? [String] ?? Array(mutedContextTopicIds))
            mutedContextTypes = Set(data["mutedTypes"] as? [String] ?? Array(mutedContextTypes))
            contextualLabelsDisabled = data["disabled"] as? Bool ?? contextualLabelsDisabled
            persistLocally()
        } catch {
            AmenFeedContextAnalyticsTracker.shared.trackDebug("context_label_preferences_sync_failed", metadata: [
                "reason": error.localizedDescription
            ])
        }
    }

    func hide(contextId: String) async {
        hiddenContextIds.insert(contextId)
        persistLocally()
        await saveRemote()
    }

    func mute(topicId: String) async {
        mutedContextTopicIds.insert(topicId)
        persistLocally()
        await saveRemote()
    }

    func mute(type: AmenFeedContextType) async {
        mutedContextTypes.insert(type.rawValue)
        persistLocally()
        await saveRemote()
    }

    func unmute(topicId: String) async {
        mutedContextTopicIds.remove(topicId)
        persistLocally()
        await saveRemote()
    }

    func unmute(typeRawValue: String) async {
        mutedContextTypes.remove(typeRawValue)
        persistLocally()
        await saveRemote()
    }

    func setDisabled(_ disabled: Bool) async {
        contextualLabelsDisabled = disabled
        persistLocally()
        await saveRemote()
    }

    func resetHiddenLabels() async {
        hiddenContextIds.removeAll()
        persistLocally()
        await saveRemote()
    }

    func replaceStateForTesting(
        hiddenContextIds: Set<String> = [],
        mutedContextTopicIds: Set<String> = [],
        mutedContextTypes: Set<String> = [],
        contextualLabelsDisabled: Bool = false
    ) {
        self.hiddenContextIds = hiddenContextIds
        self.mutedContextTopicIds = mutedContextTopicIds
        self.mutedContextTypes = mutedContextTypes
        self.contextualLabelsDisabled = contextualLabelsDisabled
    }

    private func persistLocally() {
        defaults.set(Array(hiddenContextIds), forKey: hiddenKey)
        defaults.set(Array(mutedContextTopicIds), forKey: mutedTopicsKey)
        defaults.set(Array(mutedContextTypes), forKey: mutedTypesKey)
        defaults.set(contextualLabelsDisabled, forKey: disabledKey)
    }

    private func saveRemote() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users")
                .document(uid)
                .collection("feedPreferences")
                .document("contextLabels")
                .setData([
                    "disabled": contextualLabelsDisabled,
                    "mutedTopicIds": Array(mutedContextTopicIds),
                    "mutedTypes": Array(mutedContextTypes),
                    "hiddenContextIds": Array(hiddenContextIds),
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
        } catch {
            AmenFeedContextAnalyticsTracker.shared.trackDebug("context_label_preferences_save_failed", metadata: [
                "reason": error.localizedDescription
            ])
        }
    }
}

@MainActor
final class ContextLabelVisibilityCoordinator: ObservableObject {
    static let shared = ContextLabelVisibilityCoordinator()

    @Published private(set) var visiblePostIds: [String] = []
    @Published private(set) var refreshNonce = UUID()
    let maxVisibleLabels = 2

    private var pendingPostIds: [String] = []

    init() {}

    func register(postId: String) -> Bool {
        if visiblePostIds.contains(postId) {
            return true
        }
        guard visiblePostIds.count < maxVisibleLabels else {
            if !pendingPostIds.contains(postId) {
                pendingPostIds.append(postId)
            }
            return false
        }
        visiblePostIds.append(postId)
        return true
    }

    func unregister(postId: String) {
        if pendingPostIds.contains(postId) {
            pendingPostIds.removeAll { $0 == postId }
            return
        }

        let wasVisible = visiblePostIds.contains(postId)
        visiblePostIds.removeAll { $0 == postId }

        guard wasVisible, let next = pendingPostIds.first else { return }
        pendingPostIds.removeFirst()
        visiblePostIds.append(next)
        refreshNonce = UUID()
    }
}

final class AmenFeedContextAnalyticsTracker {
    static let shared = AmenFeedContextAnalyticsTracker()

    private init() {}

    func track(event name: String, label: AmenFeedContextLabel, postId: String, rankPosition: Int? = nil, reasonCode: String? = nil) {
        var properties: [String: Any] = [
            "contextId": label.id,
            "contextType": label.type.rawValue,
            "topicId": label.topicId ?? "",
            "postId": postId,
            "confidence": label.confidence,
            "destinationType": label.effectiveDestination.type.rawValue,
            "feedSessionId": AmenFeedContextResolver.sessionId,
            "isSensitive": label.isSensitive
        ]
        if let rankPosition {
            properties["rankPosition"] = rankPosition
        }
        if let reasonCode {
            properties["reasonCode"] = reasonCode
        }
        Analytics.logEvent(name, parameters: properties)
    }

    func trackDebug(_ name: String, metadata: [String: Any]) {
        Analytics.logEvent(name, parameters: metadata)
    }
}

enum AmenFeedContextResolver {
    static let sessionId = UUID().uuidString
    static let recentWindow = 10

    static func resolveVisibleLabels(
        for posts: [Post],
        preferences: ContextLabelPreferenceStore,
        now: Date = Date()
    ) -> [String: AmenFeedContextLabel] {
        guard !preferences.contextualLabelsDisabled else { return [:] }

        let orderedPosts = posts.enumerated().sorted { lhs, rhs in
            let leftPriority = lhs.element.feedContext?.priority ?? lhs.element.feedContext?.type.priorityWeight ?? 0
            let rightPriority = rhs.element.feedContext?.priority ?? rhs.element.feedContext?.type.priorityWeight ?? 0
            if leftPriority == rightPriority {
                return lhs.offset < rhs.offset
            }
            return leftPriority > rightPriority
        }

        var occupiedIndexes = Set<Int>()
        var recentTopicIds: [String] = []
        var recentTypes: [AmenFeedContextType: Int] = [:]
        var results: [String: AmenFeedContextLabel] = [:]

        for entry in orderedPosts {
            let index = entry.offset
            let post = entry.element

            guard let label = post.feedContext else { continue }
            guard isEligible(label: label, for: post, preferences: preferences, now: now) else { continue }
            guard !occupiedIndexes.contains(index - 1), !occupiedIndexes.contains(index + 1) else {
                AmenFeedContextAnalyticsTracker.shared.track(event: "context_label_suppressed_duplicate", label: label, postId: post.contextStableId, rankPosition: index, reasonCode: "adjacent")
                continue
            }
            if let topicId = label.topicId, recentTopicIds.contains(topicId) {
                AmenFeedContextAnalyticsTracker.shared.track(event: "context_label_suppressed_duplicate", label: label, postId: post.contextStableId, rankPosition: index, reasonCode: "duplicate_topic")
                continue
            }
            if let previousIndex = recentTypes[label.type], index - previousIndex < recentWindow {
                AmenFeedContextAnalyticsTracker.shared.track(event: "context_label_suppressed_duplicate", label: label, postId: post.contextStableId, rankPosition: index, reasonCode: "duplicate_type")
                continue
            }

            results[post.contextStableId] = label
            occupiedIndexes.insert(index)
            recentTypes[label.type] = index
            if let topicId = label.topicId {
                recentTopicIds.append(topicId)
                if recentTopicIds.count > recentWindow {
                    recentTopicIds.removeFirst(recentTopicIds.count - recentWindow)
                }
            }
        }

        return results
    }

    static func isEligible(
        label: AmenFeedContextLabel,
        for post: Post,
        preferences: ContextLabelPreferenceStore,
        now: Date = Date()
    ) -> Bool {
        guard !preferences.hiddenContextIds.contains(label.id) else { return false }
        guard !preferences.mutedContextTypes.contains(label.type.rawValue) else { return false }
        if let topicId = label.topicId, preferences.mutedContextTopicIds.contains(topicId) {
            return false
        }
        guard !label.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            AmenFeedContextAnalyticsTracker.shared.trackDebug("context_label_malformed", metadata: [
                "contextId": label.id,
                "reasonCode": "missing_title"
            ])
            return false
        }
        guard !isVagueTitle(label.title), !looksLikeEngagementBait(label.title), !looksLikeEngagementBait(label.reason) else {
            return false
        }
        guard label.confidence >= label.type.minimumConfidence else {
            AmenFeedContextAnalyticsTracker.shared.track(event: "context_label_suppressed_low_confidence", label: label, postId: post.contextStableId, reasonCode: "confidence")
            return false
        }
        if label.isSensitive {
            guard label.confidence >= 0.86, isAllowedSensitiveType(label.type) else {
                AmenFeedContextAnalyticsTracker.shared.track(event: "context_label_suppressed_sensitive", label: label, postId: post.contextStableId, reasonCode: "sensitive")
                return false
            }
        }
        if let expiresAt = label.expiresAt, expiresAt < now {
            return false
        }
        guard !post.lowTrustAuthor else { return false }
        guard !post.flaggedForReview, !post.removed else { return false }
        return true
    }

    private static func looksLikeEngagementBait(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let bannedPhrases = [
            "trending",
            "viral",
            "breaking",
            "exploding",
            "everyone is talking about",
            "hot topic"
        ]
        return bannedPhrases.contains(where: lowered.contains)
    }

    private static func isVagueTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let vague = ["update", "discussion", "topic", "news", "thoughts"]
        return trimmed.count < 3 || vague.contains(trimmed.lowercased())
    }

    private static func isAllowedSensitiveType(_ type: AmenFeedContextType) -> Bool {
        switch type {
        case .inConversation, .scriptureFocus, .churchPulse, .gentleFollowUp, .livePrayerMoment:
            return true
        default:
            return false
        }
    }
}

struct AmenFeedContextLabelModifier: ViewModifier {
    let label: AmenFeedContextLabel?
    let postId: String
    let onTap: () -> Void
    let onLongPress: () -> Void

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label {
                AmenFeedContextLabelView(
                    label: label,
                    postId: postId,
                    onTap: onTap,
                    onLongPress: onLongPress
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
            content
        }
    }
}

extension View {
    func amenFeedContextLabel(
        _ label: AmenFeedContextLabel?,
        postId: String,
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void
    ) -> some View {
        modifier(AmenFeedContextLabelModifier(label: label, postId: postId, onTap: onTap, onLongPress: onLongPress))
    }
}

struct AmenFeedContextLabelView: View {
    let label: AmenFeedContextLabel
    let postId: String
    let onTap: () -> Void
    let onLongPress: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var visibilityCoordinator = ContextLabelVisibilityCoordinator.shared
    @State private var isVisible = false

    var body: some View {
        Group {
            if isVisible {
                Button(action: onTap) {
                    HStack(spacing: 6) {
                        Image(systemName: label.type.iconName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.7))
                            .accessibilityHidden(true)
                        (
                            Text("\(label.displayPrefix): ")
                                .font(.system(size: 12, weight: .medium))
                            +
                            Text(label.title)
                                .font(.system(size: 12, weight: .semibold))
                        )
                        .foregroundStyle(Color.black.opacity(0.88))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.78))
                            .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.black.opacity(0.05), lineWidth: 0.6)
                            )
                    )
                }
                .buttonStyle(.liquidGlass)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .onEnded { _ in onLongPress() }
                )
                .contextMenu {
                    Button("Why am I seeing this?") { onLongPress() }
                }
                .accessibilityLabel(label.accessibilityText)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: Text("Why am I seeing this?"), onLongPress)
                .transition(
                    reduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
                )
                .task {
                    isVisible = visibilityCoordinator.register(postId: postId)
                    if isVisible {
                        AmenFeedContextAnalyticsTracker.shared.track(
                            event: "context_label_impression",
                            label: label,
                            postId: postId
                        )
                    }
                }
                .onDisappear {
                    visibilityCoordinator.unregister(postId: postId)
                }
            }
        }
    }
}

struct AmenFeedContextActionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let label: AmenFeedContextLabel
    let onWhy: () -> Void
    let onShowLess: () -> Void
    let onMuteTopic: () -> Void
    let onHideAll: () -> Void
    let onReportIssue: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Button("Why am I seeing this?", action: fire(onWhy))
                Button("Show less like this", action: fire(onShowLess))
                Button("Not interested in this topic", action: fire(onMuteTopic))
                Button("Hide context labels", action: fire(onHideAll))
                Button("Report context label issue", role: .destructive, action: fire(onReportIssue))
            }
            .listStyle(.insetGrouped)
            .navigationTitle(label.displayPrefix)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationCornerRadius(24)
        .presentationBackground(.regularMaterial)
    }

    private func fire(_ action: @escaping () -> Void) -> () -> Void {
        {
            dismiss()
            action()
        }
    }
}

struct WhyThisAppearedSheet: View {
    @Environment(\.dismiss) private var dismiss

    let post: Post
    let label: AmenFeedContextLabel
    let onShowLess: () -> Void
    let onMuteTopic: () -> Void
    let onHideAll: () -> Void

    private var signalBullets: [String] {
        var items: [String] = []
        switch label.type {
        case .scriptureFocus:
            items.append("This connects with scripture themes people are reflecting on.")
        case .sharedInYourCircles, .churchPulse:
            items.append("People in your community are engaging with this thoughtfully.")
        case .gentleFollowUp, .bereanInsight:
            items.append("This connects with topics you have shown interest in.")
        case .livePrayerMoment:
            items.append("There is an active prayer response around this right now.")
        default:
            items.append("This topic is surfacing with meaningful engagement.")
        }
        if let verseRef = label.verseRef, !verseRef.isEmpty {
            items.append("It connects with \(verseRef).")
        }
        if label.topicId != nil {
            items.append("This relates to a topic already present in your feed journey.")
        }
        return Array(items.prefix(3))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(label.displayPrefix): \(label.title)")
                        .font(AMENFont.bold(20))
                        .foregroundStyle(.primary)
                    Text(label.reason.isEmpty ? label.type.fallbackCopy : label.reason)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(signalBullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5, weight: .semibold))
                                .padding(.top, 6)
                                .foregroundStyle(.secondary)
                            Text(bullet)
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.primary.opacity(0.8))
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.75))
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
                )

                VStack(spacing: 10) {
                    quietActionButton(title: "Show less like this", action: onShowLess)
                    quietActionButton(title: "Not interested in this topic", action: onMuteTopic)
                    quietActionButton(title: "Hide labels", action: onHideAll)

                    Button("Done") { dismiss() }
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Why this appeared")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(28)
        .presentationBackground(.regularMaterial)
    }

    private func quietActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button {
            dismiss()
            action()
        } label: {
            Text(title)
                .font(AMENFont.semiBold(14))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.82))
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial))
                )
        }
        .buttonStyle(.liquidGlass)
    }
}
