// NearbyPeopleView.swift
// AMENAPP
//
// "Find People Nearby" — Liquid Glass surface wired to NearbyUsersService.
// Entry points:
//   1. "Near Me" filter chip on PeopleDiscoveryView / AmenDiscoverViewModel
//   2. Direct `sheet(isPresented:) { NearbyPeopleView() }`
//
// Privacy flow:
//   .notDetermined → NearbyPermissionSheet (explain + consent)
//   .authorized    → run search immediately
//   .denied        → NearbyPermissionDeniedView (link to Settings)

import SwiftUI
import CoreLocation
import FirebaseAuth
import Combine

// MARK: - NearbyPeopleViewModel

@MainActor
final class NearbyPeopleViewModel: ObservableObject {

    // MARK: - Published

    @Published var showPermissionSheet = false
    @Published var showDeniedSheet = false
    @Published var results: [NearbyUserProfile] = []
    @Published var isSearching = false
    @Published var hasSearched = false
    @Published var error: String?
    @Published var followingUserIds: Set<String> = []

    // MARK: - Private

    private let service = NearbyUsersService.shared
    private var followCancellable: AnyCancellable?

    // MARK: - Init

    init() {
        // Mirror FollowService following set
        followCancellable = FollowService.shared.$following
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ids in self?.followingUserIds = ids }
    }

    // MARK: - Actions

    /// Called when the user taps "Find People Near Me".
    /// Checks current location authorization and branches to the appropriate flow.
    func handleFindNearbyTapped() {
        let status = NearbyUsersService.shared.locationStatus
        switch status {
        case .notDetermined:
            showPermissionSheet = true
        case .authorizedWhenInUse, .authorizedAlways:
            Task { await runSearch() }
        case .denied, .restricted:
            showDeniedSheet = true
        @unknown default:
            showPermissionSheet = true
        }
    }

    /// Called after user consents on NearbyPermissionSheet.
    func handlePermissionAllowed() {
        showPermissionSheet = false
        Task { await runSearch() }
    }

    /// Called when user dismisses the permission sheet without allowing.
    func handlePermissionDeclined() {
        showPermissionSheet = false
    }

    /// Open iOS Settings for the app.
    func openSettings() {
        showDeniedSheet = false
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Follow / unfollow a nearby user (optimistic).
    func toggleFollow(userId: String) {
        let wasFollowing = followingUserIds.contains(userId)
        if wasFollowing {
            followingUserIds.remove(userId)
        } else {
            followingUserIds.insert(userId)
        }
        Task {
            do {
                if wasFollowing {
                    try await FollowService.shared.unfollowUser(userId: userId)
                } else {
                    try await FollowService.shared.followUser(userId: userId)
                }
            } catch {
                // Revert on failure
                if wasFollowing {
                    followingUserIds.insert(userId)
                } else {
                    followingUserIds.remove(userId)
                }
            }
        }
    }

    // MARK: - Search

    private func runSearch() async {
        isSearching = true
        error = nil
        defer { isSearching = false; hasSearched = true }
        do {
            results = try await service.requestNearbySearch(followingIds: followingUserIds)
        } catch let nearbyError as NearbySearchError {
            error = nearbyError.errorDescription
            if nearbyError == .locationDenied {
                showDeniedSheet = true
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Cleanup

    func onDisappear() {
        // Remove our own discoveryLocation when the view leaves
        service.clearDiscoveryLocation()
    }
}

// MARK: - NearbyPeopleView

struct NearbyPeopleView: View {

    @StateObject private var vm = NearbyPeopleViewModel()
    @State private var showProfileSheet: NearbyUserProfile?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {

                        // Hero banner
                        heroBanner
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 20)

                        // State: loading
                        if vm.isSearching {
                            loadingState
                        }
                        // State: error
                        else if let errorMsg = vm.error, !vm.isSearching {
                            errorState(message: errorMsg)
                        }
                        // State: results
                        else if vm.hasSearched && !vm.results.isEmpty {
                            resultsSection
                        }
                        // State: empty after search
                        else if vm.hasSearched && vm.results.isEmpty {
                            emptyState
                        }

                        // Privacy footer
                        privacyFooter
                            .padding(.top, 24)
                            .padding(.bottom, 48)
                    }
                }
            }
            .navigationTitle("Near Me")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(AMENFont.semiBold(15))
                }
            }
            .sheet(isPresented: $vm.showPermissionSheet) {
                NearbyPermissionSheet(
                    onAllow: { vm.handlePermissionAllowed() },
                    onDismiss: { vm.handlePermissionDeclined() }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $vm.showDeniedSheet) {
                NearbyPermissionDeniedView(
                    onOpenSettings: { vm.openSettings() },
                    onDismiss: { vm.showDeniedSheet = false }
                )
                .presentationDetents([.medium])
            }
            .sheet(item: $showProfileSheet) { profile in
                NavigationView {
                    SafeUserProfileWrapper(userId: profile.id)
                }
            }
            .onDisappear { vm.onDisappear() }
        }
    }

    // MARK: - Hero Banner

    private var heroBanner: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 72, height: 72)
                Image(systemName: "person.2.wave.2.fill")
                    .font(.systemScaled(28, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 6) {
                Text("Find Believers Near You")
                    .font(AMENFont.bold(20))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text("Discover AMEN members within about 1 km.\nYour location is approximate and expires in 1 hour.")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            // Search button
            Button {
                HapticManager.impact(style: .medium)
                vm.handleFindNearbyTapped()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: vm.isSearching ? "location.fill" : "location.magnifyingglass")
                        .font(.systemScaled(15, weight: .semibold))
                    Text(vm.isSearching ? "Searching…" : (vm.hasSearched ? "Search Again" : "Find People Near Me"))
                        .font(AMENFont.bold(15))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(vm.isSearching ? Color.accentColor.opacity(0.6) : Color.accentColor)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 3)
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(vm.isSearching)
            .accessibilityLabel(vm.hasSearched ? "Search again for people nearby" : "Find people near me")
            .accessibilityHint("Requires location access. Your approximate location will be shared for 1 hour.")
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 14) {
            // Skeleton rows while searching
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { i in
                    PersonRowSkeletonView()
                    if i < 3 { Divider().padding(.leading, 74) }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)

            Text("Finding believers near you…")
                .font(AMENFont.regular(13))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Error State

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "location.slash.fill")
                .font(.systemScaled(42, weight: .light))
                .foregroundStyle(.orange)
            Text("Search unavailable")
                .font(AMENFont.semiBold(17))
                .foregroundStyle(.primary)
            Text(message)
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                HapticManager.impact(style: .light)
                vm.handleFindNearbyTapped()
            } label: {
                Text("Try Again")
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(.top, 32)
        .transition(.opacity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 72, height: 72)
                Image(systemName: "person.2.slash")
                    .font(.systemScaled(30, weight: .light))
                    .foregroundStyle(.tertiary)
            }
            Text("No one nearby right now")
                .font(AMENFont.semiBold(17))
                .foregroundStyle(.primary)
            Text("There are no active AMEN members within about 1 km at the moment.\nCheck back later or invite friends to join!")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 32)
        .transition(.opacity)
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Nearby Believers")
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(.primary)
                Text("(\(vm.results.count))")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(Array(vm.results.enumerated()), id: \.element.id) { idx, profile in
                    NearbyPersonRow(
                        profile: profile,
                        isFollowing: vm.followingUserIds.contains(profile.id),
                        cardIndex: idx,
                        onTap: { showProfileSheet = profile },
                        onFollow: { vm.toggleFollow(userId: profile.id) }
                    )
                    if idx < vm.results.count - 1 {
                        Divider().padding(.leading, 74)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Privacy Footer

    private var privacyFooter: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.systemScaled(12))
                    .foregroundStyle(.tertiary)
                Text("Approximate location only • Expires in 1 hour • Opt-in only")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.tertiary)
            }
            Button {
                if let url = URL(string: "https://amenapp.com/privacy") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Privacy Policy")
                    .font(AMENFont.medium(12))
                    .foregroundStyle(.secondary)
                    .underline()
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
    }
}

