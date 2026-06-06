import SwiftUI

struct FaithWrappedView: View {
    @StateObject private var viewModel = SpiritualJourneyViewModel()
    @GestureState private var isPressing = false
    @Environment(\.dismiss) private var dismiss

    let period: JourneyPeriod
    @State private var selectedPeriod: JourneyPeriod
    @State private var showShareSheet = false
    @State private var shareText: String = ""
    @State private var showDeeperInsights = false

    init(period: JourneyPeriod) {
        self.period = period
        _selectedPeriod = State(initialValue: period)
    }

    var body: some View {
        ZStack {
            backgroundLayer

            switch viewModel.state {
            case .loading:
                WrappedLoadingView()
            case .failed(let message):
                failureView(message)
            default:
                if let story = viewModel.story {
                    VStack(spacing: 0) {
                        FaithWrappedProgressBar(
                            total: story.slides.count,
                            currentIndex: viewModel.currentSlideIndex,
                            progress: viewModel.progress
                        )
                        .padding(.top, 8)
                        .padding(.horizontal, 12)

                        periodSelector
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        Spacer()

                        FaithWrappedSlideView(slide: story.slides[viewModel.currentSlideIndex])
                            .id(story.slides[viewModel.currentSlideIndex].id)
                            .transition(.opacity.combined(with: .scale(scale: 0.985)))

                        Spacer()

                        bottomActions
                    }
                }
            }
        }
        .background(Color.white)
        .overlay(gestureOverlay)
        .task {
            await viewModel.loadStory(period: selectedPeriod)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [shareText])
        }
    }

    private var backgroundLayer: some View {
        LinearGradient(
            colors: [
                Color.white,
                Color(red: 0.98, green: 0.97, blue: 0.95),
                Color(red: 0.96, green: 0.95, blue: 0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var gestureOverlay: some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { viewModel.goBack() }

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { viewModel.advance() }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.15)
                .updating($isPressing) { current, state, _ in
                    state = current
                }
                .onEnded { _ in
                    viewModel.resume()
                }
        )
        .onChange(of: isPressing) { _, pressing in
            if pressing {
                viewModel.pause()
            }
        }
    }

    private var periodSelector: some View {
        HStack {
            Menu {
                ForEach(JourneyPeriod.allCases, id: \.self) { option in
                    Button(option.rawValue.capitalized) {
                        selectedPeriod = option
                        Task { await viewModel.loadStory(period: option) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedPeriod.rawValue.capitalized)
                        .font(AMENFont.semiBold(12))
                    Image(systemName: "chevron.down")
                        .font(.systemScaled(10, weight: .semibold))
                }
                .foregroundStyle(.black.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.05), in: Capsule())
            }
            Spacer()
        }
    }

    private var bottomActions: some View {
        HStack(spacing: 12) {
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.plain)
            Button("Share Summary") {
                shareText = makeShareText()
                showShareSheet = true
            }
            .buttonStyle(.plain)
            Button("Deeper Insights") {
                showDeeperInsights = true
            }
            .buttonStyle(.plain)
        }
        .font(AMENFont.semiBold(12))
        .foregroundStyle(.black.opacity(0.7))
        .padding(.bottom, 24)
        .sheet(isPresented: $showDeeperInsights) {
            FaithWrappedInsightsSheet(story: viewModel.story, period: selectedPeriod)
        }
    }

    private func makeShareText() -> String {
        guard let story = viewModel.story else { return "My Spiritual Journey" }
        let summary = story.safeShareCard?.highlights.joined(separator: " · ") ?? ""
        let subtitle = story.safeShareCard?.subtitle ?? "A season of faith"
        return "My Spiritual Journey — \(subtitle)\n\(summary)"
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("Couldn’t load your spiritual journey")
                .font(AMENFont.bold(18))
            Text(message)
                .font(AMENFont.medium(13))
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Deeper Insights Sheet

struct FaithWrappedInsightsSheet: View {
    let story: SpiritualJourneyStory?
    let period: JourneyPeriod
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let story {
                        // Summary card
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Journey Summary", systemImage: "chart.bar.fill")
                                .font(.headline)
                            Text(story.safeShareCard?.subtitle ?? "A season of faith")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )

                        // Highlights
                        if let highlights = story.safeShareCard?.highlights, !highlights.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Highlights")
                                    .font(.headline)
                                ForEach(highlights, id: \.self) { highlight in
                                    Label(highlight, systemImage: "star.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            )
                        }

                        // Slide themes
                        let themes = story.slides.compactMap { $0.subtitle }.filter { !$0.isEmpty }
                        if !themes.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Themes This \(period.rawValue.capitalized)")
                                    .font(.headline)
                                ForEach(themes.prefix(6), id: \.self) { theme in
                                    Text("• \(theme)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            )
                        }
                    } else {
                        Text("No insights available for this period.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Deeper Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct FaithWrappedProgressBar: View {
    let total: Int
    let currentIndex: Int
    let progress: Double

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.12))
                        Capsule()
                            .fill(Color.black.opacity(index == currentIndex ? 0.85 : 0.45))
                            .frame(width: fillWidth(total: geo.size.width, index: index))
                    }
                }
                .frame(height: 3)
            }
        }
        .frame(height: 3)
    }

    private func fillWidth(total width: CGFloat, index: Int) -> CGFloat {
        if index < currentIndex { return width }
        if index == currentIndex { return width * progress }
        return 0
    }
}

