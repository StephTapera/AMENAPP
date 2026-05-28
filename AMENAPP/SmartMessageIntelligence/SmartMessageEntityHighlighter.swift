import SwiftUI

struct SmartMessageEntityHighlighter: View {
    let text: String
    let entities: [SmartDetectedEntity]
    var onEntityTap: (SmartDetectedEntity) -> Void

    var body: some View {
        Text(attributedText)
            .textSelection(.enabled)
            .contextMenu {
                if AMENFeatureFlags.shared.contextualBereanActionsEnabled {
                    Button("Ask Berean", systemImage: "sparkles") {
                        let payload = BereanContextPayload(selectedText: text, sourceSurface: "message", contentType: .message)
                        BereanContextMenuManager.shared.activate(payload: payload, action: .askBerean)
                    }
                }
            }
            .accessibilityLabel(text)
            .overlay(alignment: .topLeading) {
                if !entities.isEmpty {
                    entityTapLayer
                }
            }
    }

    private var attributedText: AttributedString {
        var value = AttributedString(text)
        for entity in entities where entity.confidence >= 0.6 {
            guard let start = value.characters.index(value.startIndex, offsetBy: entity.range.start, limitedBy: value.endIndex),
                  let end = value.characters.index(start, offsetBy: entity.range.length, limitedBy: value.endIndex) else { continue }
            value[start..<end].foregroundColor = color(for: entity.type)
            value[start..<end].underlineStyle = .single
        }
        return value
    }

    private var entityTapLayer: some View {
        Menu {
            ForEach(entities.prefix(8)) { entity in
                Button(entityMenuTitle(entity), systemImage: icon(for: entity.type)) {
                    onEntityTap(entity)
                }
            }
        } label: {
            Color.clear.contentShape(Rectangle())
        }
        .accessibilityHidden(true)
    }

    private func entityMenuTitle(_ entity: SmartDetectedEntity) -> String {
        switch entity.type {
        case .scriptureReference: return "Open \(entity.normalizedValue)"
        case .dateTime, .event: return "Use \(entity.sourceText)"
        case .prayerRequest: return "Review Prayer"
        case .topic: return "Topic: \(entity.normalizedValue.capitalized)"
        default: return entity.sourceText
        }
    }

    private func color(for type: SmartDetectedEntityType) -> Color {
        switch type {
        case .scriptureReference: return .blue
        case .dateTime, .event: return .green
        case .prayerRequest: return .purple
        case .topic: return .orange
        default: return .primary
        }
    }

    private func icon(for type: SmartDetectedEntityType) -> String {
        switch type {
        case .scriptureReference: return "book"
        case .dateTime, .event: return "calendar"
        case .prayerRequest: return "hands.sparkles"
        case .topic: return "tag"
        default: return "sparkles"
        }
    }
}
