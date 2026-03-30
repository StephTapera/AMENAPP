// HeyFeedPostCardBadge.swift
// AMENAPP
//
// Badge overlay components shown on active HeyFeed request posts in the feed.
// These are overlaid from the parent feed list view, NOT from inside PostCard.

import SwiftUI
import FirebaseAuth

// MARK: - HeyFeedBadgeView

struct HeyFeedBadgeView: View {
    let postId: String
    @State private var isExpanded = false
    @State private var collapseTask: Task<Void, Never>? = nil
    @ObservedObject private var service = HeyFeedService.shared

    var body: some View {
        if service.isActiveRequest(postId: postId),
           let request = service.getRequest(for: postId) {
            VStack(alignment: .leading, spacing: 6) {
                if isExpanded {
                    expandedContent(request: request)
                        .transition(
                            .scale(scale: 0.85, anchor: .bottomLeading)
                            .combined(with: .opacity)
                        )
                }

                collapsedPill(request: request)
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isExpanded)
            .task {
                service.startListening()
            }
        }
    }

    // MARK: Collapsed Pill

    private func collapsedPill(request: HeyFeedRequest) -> some View {
        Button {
            toggleExpanded()
        } label: {
            HStack(spacing: 6) {
                Text(request.requestType.icon)
                    .font(.system(size: 13))

                Text(request.requestType.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.88))
                    .lineLimit(1)

                if request.resonanceCount > 0 {
                    Text("· \(request.resonanceCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.60))
                }

                if isExpanded {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 6)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Expanded Resonance Row

    private func expandedContent(request: HeyFeedRequest) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HeyFeedResonanceType.allCases, id: \.self) { resonanceType in
                    HeyFeedFeedbackButton(
                        postId: postId,
                        requestId: request.id,
                        type: resonanceType
                    )
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .frame(maxWidth: 300)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 6)
        )
    }

    // MARK: Helpers

    private func toggleExpanded() {
        collapseTask?.cancel()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
            isExpanded.toggle()
        }
        if isExpanded {
            scheduleAutoCollapse()
        }
    }

    private func scheduleAutoCollapse() {
        collapseTask?.cancel()
        collapseTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                    isExpanded = false
                }
            }
        }
    }
}

// MARK: - HeyFeedFeedbackButton

struct HeyFeedFeedbackButton: View {
    let postId: String
    let requestId: String
    let type: HeyFeedResonanceType
    @State private var isAnimating = false
    @ObservedObject private var service = HeyFeedService.shared

    private var isActive: Bool {
        service.hasMyResonance(postId: postId)
    }

    var body: some View {
        Button {
            handleTap()
        } label: {
            HStack(spacing: 4) {
                Text(type.icon)
                    .font(.system(size: 13))

                Text(type.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isActive ? .white : Color.white.opacity(0.88))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? AnyShapeStyle(Color.accentColor.opacity(0.85)) : AnyShapeStyle(.ultraThinMaterial))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isAnimating ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isAnimating)
    }

    // MARK: Helpers

    private func handleTap() {
        triggerHaptic()
        triggerScaleAnimation()

        Task {
            do {
                if isActive {
                    dlog("[HeyFeedFeedbackButton] Removing resonance type=\(type.displayName) postId=\(postId)")
                    try await service.removeResonance(postId: postId, requestId: requestId, type: type)
                } else {
                    dlog("[HeyFeedFeedbackButton] Recording resonance type=\(type.displayName) postId=\(postId)")
                    try await service.recordResonance(postId: postId, requestId: requestId, type: type)
                }
            } catch {
                dlog("[HeyFeedFeedbackButton] Error: \(error.localizedDescription)")
            }
        }
    }

    private func triggerScaleAnimation() {
        isAnimating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isAnimating = false
        }
    }

    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

// MARK: - FeedbackChip

struct FeedbackChip: View {
    let type: HeyFeedResonanceType
    let count: Int
    let isActive: Bool

    var body: some View {
        HStack(spacing: 3) {
            Text(type.icon)
                .font(.system(size: 11))

            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isActive ? .white : Color.white.opacity(0.75))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isActive ? AnyShapeStyle(Color.accentColor.opacity(0.80)) : AnyShapeStyle(.ultraThinMaterial))
        )
    }
}

// MARK: - HeyFeedBadgeModifier

struct HeyFeedBadgeModifier: ViewModifier {
    let postId: String

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomLeading) {
                if HeyFeedService.shared.isActiveRequest(postId: postId) {
                    HeyFeedBadgeView(postId: postId)
                        .padding(.leading, 12)
                        .padding(.bottom, 8)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
    }
}

extension View {
    func heyFeedBadge(postId: String?) -> some View {
        guard let postId = postId else { return AnyView(self) }
        return AnyView(self.modifier(HeyFeedBadgeModifier(postId: postId)))
    }
}
