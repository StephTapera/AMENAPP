// FindPeopleView.swift
// AMENAPP
//
// "Find People to Follow" — dedicated Liquid Glass discovery screen.
// Navigated to from:
//   • EmptyFeedView "Find People to Follow" CTA
//
// Sections:
//   From Your Church  → users sharing same church field
//   Nearby Believers  → (location-gated) users nearby
//   Friends of Friends→ 2nd-degree connections via RecommendedUsersAIService
//   New to AMEN       → recently joined users
//
// Filter pills (Liquid Glass): All | Your Church | Nearby | New to AMEN
// Search bar: filters by name/username across all sections
// Each card: 48pt avatar · display name · @username · reason chip · Follow button
//
// Design tokens: AmenTheme.Colors.amenGold / amenPurple / amenBlue / amenBlack
// Glass: .ultraThinMaterial, glassStroke border, .regularMaterial card containers
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CoreLocation
import Combine

// MARK: - Filter Scope

enum PeopleDiscoveryFilter: String, CaseIterable, Identifiable {
    case all        = "All"
    case yourChurch = "Your Church"
    case nearby     = "Nearby"
    case newToAMEN  = "New to AMEN"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all:        return "person.2"
        case .yourChurch: return "building.columns"
        case .nearby:     return "location.fill"
        case .newToAMEN:  return "sparkles"
        }
    }
}

// MARK: - Section model

struct PeopleSection: Identifiable {
    let id: PeopleDiscoveryFilter
    let title: String
    var users: [DiscoveredPerson]
    var isLoading: Bool
}

// MARK: - Person model

struct DiscoveredPerson: Identifiable {
    let id: String
    let displayName: String
    let username: String
    let profileImageURL: String?
    /// Human-readable reason chip, e.g. "Goes to First Baptist" / "1.2 km away" / "New member"
    let reasonChip: String
    let section: PeopleDiscoveryFilter
}

// MARK: - ViewModel

@MainActor
final class FindPeopleViewModel: ObservableObject {

    @Published var searchText: String = ""
    @Published var selectedFilter: PeopleDiscoveryFilter = .all
    @Published var sections: [PeopleSection] = []
    @Published var followStates: [String: Bool] = [:]
    @Published var pendingFollowIds: Set<String> = []
    @Published var hasLoaded = false
    @Published var networkError: String?
    @Published var locationDenied = false

    private var userLocation: CLLocation?
    private let db = Firestore.firestore()
    private var followCancellable: AnyCancellable?

