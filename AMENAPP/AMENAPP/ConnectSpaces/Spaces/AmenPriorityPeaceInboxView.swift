// AmenPriorityPeaceInboxView.swift
// AMEN Spaces — Agent 4: Spaces Intelligence
//
// Priority & Peace inbox for a space.
// Glass shell with amenPurple header.
// 7 collapsible sections. Each section may derive from DerivedItem or Message arrays.
// Empty state: matte "All clear ✦" in amenGold.

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Design Tokens

private extension Color {
    static let amenGold   = Color(hex: "#D9A441")
    static let amenPurple = Color(hex: "#6E4BB5")
    static let amenBlue   = Color(hex: "#245B8F")
    static let amenBlack  = Color(hex: "#070607")

    init(hex: String) {
        let stripped = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: stripped).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Inbox ViewModel

@MainActor
final class AmenPriorityPeaceInboxViewModel: ObservableObject {
    @Published var needsResponse: [AmenConnectSpacesDerivedItem] = []
    @Published var mentions: [AmenConnectSpacesMessage] = []
    @Published var prayerForMe: [AmenConnectSpacesDerivedItem] = []
    @Published var ministriesAtRisk: [AmenConnectSpacesDerivedItem] = []
    @Published var waitingOnMe: [AmenConnectSpacesDerivedItem] = []
    @Published var fyiItems: [AmenConnectSpacesDerivedItem] = []
    @Published var canIgnore: [AmenConnectSpacesDerivedItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()

    func load(spaceId: String, userId: String,
              preloadedItems: [AmenConnectSpacesDerivedItem]? = nil,
              preloadedMessages: [AmenConnectSpacesMessage]? = nil) async {

        guard Auth.auth().currentUser != nil else { return }
        isLoading = true
        errorMessage = nil

        do {
            let items: [AmenConnectSpacesDerivedItem]
            let messages: [AmenConnectSpacesMessage]

            if let pi = preloadedItems {
                items = pi
            } else {
                let snap = try await db
                    .collection(AmenConnectSpacesFirestoreBinding.spacesCollection)
                    .document(spaceId)
                    .collection(AmenConnectSpacesFirestoreBinding.itemsSubcollection)
                    .getDocuments()
                items = snap.documents.compactMap { try? AmenConnectSpacesFirestoreBinding.bindDerivedItem($0) }
            }

            if let pm = preloadedMessages {
                messages = pm
            } else {
                let snap = try await db
                    .collection(AmenConnectSpacesFirestoreBinding.spacesCollection)
                    .document(spaceId)
                    .collection(AmenConnectSpacesFirestoreBinding.messagesSubcollection)
                    .getDocuments()
                messages = snap.documents.compactMap { try? AmenConnectSpacesFirestoreBinding.bindMessage($0) }
            }

            // 1. Needs my response: items with task/decision intents where owner == userId
            needsResponse = items.filter {
                ($0.kind == .task || $0.kind == .decision) &&
                $0.owner == userId &&
                $0.status != .done &&
                $0.status != .archived
            }

            // 2. Mentions: messages containing userId (stub — requires server-side index)
            mentions = messages.filter { $0.body.contains(userId) }

            // 3. Prayer for me: items where kind == .prayer && owner == userId
            prayerForMe = items.filter { $0.kind == .prayer && $0.owner == userId }

            // 4. My ministries at risk: items where kind == .risk
            ministriesAtRisk = items.filter { $0.kind == .risk }

            // 5. Waiting on me: kind == .task && status == .waiting && owner == userId
            waitingOnMe = items.filter {
                $0.kind == .task && $0.status == .waiting && $0.owner == userId
            }

            // 6. FYI: kind == .careFollowUp
            fyiItems = items.filter { $0.kind == .careFollowUp }

            // 7. Can ignore: status == .archived
            canIgnore = items.filter { $0.status == .archived }

        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Section Header (collapsible, glass chevron)

private struct InboxSectionHeader: View {
    let title: String
    let count: Int
    let tint: Color
    @Binding var isExpanded: Bool

    var body: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.20)) { isExpanded.toggle() } }) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.78))

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(tint.opacity(0.20))
                                .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
                        )
                        .foregroundStyle(tint)
                }

                Spacer()

                // Glass chevron
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .padding(6)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) items, \(isExpanded ? "expanded" : "collapsed")")
        .accessibilityHint("Double-tap to \(isExpanded ? "collapse" : "expand")")
    }
}

