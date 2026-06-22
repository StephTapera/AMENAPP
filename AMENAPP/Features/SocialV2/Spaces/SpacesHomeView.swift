import SwiftUI

struct SpacesHomeView: View {
    private let previews: [SpacesSpacePreview]
    private let pillColumns = [GridItem(.adaptive(minimum: 140), spacing: 8)]

    init(previews: [SpacesSpacePreview] = SpacesSampleService.previews) {
        self.previews = previews
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                LazyVStack(spacing: 12) {
                    ForEach(previews) { preview in
                        SpacePreviewCard(preview: preview)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.sRGB, red: 0.95, green: 0.96, blue: 0.98, opacity: 1))
        .navigationTitle("Spaces")
    }

    private var header: some View {
        SocialV2GlassCard(tintContext: .interactive, isActive: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Spaces")
                            .font(.title2.weight(.bold))

                        Text("Discover moderated communities without exposing exact location.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "person.3.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                }

                LazyVGrid(columns: pillColumns, alignment: .leading, spacing: 8) {
                    SocialV2GlassPill(tintContext: .state, isSelected: true) {
                        Label("Moderated first", systemImage: "checkmark.shield")
                    }

                    SocialV2GlassPill(tintContext: .interactive) {
                        Label("Approximate scope", systemImage: "location.magnifyingglass")
                    }

                    SocialV2GlassPill(tintContext: .neutral) {
                        Label("Categorical trust", systemImage: "tag")
                    }
                }
            }
        }
    }
}

private struct SpacePreviewCard: View {
    let preview: SpacesSpacePreview
    private let pillColumns = [GridItem(.adaptive(minimum: 112), spacing: 8)]

    var body: some View {
        SocialV2GlassCard(tintContext: preview.isReadable ? .neutral : .alert) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(preview.space.name)
                        .font(.headline)

                    Spacer(minLength: 12)

                    moderationBadge
                }

                Text(preview.isReadable ? preview.space.summary : preview.moderationDecision.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: pillColumns, alignment: .leading, spacing: 8) {
                    infoPill(title: preview.space.kind.rawValue.capitalized, systemImage: "square.grid.2x2")
                    infoPill(title: locationScopeLabel, systemImage: "location")
                    infoPill(title: preview.memberCountLabel, systemImage: "person.2")
                }

                topics
                trustSignals
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var moderationBadge: some View {
        SocialV2GlassPill(tintContext: preview.isReadable ? .state : .alert, isSelected: true) {
            Label(moderationLabel, systemImage: moderationIcon)
        }
    }

    private var trustSignals: some View {
        LazyVGrid(columns: pillColumns, alignment: .leading, spacing: 8) {
            ForEach(preview.space.trustSignals, id: \.self) { signal in
                SocialV2GlassPill(tintContext: .interactive) {
                    Text(signal.rawValue.capitalized)
                }
            }
        }
    }

    private var topics: some View {
        LazyVGrid(columns: pillColumns, alignment: .leading, spacing: 8) {
            ForEach(preview.highlightedTopics, id: \.self) { topic in
                SocialV2GlassPill(tintContext: .neutral) {
                    Text(topic)
                }
            }
        }
    }

    private func infoPill(title: String, systemImage: String) -> some View {
        SocialV2GlassPill(tintContext: .neutral) {
            Label(title, systemImage: systemImage)
        }
    }

    private var moderationLabel: String {
        switch preview.moderationDecision.status {
        case .pending:
            return "Pending"
        case .approved:
            return "Approved"
        case .held:
            return "Held"
        case .removed:
            return "Removed"
        }
    }

    private var moderationIcon: String {
        preview.isReadable ? "checkmark.shield" : "hourglass"
    }

    private var locationScopeLabel: String {
        switch preview.space.locationScope {
        case .approximate:
            return "Approximate"
        case .city:
            return "City"
        case .region:
            return "Region"
        case .hidden:
            return "Hidden"
        }
    }
}