    init() {
        followCancellable = FollowService.shared.$following
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ids in
                guard let self else { return }
                for id in ids { self.followStates[id] = true }
            }
    }

    // MARK: Computed

    var filteredSections: [PeopleSection] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return sections.compactMap { section in
            if selectedFilter != .all && section.id != selectedFilter { return nil }
            let users = query.isEmpty ? section.users : section.users.filter {
                $0.displayName.lowercased().contains(query) ||
                $0.username.lowercased().contains(query)
            }
            if users.isEmpty && !section.isLoading { return nil }
            return PeopleSection(id: section.id, title: section.title, users: users, isLoading: section.isLoading)
        }
    }

    // MARK: Load

    func loadAll() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        networkError = nil
        sections = [
            PeopleSection(id: .yourChurch, title: "From Your Church",  users: [], isLoading: true),
            PeopleSection(id: .nearby,     title: "Nearby Believers",  users: [], isLoading: true),
            PeopleSection(id: .all,        title: "Friends of Friends", users: [], isLoading: true),
            PeopleSection(id: .newToAMEN,  title: "New to AMEN",       users: [], isLoading: true),
        ]
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadChurchSection() }
            group.addTask { await self.loadFriendsOfFriends() }
            group.addTask { await self.loadNewToAMEN() }
            group.addTask { await self.loadOrRequestNearby() }
        }
    }

    func refresh() async {
        hasLoaded = false
        sections = []
        followStates = [:]
        await loadAll()
    }

    // MARK: Section loaders

    private func loadChurchSection() async {
        guard let uid = Auth.auth().currentUser?.uid else { markDone(.yourChurch, []); return }
        do {
            let meDoc = try await db.collection("users").document(uid).getDocument()
            guard let churchName = meDoc.data()?["churchName"] as? String, !churchName.isEmpty else {
                markDone(.yourChurch, [])
                return
            }
            let blocked = BlockService.shared.blockedUsers
            let snap = try await db.collection("users")
                .whereField("churchName", isEqualTo: churchName)
                .whereField("isPrivate", isEqualTo: false)
                .limit(to: 15)
                .getDocuments()
            let users: [DiscoveredPerson] = snap.documents.compactMap { doc in
                guard doc.documentID != uid, !blocked.contains(doc.documentID) else { return nil }
                let d = doc.data()
                guard d["showInDiscovery"] as? Bool ?? true else { return nil }
                return DiscoveredPerson(
                    id: doc.documentID,
                    displayName: d["displayName"] as? String ?? "Unknown",
                    username: d["username"] as? String ?? "",
                    profileImageURL: d["profileImageURL"] as? String,
                    reasonChip: "Goes to \(churchName)",
                    section: .yourChurch
                )
            }
            markDone(.yourChurch, users)
        } catch { markDone(.yourChurch, []) }
    }

    private func loadFriendsOfFriends() async {
        await RecommendedUsersAIService.shared.fetchRecommendations()
        let blocked = BlockService.shared.blockedUsers
        let users: [DiscoveredPerson] = RecommendedUsersAIService.shared.recommendations
            .filter { !blocked.contains($0.id) }
            .map { rec in
                DiscoveredPerson(
                    id: rec.id,
                    displayName: rec.name,
                    username: rec.username,
                    profileImageURL: rec.profileImageURL,
                    reasonChip: rec.matchReason.isEmpty ? "Suggested for you" : rec.matchReason,
                    section: .all
                )
            }
        markDone(.all, users)
    }

    private func loadNewToAMEN() async {
        guard let uid = Auth.auth().currentUser?.uid else { markDone(.newToAMEN, []); return }
        let blocked = BlockService.shared.blockedUsers
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else {
            markDone(.newToAMEN, [])
            return
        }
        let cutoff = Timestamp(date: cutoffDate)
        do {
            let snap = try await db.collection("users")
                .whereField("createdAt", isGreaterThan: cutoff)
                .whereField("isPrivate", isEqualTo: false)
                .order(by: "createdAt", descending: true)
                .limit(to: 15)
                .getDocuments()
            let users: [DiscoveredPerson] = snap.documents.compactMap { doc in
                guard doc.documentID != uid, !blocked.contains(doc.documentID) else { return nil }
                let d = doc.data()
                guard d["showInDiscovery"] as? Bool ?? true else { return nil }
                return DiscoveredPerson(
                    id: doc.documentID,
                    displayName: d["displayName"] as? String ?? "Unknown",
                    username: d["username"] as? String ?? "",
                    profileImageURL: d["profileImageURL"] as? String,
                    reasonChip: "New member",
                    section: .newToAMEN
                )
            }
            markDone(.newToAMEN, users)
        } catch { markDone(.newToAMEN, []) }
    }

    private func loadOrRequestNearby() async {
        let manager = CLLocationManager()
        switch manager.authorizationStatus {
        case .denied, .restricted:
            locationDenied = true
            markDone(.nearby, [])
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            markDone(.nearby, [])  // Will retry once permission is granted
        case .authorizedWhenInUse, .authorizedAlways:
            if userLocation != nil {
                await loadNearby()
            } else {
                markDone(.nearby, [])
            }
        @unknown default:
            markDone(.nearby, [])
        }
    }

    private func loadNearby() async {
        guard let loc = userLocation, let uid = Auth.auth().currentUser?.uid else {
            markDone(.nearby, [])
            return
        }
        let blocked = BlockService.shared.blockedUsers
        do {
            let snap = try await db.collection("users")
                .whereField("isPrivate", isEqualTo: false)
                .whereField("shareLocation", isEqualTo: true)
                .limit(to: 50)
                .getDocuments()
            var nearby: [DiscoveredPerson] = []
            for doc in snap.documents {
                guard doc.documentID != uid, !blocked.contains(doc.documentID) else { continue }
                let d = doc.data()
                guard d["showInDiscovery"] as? Bool ?? true else { continue }
                guard let lat = d["latitude"] as? Double, let lng = d["longitude"] as? Double else { continue }
                let dist = loc.distance(from: CLLocation(latitude: lat, longitude: lng)) / 1000
                guard dist <= 80 else { continue }
                let label = dist < 1 ? "< 1 km away" : String(format: "%.1f km away", dist)
                nearby.append(DiscoveredPerson(
                    id: doc.documentID,
                    displayName: d["displayName"] as? String ?? "Unknown",
                    username: d["username"] as? String ?? "",
                    profileImageURL: d["profileImageURL"] as? String,
                    reasonChip: label,
                    section: .nearby
                ))
            }
            markDone(.nearby, nearby.sorted { $0.reasonChip < $1.reasonChip })
        } catch { markDone(.nearby, []) }
    }

    // MARK: Follow

    func toggleFollow(userId: String) {
        let wasFollowing = followStates[userId] ?? false
        followStates[userId] = !wasFollowing
        pendingFollowIds.insert(userId)
        Task {
            do {
                if wasFollowing {
                    try await FollowService.shared.unfollowUser(userId: userId)
                } else {
                    try await FollowService.shared.followUser(userId: userId)
                }
            } catch {
                followStates[userId] = wasFollowing
            }
            pendingFollowIds.remove(userId)
        }
    }

    func isFollowing(_ id: String) -> Bool { followStates[id] ?? false }
    func isPending(_ id: String) -> Bool   { pendingFollowIds.contains(id) }

    private func markDone(_ filter: PeopleDiscoveryFilter, _ users: [DiscoveredPerson]) {
        if let idx = sections.firstIndex(where: { $0.id == filter }) {
            sections[idx] = PeopleSection(
                id: filter,
                title: sections[idx].title,
                users: users,
                isLoading: false
            )
        }
    }
}

