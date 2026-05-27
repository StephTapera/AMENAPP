import SwiftUI

struct WellnessLibraryView: View {
    @StateObject private var service = WellnessLibraryService()
    @State private var selectedType: WellnessContentType? = nil
    @State private var selectedCategory: WellnessCategory? = nil
    @State private var selectedDifficulty: WellnessDifficulty? = nil
    @State private var searchText = ""
    @State private var showOnboarding = false
    @State private var selectedItem: WellnessContent? = nil

    var filtered: [WellnessContent] {
        guard !searchText.isEmpty else { return service.items }
        return service.items.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    typeFilterRow
                    categoryFilterRow
                    if service.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        itemGrid
                    }
                }
                .padding(.bottom, 32)
            }
            .searchable(text: $searchText, prompt: "Search wellness content")
            .navigationTitle("Wellness Library")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                service.fetchItems(category: selectedCategory, type: selectedType, difficulty: selectedDifficulty)
                showOnboarding = !UserDefaults.standard.bool(forKey: "wellnessOnboardingShown")
            }
            .sheet(isPresented: $showOnboarding) { WellnessOnboardingSheet() }
            .sheet(item: $selectedItem) { item in WellnessDetailView(content: item, service: service) }
        }
    }

    private var typeFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", icon: "square.grid.2x2.fill", isSelected: selectedType == nil) {
                    selectedType = nil
                    service.fetchItems(category: selectedCategory, type: nil, difficulty: selectedDifficulty)
                }
                ForEach(WellnessContentType.allCases, id: \.self) { type in
                    filterChip(label: type.displayName, icon: type.icon, isSelected: selectedType == type) {
                        selectedType = type
                        service.fetchItems(category: selectedCategory, type: type, difficulty: selectedDifficulty)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var categoryFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WellnessCategory.allCases, id: \.self) { cat in
                    filterChip(label: cat.displayName, icon: cat.icon, isSelected: selectedCategory == cat) {
                        selectedCategory = (selectedCategory == cat) ? nil : cat
                        service.fetchItems(category: selectedCategory, type: selectedType, difficulty: selectedDifficulty)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var itemGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(filtered) { item in
                WellnessLibraryCard(content: item)
                    .onTapGesture { selectedItem = item }
                    .accessibilityLabel("\(item.title), \(item.type.displayName), \(item.difficulty.displayName)")
            }
        }
        .padding(.horizontal, 16)
    }

    private func filterChip(label: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption)
                Text(label).font(.custom("OpenSans-Regular", size: 13))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color(red: 0.10, green: 0.60, blue: 0.56) : AmenTheme.Colors.surfaceChip)
            .foregroundStyle(isSelected ? .white : AmenTheme.Colors.textPrimary)
            .cornerRadius(20)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct WellnessLibraryCard: View {
    let content: WellnessContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: content.type.icon)
                    .foregroundStyle(Color(red: 0.10, green: 0.60, blue: 0.56))
                Spacer()
                Text(content.difficulty.displayName)
                    .font(.custom("OpenSans-Regular", size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(difficultyColor(content.difficulty).opacity(0.2))
                    .foregroundStyle(difficultyColor(content.difficulty))
                    .cornerRadius(8)
            }
            Text(content.title)
                .font(.custom("OpenSans-Bold", size: 14))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(2)
            Text(content.description)
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(2)
            if let dur = content.durationSeconds {
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.caption2)
                    Text(formatDuration(dur)).font(.custom("OpenSans-Regular", size: 11))
                }
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
        }
        .padding(12)
        .background(AmenTheme.Colors.surfaceCard)
        .cornerRadius(12)
    }

    private func difficultyColor(_ d: WellnessDifficulty) -> Color {
        switch d { case .beginner: return .green; case .intermediate: return .orange; case .advanced: return .red }
    }
    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        return minutes > 0 ? "\(minutes) min" : "\(seconds) sec"
    }
}
