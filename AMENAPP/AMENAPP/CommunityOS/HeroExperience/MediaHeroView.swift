// MediaHeroView.swift
// AMEN App — Community Around Content OS › Dynamic Hero Experience
//
// Full-screen immersive page for a ContentObject.
// Gated by CommunityOSFlag.heroExperience.

import SwiftUI
import Foundation

// MARK: - MediaHeroView

struct MediaHeroView: View {

    @StateObject private var viewModel: ContentHeroViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(contentObject: ContentObject) {
        _viewModel = StateObject(
            wrappedValue: ContentHeroViewModel(contentObject: contentObject)
        )
    }

    var body: some View {
        guard CommunityOSFlagService.shared.isEnabled(.heroExperience) else {
            return AnyView(featureGatedFallback)
        }
        return AnyView(mainBody)
    }

    // MARK: Feature-gated fallback

    private var featureGatedFallback: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(Color(.secondaryLabel))
            Text("Community Hero not yet available")
                .font(.headline)
                .foregroundStyle(Color(.label))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: Main body

    private var mainBody: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                // Full-screen scroll container.
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // 1. Hero section — top ~45% of the screen.
                        heroSection(screenHeight: proxy.size.height)

                        // 2. Community snapshot strip.
                        communitySnapshotStrip

                        // 3. Layer selector.
                        layerSelector