// MARK: - FindPeopleView

struct FindPeopleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var vm = FindPeopleViewModel()
    @State private var profileSheetUserId: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    filterPillRow
                        .padding(.bottom, 8)
                    Divider().opacity(0.5)
                    contentArea
                }
            }
            .navigationTitle("Find People to Follow")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 30, height: 30)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5))
                    }
                    .accessibilityLabel("Close")
                }
            }
            .task { await vm.loadAll() }
            .refreshable { await vm.refresh() }
            .sheet(item: $profileSheetUserId) { userId in
                NavigationView {
                    UserProfileView(userId: userId, showsDismissButton: true)
                }
            }
        }
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search by name or username", text: $vm.searchText)
                .font(AMENFont.regular(15))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Search for people")
            if !vm.searchText.isEmpty {
                Button {
                    vm.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
        )
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.15), value: vm.searchText.isEmpty)
    }

    // MARK: Filter pills

    private var filterPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PeopleDiscoveryFilter.allCases) { filter in
                    PeopleDiscoveryFilterPill(
                        filter: filter,
                        isSelected: vm.selectedFilter == filter
                    ) {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.72)) {
                            vm.selectedFilter = filter
                        }
                        HapticManager.impact(style: .light)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var contentArea: some View {
        let sections = vm.filteredSections
        if sections.isEmpty && !vm.hasLoaded {
            loadingPlaceholder
        } else if sections.isEmpty {
            emptySearchState
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 20) {
                    ForEach(sections) { section in
                        PeopleSectionView(
                            section: section,
                            followStates: vm.followStates,
                            pendingIds: vm.pendingFollowIds,
                            onFollow: { vm.toggleFollow(userId: $0) },
                            onTap: { profileSheetUserId = $0 }
                        )
                    }
                    Color.clear.frame(height: 40)
                }
                .padding(.top, 16)
            }
        }
    }

    private var loadingPlaceholder: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 20) {
                ForEach(0..<3, id: \.self) { _ in PeopleSectionSkeletonView() }
            }
            .padding(.top, 16)
        }
    }

    private var emptySearchState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("No results for \"\(vm.searchText)\"")
                .font(AMENFont.semiBold(17))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text("Try a different name or username.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Filter Pill

private struct PeopleDiscoveryFilterPill: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let filter: PeopleDiscoveryFilter
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: filter.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(filter.rawValue)
                    .font(AMENFont.semiBold(13))
            }
            .foregroundStyle(isSelected ? AmenTheme.Colors.amenBlack : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule(style: .continuous).fill(AmenTheme.Colors.amenGold)
                } else {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                        )
                }
            }
            .shadow(color: isSelected ? AmenTheme.Colors.amenGold.opacity(0.25) : .clear, radius: 6, y: 2)
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(filter.rawValue)
        .accessibilityHint(isSelected ? "Currently selected filter" : "Filter by \(filter.rawValue)")
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Section view