// MARK: - Empty State

private struct InboxEmptyState: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("All clear ✦")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.amenGold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
        .accessibilityLabel("All clear")
    }
}

// MARK: - Derived Item Inbox Row

private struct InboxDerivedItemRow: View {
    let item: AmenConnectSpacesDerivedItem
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(tint.opacity(0.25))
                .frame(width: 3)
                .frame(height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(2)

                if let owner = item.owner {
                    Text(owner)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.38))
                }
            }

            Spacer()

            if let due = item.due {
                Text(due.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.38))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            // Matte row background
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
        .accessibilityLabel("\(item.title)\(item.owner.map { ", owner: \($0)" } ?? "")")
    }
}

// MARK: - Message Inbox Row (mentions)

private struct InboxMessageRow: View {
    let message: AmenConnectSpacesMessage

    var body: some View {
        HStack(spacing: 10) {
            Text(message.body)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.80))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
        .accessibilityLabel("Mention: \(message.body.prefix(80))")
    }
}

// MARK: - Inbox Section

private struct InboxSection<RowContent: View>: View {
    let title: String
    let count: Int
    let tint: Color
    let isExpanded: Binding<Bool>
    let isEmpty: Bool
    @ViewBuilder let rows: () -> RowContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InboxSectionHeader(
                title: title,
                count: count,
                tint: tint,
                isExpanded: isExpanded
            )

            if isExpanded.wrappedValue {
                if isEmpty {
                    InboxEmptyState()
                } else {
                    rows()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - AmenPriorityPeaceInboxView

struct AmenPriorityPeaceInboxView: View {
    let spaceId: String
    let userId: String

    /// Optional: caller may pre-supply items/messages to avoid extra Firestore round-trips.
    var preloadedItems: [AmenConnectSpacesDerivedItem]? = nil
    var preloadedMessages: [AmenConnectSpacesMessage]? = nil

    @StateObject private var viewModel = AmenPriorityPeaceInboxViewModel()

    // Per-section expansion state (all start expanded)
    @State private var s1Expanded = true
    @State private var s2Expanded = true
    @State private var s3Expanded = true
    @State private var s4Expanded = true
    @State private var s5Expanded = true
    @State private var s6Expanded = false
    @State private var s7Expanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Glass header with amenPurple
            HStack {
                Text("Priority & Peace")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.95))
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(Color.amenPurple)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                // Glass header — chrome surface
                Rectangle()
                    .fill(Color.amenPurple.opacity(0.18))
                    .overlay(
                        Rectangle()
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundStyle(Color.amenPurple.opacity(0.35))
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    )
            )

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.amenGold.opacity(0.80))
                    .padding()
            }

            // Sections
            ScrollView {
                VStack(spacing: 0) {
                    sectionDivider

                    // 1. Needs my response
                    InboxSection(
                        title: "Needs my response",
                        count: viewModel.needsResponse.count,
                        tint: Color.amenBlue,
                        isExpanded: $s1Expanded,
                        isEmpty: viewModel.needsResponse.isEmpty
                    ) {
                        VStack(spacing: 6) {
                            ForEach(viewModel.needsResponse) { item in
                                InboxDerivedItemRow(item: item, tint: Color.amenBlue)
                            }
                        }
                    }

                    sectionDivider

                    // 2. Mentions (stub: empty state)
                    InboxSection(
                        title: "Mentions",
                        count: viewModel.mentions.count,
                        tint: Color.amenPurple,
                        isExpanded: $s2Expanded,
                        isEmpty: viewModel.mentions.isEmpty
                    ) {
                        VStack(spacing: 6) {
                            ForEach(viewModel.mentions) { msg in
                                InboxMessageRow(message: msg)
                            }
                        }
                    }

                    sectionDivider

                    // 3. Prayer for me
                    InboxSection(
                        title: "Prayer for me",
                        count: viewModel.prayerForMe.count,
                        tint: Color.amenGold,
                        isExpanded: $s3Expanded,
                        isEmpty: viewModel.prayerForMe.isEmpty
                    ) {
                        VStack(spacing: 6) {
                            ForEach(viewModel.prayerForMe) { item in
                                InboxDerivedItemRow(item: item, tint: Color.amenGold)
                            }
                        }
                    }

                    sectionDivider

                    // 4. My ministries at risk
                    InboxSection(
                        title: "My ministries at risk",
                        count: viewModel.ministriesAtRisk.count,
                        tint: Color.amenGold,
                        isExpanded: $s4Expanded,
                        isEmpty: viewModel.ministriesAtRisk.isEmpty
                    ) {
                        VStack(spacing: 6) {
                            ForEach(viewModel.ministriesAtRisk) { item in
                                InboxDerivedItemRow(item: item, tint: Color.amenGold)
                            }
                        }
                    }

                    sectionDivider

                    // 5. Waiting on me
                    InboxSection(
                        title: "Waiting on me",
                        count: viewModel.waitingOnMe.count,
                        tint: Color.amenBlue,
                        isExpanded: $s5Expanded,
                        isEmpty: viewModel.waitingOnMe.isEmpty
                    ) {
                        VStack(spacing: 6) {
                            ForEach(viewModel.waitingOnMe) { item in
                                InboxDerivedItemRow(item: item, tint: Color.amenBlue)
                            }
                        }
                    }

                    sectionDivider

                    // 6. FYI
                    InboxSection(
                        title: "FYI",
                        count: viewModel.fyiItems.count,
                        tint: Color(hex: "#5DD178"),
                        isExpanded: $s6Expanded,
                        isEmpty: viewModel.fyiItems.isEmpty
                    ) {
                        VStack(spacing: 6) {
                            ForEach(viewModel.fyiItems) { item in
                                InboxDerivedItemRow(item: item, tint: Color(hex: "#5DD178"))
                            }
                        }
                    }

                    sectionDivider

                    // 7. Can ignore
                    InboxSection(
                        title: "Can ignore",
                        count: viewModel.canIgnore.count,
                        tint: Color.white.opacity(0.30),
                        isExpanded: $s7Expanded,
                        isEmpty: viewModel.canIgnore.isEmpty
                    ) {
                        VStack(spacing: 6) {
                            ForEach(viewModel.canIgnore) { item in
                                InboxDerivedItemRow(item: item, tint: Color.white.opacity(0.25))
                            }
                        }
                    }
                }
            }
        }
        .background(
            // Glass shell
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.amenPurple.opacity(0.25), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .task {
            await viewModel.load(
                spaceId: spaceId,
                userId: userId,
                preloadedItems: preloadedItems,
                preloadedMessages: preloadedMessages
            )
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
    }
}

