import SwiftUI

struct WellnessOnboardingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    @State private var selectedCategories: Set<WellnessCategory> = []

    private let pages: [(title: String, subtitle: String, icon: String)] = [
        ("Your Wellbeing Matters", "AMEN offers tools, prayers, and resources to support your whole self — mind, body, and spirit.", "heart.text.square.fill"),
        ("Explore the Library", "Browse grounding exercises, articles, meditations, and prayers curated for your journey.", "books.vertical.fill"),
        ("Build Daily Habits", "Track your wellness streaks and earn badges as you grow in consistency and faith.", "flame.fill")
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    onboardingPage(page: page, index: index).tag(index)
                }
                categorySelectionPage.tag(pages.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            pageIndicator
            navigationButtons
        }
        .background(AmenTheme.Colors.backgroundPrimary)
    }

    private func onboardingPage(page: (title: String, subtitle: String, icon: String), index: Int) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: page.icon)
                .font(.system(size: 64))
                .foregroundStyle(Color(red: 0.10, green: 0.60, blue: 0.56))
                .symbolEffect(.pulse)
            Text(page.title)
                .font(.custom("OpenSans-Bold", size: 26))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(page.subtitle)
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var categorySelectionPage: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("What's your primary focus?")
                .font(.custom("OpenSans-Bold", size: 22))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text("Select up to 3 areas. We'll personalize your recommendations.")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(WellnessCategory.allCases, id: \.self) { cat in
                    let isSelected = selectedCategories.contains(cat)
                    Button {
                        if isSelected { selectedCategories.remove(cat) }
                        else if selectedCategories.count < 3 { selectedCategories.insert(cat) }
                    } label: {
                        HStack {
                            Image(systemName: cat.icon)
                            Text(cat.displayName).font(.custom("OpenSans-Regular", size: 14))
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? Color(red: 0.10, green: 0.60, blue: 0.56) : AmenTheme.Colors.surfaceCard)
                        .foregroundStyle(isSelected ? .white : AmenTheme.Colors.textPrimary)
                        .cornerRadius(10)
                    }
                    .accessibilityLabel(cat.displayName)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            Spacer()
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<(pages.count + 1), id: \.self) { i in
                Circle()
                    .fill(i == currentPage ? Color(red: 0.10, green: 0.60, blue: 0.56) : AmenTheme.Colors.surfaceChip)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 12)
    }

    private var navigationButtons: some View {
        HStack {
            if currentPage > 0 {
                Button("Back") {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) { currentPage -= 1 }
                }
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .padding()
            }
            Spacer()
            Button(currentPage < pages.count ? "Next" : "Get Started") {
                if currentPage < pages.count {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) { currentPage += 1 }
                } else {
                    if !selectedCategories.isEmpty {
                        UserDefaults.standard.set(Array(selectedCategories.map { $0.rawValue }), forKey: "wellnessFocusCategories")
                    }
                    UserDefaults.standard.set(true, forKey: "wellnessOnboardingShown")
                    dismiss()
                }
            }
            .font(.custom("OpenSans-Bold", size: 16))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color(red: 0.10, green: 0.60, blue: 0.56))
            .cornerRadius(12)
            .padding()
        }
    }
}
