// SpacesDiscoveryView.swift — AMEN App
// Communities discovery screen with AI-powered recommendations

import SwiftUI
import FirebaseAuth

// MARK: - SpacesDiscoveryView

struct SpacesDiscoveryView: View {
    @StateObject private var vm = SpacesViewModel()
    @State private var showCreateSheet = false
    @State private var selectedSpace: AMENSpace? = nil
    @State private var showSpaceFeed = false
    @Namespace private var filterNamespace
    @AppStorage("spiritualOS_create_space_enhanced_enabled") private var enhancedCreateEnabled = false

    // Background color matching #0A0A0F
    private let background = Color(red: 0.039, green: 0.039, blue: 0.059)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Search bar
                        searchBar
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 12)

                        // Filter tabs
                        filterTabs
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)

                        // Recommended horizontal strip
                        if !vm.recommendedSpaces.isEmpty && vm.searchText.isEmpty {
                            recommendedSection
                                .padding(.bottom, 24)
                        }

                        // Main list
                        mainList
                            .padding(.horizontal, 16)
                            .padding(.bottom, 100) // FAB clearance
                    }
                }

                // FAB
                fabButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 32)
            }
            .navigationTitle("Communities")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showCreateSheet) {
                // Spiritual OS — Create Space Enhanced Sheet (Agent E, gated by AppStorage flag)
                if enhancedCreateEnabled {
                    AmenCreateSpaceEnhancedSheet(
                        userId: Auth.auth().currentUser?.uid ?? "",
                        onDismiss: { showCreateSheet = false },
                        onCreated: { _ in showCreateSheet = false }
                    )
                } else {
                    CreateSpaceSheet(vm: vm)
                }
            }
            .navigationDestination(isPresented: $showSpaceFeed) {
                if let space = selectedSpace {
                    SpaceFeedView(space: space, vm: vm)
                }
            }
            .onAppear { vm.load() }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.45))
                .font(.systemScaled(15, weight: .medium))

            TextField("", text: $vm.searchText)
                .font(AMENFont.regular(15))
                .foregroundStyle(.white)
                .tint(Color(red: 0.6, green: 0.4, blue: 1.0))
                .placeholder(when: vm.searchText.isEmpty) {
                    Text("Search communities…")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(.white.opacity(0.35))
                }

            if !vm.searchText.isEmpty {
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                        vm.searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.4))
                        .font(.systemScaled(14))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Filter Tabs

    private var filterTabs: some View {
        HStack(spacing: 8) {
            ForEach(SpacesViewModel.SpaceFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.75))) {
                        vm.selectedFilter = filter
                    }
                } label: {
                    Text(filter.rawValue)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(vm.selectedFilter == filter ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background {
                            if vm.selectedFilter == filter {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.6, green: 0.35, blue: 1.0),
                                                Color(red: 0.45, green: 0.2, blue: 0.9)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .matchedGeometryEffect(id: "filterPill", in: filterNamespace)
                                    .shadow(color: Color(red: 0.5, green: 0.2, blue: 0.9).opacity(0.45), radius: 8, y: 3)
                            } else {
                                Capsule()
                                    .fill(.white.opacity(0.06))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Recommended Section

    private var recommendedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommended for You")
                .font(AMENFont.semiBold(15))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(vm.recommendedSpaces) { space in
                        SpaceChipView(
                            space: space,
                            isJoined: vm.joinedSpaceIds.contains(space.id ?? ""),
                            onJoin: { Task { await vm.toggleJoin(space: space) } },
                            onTap: {
                                selectedSpace = space
                                showSpaceFeed = true
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Main List

    @ViewBuilder
    private var mainList: some View {
        if vm.isLoading {
            VStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { _ in
                    SpaceCardShimmer()
                }
            }
        } else if vm.filteredSpaces.isEmpty {
            emptyState
                .padding(.top, 60)
        } else {
            LazyVStack(spacing: 14) {
                ForEach(vm.filteredSpaces) { space in
                    SpaceCardView(
                        space: space,
                        isJoined: vm.joinedSpaceIds.contains(space.id ?? ""),
                        onJoin: { Task { await vm.toggleJoin(space: space) } },
                        onTap: {
                            selectedSpace = space
                            showSpaceFeed = true
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.systemScaled(44, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.6, green: 0.4, blue: 1.0), Color(red: 0.4, green: 0.2, blue: 0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("No communities found")
                .font(AMENFont.semiBold(17))
                .foregroundStyle(.white.opacity(0.8))

            Text(vm.searchText.isEmpty ? "Be the first to create one" : "Try a different search term")
                .font(AMENFont.regular(14))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - FAB

    private var fabButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showCreateSheet = true
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.65, green: 0.4, blue: 1.0),
                                Color(red: 0.45, green: 0.2, blue: 0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(color: Color(red: 0.5, green: 0.2, blue: 0.9).opacity(0.5), radius: 12, y: 4)

                Image(systemName: "plus")
                    .font(.systemScaled(22, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - SpaceChipView

struct SpaceChipView: View {
    let space: AMENSpace
    let isJoined: Bool
    let onJoin: () -> Void
    let onTap: () -> Void

    private let accentPurple = Color(red: 0.6, green: 0.35, blue: 1.0)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Icon placeholder / initial
                ZStack {
                    Circle()
                        .fill(accentPurple.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Text(String(space.name.prefix(1)).uppercased())
                        .font(AMENFont.bold(15))
                        .foregroundStyle(accentPurple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(space.name)
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("\(space.memberCount.formatted()) members")
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.white.opacity(0.5))
                }

                // Join mini button
                Button(action: onJoin) {
                    Text(isJoined ? "Joined" : "Join")
                        .font(AMENFont.semiBold(11))
                        .foregroundStyle(isJoined ? accentPurple : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(isJoined ? accentPurple.opacity(0.12) : accentPurple)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(accentPurple.opacity(isJoined ? 0.5 : 0), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shimmer placeholder

private struct SpaceCardShimmer: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay(
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.07), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: phase * geo.size.width * 1.5)
                        .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: phase)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            )
            .frame(height: 130)
            .onAppear { phase = 1 }
    }
}

// MARK: - View+Placeholder helper (local extension guard)

private extension View {
    @ViewBuilder
    func placeholder<Content: View>(
        when shouldShow: Bool,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: .leading) {
            if shouldShow { placeholder() }
            self
        }
    }
}