// MARK: - Preview

#if DEBUG
private let previewItems: [AmenConnectSpacesDerivedItem] = [
    AmenConnectSpacesDerivedItem(
        id: "i1", kind: .task, title: "Review Sunday logistics",
        owner: "preview-user", due: Date().addingTimeInterval(3600 * 48),
        status: .open, sourceMsgId: "m1", createdAt: Date(), updatedAt: Date()
    ),
    AmenConnectSpacesDerivedItem(
        id: "i2", kind: .prayer, title: "Pray for James' health",
        owner: "preview-user", due: nil,
        status: .open, sourceMsgId: "m2", createdAt: Date(), updatedAt: Date()
    ),
    AmenConnectSpacesDerivedItem(
        id: "i3", kind: .risk, title: "AV system backup needed",
        owner: nil, due: nil,
        status: .open, sourceMsgId: "m3", createdAt: Date(), updatedAt: Date()
    ),
    AmenConnectSpacesDerivedItem(
        id: "i4", kind: .careFollowUp, title: "Follow up with Maria",
        owner: nil, due: nil,
        status: .open, sourceMsgId: "m4", createdAt: Date(), updatedAt: Date()
    ),
    AmenConnectSpacesDerivedItem(
        id: "i5", kind: .task, title: "Old task",
        owner: "preview-user", due: nil,
        status: .archived, sourceMsgId: "m5", createdAt: Date(), updatedAt: Date()
    )
]

#Preview {
    AmenPriorityPeaceInboxView(
        spaceId: "demo-space",
        userId: "preview-user",
        preloadedItems: previewItems,
        preloadedMessages: []
    )
    .padding()
    .background(Color(hex: "#070607"))
}
#endif
