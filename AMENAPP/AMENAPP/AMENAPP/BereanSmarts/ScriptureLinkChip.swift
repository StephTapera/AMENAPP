import SwiftUI

// MARK: - ScriptureLinkChip
// Tappable glass chip showing a verse reference. Tap to expand inline verse text.
// Used in CommunalChatView bubble rows and LiveMeetingView.

struct ScriptureLinkChip: View {
    let reference: String
    let isExpanded: Bool
    let onTap: () -> Void

    @State private var verseText: String?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                onTap()
                if verseText == nil && !isLoading { Task { await load() } }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "book.pages").font(.caption2)
                    Text(reference).font(.caption.weight(.medium))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .opacity(0.6)
                }
                .foregroundStyle(AmenTheme.Colors.accentPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule()
                                .strokeBorder(AmenTheme.Colors.accentPrimary.opacity(0.35), lineWidth: 0.5)
                        }
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Group {
                    if isLoading {
                        ProgressView().scaleEffect(0.7).padding(12)
                    } else if let text = verseText {
                        Text(text)
                            .font(.callout).italic()
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .padding(12)
                    } else {
                        Text("Verse not found")
                            .font(.caption)
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                            .padding(12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                        }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func load() async {
        isLoading = true
        verseText = await BereanSmartChannelHook.shared.fetchVerseText(for: reference)
        isLoading = false
    }
}
