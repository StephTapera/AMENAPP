import SwiftUI

// MARK: - Berean Quick Action Button (iOS-Style with Smart Animations)
struct BereanQuickActionButton: View {
    let icon: String
    let title: String
    let delay: Double
    let action: () -> Void

    @State private var isPressed = false
    @State private var isAppeared = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.systemScaled(16, weight: .medium))
                    .foregroundStyle(isPressed ? Color.primary.opacity(0.5) : Color.primary)
                    .frame(width: 22)

                Text(title)
                    .font(.systemScaled(15, weight: .regular))
                    .foregroundStyle(isPressed ? Color.primary.opacity(0.5) : Color.primary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isPressed ? Color.black.opacity(0.08) : Color.clear)
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .opacity(isAppeared ? 1 : 0)
            .offset(x: isAppeared ? 0 : 10)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeIn(duration: 0.08)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        isPressed = false
                    }
                }
        )
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75)).delay(delay)) {
                isAppeared = true
            }
        }
    }
}

// MARK: - Quick Action Row
struct QuickActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradient: LinearGradient
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon with gradient
                ZStack {
                    Circle()
                        .fill(gradient.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.systemScaled(18, weight: .medium))
                        .foregroundStyle(gradient)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.systemScaled(12, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isPressed ? Color.black.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
}

// ScrollView delegate handler for detecting scroll direction
class ScrollViewDelegateHandler: NSObject, UIScrollViewDelegate {
    private var lastContentOffset: CGFloat = 0
    private var lastUpdateTime: Date = Date.distantPast
    private let onScroll: (CGFloat) -> Void
    private let throttleInterval: TimeInterval = 0.1 // 100ms throttle

    init(onScroll: @escaping (CGFloat) -> Void) {
        self.onScroll = onScroll
        super.init()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let currentOffset = scrollView.contentOffset.y
        let delta = currentOffset - lastContentOffset

        // P0 FIX: Always show UI when at top (within bounce threshold)
        // This ensures header/tab bar appear when user scrolls to top
        if currentOffset <= 0 {
            DispatchQueue.main.async {
                self.onScroll(-999) // Special signal: at top, show all UI
            }
            lastContentOffset = currentOffset
            return
        }

        // Throttle: Only update if enough time has passed since last update
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= throttleInterval else {
            return
        }

        // Only trigger if scrolled more than 5 points
        if abs(delta) > 5 {
            lastContentOffset = currentOffset
            lastUpdateTime = now

            // Defer state updates to avoid "Modifying state during view update" error
            DispatchQueue.main.async {
                self.onScroll(delta)
            }
        }
    }
}

// View modifier to attach scroll delegate
struct ScrollViewDelegateModifier: ViewModifier {
    let onScroll: (CGFloat) -> Void
    @State private var delegate: ScrollViewDelegateHandler?

    func body(content: Content) -> some View {
        content
            .background(
                ScrollViewDelegateAttacher(delegate: $delegate, onScroll: onScroll)
            )
    }
}

// UIViewRepresentable to find and attach to UIScrollView
struct ScrollViewDelegateAttacher: UIViewRepresentable {
    @Binding var delegate: ScrollViewDelegateHandler?
    let onScroll: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isHidden = true

        DispatchQueue.main.async {
            if let scrollView = view.findScrollView() {
                let handler = ScrollViewDelegateHandler(onScroll: onScroll)
                scrollView.delegate = handler
                delegate = handler
            }
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
    }
}

extension UIView {
    func findScrollView() -> UIScrollView? {
        if let scrollView = self as? UIScrollView {
            return scrollView
        }

        for subview in superview?.subviews ?? [] {
            if let scrollView = subview as? UIScrollView {
                return scrollView
            }
        }

        return superview?.findScrollView()
    }
}

extension View {
    func onScrollViewScroll(_ onScroll: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollViewDelegateModifier(onScroll: onScroll))
    }
}

// MARK: - Create Quick Action Row
struct CreateQuickActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradient: LinearGradient
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon with gradient
                ZStack {
                    Circle()
                        .fill(gradient.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.systemScaled(18, weight: .medium))
                        .foregroundStyle(gradient)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.systemScaled(12, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.circle.fill")
                    .font(.systemScaled(20, weight: .semibold))
                    .foregroundStyle(gradient)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isPressed ? Color.black.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Rotate Transition (compose button + icon unfurl)

extension AnyTransition {
    static var rotate: AnyTransition {
        .modifier(
            active:   RotateModifier(angle: 45),
            identity: RotateModifier(angle: 0)
        )
    }
}

private struct RotateModifier: ViewModifier {
    let angle: Double
    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(angle))
    }
}
