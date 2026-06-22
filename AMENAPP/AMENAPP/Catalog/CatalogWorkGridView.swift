import SwiftUI

struct CatalogWorkGridView: View {

    let creatorId: String
    let creatorName: String

    @StateObject private var vm: CatalogViewModel
    @State private var selectedWork: CatalogWork? = nil

    init(creatorId: String, creatorName: String) {
        self.creatorId = creatorId
        self.creatorName = creatorName
        _vm = StateObject(wrappedValue: CatalogViewModel(creatorId: creatorId))
    }

    private let gridColumns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !vm.tabs.isEmpty {
                    CatalogWorkTypeTabBar(tabs: vm.tabs, selectedType: $vm.selectedType) { type in
                        Task { await vm.selectType(type) }
                    }
                    .padding(.horizontal, 16)
                }

                stateContent
            }
            .padding(.bottom, 32)
        }
        .task { await vm.load() }
        .sheet(item: $selectedWork) { work in
            CatalogWorkDetailView(work: work)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch vm.state {
        case .loading:
            loadingView

        case .empty:
            emptyView

        case .syncing:
            syncingView

        case .populated(let works):
            let filtered = vm.filteredWorks(from: works)
            VStack(alignment: .leading, spacing: 20) {
                carouselSection(works: filtered)
                gridSection(works: filtered)
                AskCreatorBar(
                    query: $vm.askQuery,
                    onSubmit: { await vm.askCreator() },
                    result: vm.askResult,
                    isLoading: vm.isAsking
                )
                .padding(.horizontal, 16)
            }

        case .error(let message):
            errorView(message: message)

        case .locked:
            CatalogEntitlementGateView(feature: .catalog)
        }
    }

    // MARK: - Carousel

    private func carouselSection(works: [CatalogWork]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.systemScaled(13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(works.prefix(8)) { work in
                        CatalogCoverCard(work: work)
                            .onTapGesture { selectedWork = work }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Grid

    private func gridSection(works: [CatalogWork]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All Works")
                .font(.systemScaled(13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(works) { work in
                    CatalogWorkCard(work: work)
                        .onTapGesture { selectedWork = work }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading catalog...")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.systemScaled(40, weight: .light))
                .foregroundStyle(.secondary)
            Text("No published works yet")
                .font(.systemScaled(16, weight: .medium))
            Text("This creator hasn't published any works to their catalog.")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var syncingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Importing works...")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
            Text("This may take a moment.")
                .font(.systemScaled(12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.systemScaled(32, weight: .light))
                .foregroundStyle(.secondary)
            Text("Couldn't load catalog")
                .font(.systemScaled(16, weight: .medium))
            Text(message)
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await vm.load() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }
}

// MARK: - CatalogCoverCard

struct CatalogCoverCard: View {
    let work: CatalogWork

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.secondary.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: work.type.icon)
                    .font(.systemScaled(32, weight: .light))
                    .foregroundStyle(.secondary)
            }
            Text(work.title)
                .font(.systemScaled(12, weight: .medium))
                .lineLimit(2)
                .frame(width: 100, alignment: .leading)
            Text(work.type.displayName)
                .font(.systemScaled(10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.secondary.opacity(0.1)))
        }
        .frame(width: 100)
    }
}

// MARK: - CatalogWorkCard

struct CatalogWorkCard: View {
    let work: CatalogWork

    var primaryLink: WorkLink? {
        work.links.first(where: { ["listen", "read", "watch"].contains($0.kind) }) ?? work.links.first
    }

    var ctaLabel: String {
        guard let link = primaryLink else { return "Open" }
        switch link.kind {
        case "listen": return "Listen"
        case "read":   return "Read"
        case "watch":  return "Watch"
        case "buy":    return "Buy"
        case "register": return "Register"
        default:       return "Open"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.secondary.opacity(0.08))
                    .aspectRatio(1, contentMode: .fit)
                Image(systemName: work.type.icon)
                    .font(.systemScaled(28, weight: .light))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(work.title)
                    .font(.systemScaled(13, weight: .medium))
                    .lineLimit(2)
                Text(work.type.displayName)
                    .font(.systemScaled(11))
                    .foregroundStyle(.secondary)
            }

            if let link = primaryLink, let url = URL(string: link.url) {
                Link(ctaLabel, destination: url)
                    .font(.systemScaled(12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.primary.opacity(0.08)))
                    .foregroundStyle(.primary)
            }
        }
        .padding(10)
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
