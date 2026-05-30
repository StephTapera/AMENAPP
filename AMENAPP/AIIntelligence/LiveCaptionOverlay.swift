import SwiftUI

struct LiveCaptionOverlay: View {
    let captions: [BereanCaptionChunk]
    let scriptureReferences: [BereanResolvedScriptureRef]
    var maxVisibleCaptions = 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var visibleCaptions: [BereanCaptionChunk] {
        Array(captions.suffix(maxVisibleCaptions)).filter { !$0.text.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            captionStack
            scriptureRefRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 560, alignment: .leading)
        .background { backgroundView }
        .overlay { borderOverlay }
        .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: visibleCaptions.map(\.id))
    }

    @ViewBuilder
    private var captionStack: some View {
        if !visibleCaptions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(visibleCaptions) { caption in
                    captionRow(caption)
                }
            }
        }
    }

    @ViewBuilder
    private func captionRow(_ caption: BereanCaptionChunk) -> some View {
        let fontWeight: Font.Weight = caption.isFinal ? .regular : .medium
        let lineLimit: Int? = dynamicTypeSize.isAccessibilitySize ? nil : 3
        let rowTransition: AnyTransition = reduceMotion
            ? .identity
            : .move(edge: .bottom).combined(with: .opacity)
        Text(caption.text)
            .font(.body.weight(fontWeight))
            .foregroundStyle(.primary)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .transition(rowTransition)
    }

    @ViewBuilder
    private var scriptureRefRow: some View {
        if let reference = scriptureReferences.last {
            HStack(spacing: 6) {
                Image(systemName: "book.closed")
                    .font(.caption.weight(.semibold))
                Text(reference.displayString)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("Detected scripture reference, \(reference.displayString)")
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        let bgOpacity: Double = reduceTransparency ? 0.98 : 0.70
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.systemBackground).opacity(bgOpacity))
            .background {
                if !reduceTransparency {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.ultraThinMaterial)
                }
            }
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.7)
    }
}
