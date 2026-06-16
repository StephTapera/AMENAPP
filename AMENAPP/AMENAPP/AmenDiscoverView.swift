import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import UIKit

struct AmenDiscoverView: View {
    @StateObject private var viewModel = AmenDiscoverViewModel()
    @Namespace private var tileNamespace
    @State private var showReasonSheet = false
    @State private var showFeedbackSheet = false
    @State private var scrollOffset: CGFloat = 0

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            ScrollView {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: DiscoverOffsetKey.self, value: proxy.frame(in: .named("amen_discover")).minY)
                }
                .frame(height: 0)

                VStack(spacing: 12) {
                    AmenDiscoverSearchCapsule(text: $viewModel.searchQuery, compactProgress: min(max(-scrollOffset / 160, 0), 1))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    AmenDiscoverTopicRail(filters: viewModel.filters, selected: viewModel.selectedFilter) { filter in
                        Task { await viewModel.applyFilter(filter) }
                    }

                    if viewModel.isLoading {
                        AmenDiscoverSkeletonGrid()
                    } else if let error = viewModel.errorMessage {
                        AmenDiscoverErrorState(message: error) {
                            Task { await viewModel.loadInitial() }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                    } else if viewModel.items.isEmpty {
                        AmenDiscoverEmptyState(filter: viewModel.selectedFilter)
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                    } else {
                        AmenDiscoverGridView(
                            items: viewModel.items,
                            onTap: { item in
                                viewModel.logTap(item)
                                viewModel.openDetail(item)
                            },
                            onAppear: { item in
                                Task { await viewModel.loadMoreIfNeeded(current: item) }
                            },
                            namespace: tileNamespace
                        )
                    }
                }
                .padding(.bottom, 90)
            }
            .coordinateSpace(name: "amen_discover")
            .onPreferenceChange(DiscoverOffsetKey.self) { scrollOffset = $0 }

            AmenDiscoverGlassTabBar(selected: $viewModel.selectedFilter, tabs: ["For You", "Churches", "Sermons", "Selah"])
                .padding(.bottom, 12)
                .opacity(max(0.72, min(1, 1 - (-scrollOffset / 900))))
        }
        .task {
            AMENAnalyticsService.shared.track(.discoverView)
            await viewModel.loadInitial()
        }
        .sheet(item: $viewModel.selectedItem) { item in
            AmenDiscoverDetailView(
                item: item,
                namespace: tileNamespace,
                onPray: {
                    AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "pray"))
                    dlog("[AmenDiscoverView] Pray tapped on item: \(item.id)")
                    Task { await AmenDiscoverView.recordPray(itemId: item.sourceId) }
                },
                onSave: {
                    AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "save"))
                    dlog("[AmenDiscoverView] Save tapped on item: \(item.id)")
                    Task { try? await SavedPostsService.shared.savePost(postId: item.sourceId) }
                },
                onShare: {
                    AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "share"))
                    dlog("[AmenDiscoverView] Share tapped on item: \(item.id)")
                    AmenDiscoverView.presentShare(itemId: item.sourceId)
                },
                onWhyThis: {
                    Task {
                        await viewModel.loadWhyThis(for: item)
                        showReasonSheet = true
                    }
                },
                onFeedback: {
                    showFeedbackSheet = true
                }
            )
            .sheet(isPresented: $showReasonSheet) {
                AmenDiscoverReasonSheet(reason: viewModel.reasonText)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showFeedbackSheet) {
                AmenDiscoverSafetyFeedbackSheet { feedback in
                    Task { await viewModel.submitFeedback(item, feedback: feedback) }
                }
            }
        }
    }
}

// MARK: - Discover action helpers

private extension AmenDiscoverView {

    /// Records a "prayed for" edge for a Discover item's underlying source document.
    /// Uses a lightweight Firestore write to /discoverPrayers/{uid}/{sourceId}
    /// so it does not require the full AmenPrayerService edge flow (which demands
    /// a prayer-request document to exist). Fails silently — prayer is never blocked.
    @MainActor
    static func recordPray(itemId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        do {
            try await Firestore.firestore()
                .collection("discoverPrayers")
                .document(uid)
                .collection("items")
                .document(itemId)
                .setData(["prayedAt": FieldValue.serverTimestamp()], merge: true)
        } catch {
            dlog("[AmenDiscoverView] recordPray non-fatal: \(error.localizedDescription)")
        }
    }

    /// Presents a UIActivityViewController for the canonical Discover item URL.
    /// Must be called on the main thread.
    @MainActor
    static func presentShare(itemId: String) {
        guard let url = URL(string: "https://amenapp.com/discover/\(itemId)") else { return }
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController?.present(av, animated: true)
    }
}

private struct DiscoverOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct AmenDiscoverSkeletonGrid: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(0..<8, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 170)
                    .redacted(reason: .placeholder)
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Empty State

private struct AmenDiscoverEmptyState: View {
    let filter: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.black.opacity(0.35))

            VStack(spacing: 6) {
                Text("Discover content loading")
                    .font(.headline)
                    .foregroundStyle(.black.opacity(0.75))

                Text("We're personalising your \(filter) feed. Check back in a moment, or try a different topic above.")
                    .font(.subheadline)
                    .foregroundStyle(.black.opacity(0.45))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .liquidGlass(opacity: 0.06, cornerRadius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Discover content is loading for the \(filter) topic. Try a different topic or check back soon.")
    }
}

// MARK: - Error State

private struct AmenDiscoverErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.black.opacity(0.35))

            VStack(spacing: 6) {
                Text("Couldn't load Discover")
                    .font(.headline)
                    .foregroundStyle(.black.opacity(0.75))

                Text("Pull down or tap Retry to try again.")
                    .font(.subheadline)
                    .foregroundStyle(.black.opacity(0.45))
                    .multilineTextAlignment(.center)
            }

            Button(action: onRetry) {
                Text("Retry")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.75))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .liquidGlass(opacity: 0.10, cornerRadius: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .liquidGlass(opacity: 0.06, cornerRadius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Couldn't load Discover. \(message). Double-tap to retry.")
        .accessibilityAction(named: "Retry") { onRetry() }
    }
}

#Preview {
    AmenDiscoverView()
}
