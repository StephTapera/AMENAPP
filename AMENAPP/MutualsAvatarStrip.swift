//
//  MutualsAvatarStrip.swift
//  AMENAPP
//
//  Compact overlapping-avatar strip + label, Instagram/Threads-style.
//  Shows up to 5 avatars with a +N overflow bubble.
//  Tapping the strip triggers the onTap callback (opens MutualsListView sheet).
//  Shows a shimmer skeleton while loading.
//

import SwiftUI

// MARK: - Main Strip

struct MutualsAvatarStrip: View {
    let mutuals: [MutualConnection]
    let isLoading: Bool
    let onTap: () -> Void

    private let avatarSize: CGFloat = 28
    private let overlap: CGFloat = 10
    private let maxVisible = 5

    private var visible: [MutualConnection] { Array(mutuals.prefix(maxVisible)) }
    private var overflow: Int { max(0, mutuals.count - maxVisible) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                avatarRow
                labelText
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .overlay(
            Group {
                if isLoading { shimmerOverlay }
            }
        )
    }

    // MARK: - Avatar row

    private var avatarRow: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, mutual in
                MutualsCircleAvatar(url: mutual.profilePhotoURL, size: avatarSize)
                    .offset(x: CGFloat(index) * (avatarSize - overlap))
                    .zIndex(Double(maxVisible - index))
            }
            if overflow > 0 {
                overflowBubble
                    .offset(x: CGFloat(visible.count) * (avatarSize - overlap))
                    .zIndex(0)
            }
        }
        .frame(
            width: CGFloat(min(mutuals.count, maxVisible + (overflow > 0 ? 1 : 0))) * (avatarSize - overlap) + overlap,
            height: avatarSize
        )
    }

    private var overflowBubble: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.15))
                .overlay(Circle().stroke(Color.black, lineWidth: 2))
            Text("+\(overflow)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: avatarSize, height: avatarSize)
    }

    // MARK: - Label

    private var labelText: some View {
        Group {
            if isLoading {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 160, height: 13)
            } else {
                Text(buildLabelString())
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
    }

    private func buildLabelString() -> String {
        switch mutuals.count {
        case 0:
            return ""
        case 1:
            return "Followed by \(mutuals[0].displayName.components(separatedBy: " ").first ?? mutuals[0].displayName)"
        case 2:
            let n1 = firstName(mutuals[0])
            let n2 = firstName(mutuals[1])
            return "Followed by \(n1) and \(n2)"
        default:
            let n1 = firstName(mutuals[0])
            let n2 = firstName(mutuals[1])
            let rest = mutuals.count - 2
            return "Followed by \(n1), \(n2) and \(rest) others you follow"
        }
    }

    private func firstName(_ m: MutualConnection) -> String {
        m.displayName.components(separatedBy: " ").first ?? m.displayName
    }

    // MARK: - Shimmer

    private var shimmerOverlay: some View {
        HStack(spacing: 10) {
            // Ghost avatar circles
            HStack(spacing: -(overlap)) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: avatarSize, height: avatarSize)
                        .shimmer()
                }
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.08))
                .frame(width: 130, height: 13)
                .shimmer()
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
    }
}

// MARK: - Single Avatar

struct MutualsCircleAvatar: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure, .empty:
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.12))
            @unknown default:
                Color.white.opacity(0.08)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.black, lineWidth: 2))
    }
}

// MARK: - Shimmer modifier (lightweight, no external deps)

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.0),
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.0)
                    ]),
                    startPoint: .init(x: phase - 0.3, y: 0.5),
                    endPoint: .init(x: phase + 0.3, y: 0.5)
                )
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}

private extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
