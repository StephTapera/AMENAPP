import SwiftUI

enum CatalogMorphState {
    case compact, expanded, fullScreen
}

struct CatalogPillView: View {

    let creatorId: String
    let creatorName: String

    @StateObject private var vm: CatalogViewModel
    @State private var morphState: CatalogMorphState = .compact
    @State private var showFullScreen = false
    @Namespace private var morphNamespace

    init(creatorId: String, creatorName: String) {
        self.creatorId = creatorId
        self.creatorName = creatorName
        _vm = StateObject(wrappedValue: CatalogViewModel(creatorId: creatorId))
    }

    var body: some View {
        Group {
            switch morphState {
            case .compact:
                compactPill
            case .expanded:
                expandedCard
            case .fullScreen:
                expandedCard
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: morphState)
        .task { await vm.load() }
        .fullScreenCover(isPresented: $showFullScreen) {
            fullScreenCatalog
        }
    }

    // MARK: - Compact

    private var compactPill: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                morphState = .expanded
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "books.vertical")
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(.primary)
                Text(pillSummary)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .amenGlassEffect(in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var pillSummary: String {
        let count = vm.workCount
        let typeNames = vm.activeTypeNames.prefix(3).joined(separator: " · ")
        if count == 0 { return "Catalog" }
        return "\(count) works · \(typeNames)"
    }

    // MARK: - Expanded

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "books.vertical")
                    .font(.systemScaled(16, weight: .medium))
                Text(creatorName)
                    .font(.systemScaled(16, weight: .semibold))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        morphState = .compact
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if case .populated(let works) = vm.state {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(works.prefix(3)) { work in
                            compactCoverThumb(work: work)
                        }
                    }
                }
            }

            if !vm.tabs.isEmpty {
                CatalogWorkTypeTabBar(tabs: vm.tabs, selectedType: $vm.selectedType) { type in
                    Task { await vm.selectType(type) }
                }
            }

            Button {
                showFullScreen = true
            } label: {
                HStack {
                    Text("See all →")
                        .font(.systemScaled(14, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(.primary)
            }
        }
        .padding(16)
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func compactCoverThumb(work: CatalogWork) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.secondary.opacity(0.1))
                    .frame(width: 56, height: 56)
                Image(systemName: work.type.icon)
                    .font(.systemScaled(20, weight: .light))
                    .foregroundStyle(.secondary)
            }
            Text(work.title)
                .font(.systemScaled(10, weight: .medium))
                .lineLimit(1)
                .frame(width: 56)
        }
    }

    // MARK: - Full-Screen

    private var fullScreenCatalog: some View {
        NavigationStack {
            CatalogWorkGridView(creatorId: creatorId, creatorName: creatorName)
                .navigationTitle("\(creatorName)'s Catalog")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showFullScreen = false }
                    }
                }
        }
    }
}
