// SuggestedForYouModule.swift
// AMENAPP
//
// Compact "Suggested for you" horizontal rail — injected after the 3rd post
// in OpenTable (Everyone mode). Threads/Instagram density, AMEN Liquid Glass style.
//
// Architecture:
//   SuggestedForYouModule        — section container (hide/show, header, rail)
//   SuggestionCard               — individual compact card
//   SuggestionSkeletonCard       — loading placeholder
//   SuggestionsViewModel         — fetch, follow, dismiss, hide/show state
//   SuggestionsService           — Firestore fetch + ranking

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Model

enum SuggestionAccountType: String {
    case personal, church, creator, business, ministry, official
    var badge: String? {
        switch self {
        case .church:    return "Church"
        case .creator:   return "Creator"
        case .ministry:  return "Ministry"
        case .business:  return "Business"
        case .official:  return nil
        case .personal:  return nil
        }
    }
}

struct SuggestionItem: Identifiable {
    let id: String
    let displayName: String
    let handle: String
    let avatarURL: String?
    let isVerified: Bool
    let accountType: SuggestionAccountType
    let reasonText: String          // "3 mutuals follow", "Near you", etc.
    let mutualCount: Int            // 0 = not shown
    let distanceText: String?       // churches only

    // Initials fallback
    var initials: String {
        displayName.components(separatedBy: " ")
            .compactMap { $0.first }
            .map { String($0) }
            .joined()
            .prefix(2)
            .uppercased()
    }
}

// MARK: - Analytics hooks (fire-and-forget stubs — wire to real analytics later)

private func trackSuggestionEvent(_ name: String, id: String) {
    // e.g. AnalyticsService.shared.log(name, parameters: ["user_id": id])
}

// MARK: - Service

@MainActor
final class SuggestionsService {
    static let shared = SuggestionsService()
    private let db = Firestore.firestore()

    func fetchSuggestions(limit: Int = 12) async -> [SuggestionItem] {
        guard let currentUID = Auth.auth().currentUser?.uid else { return [] }

        let alreadyFollowing = FollowService.shared.following
        let dismissed = SuggestionsViewModel.loadDismissed()

        do {
            // Fetch highest-follower-count users as a basic signal
            let snap = try await db.collection("users")
                .order(by: "followersCount", descending: true)
                .limit(to: limit * 3) // over-fetch to account for filtering
                .getDocuments()

            var items: [SuggestionItem] = []
            for doc in snap.documents {
                let d = doc.data()
                let uid = doc.documentID
                guard uid != currentUID,
                      !alreadyFollowing.contains(uid),
                      !dismissed.contains(uid)
                else { continue }

                let displayName = d["displayName"] as? String
                    ?? d["username"] as? String
                    ?? "AMEN User"
                let handle = d["username"] as? String ?? uid
                let avatar = d["profileImageURL"] as? String
                    ?? d["photoURL"] as? String
                let verified = d["isVerified"] as? Bool ?? false
                let followersCount = d["followersCount"] as? Int ?? 0
                let accountTypeRaw = d["accountType"] as? String ?? "personal"
                let accountType = SuggestionAccountType(rawValue: accountTypeRaw) ?? .personal
                let mutuals = d["mutualFollowersCount"] as? Int ?? 0

                let reason = buildReason(
                    mutuals: mutuals,
                    accountType: accountType,
                    followersCount: followersCount,
                    distanceText: d["distanceText"] as? String
                )

                items.append(SuggestionItem(
                    id: uid,
                    displayName: displayName,
                    handle: handle,
                    avatarURL: avatar,
                    isVerified: verified,
                    accountType: accountType,
                    reasonText: reason,
                    mutualCount: mutuals,
                    distanceText: d["distanceText"] as? String
                ))

                if items.count == limit { break }
            }
            return items
        } catch {
            return []
        }
    }

