import SwiftUI

struct CatalogTimelineView: View {

    let creatorId: String

    @StateObject private var vm: CatalogViewModel
    @State private var selectedWork: CatalogWork? = nil

    init(creatorId: String) {
        self.creatorId = creatorId
        _vm = StateObject(wrappedValue: CatalogViewModel(creatorId: creatorId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch vm.state {
                case .loading:
                    loadingView
                case .empty:
                    emptyView
                case .syncing:
                    syncingView
                case .populated(let works):
                    timelineContent(works: works)
                case .error(let message):
                    errorView(message: message)
                case .locked:
                    CatalogEntitlementGateView(feature: .catalog)
                }
            }
            .padding(.bottom, 32)
        }
        .task { await vm.load() }
        .sheet(item: $selectedWork) { work in
            CatalogWorkDetailView(work: work)
        }
    }

    // MARK: - Timeline Content

    private func timelineContent(works: [CatalogWork]) -> some View {
        let grouped = groupByYear(works: works)
        let years = grouped.keys.sorted(by: >)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(years, id: \.self) { year in
                if let yearWorks = grouped[year] {
                    yearSection(year: year, works: yearWorks)
                }
            }
        }
    }

    private func groupByYear(works: [CatalogWork]) -> [Int: [CatalogWork]] {
        var result: [Int: [CatalogWork]] = [:]
        let calendar = Calendar.current
        for work in works {
            let date = work.publishedAt ?? work.createdAt
            let year = calendar.component(.year, from: date)
            result[year, default: []].append(work)
        }
        return result
    }

    private func yearSection(year: Int, works: [CatalogWork]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(year)")
                    .font(.systemScaled(15, weight: .semibold))
                Spacer()
                Text("\(works.count) works")
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .amenGlassEffect(in: Rectangle())

            VStack(spacing: 0) {
                ForEach(works) { work in
                    timelineRow(work: work)
                    if work.id != works.last?.id {
                        Divider()
                            .padding(.leading, 64)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 20)
    }

    private func timelineRow(work: CatalogWork) -> some View {
        Button {
            selectedWork = work
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.secondary.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: work.type.icon)
                        .font(.systemScaled(15, weight: .light))
                        .foregroundStyle(.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(work.title)
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(work.type.displayName)
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                        if let date = work.publishedAt {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(date, style: .date)
                                .font(.systemScaled(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.secondary.opacity(0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: work.type.icon)
                        .font(.systemScaled(14, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading timeline...")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.systemScaled(36, weight: .light))
                .foregroundStyle(.secondary)
            Text("No timeline yet")
                .font(.systemScaled(16, weight: .medium))
            Text("Published works will appear here in chronological order.")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var syncingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Syncing works...")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.systemScaled(32, weight: .light))
                .foregroundStyle(.secondary)
            Text("Couldn't load timeline")
                .font(.systemScaled(16, weight: .medium))
            Text(message)
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
            Button("Try Again") {
                Task { await vm.load() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}
