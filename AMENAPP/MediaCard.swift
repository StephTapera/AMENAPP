// MediaCard.swift — Card cell for Christian Media items

import SwiftUI

struct MediaCard: View {
    let item: MediaItem
    let index: Int
    let isCurrentlyPlaying: Bool
    let onPlay: () -> Void
    let onBookmark: () -> Void
    let onShare: () -> Void
    var onBerean: (() -> Void)? = nil

    @State private var appeared = false
    @State private var isPressed = false

    private let accentPurple = Color(red: 0.49, green: 0.23, blue: 0.93)

    var body: some View {
        HStack(spacing: 14) {
            // MARK: Thumbnail
            ZStack(alignment: .topLeading) {
                thumbnailLayer
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Type badge overlay on thumbnail
                typeBadge
                    .padding(6)
            }

            // MARK: Text content
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text("\(item.author) · \(item.channelOrShow)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let scripture = item.scriptureRef {
                    Text(scripture)
                        .font(.system(size: 11))
                        .italic()
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 4)

                // Action row
                HStack(spacing: 10) {
                    // Play button
                    Button(action: onPlay) {
                        HStack(spacing: 5) {
                            Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(isCurrentlyPlaying ? "Playing" : "Play")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isCurrentlyPlaying ? accentPurple : Color.primary)
                        .foregroundStyle(isCurrentlyPlaying ? .white : Color(.systemBackground))
                        .clipShape(Capsule())
                    }

                    if item.scriptureRef != nil, let bereanAction = onBerean {
                        Button(action: bereanAction) {
                            HStack(spacing: 3) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Berean")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(accentPurple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(accentPurple.opacity(0.10))
                            .clipShape(Capsule())
                        }
                    }

                    Spacer()

                    Button(action: onBookmark) {
                        Image(systemName: item.isBookmarked ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 14))
                            .foregroundStyle(item.isBookmarked ? accentPurple : .secondary)
                    }

                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .animation(
            .spring(response: 0.45, dampingFraction: 0.8)
            .delay(Double(index) * 0.06),
            value: appeared
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .onAppear { appeared = true }
    }

    // MARK: - Sub Views

    @ViewBuilder
    private var thumbnailLayer: some View {
        if let url = URL(string: item.thumbnailURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Color(hex: item.dominantColor)
                case .empty:
                    Color(hex: item.dominantColor)
                        .overlay(
                            ProgressView()
                                .tint(.white.opacity(0.6))
                        )
                @unknown default:
                    Color(hex: item.dominantColor)
                }
            }
        } else {
            Color(hex: item.dominantColor)
        }
    }

    private var typeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: item.type.icon)
                .font(.system(size: 9, weight: .bold))
            Text(item.type.label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .kerning(0.5)
            if !item.duration.isEmpty {
                Text("·")
                    .font(.system(size: 9))
                Text(item.duration)
                    .font(.system(size: 9))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}

