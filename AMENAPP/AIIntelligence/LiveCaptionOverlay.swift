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
                    Image(systemName: "book.closed")
                        .font(.caption.weight(.semibold))
                    Text(reference.reference)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("Detected scripture reference, \(reference.reference)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 560, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(reduceTransparency ? Color(.systemBackground).opacity(0.98) : Color(.systemBackground).opacity(0.70))
                .background {
                    if !reduceTransparency {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.ultraThinMaterial)
                    }
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: visibleCaptions.map(\.id))
    }
}
