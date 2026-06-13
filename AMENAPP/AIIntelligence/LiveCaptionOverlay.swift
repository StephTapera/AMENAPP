import SwiftUI

struct LiveCaptionOverlay: View {
    let captions: [BereanCaptionChunk]
    let scriptureReferences: [BereanScriptureReference]
    var maxVisibleCaptions = 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var visibleCaptions: [BereanCaptionChunk] {
        Array(captions.suffix(maxVisibleCaptions)).filter { !$0.text.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !visibleCaptions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(visibleCaptions) { caption in
                        Text(caption.text)
                            .font(.body.weight(caption.isFinal ? .regular : .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }

            if let reference = scriptureReferences.last, !reference.reference.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: reference.isUnverified ? "questionmark.circle" : "book.closed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reference.isUnverified ? Color.orange : Color.secondary)
                    Text(reference.reference)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reference.isUnverified ? Color.orange : Color.secondary)
                        .lineLimit(1)
                }
                .accessibilityLabel("Detected scripture reference, \(reference.reference)\(reference.isUnverified ? ", unverified" : "")")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 560, alignment: .leading)
        .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 8)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.98))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        LiquidGlassSpecularRenderer(cornerRadius: 8, opacity: 0.18)
                    }
                    .overlay {
                        LiquidGlassAdaptiveBorder(cornerRadius: 8, contrastBoost: false)
                    }
            }
        }
        .accessibilityElement(children: .combine)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: visibleCaptions.map(\.id))
    }
}
