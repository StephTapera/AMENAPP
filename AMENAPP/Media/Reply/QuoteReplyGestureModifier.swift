import SwiftUI

struct QuoteReplyGestureModifier: ViewModifier {
    var authorName: String
    var content: String
    var onQuoteSelected: (String, String) -> Void

    @State private var dragWidth: CGFloat = 0
    @GestureState private var isDragging = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                if dragWidth > 10 {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.purple)
                        .opacity(min(1, dragWidth / 60))
                        .padding(.leading, 4)
                        .transition(.opacity)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { val in
                        guard val.translation.width > 0,
                              abs(val.translation.height) < 30 else { return }
                        dragWidth = val.translation.width
                    }
                    .onEnded { val in
                        if val.translation.width > 60 && abs(val.translation.height) < 30 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onQuoteSelected(authorName, self.content)
                        }
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                            dragWidth = 0
                        }
                    }
            )
    }
}

extension View {
    func quoteReplyGesture(
        authorName: String,
        content: String,
        onQuoteSelected: @escaping (String, String) -> Void
    ) -> some View {
        modifier(QuoteReplyGestureModifier(
            authorName: authorName,
            content: content,
            onQuoteSelected: onQuoteSelected
        ))
    }
}
