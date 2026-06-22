// VideoExplainSheet.swift
// Glass bottom sheet showing an AI-generated explanation of a sermon/teaching video.
//
// STATE MACHINE
// ─────────────
//  .idle              → shown briefly on first appear; triggers requestExplanation
//  .flagDisabled      → "Not available" — no button, no retry
//  .transcriptMissing → "Transcript required" — explains why, no retry
//  .loading           → shimmer placeholder; non-blocking to video playback
//  .success           → explanation + themes + scripture refs
//  .failure           → error message + retry button
//
// ACCESSIBILITY
// ─────────────
// - VoiceOver labels and hints on all interactive elements.
// - Dynamic Type: all text uses system font styles (.body, .subheadline, etc.).
// - Reduce Motion: no spring animations when accessibilityReduceMotion is on.
// - Reduce Transparency: solid overlay replaces ultraThinMaterial tint.

import SwiftUI

// MARK: - Modifier helper

extension View {
    func videoExplainSheet(
        isPresented: Binding<Bool>,
        postId: String,
        mediaId: String,
        surface: String = "media_detail"
    ) -> some View {
        self.sheet(isPresented: isPresented, onDismiss: nil) {
            VideoExplainSheet(
                postId: postId,
                mediaId: mediaId,
                surface: surface,
                isPresented: isPresented
            )
        }
    }
}

// MARK: - Sheet

struct VideoExplainSheet: View {

    let postId: String
    let mediaId: String
    let surface: String
    @Binding var isPresented: Bool

    @StateObject private var service = VideoExplainService()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(white: reduceTransparency ? 0.96 : 0.97)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    sheetHeader
                        .padding(.top, 8)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    ScrollView(.vertical, showsIndicators: false) {
                        contentForState
                            .padding(.horizontal, 16)
                            .padding(.bottom, 36)
                            .animation(
                                reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82),
                                value: service.state
                            )
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await service.requestExplanation(postId: postId, mediaId: mediaId, surface: surface)
        }
        .onDisappear {
            service.cancel()
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 34, height: 34)
                    Image(systemName: "sparkles")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                Text("Video Explained")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
            }

            Spacer()

            Button {
                isPresented = false
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle().fill(Color.white.opacity(reduceTransparency ? 1.0 : 0.55))
                        )
                        .overlay(
                            Circle().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: "xmark")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close explanation")
        }
        .padding(14)
        .explainGlassCard(reduceTransparency: reduceTransparency)
    }

    // MARK: - Content dispatch

    @ViewBuilder
    private var contentForState: some View {
        switch service.state {
        case .idle, .loading:
            loadingContent

        case .flagDisabled:
            unavailableContent(
                icon: "sparkles.slash",
                title: "Not Available",
                message: "Video explanations aren't available right now."
            )

        case .transcriptMissing:
            unavailableContent(
                icon: "doc.text.slash",
                title: "Transcript Required",
                message: "A transcript is needed to generate an explanation. It may still be processing."
            )

        case .success(let explanation):
            successContent(explanation)

        case .failure(let message):
            failureContent(message: message)
        }
    }

    // MARK: - Loading state

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExplainShimmerBar(widthFraction: 1.0)
            ExplainShimmerBar(widthFraction: 1.0)
            ExplainShimmerBar(widthFraction: 0.7)
            HStack(spacing: 8) {
                ExplainShimmerBar(widthFraction: 0.28).frame(height: 26).clipShape(Capsule())
                ExplainShimmerBar(widthFraction: 0.28).frame(height: 26).clipShape(Capsule())
                ExplainShimmerBar(widthFraction: 0.22).frame(height: 26).clipShape(Capsule())
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Generating explanation, please wait.")
    }

    // MARK: - Success state

    private func successContent(_ explanation: VideoExplanation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Explanation text card
            VStack(alignment: .leading, spacing: 8) {
                Label("Summary", systemImage: "text.alignleft")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .accessibilityHidden(true)

                Text(explanation.explanation)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .explainGlassCard(reduceTransparency: reduceTransparency)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Summary: \(explanation.explanation)")

            // Themes card
            if !explanation.themes.isEmpty {
                themesCard(explanation.themes)
            }

            // Scripture refs card
            if !explanation.scriptureRefs.isEmpty {
                scriptureRefsCard(explanation.scriptureRefs)
            }

            // AI disclosure
            Text("Generated by AI · Content may not reflect the speaker's full intent")
                .font(.caption2)
                .foregroundStyle(Color.black.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .padding(.top, 8)
    }

    private func themesCard(_ themes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Themes", systemImage: "tag")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.55))
                .accessibilityHidden(true)

            ExplainFlowLayout(spacing: 8) {
                ForEach(themes, id: \.self) { theme in
                    Text(theme)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule().fill(Color.white.opacity(reduceTransparency ? 1.0 : 0.55))
                                )
                                .overlay(
                                    Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                                )
                        )
                }
            }
        }
        .padding(16)
        .explainGlassCard(reduceTransparency: reduceTransparency)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Themes: \(themes.joined(separator: ", "))")
    }

    private func scriptureRefsCard(_ refs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Scripture References", systemImage: "book.closed")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.55))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(refs, id: \.self) { ref in
                    HStack(spacing: 8) {
                        Image(systemName: "book.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.black.opacity(0.40))
                            .accessibilityHidden(true)
                        Text(ref)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(16)
        .explainGlassCard(reduceTransparency: reduceTransparency)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scripture references: \(refs.joined(separator: ", "))")
    }

    // MARK: - Failure state

    private func failureContent(message: String) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.systemScaled(32, weight: .light))
                    .foregroundStyle(Color.black.opacity(0.30))
                    .accessibilityHidden(true)

                Text(message)
                    .font(.body)
                    .foregroundStyle(Color.black.opacity(0.55))
                    .multilineTextAlignment(.center)
            }

            Button {
                Task {
                    await service.retry(postId: postId, mediaId: mediaId, surface: surface)
                }
            } label: {
                Text("Try Again")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Color.black))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry generating explanation")
            .accessibilityHint("Attempts to generate the video explanation again")
        }
        .padding(.top, 36)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Unavailable state

    private func unavailableContent(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.systemScaled(32, weight: .light))
                .foregroundStyle(Color.black.opacity(0.25))
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)
                .foregroundStyle(Color.black.opacity(0.55))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.black.opacity(0.40))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }
}

// MARK: - Shimmer bar

private struct ExplainShimmerBar: View {
    var widthFraction: CGFloat = 1.0
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width * widthFraction
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: reduceMotion
                            ? [Color(white: 0.88)]
                            : [Color(white: 0.90), Color(white: 0.82), Color(white: 0.90)],
                        startPoint: UnitPoint(x: phase - 0.5, y: 0),
                        endPoint: UnitPoint(x: phase + 0.5, y: 0)
                    )
                )
                .frame(width: w, height: 14)
        }
        .frame(height: 14)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1.5
            }
        }
    }
}

// MARK: - Flow layout (wrapping chip row)

private struct ExplainFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > containerWidth && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: containerWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Glass card modifier

private extension View {
    func explainGlassCard(reduceTransparency: Bool) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(reduceTransparency ? 1.0 : 0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Preview

#if DEBUG
struct VideoExplainSheet_Previews: PreviewProvider {
    static var previews: some View {
        Text("Tap to preview")
            .videoExplainSheet(
                isPresented: .constant(true),
                postId: "preview-post",
                mediaId: "preview-media"
            )
            .previewDisplayName("Explain Sheet")
    }
}
#endif
