import SwiftUI
import UIKit

// MARK: - Mention Text View
// Renders body text with @mention tokens highlighted as tappable chips.
// Pass resolved MentionEntity array alongside the raw body string.

struct AmenMentionTextView: View {
    let body: String
    let mentions: [MentionEntity]
    var font: Font = .body
    var onMentionTap: ((MentionEntity) -> Void)? = nil

    var body: some View {
        _MentionAttributedText(
            body: body,
            mentions: mentions,
            font: font,
            onMentionTap: onMentionTap
        )
    }
}

// MARK: - UIViewRepresentable bridge

private struct _MentionAttributedText: UIViewRepresentable {
    let body: String
    let mentions: [MentionEntity]
    let font: Font
    let onMentionTap: ((MentionEntity) -> Void)?

    func makeUIView(context: Context) -> MentionLabel {
        let label = MentionLabel()
        label.numberOfLines = 0
        label.onMentionTap = onMentionTap
        label.mentions = mentions
        return label
    }

    func updateUIView(_ label: MentionLabel, context: Context) {
        label.mentions = mentions
        label.setBody(body, uiFont: resolvedUIFont, mentions: mentions)
        label.onMentionTap = onMentionTap
    }

    private var resolvedUIFont: UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
        return UIFont(descriptor: descriptor, size: 0)
    }
}

// MARK: - Custom UILabel with tap detection

final class MentionLabel: UILabel {
    var onMentionTap: ((MentionEntity) -> Void)?
    var mentions: [MentionEntity] = []

    private var mentionRanges: [(NSRange, MentionEntity)] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
    }

    required init?(coder: NSCoder) { fatalError() }

    func setBody(_ text: String, uiFont: UIFont, mentions: [MentionEntity]) {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: uiFont,
                .foregroundColor: UIColor.label
            ]
        )
        mentionRanges = []
        for mention in mentions {
            let nsRange = NSRange(location: mention.range.location, length: mention.range.length)
            guard nsRange.location + nsRange.length <= (text as NSString).length else { continue }
            let highlightColor = Self.color(for: mention.type)
            attributed.addAttributes([
                .foregroundColor: highlightColor,
                .font: UIFont.systemFont(ofSize: uiFont.pointSize, weight: .semibold),
                .backgroundColor: highlightColor.withAlphaComponent(0.08)
            ], range: nsRange)
            mentionRanges.append((nsRange, mention))
        }
        attributedText = attributed
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let attributed = attributedText,
              let onMentionTap else { return }
        let location = gesture.location(in: self)
        let characterIndex = characterIndex(at: location, in: attributed)
        for (range, entity) in mentionRanges {
            if NSLocationInRange(characterIndex, range) {
                onMentionTap(entity)
                return
            }
        }
    }

    private func characterIndex(at point: CGPoint, in string: NSAttributedString) -> Int {
        let textStorage = NSTextStorage(attributedString: string)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: bounds.size)
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        return layoutManager.characterIndex(for: point, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
    }

    private static func color(for type: MentionEntity.MentionType) -> UIColor {
        switch type {
        case .everyone: return .systemRed
        case .paid:     return .systemOrange
        case .tier:     return .systemYellow
        case .creator:  return .systemPurple
        case .room:     return .systemTeal
        case .user:     return .systemBlue
        }
    }
}

// MARK: - Composer Mention Autocomplete Row

struct MentionSuggestionRow: View {
    let display: String
    let subtitle: String?
    let avatarURL: String?
    let type: MentionEntity.MentionType
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Group {
                    if let url = avatarURL {
                        AsyncImage(url: URL(string: url)) { img in img.resizable().scaledToFill() }
                            placeholder: { Circle().fill(typeColor.opacity(0.2)) }
                    } else {
                        Circle()
                            .fill(typeColor.opacity(0.15))
                            .overlay(
                                Image(systemName: typeIcon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(typeColor)
                            )
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(display)
                        .font(.subheadline.weight(.medium))
                    if let sub = subtitle {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(type.rawValue)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(typeColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(typeColor.opacity(0.1)))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private var typeColor: Color {
        switch type {
        case .everyone: return .red
        case .paid:     return .orange
        case .tier:     return .yellow
        case .creator:  return .purple
        case .room:     return .teal
        case .user:     return .blue
        }
    }

    private var typeIcon: String {
        switch type {
        case .everyone: return "megaphone.fill"
        case .paid:     return "crown.fill"
        case .tier:     return "star.fill"
        case .creator:  return "person.crop.circle.badge.checkmark"
        case .room:     return "bubble.left.and.bubble.right.fill"
        case .user:     return "person.fill"
        }
    }
}