    private func buildReason(
        mutuals: Int,
        accountType: SuggestionAccountType,
        followersCount: Int,
        distanceText: String?
    ) -> String {
        if mutuals >= 3 { return "\(mutuals) mutuals follow" }
        if mutuals > 0 { return "\(mutuals) mutual follows" }
        if let dist = distanceText, !dist.isEmpty { return dist }
        switch accountType {
        case .church:    return "Church near your community"
        case .creator:   return "Popular faith creator"
        case .ministry:  return "Active ministry"
        case .business:  return "Faith-based business"
        case .official:  return "Official AMEN account"
        case .personal:
            if followersCount > 5_000 { return "Popular in AMEN" }
            return "Suggested for you"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class SuggestionsViewModel: ObservableObject {
    @Published var items: [SuggestionItem] = []
    @Published var isLoading = true
    @Published var isModuleHidden = false
    @Published var followedIds: Set<String> = []

    private static let dismissedKey = "amen_dismissed_suggestions"
    private static let hiddenKey    = "amen_suggestions_hidden"

    init() {
        isModuleHidden = UserDefaults.standard.bool(forKey: Self.hiddenKey)
    }

    func load() async {
        guard !isModuleHidden else { isLoading = false; return }
        isLoading = true
        items = await SuggestionsService.shared.fetchSuggestions()
        isLoading = false
    }

    func dismiss(id: String) {
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.82))) {
            items.removeAll { $0.id == id }
        }
        var set = Self.loadDismissed()
        set.insert(id)
        UserDefaults.standard.set(Array(set), forKey: Self.dismissedKey)
        trackSuggestionEvent("suggestion_dismiss", id: id)
    }

    func hideModule() {
        withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.85))) {
            isModuleHidden = true
        }
        UserDefaults.standard.set(true, forKey: Self.hiddenKey)
        trackSuggestionEvent("suggestions_hide_module", id: "")
    }

    func restoreModule() {
        UserDefaults.standard.set(false, forKey: Self.hiddenKey)
        withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.85))) {
            isModuleHidden = false
        }
        trackSuggestionEvent("suggestions_restore_module", id: "")
        Task { await load() }
    }

    func follow(id: String) async {
        followedIds.insert(id) // optimistic
        trackSuggestionEvent("suggestion_follow_tap", id: id)
        do {
            try await FollowService.shared.followUser(userId: id)
            trackSuggestionEvent("suggestion_follow_success", id: id)
            // Remove from rail after short delay so user sees the state change
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.82))) {
                items.removeAll { $0.id == id }
            }
        } catch {
            followedIds.remove(id) // revert on failure
            trackSuggestionEvent("suggestion_follow_failure", id: id)
        }
    }

    static func loadDismissed() -> Set<String> {
        let stored = UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []
        return Set(stored)
    }
}

// MARK: - Module Container

struct SuggestedForYouModule: View {
    @StateObject private var vm = SuggestionsViewModel()

    var body: some View {
        Group {
            if vm.isModuleHidden {
                hiddenBanner
            } else if vm.isLoading {
                loadingRail
            } else if vm.items.isEmpty {
                EmptyView() // nothing to show
            } else {
                loadedModule
            }
        }
        .task { await vm.load() }
    }

    // MARK: Loaded state

    private var loadedModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("Suggested for you")
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    HapticManager.impact(style: .light)
                    vm.hideModule()
                } label: {
                    Text("Hide")
                        .font(.systemScaled(13, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide suggestions")
            }
            .padding(.horizontal, 16)

            // Horizontal rail
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(vm.items) { item in
                        SuggestionCard(
                            item: item,
                            isFollowing: vm.followedIds.contains(item.id),
                            onFollow: {
                                HapticManager.impact(style: .medium)
                                Task { await vm.follow(id: item.id) }
                            },
                            onDismiss: {
                                HapticManager.impact(style: .light)
                                vm.dismiss(id: item.id)
                            },
                            onOpenProfile: {
                                trackSuggestionEvent("suggestion_open_profile", id: item.id)
                                // Navigation hook — wire to ProfileView navigation if needed
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.92)),
                            removal: .opacity.combined(with: .scale(scale: 0.82))
                        ))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
        .padding(.vertical, 12)
    }

    // MARK: Loading skeleton

    private var loadingRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemFill))
                    .frame(width: 130, height: 14)
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in
                        SuggestionSkeletonCard()
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: Hidden banner

    private var hiddenBanner: some View {
        HStack(spacing: 10) {
            Text("Suggestions hidden")
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Show again") {
                HapticManager.impact(style: .light)
                vm.restoreModule()
            }
            .font(.systemScaled(13, weight: .medium))
            .foregroundStyle(.primary)
            .accessibilityLabel("Show suggestions again")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground).opacity(0.6))
        .buttonStyle(.plain)
    }
}

// MARK: - Suggestion Card

