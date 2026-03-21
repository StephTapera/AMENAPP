import SwiftUI

// MARK: - Completion Moments

enum CompletionMoment {
    case sent        // posted content — blue
    case offered     // prayer — purple
    case witnessed   // testimony — teal
    case blessed     // Shepherd's Gate cleared — green
    case faithful    // Covenant Metrics delivered — amber

    var word: String {
        switch self {
        case .sent:     return "Sent"
        case .offered:  return "Offered"
        case .witnessed: return "Witnessed"
        case .blessed:  return "Blessed"
        case .faithful: return "Faithful"
        }
    }

    var color: Color {
        switch self {
        case .sent:     return Color(red: 0.20, green: 0.42, blue: 0.98)
        case .offered:  return Color(red: 0.46, green: 0.28, blue: 0.95)
        case .witnessed: return Color(red: 0.10, green: 0.68, blue: 0.62)
        case .blessed:  return Color(red: 0.20, green: 0.72, blue: 0.44)
        case .faithful: return Color(red: 0.95, green: 0.68, blue: 0.20)
        }
    }

    var subtitle: String {
        switch self {
        case .sent:     return "Your words are out in the world."
        case .offered:  return "Your prayer has been lifted up."
        case .witnessed: return "Your testimony is now a lighthouse."
        case .blessed:  return "Your post is ready to publish."
        case .faithful: return "Your week's impact, delivered."
        }
    }
}

// MARK: - Completion Screen

struct AMENCompletionScreen: View {
    let moment: CompletionMoment
    var onDismiss: (() -> Void)? = nil

    @State private var wordOpacity: Double = 0
    @State private var pencilProgress: CGFloat = 0
    @State private var pencilX: CGFloat = 0
    @State private var subtitleOpacity: Double = 0
    @State private var dismissButtonOpacity: Double = 0

    // Measured word width — approximate for animation anchor
    @State private var wordSize: CGSize = .zero

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Word + underline group
                ZStack(alignment: .bottom) {
                    // Handwritten-style word
                    Text(moment.word)
                        .font(.custom("Georgia-Italic", size: 64))
                        .fontWeight(.light)
                        .foregroundColor(moment.color)
                        .opacity(wordOpacity)
                        .background(
                            GeometryReader { geo in
                                Color.clear.onAppear {
                                    wordSize = geo.size
                                }
                            }
                        )

                    // Animated underline
                    Canvas { context, size in
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: size.height - 2))
                        path.addLine(to: CGPoint(x: size.width * pencilProgress, y: size.height - 2))
                        context.stroke(path, with: .color(moment.color),
                                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                    .frame(height: 6)
                    .offset(y: 8)

                    // Pencil tip following the line
                    PencilView(color: moment.color)
                        .frame(width: 28, height: 28)
                        .offset(x: pencilX - (wordSize.width / 2) + 14,
                                y: 16)
                        .opacity(pencilProgress > 0 && pencilProgress < 1 ? 1 : 0)
                }
                .padding(.horizontal, 40)

                // Subtitle
                Text(moment.subtitle)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 32)
                    .padding(.horizontal, 48)
                    .opacity(subtitleOpacity)

                Spacer()

                // Dismiss
                Button(action: { onDismiss?() }) {
                    Text("continue")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(moment.color)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .stroke(moment.color.opacity(0.35), lineWidth: 1)
                        )
                }
                .opacity(dismissButtonOpacity)
                .padding(.bottom, 52)
            }
        }
        .onAppear { runAnimation() }
    }

    private func runAnimation() {
        // 1. Word fades in
        withAnimation(.easeIn(duration: 0.4)) {
            wordOpacity = 1
        }

        // 2. Pencil draws underline after 0.3s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.7)) {
                pencilProgress = 1
            }
            // Pencil tip slides right in sync
            withAnimation(.easeInOut(duration: 0.7)) {
                pencilX = wordSize.width
            }
        }

        // 3. Subtitle appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeIn(duration: 0.4)) {
                subtitleOpacity = 1
            }
        }

        // 4. Dismiss button appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeIn(duration: 0.35)) {
                dismissButtonOpacity = 1
            }
        }
    }
}

// MARK: - Pencil View

private struct PencilView: View {
    let color: Color

    var body: some View {
        ZStack {
            // Pencil body
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.9), color],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 8, height: 20)

            // Tip
            Triangle()
                .fill(Color(white: 0.85))
                .frame(width: 8, height: 7)
                .offset(y: 13)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
