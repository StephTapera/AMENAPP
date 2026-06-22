import SwiftUI

struct AmenGlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let tint: Color?
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        cornerRadius: CGFloat = 20,
        padding: CGFloat = 16,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 0.6)
            )
            .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.clear)
            .background(
                Group {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white)
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.9),
                                (tint ?? .white).opacity(0.08),
                                Color.white.opacity(0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.05), lineWidth: 0.6)
            )
    }
}

struct AmenGlassPill: View {
    let title: String
    let icon: String?
    var tint: Color = Color.black.opacity(0.7)

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.systemScaled(11, weight: .semibold))
            }
            Text(title)
                .font(.systemScaled(12, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(tint.opacity(0.08))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(tint.opacity(0.2), lineWidth: 0.8)
                )
        )
    }
}

struct AmenGlassHeaderBar: View {
    let title: String
    let subtitle: String?
    let onClose: () -> Void
    var trailing: AnyView? = nil

    var body: some View {
        AmenGlassCard(cornerRadius: 24, padding: 12) {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.6))
                        )
                }
                .buttonStyle(.plain)

                VStack(spacing: 2) {
                    Text(title)
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.systemScaled(11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)

                if let trailing {
                    trailing
                } else {
                    Color.clear.frame(width: 36, height: 36)
                }
            }
        }
    }
}

struct DiscussionTopicHeroCard: View {
    let authorName: String
    let sourceLabel: String
    let title: String
    let classification: String
    let smartTag: String?

    var body: some View {
        AmenGlassCard(cornerRadius: 28, padding: 18, tint: Color.purple) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.black.opacity(0.06))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(String(authorName.prefix(1)).uppercased())
                                .font(.systemScaled(15, weight: .bold))
                                .foregroundStyle(.primary.opacity(0.82))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(sourceLabel)
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(authorName)
                            .font(.systemScaled(15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Image(systemName: "quote.bubble.fill")
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(Color.purple.opacity(0.7))
                }

                Text(title)
                    .font(.systemScaled(20, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(4)

                HStack(spacing: 8) {
                    AmenGlassPill(title: classification, icon: "chart.bar.xaxis", tint: Color.purple.opacity(0.85))
                    if let smartTag {
                        AmenGlassPill(title: smartTag, icon: "sparkles", tint: Color.black.opacity(0.72))
                    }
                }
            }
        }
    }
}

struct PerspectiveBriefCard: View {
    let label: String
    let summary: String
    let bodyText: String
    let helperText: String
    let tint: Color
    @Binding var isExpanded: Bool
    let onToggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AmenGlassCard(cornerRadius: 22, padding: 14, tint: tint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    AmenGlassPill(title: "AI Brief", icon: "sparkles", tint: tint)
                    Spacer()
                    Button {
                        onToggle()
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.35, dampingFraction: 0.84)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.65)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Collapse \(label)" : "Expand \(label)")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(summary)
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 2)
                    Text(helperText)
                        .font(.systemScaled(11))
                        .foregroundStyle(tint.opacity(0.9))
                }

                if isExpanded {
                    AmenGlassCard(cornerRadius: 18, padding: 12, tint: tint.opacity(0.6)) {
                        Text(bodyText)
                            .font(.systemScaled(14))
                            .foregroundStyle(.primary.opacity(0.84))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

struct DiscussionEmptyState: View {
    let onArgument: () -> Void
    let onEvidence: () -> Void
    let onViewChange: () -> Void

    var body: some View {
        AmenGlassCard(cornerRadius: 24, padding: 18, tint: Color.purple.opacity(0.7)) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No one has added a view yet.")
                        .font(.systemScaled(18, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Start the thread with a thoughtful argument, a clear piece of evidence, or what changed your perspective.")
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 8) {
                    DiscussionPromptRow(title: "Add an argument", icon: "text.bubble", action: onArgument)
                    DiscussionPromptRow(title: "Add evidence", icon: "doc.text", action: onEvidence)
                    DiscussionPromptRow(title: "Share what changed your view", icon: "arrow.uturn.left.circle", action: onViewChange)
                }
            }
        }
    }
}

private struct DiscussionPromptRow: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct ThreadLoadingSkeleton: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                skeletonCard(height: 118, cornerRadius: 28)
                HStack(spacing: 8) {
                    skeletonPill(width: 126)
                    skeletonPill(width: 110)
                }
                skeletonCard(height: 110, cornerRadius: 22)
                skeletonCard(height: 110, cornerRadius: 22)
                skeletonCard(height: 160, cornerRadius: 22)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    private func skeletonCard(height: CGFloat, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.black.opacity(0.06))
            .frame(height: height)
            .redacted(reason: .placeholder)
    }

    private func skeletonPill(width: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(Color.black.opacity(0.06))
            .frame(width: width, height: 30)
    }
}

struct ThreadUnavailableState: View {
    let title: String
    let message: String
    let retryTitle: String?
    let onRetry: (() -> Void)?

    var body: some View {
        AmenGlassCard(cornerRadius: 24, padding: 18) {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                    .font(.systemScaled(28, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.systemScaled(18, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.systemScaled(13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let retryTitle, let onRetry {
                    Button(retryTitle, action: onRetry)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Color.black))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
    }
}

struct AddYourViewFloatingButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.systemScaled(12, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(title)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.78))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.8), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 18, y: 10)
            )
        }
        .buttonStyle(.plain)
    }
}
