// DiscussionSummaryView.swift — AMEN App
import SwiftUI

struct DiscussionSummaryV2: View {
    let summary: BereanThreadSummary
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: "#C9A84C"))
                    Text("Berean Summary")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "#C9A84C"))
                        .tracking(1)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(summary.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                if !summary.agreementPoints.isEmpty {
                    TagFlowRow(title: "Common Ground", items: summary.agreementPoints)
                }
                if !summary.openQuestions.isEmpty {
                    TagFlowRow(title: "Open Questions", items: summary.openQuestions)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(hex: "#C9A84C").opacity(0.25), lineWidth: 1)
                )
        )
    }
}

private struct TagFlowRow: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
                .tracking(1.5)
            FlowLayout(spacing: 4) {
                ForEach(items.prefix(4), id: \.self) { item in
                    Text(item)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                        .lineLimit(1)
                }
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: height + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