struct FaithWrappedSlideView: View {
    let slide: SpiritualJourneySlide

    var body: some View {
        Group {
            switch slide.type {
            case .intro:
                IntroSlideView(slide: slide)
            case .consistency:
                ConsistencySlideView(slide: slide)
            case .emotionRhythm:
                EmotionRhythmSlideView(slide: slide)
            case .topThemes:
                TopThemesSlideView(slide: slide)
            case .communityImpact:
                CommunityImpactSlideView(slide: slide)
            case .comeback:
                ComebackSlideView(slide: slide)
            case .blessing:
                BlessingSlideView(slide: slide)
            default:
                BasicSlideView(slide: slide)
            }
        }
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.45), value: slide.id)
    }
}

struct IntroSlideView: View {
    let slide: SpiritualJourneySlide

    var body: some View {
        VStack(spacing: 12) {
            Text(slide.title)
                .font(AMENFont.bold(28))
                .multilineTextAlignment(.center)
            if let subtitle = slide.subtitle {
                Text(subtitle)
                    .font(AMENFont.medium(15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct ConsistencySlideView: View {
    let slide: SpiritualJourneySlide

    var body: some View {
        VStack(spacing: 12) {
            Text(slide.title)
                .font(AMENFont.bold(24))
            if let subtitle = slide.subtitle {
                Text(subtitle)
                    .font(AMENFont.semiBold(18))
            }
            if let body = slide.body {
                Text(body)
                    .font(AMENFont.medium(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct EmotionRhythmSlideView: View {
    let slide: SpiritualJourneySlide

    var body: some View {
        VStack(spacing: 12) {
            Text(slide.title)
                .font(AMENFont.bold(22))
            if let subtitle = slide.subtitle {
                Text(subtitle)
                    .font(AMENFont.medium(14))
                    .foregroundStyle(.secondary)
            }
            StaggeredChipRow(chips: slide.chips)
        }
    }
}

struct TopThemesSlideView: View {
    let slide: SpiritualJourneySlide

    var body: some View {
        VStack(spacing: 12) {
            Text(slide.title)
                .font(AMENFont.bold(22))
            if let subtitle = slide.subtitle {
                Text(subtitle)
                    .font(AMENFont.medium(14))
                    .foregroundStyle(.secondary)
            }
            StaggeredChipRow(chips: slide.chips)
        }
    }
}

struct CommunityImpactSlideView: View {
    let slide: SpiritualJourneySlide

    var body: some View {
        VStack(spacing: 12) {
            Text(slide.title)
                .font(AMENFont.bold(22))
            if let subtitle = slide.subtitle {
                Text(subtitle)
                    .font(AMENFont.semiBold(16))
            }
            if let body = slide.body {
                Text(body)
                    .font(AMENFont.medium(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct ComebackSlideView: View {
    let slide: SpiritualJourneySlide

    var body: some View {
        VStack(spacing: 12) {
            Text(slide.title)
                .font(AMENFont.bold(22))
            if let subtitle = slide.subtitle {
                Text(subtitle)
                    .font(AMENFont.medium(14))
                    .foregroundStyle(.secondary)
            }
            if let body = slide.body {
                Text(body)
                    .font(AMENFont.medium(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct BlessingSlideView: View {
    let slide: SpiritualJourneySlide

    var body: some View {
        VStack(spacing: 12) {
            Text(slide.title)
                .font(AMENFont.bold(22))
            if let subtitle = slide.subtitle {
                Text(subtitle)
                    .font(AMENFont.medium(14))
                    .foregroundStyle(.secondary)
            }
            if let body = slide.body {
                Text(body)
                    .font(AMENFont.medium(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let scripture = slide.scripture {
                Text("\"\(scripture.text)\"")
                    .font(AMENFont.medium(12))
                    .foregroundStyle(.secondary)
                Text(scripture.reference)
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BasicSlideView: View {
    let slide: SpiritualJourneySlide

    var body: some View {
        VStack(spacing: 12) {
            Text(slide.title)
                .font(AMENFont.bold(22))
            if let subtitle = slide.subtitle {
                Text(subtitle)
                    .font(AMENFont.medium(14))
                    .foregroundStyle(.secondary)
            }
            if let body = slide.body {
                Text(body)
                    .font(AMENFont.medium(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct StaggeredChipRow: View {
    let chips: [String]
    @State private var visibleCount: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                if index < visibleCount {
                    Text(chip)
                        .font(AMENFont.semiBold(12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .task {
            visibleCount = 0
            for i in 0..<chips.count {
                try? await Task.sleep(nanoseconds: 80_000_000)
                visibleCount = i + 1
            }
        }
    }
}

struct WrappedLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Preparing your spiritual journey…")
                .font(AMENFont.medium(14))
                .foregroundStyle(.secondary)
        }
    }
}
