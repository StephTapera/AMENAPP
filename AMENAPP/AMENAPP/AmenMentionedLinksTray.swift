import SwiftUI

struct AmenMentionedLinksTray: View {
    let links: [AmenExtractedLink]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mentioned Links (\(links.count))")
                .font(.systemScaled(16, weight: .semibold))
            ForEach(links) { link in
                VStack(alignment: .leading, spacing: 4) {
                    Text(link.category.rawValue.capitalized)
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(link.title ?? link.url)
                        .font(.systemScaled(13, weight: .medium))
                        .lineLimit(2)
                    Text(link.url)
                        .font(.systemScaled(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
            }
        }
        .padding(16)
    }
}
