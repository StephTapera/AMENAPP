// AmenHubFeedView.swift
// AMEN Connect — Amen Hub (Activity feed, inverted ergonomics)
//
// Replaces the Slack-style Activity tab.
// Loss function: convert attention into action and embodied relationship, then get out of the way.
// Design rules:
//   • Items are living objects (pray / discuss / schedule / help inline)
//   • Berean smart collapse: "N things need you" when inbox is dense
//   • Ends in "You're caught up" + a benediction — no infinite scroll, no anxiety reel
//   • Batched digest by default; real-time only for Covenant Circle + true care escalation
//   • No read-receipt weaponization, no comparative metrics

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Tab model

enum AmenHubTab: String, CaseIterable, Identifiable {
    case all      = "All"
    case dms      = "DMs"
    case spaces   = "Spaces"
    case prayer   = "Prayer"
    case events   = "Events"
    case care     = "Care"
    case mentions = "Mentions"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all:      return "tray.full"
        case .dms:      return "bubble.left.and.bubble.right"
        case .spaces:   return "person.3"
        case .prayer:   return "hands.sparkles"
        case .events:   return "calendar"
        case .care:     return "heart.text.square"
        case .mentions: return "at"
        }
    }
}

// MARK: - Living object model

enum ConnectHubItemKind: String, Codable {
    case dm
    case spaceMessage
    case prayerRequest
    case event
    case careAlert
    case mention
    case reaction
    case testimony
    case need
}

/// Inline actions a user can take directly from the hub — the "living object" mechanic.
enum ConnectHubItemAction: String, Identifiable {
    case pray     = "Pray"
    case discuss  = "Discuss"
    case schedule = "Schedule"
    case help     = "Help"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .pray:     return "hands.sparkles"
        case .discuss:  return "bubble.left.and.text.bubble.right"
        case .schedule: return "calendar.badge.plus"
        case .help:     return "person.wave.2"
        }
    }
    var accent: Color {
        switch self {
        case .pray:     return Color.amenPurple
        case .discuss:  return Color.accentColor
        case .schedule: return Color.amenBlue
        case .help:     return .orange
        }
    }
}

struct ConnectHubItem: Identifiable {
    let id: String
    let kind: ConnectHubItemKind
    let actorName: String
    let actorInitials: String
    let preview: String
    let spaceName: String?
    let timestamp: Date
    var isRead: Bool
    let actions: [ConnectHubItemAction]
    let isCareAlert: Bool   // routes to human, never auto-resolved by AI
    let isCovenantCircle: Bool  // bypasses digest batching
}

// MARK: - ViewModel

@MainActor
final class AmenHubFeedViewModel: ObservableObject {
    @Published var selectedTab: AmenHubTab = .all
    @Published var items: [ConnectHubItem] = []
    @Published var isBereanSummaryExpanded: Bool = false
    @Published var isLoading: Bool = false

    /// When density is high, Berean surfaces the 3 items that actually need the user.
    var bereanPriorityItems: [ConnectHubItem] {
        let urgent = items.filter { !$0.isRead && ($0.isCareAlert || $0.isCovenantCircle) }
        let unread  = items.filter { !$0.isRead && !$0.isCareAlert && !$0.isCovenantCircle }
        return Array((urgent + unread).prefix(3))
    }

    var shouldShowBereanBanner: Bool {
        filteredItems.filter({ !$0.isRead }).count > 5
    }

    var isCaughtUp: Bool {
        filteredItems.allSatisfy { $0.isRead }
    }

