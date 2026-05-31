import SwiftUI

enum MorphingComposerState: String, CaseIterable {
    case collapsed
    case typing
    case aiAssist
    case expanded
}

struct MorphingComposerView<Content: View>: View {
    @State private var state: MorphingComposerState
    private let content: Content

    init(state: MorphingComposerState = .collapsed, @ViewBuilder content: () -> Content) {
        _state = State(initialValue: state)
        self.content = content()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(height: height)

            content
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .animation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.85)), value: state)
    }

    private var cornerRadius: CGFloat {
        switch state {
        case .collapsed:
            return 28
        case .typing:
            return 22
        case .expanded:
            return 16
        case .aiAssist:
            return 18
        }
    }

    private var height: CGFloat {
        switch state {
        case .collapsed:
            return 48
        case .typing:
            return 80
        case .expanded:
            return 140
        case .aiAssist:
            return 120
        }
    }
}