private struct PeopleSectionView: View {
    let section: PeopleSection
    let followStates: [String: Bool]
    let pendingIds: Set<String>
    let onFollow: (String) -> Void
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(AMENFont.semiBold(16))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                if section.isLoading {
                    ForEach(0..<3, id: \.self) { i in
                        DiscoveryPersonCardSkeleton()
                        if i < 2 { Divider().padding(.leading, 76) }
                    }
                } else if section.users.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "person.2.slash")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                            Text("None found")
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 24)
                        Spacer()
                    }
                } else {
                    ForEach(Array(section.users.enumerated()), id: \.element.id) { idx, person in
                        DiscoveryPersonCard(
                            person: person,
                            isFollowing: followStates[person.id] ?? false,
                            isPending: pendingIds.contains(person.id),
                            cardIndex: idx,
                            onFollow: { onFollow(person.id) },
                            onTap: { onTap(person.id) }
                        )
                        if idx < section.users.count - 1 {
                            Divider().padding(.leading, 76)
                        }
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
            )
            .shadow(color: AmenTheme.Colors.shadowCard, radius: 12, y: 4)
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Person Card

private struct DiscoveryPersonCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let person: DiscoveredPerson
    let isFollowing: Bool
    let isPending: Bool
    let cardIndex: Int
    let onFollow: () -> Void
    let onTap: () -> Void

    @State private var appeared = false
    @State private var localIsFollowing: Bool = false
    @State private var showCheckmark = false

    var body: some View {
        HStack(spacing: 12) {
            // Avatar — 48pt circle
            Button(action: onTap) {
                avatarView
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("\(person.displayName)'s profile photo")
            .accessibilityHint("Tap to view profile")

            // Name + username + reason chip
            Button(action: onTap) {
                infoView
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(person.displayName), @\(person.username), \(person.reasonChip)")

            Spacer(minLength: 8)

            followButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            localIsFollowing = isFollowing
            let delay = cardIndex < 6 ? Double(cardIndex) * 0.04 : 0
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8).delay(delay)) {
                appeared = true
            }
        }
        .onChange(of: isFollowing) { _, newVal in
            if newVal != localIsFollowing {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
                    localIsFollowing = newVal
                }
            }
        }
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 48, height: 48)
            if let urlStr = person.profileImageURL, !urlStr.isEmpty,
               let url = URL(string: urlStr) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                } placeholder: {
                    initialsText
                }
            } else {
                initialsText
            }
        }
    }

    private var initialsText: some View {
        Text(person.displayName.peopleInitials)
            .font(AMENFont.bold(16))
            .foregroundStyle(.secondary)
    }

    private var infoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(person.displayName)
                .font(AMENFont.semiBold(15))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("@\(person.username)")
                .font(AMENFont.regular(13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            // Reason chip — color-coded by section
            Text(person.reasonChip)
                .font(AMENFont.medium(11))
                .foregroundStyle(chipForeground)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(chipBackground, in: Capsule(style: .continuous))
        }
    }

    private var chipForeground: Color {
        switch person.section {
        case .yourChurch: return AmenTheme.Colors.amenPurple
        case .nearby:     return AmenTheme.Colors.amenBlue
        case .newToAMEN:  return AmenTheme.Colors.amenGold
        case .all:        return .secondary
        }
    }

    private var chipBackground: Color {
        switch person.section {
        case .yourChurch: return AmenTheme.Colors.amenPurple.opacity(0.12)
        case .nearby:     return AmenTheme.Colors.amenBlue.opacity(0.12)
        case .newToAMEN:  return AmenTheme.Colors.amenGold.opacity(0.14)
        case .all:        return Color(uiColor: .tertiarySystemFill)
        }
    }

    private var followButton: some View {
        Button {
            HapticManager.impact(style: .light)
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.65)) {
                if !localIsFollowing { showCheckmark = true }
                localIsFollowing.toggle()
            }
            onFollow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showCheckmark = false }
            }
        } label: {
            ZStack {
                if showCheckmark {
                    Capsule(style: .continuous).fill(AmenTheme.Colors.amenGold)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AmenTheme.Colors.amenBlack)
                        .transition(.scale.combined(with: .opacity))
                } else if localIsFollowing {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5)
                    Text("Following")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.secondary)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Capsule(style: .continuous)
                        .fill(AmenTheme.Colors.amenGold)
                        .shadow(color: AmenTheme.Colors.amenGold.opacity(0.30), radius: 6, y: 2)
                    Text("Follow")
                        .font(AMENFont.bold(13))
                        .foregroundStyle(AmenTheme.Colors.amenBlack)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: localIsFollowing ? 88 : 72, height: 32)
            .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: localIsFollowing)
            .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: showCheckmark)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isPending)
        .accessibilityLabel(localIsFollowing ? "Following \(person.displayName)" : "Follow \(person.displayName)")
        .accessibilityHint(localIsFollowing ? "Tap to unfollow" : "Tap to follow")
        .accessibilityAddTraits(localIsFollowing ? .isSelected : [])
    }
}

// MARK: - Section Skeleton

private struct PeopleSectionSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(AmenTheme.Colors.shimmerBase)
                .frame(width: 160, height: 16)
                .padding(.horizontal, 16)
                .shimmerEffect()
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { i in
                    DiscoveryPersonCardSkeleton()
                    if i < 2 { Divider().padding(.leading, 76) }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Person Card Skeleton

private struct DiscoveryPersonCardSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AmenTheme.Colors.shimmerBase)
                .frame(width: 48, height: 48)
                .shimmerEffect()
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(AmenTheme.Colors.shimmerBase)
                    .frame(width: 120, height: 12)
                    .shimmerEffect()
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(AmenTheme.Colors.shimmerBase)
                    .frame(width: 80, height: 10)
                    .shimmerEffect()
                Capsule(style: .continuous)
                    .fill(AmenTheme.Colors.shimmerBase)
                    .frame(width: 100, height: 18)
                    .shimmerEffect()
            }
            Spacer()
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AmenTheme.Colors.shimmerBase)
                .frame(width: 72, height: 32)
                .shimmerEffect()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - String initials helper (scoped to this file)

private extension String {
    var peopleInitials: String {
        split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

// MARK: - Preview

#Preview {
    FindPeopleView()
}