// MARK: - NearbyPersonRow

struct NearbyPersonRow: View {
    let profile: NearbyUserProfile
    let isFollowing: Bool
    let cardIndex: Int
    let onTap: () -> Void
    let onFollow: () -> Void

    @State private var appeared = false
    @State private var showCheckmark = false
    @State private var localIsFollowing: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Button(action: onTap) {
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(width: 46, height: 46)
                    if let urlStr = profile.profileImageURL, !urlStr.isEmpty {
                        CachedAsyncImage(url: URL(string: urlStr)) { image in
                            image.resizable().scaledToFill()
                                .frame(width: 46, height: 46)
                                .clipShape(Circle())
                        } placeholder: {
                            Text(String(profile.displayName.prefix(1)))
                                .font(AMENFont.bold(17))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(String(profile.displayName.prefix(1)))
                            .font(AMENFont.bold(17))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("\(profile.displayName)'s profile photo")
            .accessibilityHint("Tap to view profile")

            // Info
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.displayName)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text("@\(profile.username)")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if profile.followersCount > 0 {
                            Text("•").foregroundStyle(.tertiary).accessibilityHidden(true)
                            Text(formatCount(profile.followersCount))
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let bio = profile.bio, !bio.isEmpty {
                        Text(bio)
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            // Follow button
            Button {
                HapticManager.impact(style: .light)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                    if !localIsFollowing { showCheckmark = true }
                    localIsFollowing.toggle()
                }
                onFollow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    withAnimation(.easeOut(duration: 0.2)) { showCheckmark = false }
                }
            } label: {
                ZStack {
                    if showCheckmark {
                        Capsule().fill(Color.accentColor)
                        Image(systemName: "checkmark")
                            .font(.systemScaled(13, weight: .bold))
                            .foregroundStyle(.white)
                    } else if localIsFollowing {
                        Capsule().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5)
                        Text("Following")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.secondary)
                    } else {
                        Capsule().fill(Color.primary)
                            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                        Text("Follow")
                            .font(AMENFont.bold(13))
                            .foregroundStyle(Color(uiColor: .systemBackground))
                    }
                }
                .frame(width: localIsFollowing ? 90 : 72, height: 32)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: localIsFollowing)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showCheckmark)
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel(localIsFollowing ? "Following \(profile.displayName)" : "Follow \(profile.displayName)")
            .accessibilityHint(localIsFollowing ? "Tap to unfollow" : "Tap to follow")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            localIsFollowing = isFollowing
            let delay = cardIndex < 8 ? Double(cardIndex) * 0.04 : 0
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8).delay(delay)) {
                appeared = true
            }
        }
        .onChange(of: isFollowing) { _, newVal in
            if newVal != localIsFollowing {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    localIsFollowing = newVal
                }
            }
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
}