    var filteredItems: [ConnectHubItem] {
        switch selectedTab {
        case .all:      return items
        case .dms:      return items.filter { $0.kind == .dm }
        case .spaces:   return items.filter { $0.kind == .spaceMessage }
        case .prayer:   return items.filter { $0.kind == .prayerRequest }
        case .events:   return items.filter { $0.kind == .event }
        case .care:     return items.filter { $0.isCareAlert }
        case .mentions: return items.filter { $0.kind == .mention }
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()

        do {
            // Fetch user's space IDs
            let memberDocs = try await db.collection("spaces")
                .whereField("memberIds", arrayContains: uid)
                .limit(to: 20)
                .getDocuments()

            var loaded: [ConnectHubItem] = []
            for spaceDoc in memberDocs.documents {
                let spaceId = spaceDoc.documentID
                let spaceName = spaceDoc["name"] as? String
                let msgDocs = try await db.collection("spaces")
                    .document(spaceId)
                    .collection("messages")
                    .order(by: "createdAt", descending: true)
                    .limit(to: 10)
                    .getDocuments()

                for doc in msgDocs.documents {
                    let data = doc.data()
                    let senderId = data["senderId"] as? String ?? ""
                    let preview = data["text"] as? String ?? ""
                    let ts = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    let careAlert = data["isCareAlert"] as? Bool ?? false
                    let ccItem   = data["isCovenantCircle"] as? Bool ?? false
                    let kindRaw  = data["kind"] as? String ?? "spaceMessage"
                    let kind     = ConnectHubItemKind(rawValue: kindRaw) ?? .spaceMessage
                    let initials = String(senderId.prefix(2)).uppercased()
                    loaded.append(ConnectHubItem(
                        id: doc.documentID,
                        kind: kind,
                        actorName: senderId,
                        actorInitials: initials,
                        preview: preview,
                        spaceName: spaceName,
                        timestamp: ts,
                        isRead: false,
                        actions: careAlert ? [.pray, .help, .schedule] : [.pray, .discuss],
                        isCareAlert: careAlert,
                        isCovenantCircle: ccItem
                    ))
                }
            }
            items = loaded.sorted { $0.timestamp > $1.timestamp }
        } catch {
            // Firestore unavailable — show empty "caught up" state rather than stale mock data
            items = []
        }
    }

    func markRead(_ item: ConnectHubItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isRead = true
    }

    func markAllRead() {
        for idx in items.indices { items[idx].isRead = true }
    }

    // MARK: - Mock data (preview / first-run)

    private static func mockItems() -> [ConnectHubItem] {
        [
            ConnectHubItem(
                id: "h1",
                kind: .prayerRequest,
                actorName: "Marcus Williams",
                actorInitials: "MW",
                preview: "Please pray for my family — we're going through a difficult season with my father's health.",
                spaceName: "Small Group — Psalm 119",
                timestamp: Date().addingTimeInterval(-1800),
                isRead: false,
                actions: [.pray, .help, .schedule],
                isCareAlert: false,
                isCovenantCircle: false
            ),
            ConnectHubItem(
                id: "h2",
                kind: .careAlert,
                actorName: "Jordan Chen",
                actorInitials: "JC",
                preview: "I lost my job today. Really struggling.",
                spaceName: "Inner Circle",
                timestamp: Date().addingTimeInterval(-3600),
                isRead: false,
                actions: [.pray, .help, .schedule],
                isCareAlert: true,
                isCovenantCircle: true
            ),
            ConnectHubItem(
                id: "h3",
                kind: .dm,
                actorName: "Pastor Sarah",
                actorInitials: "PS",
                preview: "Wanted to check in — how are you doing this week?",
                spaceName: nil,
                timestamp: Date().addingTimeInterval(-7200),
                isRead: false,
                actions: [.discuss, .schedule],
                isCareAlert: false,
                isCovenantCircle: true
            ),
            ConnectHubItem(
                id: "h4",
                kind: .event,
                actorName: "Worship Team",
                actorInitials: "WT",
                preview: "Sunday Worship Rehearsal · Saturday 3 PM",
                spaceName: "Sunday Worship Team",
                timestamp: Date().addingTimeInterval(-10800),
                isRead: true,
                actions: [.schedule],
                isCareAlert: false,
                isCovenantCircle: false
            ),
            ConnectHubItem(
                id: "h5",
                kind: .testimony,
                actorName: "Aisha Okonkwo",
                actorInitials: "AO",
                preview: "God answered my prayer! Sharing testimony — He provided the job.",
                spaceName: "Prayer Team",
                timestamp: Date().addingTimeInterval(-18000),
                isRead: true,
                actions: [.pray, .discuss],
                isCareAlert: false,
                isCovenantCircle: false
            ),
        ]
    }
}

// MARK: - Main View

struct AmenHubFeedView: View {
    var isEmbedded: Bool = false
    @StateObject private var vm = AmenHubFeedViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showYouMenu: Bool = false
    @State private var showPresencePicker: Bool = false

    var body: some View {
        if isEmbedded {
            hubContent
                .task { await vm.load() }
        } else {
            NavigationStack {
                hubContent
            }
            .task { await vm.load() }
        }
    }

    private var hubContent: some View {
        VStack(spacing: 0) {
            // Glass tab switcher (chrome)
            glassTabBar
            // Berean smart banner (when dense)
            if vm.shouldShowBereanBanner && !vm.isBereanSummaryExpanded {
                bereanSmartBanner
            }
            // Main feed
            if vm.isLoading {
                loadingState
            } else if vm.filteredItems.isEmpty {
                emptyState
            } else {
                feedList
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Amen Hub")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showYouMenu) {
            AmenYouMenuSheet(showPresencePicker: $showPresencePicker)
        }
        .sheet(isPresented: $showPresencePicker) {
            AmenSpiritualPresencePickerView()
        }
    }

    // MARK: - Glass tab bar

    private var glassTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(AmenHubTab.allCases) { tab in
                    tabPill(tab)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Divider().opacity(0.2) }
        }
    }

