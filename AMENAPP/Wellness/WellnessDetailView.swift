import SwiftUI

struct WellnessDetailView: View {
    let content: WellnessContent
    let service: WellnessLibraryService
    @State private var currentStep = 0
    @State private var isSaved = false
    @State private var isHelpful = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    contentSection
                    linkedVersesSection
                    engagementSection
                }
                .padding(16)
                .padding(.bottom, 40)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                        .font(.custom("OpenSans-Regular", size: 16))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isSaved.toggle()
                        service.trackEngagement(wellnessId: content.id ?? "", action: isSaved ? "save" : "unsave")
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(isSaved ? Color(red: 0.83, green: 0.69, blue: 0.22) : AmenTheme.Colors.textSecondary)
                    }
                    .accessibilityLabel(isSaved ? "Remove from saved" : "Save")
                }
            }
            .onAppear {
                service.trackEngagement(wellnessId: content.id ?? "", action: "view")
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: content.type.icon)
                    .foregroundStyle(Color(red: 0.10, green: 0.60, blue: 0.56))
                Text(content.type.displayName)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                Spacer()
                Text(content.difficulty.displayName)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.10, green: 0.60, blue: 0.56).opacity(0.15))
                    .foregroundStyle(Color(red: 0.10, green: 0.60, blue: 0.56))
                    .cornerRadius(10)
            }
            Text(content.title)
                .font(.custom("OpenSans-Bold", size: 22))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text(content.description)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            if let dur = content.durationSeconds {
                Label(formatDuration(dur), systemImage: "clock")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        switch content.type {
        case .groundingExercise:
            if let steps = content.steps, !steps.isEmpty {
                groundingStepsView(steps: steps)
            }
        case .article, .prayer, .journalPrompt:
            if let body = content.body {
                Text(body)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineSpacing(6)
            }
        case .meditation, .tool, .video:
            if let url = content.audioUrl ?? content.videoUrl {
                Link(destination: URL(string: url) ?? URL(string: "https://example.com")!) {
                    Label("Open Content", systemImage: content.type == .video ? "play.rectangle.fill" : "waveform")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(red: 0.10, green: 0.60, blue: 0.56))
                        .cornerRadius(12)
                }
                .accessibilityLabel("Open \(content.type.displayName) content")
            }
        }
    }

    private func groundingStepsView(steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Steps")
                .font(.custom("OpenSans-Bold", size: 17))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(index == currentStep ? Color(red: 0.10, green: 0.60, blue: 0.56) : AmenTheme.Colors.surfaceChip)
                        .frame(width: 28, height: 28)
                        .overlay(Text("\(index + 1)").font(.custom("OpenSans-Bold", size: 13)).foregroundStyle(index == currentStep ? .white : AmenTheme.Colors.textSecondary))
                    Text(step)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(index == currentStep ? AmenTheme.Colors.textPrimary : AmenTheme.Colors.textTertiary)
                    Spacer()
                }
                .padding(12)
                .background(AmenTheme.Colors.surfaceCard)
                .cornerRadius(10)
                .onTapGesture { withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) { currentStep = index } }
                .accessibilityLabel("Step \(index + 1): \(step)")
            }
            if currentStep < (steps.count - 1) {
                AmenLiquidGlassPillButton(
                    title: "Next Step",
                    systemImage: "arrow.right",
                    isLoading: false,
                    isDisabled: false,
                    hint: "Advances to the next grounding step",
                    action: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) { currentStep += 1 }
                    }
                )
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Next step")
            }
        }
    }

    private var linkedVersesSection: some View {
        Group {
            if let verses = content.linkedVerses, !verses.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Related Scripture")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    ForEach(verses, id: \.book) { verse in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(verse.book) \(verse.chapter):\(verse.verse)")
                                .font(.custom("OpenSans-Bold", size: 13))
                                .foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
                            Text(verse.text)
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                                .italic()
                        }
                        .padding(10)
                        .background(Color(red: 0.83, green: 0.69, blue: 0.22).opacity(0.08))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    private var engagementSection: some View {
        HStack(spacing: 16) {
            Button {
                isSaved.toggle()
                service.trackEngagement(wellnessId: content.id ?? "", action: isSaved ? "save" : "unsave")
            } label: {
                Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(isSaved ? AmenTheme.Colors.amenGold : AmenTheme.Colors.textSecondary)
            }
            .accessibilityLabel(isSaved ? "Remove from saved" : "Save this content")

            Button {
                isHelpful = true
                service.trackEngagement(wellnessId: content.id ?? "", action: "helpful")
            } label: {
                Label("Helpful", systemImage: isHelpful ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(isHelpful ? Color(red: 0.10, green: 0.60, blue: 0.56) : AmenTheme.Colors.textSecondary)
            }
            .disabled(isHelpful)
            .accessibilityLabel(isHelpful ? "Marked as helpful" : "Mark as helpful")
        }
        .padding(.top, 8)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        return minutes > 0 ? "\(minutes) min" : "\(seconds) sec"
    }
}
