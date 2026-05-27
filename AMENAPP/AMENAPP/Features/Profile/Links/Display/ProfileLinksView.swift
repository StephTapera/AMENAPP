import SwiftUI

// MARK: - ProfileLinksView

/// Compact link display for the Profile Header v2.
/// Shows the first slot as a tappable capsule and an "and N more" overflow link.
/// Consumed by Agent G (integration) via `ProfileLinksView(slots:)`.
struct ProfileLinksView: View {

    // MARK: Init

    /// Primary initialiser — preferred for composability (no store dependency).
    init(slots: [LinkSlot]) {
        self.slots = slots
    }

    /// Convenience initialiser — reads live slots from the store.
    init(store: ProfileLinksStore) {
        self.slots = store.slots
    }

    // MARK: State

    private let slots: [LinkSlot]
    @State private var showExpanded = false
    @Environment(\.openURL) private var openURL

    // MARK: Body

    var body: some View {
        if slots.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 8) {
                primaryCapsule
                if slots.count > 1 {
                    overflowButton
                }
            }
        }
    }

    // MARK: Primary Capsule

    @ViewBuilder
    private var primaryCapsule: some View {
        let primary = slots[0]
        Button {
            openURL(primary.url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: primary.type.systemImage)
                    .font(.system(size: 13, weight: .medium))
                Text(primary.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(primary.label)
        .accessibilityHint("Opens \(primary.url.absoluteString)")
    }

    // MARK: Overflow Button

    @ViewBuilder
    private var overflowButton: some View {
        let extraCount = slots.count - 1
        Button {
            showExpanded = true
        } label: {
            Text("and \(extraCount) more")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(extraCount) more link\(extraCount == 1 ? "" : "s")")
        .sheet(isPresented: $showExpanded) {
            ExpandedLinksSheet(slots: slots)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Single link") {
    let slots: [LinkSlot] = [
        LinkSlot(id: "1", type: .church, url: URL(string: "https://mychurch.org")!, label: "My Church", order: 0)
    ]
    VStack {
        ProfileLinksView(slots: slots)
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Multiple links") {
    let slots: [LinkSlot] = [
        LinkSlot(id: "1", type: .church,  url: URL(string: "https://mychurch.org")!,    label: "My Church",     order: 0),
        LinkSlot(id: "2", type: .giving,  url: URL(string: "https://give.example.com")!, label: "Give",          order: 1),
        LinkSlot(id: "3", type: .podcast, url: URL(string: "https://podcasts.apple.com")!, label: "Podcast",     order: 2),
    ]
    VStack {
        ProfileLinksView(slots: slots)
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Empty") {
    ProfileLinksView(slots: [])
        .padding()
}
#endif