    private func tabPill(_ tab: AmenHubTab) -> some View {
        let isSelected = vm.selectedTab == tab
        return Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.01) : .spring(response: 0.3, dampingFraction: 0.8)) {
                vm.selectedTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.caption.weight(.semibold))
                Text(tab.rawValue)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color(uiColor: .secondarySystemBackground))
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel("\(tab.rawValue) tab")
    }

    // MARK: - Berean smart banner

    private var bereanSmartBanner: some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.01) : .easeInOut(duration: 0.2)) {
                vm.isBereanSummaryExpanded = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.amenPurple)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Berean sees \(vm.bereanPriorityItems.count) things that need you")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Tap to focus on what matters most")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemBackground))
            .overlay(alignment: .bottom) { Divider().opacity(0.2) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Berean sees \(vm.bereanPriorityItems.count) items that need your attention. Tap to see them.")
    }

    // MARK: - Feed list

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if vm.isBereanSummaryExpanded {
                    bereanPrioritySection
                }
                let displayItems = vm.isBereanSummaryExpanded
                    ? vm.bereanPriorityItems
                    : vm.filteredItems
                ForEach(displayItems) { item in
                    ConnectHubItemRow(item: item) {
                        vm.markRead(item)
                    }
                    Divider()
                        .padding(.leading, 72)
                        .opacity(0.4)
                }
                // "You're caught up" end state
                caughtUpEndState
            }
        }
    }

    private var bereanPrioritySection: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.amenPurple)
            Text("Berean's focus list")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Show all") {
                withAnimation(reduceMotion ? .easeOut(duration: 0.01) : .easeInOut(duration: 0.2)) {
                    vm.isBereanSummaryExpanded = false
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.amenPurple.opacity(0.07))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Berean focus list — showing \(vm.bereanPriorityItems.count) priority items.")
    }

    // MARK: - Caught-up end state (anti-engagement crown jewel)

    private var caughtUpEndState: some View {
        VStack(spacing: 16) {
            if vm.isCaughtUp {
                Divider().padding(.horizontal, 40).opacity(0.3)
                Image(systemName: "checkmark.circle.fill")
                    .font(.systemScaled(28))
                    .foregroundStyle(Color.accentColor.opacity(0.6))
                Text("You're caught up")
                    .font(.headline)
                    .foregroundStyle(.primary)
                // Benediction — rotates daily in production
                Text("\"The Lord bless you and keep you; the Lord make his face shine on you.\"")
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Text("Numbers 6:24–25")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Divider().padding(.horizontal, 40).opacity(0.3)
                Button(action: { vm.markAllRead() }) {
                    Text("Mark all as read")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Loading / empty

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading your Amen Hub…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.systemScaled(36))
                .foregroundStyle(.tertiary)
            Text("Nothing here yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Messages, prayers, and events from your Spaces and Covenant Circle will appear here.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !isEmbedded {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showYouMenu = true
                } label: {
                    // Covenant avatar placeholder
                    ZStack {
                        Circle()
                            .fill(Color.amenPurple.opacity(0.15))
                            .frame(width: 34, height: 34)
                        Text(Auth.auth().currentUser?.displayName?.prefix(1).uppercased() ?? "A")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.amenPurple)
                    }
                }
                .accessibilityLabel("Your profile and presence")
            }
        }
    }
}

// MARK: - Hub item row

private struct ConnectHubItemRow: View {
    let item: ConnectHubItem
    let onRead: () -> Void

    @State private var didTakeAction: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Avatar
                avatarView
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    headerRow
                    Text(item.preview)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let space = item.spaceName {
                        Text(space)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // Care alert badge
                    if item.isCareAlert {
                        careAlertBadge
                    }
                }
                Spacer(minLength: 0)
                // Unread dot
                if !item.isRead {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture { onRead() }
            // Living object inline actions
            if !item.actions.isEmpty {
                actionChipRow
                    .padding(.leading, 60)
                    .padding(.bottom, 10)
            }
        }
        .background(item.isRead
            ? Color.clear
            : Color.accentColor.opacity(0.04))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(item.isCareAlert ? Color.amenBlue.opacity(0.2) : Color(uiColor: .secondarySystemBackground))
                .frame(width: 44, height: 44)
            if item.isCareAlert {
                Image(systemName: "heart.text.square.fill")
                    .font(.title3)
                    .foregroundStyle(Color.amenBlue)
            } else {
                Text(item.actorInitials)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if item.isCovenantCircle {
                Image(systemName: "heart.fill")
                    .font(.systemScaled(10))
                    .foregroundStyle(Color.amenPurple)
                    .background(
                        Circle().fill(Color(uiColor: .systemBackground)).padding(-2)
                    )
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text(item.actorName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text(item.timestamp, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var careAlertBadge: some View {
        Label("Care alert — routed to pastoral team", systemImage: "heart.text.square.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.amenBlue)
            .padding(.top, 2)
    }

    private var actionChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(item.actions) { action in
                    Button {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.01) : .spring(response: 0.3)) {
                            didTakeAction = true
                        }
                    } label: {
                        Label(action.rawValue, systemImage: action.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(action.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(action.accent.opacity(0.12))
                            .clipShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(action.rawValue) in response to \(item.actorName)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 2)
        }
    }

    private var accessibilityLabel: String {
        var parts = [item.actorName, item.preview]
        if let space = item.spaceName { parts.append("in \(space)") }
        if item.isCareAlert { parts.append("Care alert") }
        if !item.isRead { parts.append("Unread") }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Preview

#Preview {
    AmenHubFeedView()
}
