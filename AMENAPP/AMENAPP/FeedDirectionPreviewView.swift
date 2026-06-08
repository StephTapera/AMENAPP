import SwiftUI

struct FeedDirectionPreviewView: View {
    let draft: FeedDirectionDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your feed will change like this:")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(previewLines, id: \.text) { line in
                    HStack(spacing: 8) {
                        Image(systemName: line.isIncrease ? "arrow.up" : "arrow.down")
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(line.isIncrease ? Color.black : Color.secondary)
                            .frame(width: 16)
                        Text(line.text)
                            .font(.systemScaled(13))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private struct PreviewLine: Equatable {
        let text: String
        let isIncrease: Bool
    }

    private var previewLines: [PreviewLine] {
        var lines: [PreviewLine] = []
        switch draft.intentType {
        case .increaseTopic, .worship:
            lines.append(PreviewLine(text: "More \(draft.interpretedSummary?.lowercased() ?? "of this topic")", isIncrease: true))
        case .decreaseTopic, .reduceConflict, .reducePolitics, .reduceOutrage:
            lines.append(PreviewLine(text: "Less \(draft.interpretedSummary?.lowercased() ?? "of this topic")", isIncrease: false))
        case .emotionalRegulation:
            lines.append(PreviewLine(text: "More calm, uplifting content", isIncrease: true))
            lines.append(PreviewLine(text: "Less outrage-heavy content", isIncrease: false))
            lines.append(PreviewLine(text: "Less rapid-cut media", isIncrease: false))
        case .spiritualGrowth, .bibleStudy:
            lines.append(PreviewLine(text: "More scripture teaching", isIncrease: true))
            lines.append(PreviewLine(text: "More Bible study creators", isIncrease: true))
        case .sabbathRest, .timeBasedPreference:
            lines.append(PreviewLine(text: "More worship and rest content", isIncrease: true))
            lines.append(PreviewLine(text: "Less stimulating content at this time", isIncrease: false))
        default:
            lines.append(PreviewLine(text: draft.interpretedSummary ?? "Feed adjusted", isIncrease: true))
        }
        return lines
    }
}
