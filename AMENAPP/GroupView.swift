//
//  GroupView.swift
//  AMENAPP
//
//  Liquid Glass group profile page. Renders a CommunityGroup's hero,
//  description, rules, member count, and join/leave + share actions.
//  Reachable from share entities of type `.group` via deep link
//  `amenapp://group/<groupId>` (see NotificationDeepLinkRouter).
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct GroupView: View {
    let groupId: String

    @Environment(\.dismiss) private var dismiss
    @State private var group: CommunityGroup?
    @State private var memberIds: [String] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var joinInFlight = false
    @State private var scrollOffset: CGFloat = 0

    private var db: Firestore { Firestore.firestore() }

    private var currentUserId: String? { Auth.auth().currentUser?.uid }
    private var isMember: Bool {
        guard let uid = currentUserId else { return false }
        return memberIds.contains(uid)
    }
    private var isCreator: Bool {
        guard let uid = currentUserId else { return false }
        return group?.creatorId == uid
    }
    private var scrollBehavior: LiquidGlassScrollBehavior {
        LiquidGlassScrollBehavior(offset: scrollOffset, velocityHint: 0)
    }

    var body: some View {
        Group {
            if isLoading {
                loadingState
            } else if let error = loadError {
                errorState(error)
            } else if let group {
                content(for: group)
            } else {
                emptyState
            }
        }
        .navigationTitle(group?.name ?? "Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let group {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        ShareRouter.presentGroup(group, sourceSurface: "group_profile")
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .accessibilityLabel("Share group")
                    }
                }
            }
        }
        .task { await loadGroup() }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading group…")
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .font(.systemScaled(14))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task { await loadGroup() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.sequence")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Group not found")
                .font(.systemScaled(15, weight: .semibold))
            Text("This group may have been removed or is private.")
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for group: CommunityGroup) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                heroHeader(for: group)
                joinPanel(for: group)
                if !group.description.isEmpty {
                    aboutSection(description: group.description)
                }
                if !group.rules.isEmpty {
                    rulesSection(rules: group.rules)
                }
                metadataSection(for: group)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: GroupScrollOffsetPreferenceKey.self,
                            value: geo.frame(in: .named("groupScroll")).minY
                        )
                }
            )
        }
        .coordinateSpace(name: "groupScroll")
        .onPreferenceChange(GroupScrollOffsetPreferenceKey.self) { value in
            scrollOffset = value
        }
        .background(
            LinearGradient(
                colors: [
                    group.category.color.opacity(0.12),
                    Color(.systemBackground)
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        )
    }

    private func heroHeader(for group: CommunityGroup) -> some View {
        VStack(spacing: 14) {
            avatar(for: group)
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(group.name)
                        .font(.systemScaled(22, weight: .bold))
                        .multilineTextAlignment(.center)
                    if group.isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.systemScaled(13))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Private group")
                    }
                }
                Label(group.category.rawValue, systemImage: group.category.icon)
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(group.category.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(group.category.color.opacity(0.14))
                    )
            }
            HStack(spacing: 18) {
                statBlock(value: "\(group.memberCount)", label: "Members")
                Divider().frame(height: 28)
                statBlock(
                    value: group.createdAt.formatted(.dateTime.month(.abbreviated).year()),
                    label: "Since"
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .liquidGlassPanel(scrollBehavior, cornerRadius: 24)
    }

    private func avatar(for group: CommunityGroup) -> some View {
        ZStack {
            Circle()
                .fill(group.category.color.opacity(0.18))
                .frame(width: 92, height: 92)
            if let urlString = group.coverImageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: group.category.icon)
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(group.category.color)
                    }
                }
                .frame(width: 92, height: 92)
                .clipShape(Circle())
            } else {
                Image(systemName: group.category.icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(group.category.color)
            }
        }
        .overlay(
            Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1.2)
        )
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.systemScaled(16, weight: .semibold))
            Text(label)
                .font(.systemScaled(11))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
        }
    }

    private func joinPanel(for group: CommunityGroup) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await toggleMembership(for: group) }
            } label: {
                HStack(spacing: 8) {
                    if joinInFlight {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: isMember ? "checkmark.circle.fill" : "plus.circle.fill")
                    }
                    Text(joinButtonLabel)
                        .font(.systemScaled(15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule().fill(
                        isMember ? Color(.systemGray5) : group.category.color
                    )
                )
                .foregroundStyle(isMember ? Color.primary : Color.white)
            }
            .disabled(joinInFlight || isCreator)
            .accessibilityHint(
                isMember ? "Leaves this group" : "Joins this group"
            )

            Button {
                ShareRouter.presentGroup(group, sourceSurface: "group_profile_action")
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 50, height: 50)
                    .background(
                        Circle().fill(Color(.systemGray6))
                    )
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Share group")
        }
    }

    private var joinButtonLabel: String {
        if isCreator { return "You created this" }
        return isMember ? "Joined" : "Join Group"
    }

    private func aboutSection(description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("About")
            Text(description)
                .font(.systemScaled(14))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .liquidGlassPanel(scrollBehavior, cornerRadius: 20)
    }

    private func rulesSection(rules: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Group Guidelines")
            ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.systemScaled(12, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color(.systemGray5)))
                    Text(rule)
                        .font(.systemScaled(13))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .liquidGlassPanel(scrollBehavior, cornerRadius: 20)
    }

    private func metadataSection(for group: CommunityGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Details")
            metadataRow(icon: "person.3.fill", label: "Members", value: "\(group.memberCount)")
            metadataRow(
                icon: group.isPrivate ? "lock.fill" : "globe",
                label: "Visibility",
                value: group.isPrivate ? "Private" : "Public"
            )
            metadataRow(
                icon: "calendar",
                label: "Created",
                value: group.createdAt.formatted(date: .abbreviated, time: .omitted)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .liquidGlassPanel(scrollBehavior, cornerRadius: 20)
    }

    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(label)
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.systemScaled(13, weight: .medium))
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.systemScaled(12, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    // MARK: - Data

    private func loadGroup() async {
        isLoading = true
        loadError = nil
        do {
            let snapshot = try await db.collection("communityGroups")
                .document(groupId)
                .getDocument()
            guard snapshot.exists else {
                isLoading = false
                return
            }
            let decoded = try snapshot.data(as: CommunityGroup.self)
            let ids = (snapshot.data()?["memberIds"] as? [String]) ?? []
            await MainActor.run {
                self.group = decoded
                self.memberIds = ids
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.loadError = "Couldn't load this group."
                self.isLoading = false
            }
        }
    }

    private func toggleMembership(for group: CommunityGroup) async {
        guard let uid = currentUserId, !joinInFlight else { return }
        joinInFlight = true
        defer { joinInFlight = false }

        let docRef = db.collection("communityGroups").document(group.id)
        do {
            if isMember {
                try await docRef.updateData([
                    "memberIds": FieldValue.arrayRemove([uid]),
                    "memberCount": FieldValue.increment(Int64(-1))
                ])
                await MainActor.run {
                    memberIds.removeAll { $0 == uid }
                    self.group?.memberCount = max(0, (self.group?.memberCount ?? 1) - 1)
                }
            } else {
                try await docRef.updateData([
                    "memberIds": FieldValue.arrayUnion([uid]),
                    "memberCount": FieldValue.increment(Int64(1))
                ])
                await MainActor.run {
                    if !memberIds.contains(uid) { memberIds.append(uid) }
                    self.group?.memberCount = (self.group?.memberCount ?? 0) + 1
                }
            }
        } catch {
            await MainActor.run {
                loadError = "Couldn't update membership. Please try again."
            }
        }
    }
}

// MARK: - Scroll preference

private struct GroupScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