                        // 4. Content area — fills remaining space.
                        contentArea
                            .frame(minHeight: proxy.size.height * 0.5)
                    }
                }
                .ignoresSafeArea(edges: .top)

                // 5. Floating action tray — pinned above safe area.
                VStack(spacing: 0) {
                    // Community join banner (above the tray when visible).
                    if !viewModel.hasJoinedCommunity, let node = viewModel.communityNode {
                        joinBanner(node: node)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    ContentActionTrayView(
                        contentObject: viewModel.contentObject,
                        onPray:              { viewModel.switchLayer(.prayer) },
                        onDiscuss:           { viewModel.switchLayer(.discussion) },
                        onStudy:             { viewModel.switchLayer(.study) },
                        onTestify:           { viewModel.switchLayer(.reflection) },
                        onSaveToChurchNotes: { dlog("[MediaHeroView] save to church notes tapped") },
                        onJoinCommunity:     { Task { await viewModel.joinCommunity() } }
                    )
                    .padding(.bottom, proxy.safeAreaInsets.bottom > 0 ? proxy.safeAreaInsets.bottom : 16)
                }
                .animation(AppAnimation.stateChange, value: viewModel.hasJoinedCommunity)
                .animation(AppAnimation.stateChange, value: viewModel.communityNode?.id)
            }
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(edges: .top)
        .task { await viewModel.load() }
    }

    // MARK: 1. Hero section

    private func heroSection(screenHeight: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            // Background: thumbnail image or fallback gradient.
            heroBackground(screenHeight: screenHeight)

            // Dark scrim for text legibility.
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.65)],
                startPoint: .center,
                endPoint: .bottom
            )

            // Close button — top-left, Liquid Glass.
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.systemScaled(15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                            .amenGlassEffect(in: Circle())
                    }
                    .accessibilityLabel("Close")
                    .accessibilityHint("Dismiss the hero view")
                    .padding(.top, 56) // below dynamic island / status bar
                    .padding(.leading, 16)

                    Spacer()
                }
                Spacer()
            }

            // Text overlay — bottom-aligned.
            VStack(alignment: .leading, spacing: 6) {
                // Kind pill.
                HStack(spacing: 5) {
                    Image(systemName: viewModel.contentObject.kind.systemImage)
                        .font(.caption2)
                    Text(viewModel.contentObject.kind.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())

                // Title.
                Text(viewModel.contentObject.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                // Subtitle.
                if let subtitle = viewModel.contentObject.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(height: screenHeight * 0.45)
        .clipped()
    }

    @ViewBuilder
    private func heroBackground(screenHeight: CGFloat) -> some View {
        if let urlString = viewModel.contentObject.thumbnailURL,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: screenHeight * 0.45)
                        .clipped()
                        .overlay(Color.black.opacity(0.25))
                case .failure:
                    fallbackGradient(height: screenHeight * 0.45)
                case .empty:
                    fallbackGradient(height: screenHeight * 0.45)
                        .redacted(reason: .placeholder)
                @unknown default:
                    fallbackGradient(height: screenHeight * 0.45)
                }
            }
        } else {
            fallbackGradient(height: screenHeight * 0.45)
        }
    }

    private func fallbackGradient(height: CGFloat) -> some View {
        LinearGradient(
            colors: [
                viewModel.dominantColor == .clear ? Color(.systemIndigo) : viewModel.dominantColor,
                Color.black.opacity(0.85)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    // MARK: 2. Community snapshot strip

    private var communitySnapshotStrip: some View {
        VStack(spacing: 0) {
            Divider()
            CommunitySnapshotView(
                node: viewModel.communityNode,
                isLoading: viewModel.isLoadingCommunity
            )
            Divider()
        }
    }

    // MARK: 3. Layer selector

    private var layerSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.availableLayers, id: \.self) { layer in
                    let isSelected = viewModel.activeLayer == layer
                    Button {
                        viewModel.switchLayer(layer)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: layer.systemImage)
                                .font(.caption)
                            Text(layer.displayName)
                                .font(.subheadline)
                                .fontWeight(isSelected ? .semibold : .regular)
                        }
                        .foregroundStyle(isSelected ? Color(.label) : Color(.secondaryLabel))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color(.secondarySystemBackground))
                                    .amenGlassEffect(in: Capsule())
                            } else {
                                Capsule()
                                    .fill(Color.clear)
                                    .overlay(
                                        Capsule()
                                            .stroke(Color(.separator), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(layer.displayName)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .animation(AppAnimation.stateChange, value: viewModel.activeLayer)
        }
        .background(Color(.systemBackground))
    }

    // MARK: 4. Content area

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch viewModel.activeLayer {
            case .discussion:
                discussionLayer
            case .prayer:
                prayerLayer
            case .reflection:
                reflectionLayer
            case .study:
                studyLayer
            case .mentorship:
                mentorshipLayer
            case .realWorld:
                realWorldLayer
            case .worship:
                worshipLayer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .padding(.bottom, 140) // clearance for floating tray
    }

    // MARK: Layer content views

    private var discussionLayer: some View {
        VStack(alignment: .leading, spacing: 12) {
            layerHeader(layer: .discussion)
            Text("Discussion coming soon")
                .font(.body)
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.horizontal, 16)
        }
        .padding(.top, 16)
    }

    private var prayerLayer: some View {
        VStack(alignment: .leading, spacing: 16) {
            layerHeader(layer: .prayer)
            Text(CommunityLayer.prayer.prompt)
                .font(.body)
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.horizontal, 16)

            // Prayer input placeholder.
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .frame(height: 100)
                .overlay(
                    Text("Write your prayer…")
                        .font(.body)
                        .foregroundStyle(Color(.tertiaryLabel))
                        .padding(12),
                    alignment: .topLeading
                )
                .padding(.horizontal, 16)
                .accessibilityLabel("Prayer input field")
                .accessibilityHint("Tap to write your prayer")
        }
        .padding(.top, 16)
    }

    private var reflectionLayer: some View {
        VStack(alignment: .leading, spacing: 16) {
            layerHeader(layer: .reflection)
            if viewModel.reflectionPrompts.isEmpty {
                Text("Reflection prompts loading…")
                    .font(.body)
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.horizontal, 16)
                    .redacted(reason: .placeholder)
            } else {
                ForEach(Array(viewModel.reflectionPrompts.enumerated()), id: \.offset) { _, prompt in
                    ReflectionPromptRow(prompt: prompt)
                }
            }
        }
        .padding(.top, 16)
    }

    private var studyLayer: some View {
        VStack(alignment: .leading, spacing: 16) {
            layerHeader(layer: .study)
            if viewModel.matchedVerses.isEmpty {
                Text("No scripture references attached yet.")
                    .font(.body)
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.horizontal, 16)
            } else {
                ForEach(viewModel.matchedVerses, id: \.self) { ref in
                    VerseRefRow(verseRef: ref)
                }
            }
        }
        .padding(.top, 16)
    }

    private var mentorshipLayer: some View {
        VStack(alignment: .leading, spacing: 12) {
            layerHeader(layer: .mentorship)
            Text(CommunityLayer.mentorship.prompt)
                .font(.body)
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.horizontal, 16)
            Text("Mentorship connections coming soon.")
                .font(.footnote)
                .foregroundStyle(Color(.tertiaryLabel))
                .padding(.horizontal, 16)
        }
        .padding(.top, 16)
    }

    private var realWorldLayer: some View {
        VStack(alignment: .leading, spacing: 12) {
            layerHeader(layer: .realWorld)
            Text(CommunityLayer.realWorld.prompt)
                .font(.body)
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.horizontal, 16)
            Text("Real-world impact tracking coming soon.")
                .font(.footnote)
                .foregroundStyle(Color(.tertiaryLabel))
                .padding(.horizontal, 16)
        }
        .padding(.top, 16)
    }

    private var worshipLayer: some View {
        VStack(alignment: .leading, spacing: 12) {
            layerHeader(layer: .worship)
            Text(CommunityLayer.worship.prompt)
                .font(.body)
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.horizontal, 16)
            Text("Worship session coming soon.")
                .font(.footnote)
                .foregroundStyle(Color(.tertiaryLabel))
                .padding(.horizontal, 16)
        }
        .padding(.top, 16)
    }

    // MARK: Shared layer subviews

    private func layerHeader(layer: CommunityLayer) -> some View {
        HStack(spacing: 8) {
            Image(systemName: layer.systemImage)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
            Text(layer.displayName)
                .font(.headline)
                .foregroundStyle(Color(.label))
        }
        .padding(.horizontal, 16)
    }

    // MARK: Join banner

    private func joinBanner(node: CommunityNode) -> some View {
        HStack {
            Text("Join the \(node.name) community")
                .font(.subheadline)
                .foregroundStyle(Color(.label))
                .lineLimit(1)

            Spacer()

            Button {
                Task { await viewModel.joinCommunity() }
            } label: {
                Text("Join")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .amenGlassEffect(in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Join \(node.name)")
            .accessibilityHint("Become a member of this content community")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .top)
    }
}

// MARK: - ReflectionPromptRow

private struct ReflectionPromptRow: View {
    let prompt: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 3)
            Text(prompt)
                .font(.body)
                .foregroundStyle(Color(.label))
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reflection prompt: \(prompt)")
    }
}