private struct SuggestionCard: View {
    let item: SuggestionItem
    let isFollowing: Bool
    let onFollow: () -> Void
    let onDismiss: () -> Void
    let onOpenProfile: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Glass card body
            cardContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.displayName), @\(item.handle). \(item.reasonText)")

            // Dismiss X
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.systemScaled(10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(Color(.systemFill))
                    )
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel("Dismiss \(item.displayName)")
        }
        .frame(width: 158)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Avatar + name block ──────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                // Avatar
                Button(action: onOpenProfile) {
                    SuggestionAvatarView(item: item, size: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View \(item.displayName)'s profile")

                // Name + verified badge
                HStack(spacing: 4) {
                    Text(item.displayName)
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if item.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.systemScaled(11))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                // Handle
                Text("@\(item.handle)")
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Reason
                Text(item.reasonText)
                    .font(.systemScaled(11))
                    .foregroundStyle(.secondary.opacity(0.85))
                    .lineLimit(1)

                // Account type badge (optional)
                if let badge = item.accountType.badge {
                    Text(badge)
                        .font(.systemScaled(10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color(.systemFill))
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Spacer(minLength: 0)

            // ── Follow button ────────────────────────────────────────────
            SuggestionFollowButton(isFollowing: isFollowing, action: onFollow)
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
        }
        .frame(width: 158, height: 200)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.60))
                )
                .overlay(
                    // Subtle top highlight
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.50), Color.clear],
                                startPoint: .top,
                                endPoint: .init(x: 0.5, y: 0.35)
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.72), lineWidth: 0.75)
                )
        }
        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Follow Button

private struct SuggestionFollowButton: View {
    let isFollowing: Bool
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                Text(isFollowing ? "Following" : "Follow")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(isFollowing ? Color.primary : Color.white)
                Spacer()
            }
            .frame(height: 32)
            .background {
                if isFollowing {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.65))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.75)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(isPressed ? 0.80 : 1.0))
                }
            }
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.80), value: isPressed)
            .animation(.spring(response: 0.25, dampingFraction: 0.80), value: isFollowing)
        }
        .buttonStyle(.plain)
        ._onButtonGesture(pressing: { isPressed = $0 }, perform: {})
        .accessibilityLabel(isFollowing ? "Following \("")" : "Follow")
        .disabled(isFollowing)
    }
}

// MARK: - Avatar View

private struct SuggestionAvatarView: View {
    let item: SuggestionItem
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(avatarBackground)
                .frame(width: size, height: size)

            if let url = item.avatarURL.flatMap(URL.init) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    default:
                        Text(item.initials)
                            .font(.systemScaled(size * 0.35, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            } else {
                Text(item.initials)
                    .font(.systemScaled(size * 0.35, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Verified ring
            if item.isVerified {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
    }

    private var avatarBackground: some ShapeStyle {
        switch item.accountType {
        case .church:    return AnyShapeStyle(LinearGradient(colors: [Color(hex: "10B981"), Color(hex: "34D399")], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .creator:   return AnyShapeStyle(LinearGradient(colors: [Color(hex: "EC4899"), Color(hex: "F472B6")], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .ministry:  return AnyShapeStyle(LinearGradient(colors: [Color(hex: "6B48FF"), Color(hex: "8B5CF6")], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .business:  return AnyShapeStyle(LinearGradient(colors: [Color(hex: "F59E0B"), Color(hex: "FBBF24")], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .official:  return AnyShapeStyle(Color.black)
        case .personal:  return AnyShapeStyle(LinearGradient(colors: [Color(.systemGray3), Color(.systemGray4)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}

// MARK: - Skeleton Card

private struct SuggestionSkeletonCard: View {
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Avatar placeholder
            Circle()
                .fill(Color(.systemFill))
                .frame(width: 44, height: 44)

            // Name placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemFill))
                .frame(width: 90, height: 12)

            // Handle placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemFill))
                .frame(width: 60, height: 10)

            // Reason placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemFill))
                .frame(width: 110, height: 10)

            Spacer(minLength: 0)

            // Button placeholder
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemFill))
                .frame(height: 32)
                .padding(.horizontal, 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: 158, height: 200)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.50), lineWidth: 0.75)
                )
        )
        .opacity(shimmer ? 0.55 : 1.0)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: shimmer)
        .onAppear { shimmer = true }
    }
}
