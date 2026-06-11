//
//  WhatsNewArchiveView.swift
//  AMEN — Amen Pulse (What's New archive)
//
//  A finite, chronological archive (newest first) of editorial "What's New"
//  stories. The archive is allowed to be chronological — it is not the daily
//  Pulse surface. Each compact glass card opens the full WhatsNewStoryView.
//  The presenting surface already wraps this in a NavigationStack, so this view
//  only sets navigationTitle + a toolbar Close button.
//

import SwiftUI

struct WhatsNewArchiveView: View {
    init() {}

    @Environment(\.dismiss) private var dismiss

    @State private var stories: [WhatsNewStory] = []
    @State private var isLoading: Bool = true
    @State private var selection: StorySelection?

    var body: some View {
        ZStack {
            Color(hex: "F2F2F7").ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            } else if stories.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("What's New")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .font(.system(size: 16, weight: .semibold))
                }
                .accessibilityLabel(Text("Close"))
            }
        }
        .task {
            await load()
        }
        .fullScreenCover(item: $selection) { sel in
            WhatsNewStoryView(storyId: sel.id)
        }
    }

    // MARK: - Loading

    private func load() async {
        defer { isLoading = false }
        if let loaded = try? await PulseService.shared.loadWhatsNew(includeAdultOnly: false) {
            stories = loaded.sorted { lhs, rhs in
                (lhs.publishedAt ?? .distantPast) > (rhs.publishedAt ?? .distantPast)
            }
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(stories) { story in
                    Button {
                        selection = StorySelection(id: story.id)
                    } label: {
                        StoryCard(story: story)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .regular))
                .foregroundColor(Color(hex: "8A8A8E"))
            Text("No updates yet.")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(hex: "3C3C43"))
        }
    }

    // MARK: - Card

    private struct StoryCard: View {
        let story: WhatsNewStory

        private var heroStyle: PulseHeroStyle {
            PulseHeroStyle.resolve(story.pages.first?.style ?? "whatsnew")
        }

        var body: some View {
            HStack(spacing: 14) {
                thumbnail
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(story.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(hex: "1C1C1E"))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    Text(story.tagline)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "3C3C43").opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if !story.version.isEmpty {
                            Text(story.version)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: "8A8A8E"))
                        }
                        if !story.version.isEmpty, story.publishedAt != nil {
                            Text("·")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: "C7C7CC"))
                        }
                        if let published = story.publishedAt {
                            Text(Self.relativeDate(published))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(hex: "8A8A8E"))
                        }
                    }
                    .padding(.top, 1)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }

        @ViewBuilder
        private var thumbnail: some View {
            if let urlString = story.pages.first?.heroImageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        heroStyle.background()
                    case .failure:
                        heroStyle.background()
                    @unknown default:
                        heroStyle.background()
                    }
                }
            } else {
                heroStyle.background()
            }
        }

        private static func relativeDate(_ date: Date) -> String {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: date, relativeTo: Date())
        }
    }

    // MARK: - Selection box

    private struct StorySelection: Identifiable {
        let id: String
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        WhatsNewArchiveView()
    }
}
#endif