// MARK: - VerseRefRow

private struct VerseRefRow: View {
    let verseRef: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.fill")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            Text(verseRef)
                .font(.body)
                .foregroundStyle(Color(.label))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scripture: \(verseRef)")
        .accessibilityHint("Tap to read \(verseRef)")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Song — loaded") {
    let song = ContentObject(
        kind: .song,
        source: .spotify,
        title: "Goodness of God",
        subtitle: "Bethel Music",
        thumbnailURL: nil,
        rawURL: "https://open.spotify.com/track/example",
        communityScore: 0.92,
        discussionCount: 4_200,
        prayerCount: 900,
        testimonyCount: 220,
        themes: ["gratitude", "grace", "worship"],
        linkedVerseRefs: ["Psalm 23:6", "Romans 8:28"]
    )
    MediaHeroView(contentObject: song)
}

#Preview("Bible Verse") {
    let verse = ContentObject(
        kind: .bibleVerse,
        source: .bibleRef,
        title: "For God so loved the world",
        subtitle: "John 3:16 (NIV)",
        rawURL: "bible://john/3/16",
        discussionCount: 12_500,
        prayerCount: 3_400,
        linkedVerseRefs: ["John 3:16", "Romans 5:8", "1 John 4:9"]
    )
    MediaHeroView(contentObject: verse)
}
#endif
