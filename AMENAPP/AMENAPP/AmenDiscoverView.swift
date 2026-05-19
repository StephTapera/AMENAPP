import SwiftUI

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
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.black.opacity(0.7))
                            .padding(20)
                    } else if viewModel.items.isEmpty {
                        Text("No discover items yet.")
                            .font(.subheadline)
                            .foregroundStyle(.black.opacity(0.7))
                            .padding(20)
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

#Preview {
    AmenDiscoverView()
}
