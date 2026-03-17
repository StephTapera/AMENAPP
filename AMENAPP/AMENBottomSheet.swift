//
//  AMENBottomSheet.swift
//  AMENAPP
//
//  Reusable interactive bottom sheet with snap points, gesture-driven drag,
//  keyboard awareness, and coordinated inner-scroll/outer-drag disambiguation.
//
//  Usage:
//    anyView
//      .amenBottomSheet(isPresented: $show, configuration: .comments) {
//          CommentsView(post: post)
//      }
//
//  Or with a custom configuration:
//    .amenBottomSheet(isPresented: $show,
//                    configuration: AMENSheetConfiguration(
//                        snapPoints: [.medium, .large],
//                        initialSnap: .medium,
//                        showDragIndicator: true
//                    )) { MyContent() }
//

import SwiftUI
import Combine

// MARK: - Snap Point

/// Defines where the sheet can rest.
enum AMENSnapPoint: Equatable {
    /// Fixed fraction of the screen height (0 = top, 1 = bottom).
    case fraction(CGFloat)
    /// Fixed pixel height from the bottom.
    case height(CGFloat)
    /// Full screen minus the safe-area top inset.
    case large
    /// ~50 % of the screen.
    case medium
    /// A compact peek (~280 pt).
    case compact

    /// Resolved offset from the top of the available area.
    func resolvedOffset(in totalHeight: CGFloat, topSafeArea: CGFloat) -> CGFloat {
        switch self {
        case .fraction(let f):  return totalHeight * (1 - f)
        case .height(let h):    return max(0, totalHeight - h)
        case .large:            return topSafeArea + 16   // leaves a small gap at the very top
        case .medium:           return totalHeight * 0.45
        case .compact:          return totalHeight - 280
        }
    }
}

// MARK: - Sheet Configuration

struct AMENSheetConfiguration {
    var snapPoints: [AMENSnapPoint]
    var initialSnap: AMENSnapPoint
    var showDragIndicator: Bool
    var tapBackgroundToDismiss: Bool
    var backgroundStyle: BackgroundStyle

    enum BackgroundStyle {
        case dimmed(opacity: CGFloat)   // solid dark scrim
        case blurred                    // UIBlurEffect behind the sheet
        case none
    }

    // Preset for comments
    static let comments = AMENSheetConfiguration(
        snapPoints: [.medium, .large],
        initialSnap: .medium,
        showDragIndicator: true,
        tapBackgroundToDismiss: true,
        backgroundStyle: .dimmed(opacity: 0.35)
    )

    // Preset for quick action sheets (share, report, save)
    static let quickAction = AMENSheetConfiguration(
        snapPoints: [.compact],
        initialSnap: .compact,
        showDragIndicator: true,
        tapBackgroundToDismiss: true,
        backgroundStyle: .dimmed(opacity: 0.25)
    )

    // Preset for detail expansion (church card, Berean answer)
    static let detail = AMENSheetConfiguration(
        snapPoints: [.medium, .large],
        initialSnap: .large,
        showDragIndicator: true,
        tapBackgroundToDismiss: true,
        backgroundStyle: .dimmed(opacity: 0.30)
    )

    // Full-height only (prayer thread, testimony replies)
    static let fullHeight = AMENSheetConfiguration(
        snapPoints: [.large],
        initialSnap: .large,
        showDragIndicator: true,
        tapBackgroundToDismiss: true,
        backgroundStyle: .dimmed(opacity: 0.35)
    )
}

// MARK: - Sheet State Controller

@MainActor
final class AMENSheetController: ObservableObject {

    @Published var currentOffset: CGFloat = 0
    @Published var dragOffset: CGFloat = 0   // live drag delta on top of currentOffset
    @Published var isPresented: Bool = false
    @Published var currentSnap: AMENSnapPoint

    var configuration: AMENSheetConfiguration
    var totalHeight: CGFloat = 0
    var topSafeArea: CGFloat = 0

    /// When the inner ScrollView tells us it's scrolled to top, sheet drag is re-enabled.
    @Published var innerScrollAtTop: Bool = true

    private var velocityTracker: [CGFloat] = []

    init(configuration: AMENSheetConfiguration) {
        self.configuration = configuration
        self.currentSnap = configuration.initialSnap
    }

    func present(totalHeight: CGFloat, topSafeArea: CGFloat) {
        self.totalHeight = totalHeight
        self.topSafeArea = topSafeArea
        let target = configuration.initialSnap.resolvedOffset(in: totalHeight, topSafeArea: topSafeArea)
        currentOffset = totalHeight   // start off-screen
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            isPresented = true
            currentOffset = target
        }
        HapticManager.impact(style: .light)
    }

    func dismiss() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
            currentOffset = totalHeight
            isPresented = false
        }
        HapticManager.impact(style: .light)
        dragOffset = 0
    }

    // MARK: Drag Handling

    func onDragChanged(_ value: DragGesture.Value, keyboardHeight: CGFloat) {
        // If inner scroll is not at the top and the user is dragging up, let the scroll handle it.
        if !innerScrollAtTop && value.translation.height < 0 { return }

        velocityTracker.append(value.translation.height)
        if velocityTracker.count > 8 { velocityTracker.removeFirst() }

        let raw = value.translation.height
        // Add rubber-band resistance when dragging beyond the topmost snap point
        let topLimit = topSnap
        let liveOffset = currentOffset + raw
        if liveOffset < topLimit {
            let overshoot = topLimit - liveOffset
            dragOffset = raw - overshoot * (1 - min(overshoot / 160, 0.85))
        } else {
            dragOffset = raw
        }
    }

    func onDragEnded(_ value: DragGesture.Value) {
        let velocity = averageVelocity()
        let projectedEnd = currentOffset + dragOffset + velocity * 0.22
        snapToNearest(projectedEnd: projectedEnd, velocity: velocity)
        velocityTracker = []
    }

    // MARK: Private

    private var topSnap: CGFloat {
        configuration.snapPoints
            .map { $0.resolvedOffset(in: totalHeight, topSafeArea: topSafeArea) }
            .min() ?? 0
    }

    private func averageVelocity() -> CGFloat {
        guard velocityTracker.count > 1 else { return 0 }
        let diffs = zip(velocityTracker, velocityTracker.dropFirst()).map { $1 - $0 }
        return diffs.reduce(0, +) / CGFloat(diffs.count)
    }

    private func snapToNearest(projectedEnd: CGFloat, velocity: CGFloat) {
        let offsets = configuration.snapPoints.map {
            ($0, $0.resolvedOffset(in: totalHeight, topSafeArea: topSafeArea))
        }

        // Strong downward flick: dismiss (if dragging past the bottom snap + 60pt)
        let bottomSnapOffset = offsets.map(\.1).max() ?? totalHeight
        if velocity > 18 || projectedEnd > bottomSnapOffset + 60 {
            dismiss()
            dragOffset = 0
            return
        }

        // Strong upward flick: snap to the topmost point
        if velocity < -18 {
            if let topMost = offsets.min(by: { $0.1 < $1.1 }) {
                snap(to: topMost.0, offset: topMost.1)
            }
            return
        }

        // Otherwise snap to closest
        if let nearest = offsets.min(by: { abs($0.1 - projectedEnd) < abs($1.1 - projectedEnd) }) {
            snap(to: nearest.0, offset: nearest.1)
        }
    }

    private func snap(to point: AMENSnapPoint, offset: CGFloat) {
        currentSnap = point
        withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
            currentOffset = offset
            dragOffset = 0
        }
        HapticManager.selection()
    }
}

// MARK: - Inner Scroll Coordinator

/// Bridges a UIScrollView's contentOffset back to the sheet controller,
/// so we can decide whether to pass drags to the sheet or the scroll view.
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct AMENSheetScrollSpacer: View {
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(key: ScrollOffsetKey.self,
                            value: geo.frame(in: .named("sheetScroll")).minY)
        }
        .frame(height: 0)
    }
}

// MARK: - Background Dimmer

private struct AMENSheetDimmer: View {
    let style: AMENSheetConfiguration.BackgroundStyle
    let isVisible: Bool
    let opacity: CGFloat       // 0-1 driven by live sheet position
    let onTap: () -> Void

    var body: some View {
        switch style {
        case .dimmed(let maxOpacity):
            Color.black
                .opacity(isVisible ? maxOpacity * opacity : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .animation(.easeInOut(duration: 0.22), value: isVisible)

        case .blurred:
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(isVisible ? opacity : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .animation(.easeInOut(duration: 0.22), value: isVisible)

        case .none:
            EmptyView()
        }
    }
}

// MARK: - Drag Indicator

private struct AMENDragIndicator: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(Color.primary.opacity(0.22))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

// MARK: - Sheet Container

struct AMENBottomSheetContainer<Content: View>: View {

    @ObservedObject var controller: AMENSheetController
    @Binding var isPresented: Bool
    let content: Content

    // Keyboard height publisher
    @State private var keyboardHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let totalH = geo.size.height + geo.safeAreaInsets.bottom
            let topSafe = geo.safeAreaInsets.top

            ZStack(alignment: .bottom) {
                // Background
                AMENSheetDimmer(
                    style: controller.configuration.backgroundStyle,
                    isVisible: controller.isPresented,
                    opacity: dimmerOpacity(totalH: totalH),
                    onTap: {
                        guard controller.configuration.tapBackgroundToDismiss else { return }
                        isPresented = false
                        controller.dismiss()
                    }
                )

                // Sheet card
                if controller.isPresented {
                    sheetCard(totalH: totalH, topSafe: topSafe, geo: geo)
                        .transition(.identity) // managed by controller offset
                }
            }
            .ignoresSafeArea()
            .onAppear {
                controller.present(totalHeight: totalH, topSafeArea: topSafe)
            }
            .onChange(of: isPresented) { _, newValue in
                if !newValue { controller.dismiss() }
            }
            .onReceive(keyboardPublisher) { height in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
                    keyboardHeight = height
                }
            }
        }
    }

    // MARK: Sheet Card

    @ViewBuilder
    private func sheetCard(totalH: CGFloat, topSafe: CGFloat, geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            if controller.configuration.showDragIndicator {
                AMENDragIndicator()
            }
            content
        }
        .background(
            // Material background matching system sheet look
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.14), radius: 24, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .ignoresSafeArea(edges: .bottom)
        .offset(y: liveOffset(totalH: totalH, topSafe: topSafe) - geo.safeAreaInsets.bottom)
        .gesture(dragGesture(totalH: totalH))
        // Scroll-to-top coordination
        .onPreferenceChange(ScrollOffsetKey.self) { offset in
            controller.innerScrollAtTop = offset >= -4
        }
        .coordinateSpace(name: "sheetScroll")
        // Keyboard clearance: shift the entire sheet up when keyboard is visible
        .padding(.bottom, keyboardHeight > 0 ? keyboardHeight - geo.safeAreaInsets.bottom : 0)
    }

    // MARK: Offset

    private func liveOffset(totalH: CGFloat, topSafe: CGFloat) -> CGFloat {
        max(topSafe + 16, controller.currentOffset + controller.dragOffset)
    }

    // MARK: Dimmer Opacity

    private func dimmerOpacity(totalH: CGFloat) -> CGFloat {
        guard totalH > 0 else { return 0 }
        let topLimit = controller.configuration.snapPoints
            .map { $0.resolvedOffset(in: totalH, topSafeArea: controller.topSafeArea) }
            .min() ?? 0
        let bottomLimit = totalH
        let live = controller.currentOffset + controller.dragOffset
        let fraction = 1 - (live - topLimit) / max(1, bottomLimit - topLimit)
        return max(0, min(1, fraction))
    }

    // MARK: Drag Gesture

    private func dragGesture(totalH: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in controller.onDragChanged(v, keyboardHeight: keyboardHeight) }
            .onEnded   { v in controller.onDragEnded(v) }
    }

    // MARK: Keyboard Publisher

    private var keyboardPublisher: AnyPublisher<CGFloat, Never> {
        Publishers.Merge(
            NotificationCenter.default
                .publisher(for: UIResponder.keyboardWillShowNotification)
                .map { note -> CGFloat in
                    (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
                },
            NotificationCenter.default
                .publisher(for: UIResponder.keyboardWillHideNotification)
                .map { _ in CGFloat(0) }
        )
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }
}

// MARK: - View Modifier

private struct AMENBottomSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let configuration: AMENSheetConfiguration
    let sheetContent: () -> SheetContent

    @StateObject private var controller: AMENSheetController

    init(isPresented: Binding<Bool>,
         configuration: AMENSheetConfiguration,
         @ViewBuilder sheetContent: @escaping () -> SheetContent) {
        self._isPresented = isPresented
        self.configuration = configuration
        self.sheetContent = sheetContent
        self._controller = StateObject(wrappedValue: AMENSheetController(configuration: configuration))
    }

    func body(content: Content) -> some View {
        ZStack {
            content
                // Subtle scale-down of the feed when the sheet is presented (Apple-style)
                .scaleEffect(isPresented ? 0.965 : 1.0)
                .animation(.spring(response: 0.40, dampingFraction: 0.88), value: isPresented)

            if isPresented {
                AMENBottomSheetContainer(
                    controller: controller,
                    isPresented: $isPresented,
                    content: sheetContent()
                )
                .transition(.identity)
            }
        }
        .onChange(of: isPresented) { _, newVal in
            if newVal {
                // Controller will be presented inside onAppear of the container,
                // but we reset snap to initial here for repeated opens.
                controller.currentSnap = configuration.initialSnap
            }
        }
    }
}

// MARK: - View Extension

extension View {
    /// Presents an AMEN-style interactive bottom sheet.
    func amenBottomSheet<Content: View>(
        isPresented: Binding<Bool>,
        configuration: AMENSheetConfiguration = .comments,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.modifier(AMENBottomSheetModifier(
            isPresented: isPresented,
            configuration: configuration,
            sheetContent: content
        ))
    }
}

// MARK: - Scroll View Wrapper for Sheet Content
//
// Drop-in replacement for ScrollView when placed inside an AMENBottomSheet.
// Reports its scroll offset via ScrollOffsetKey so the sheet can hand off
// drag events to the scroll view once it's no longer at the top.

struct AMENSheetScrollView<Content: View>: View {
    let axes: Axis.Set
    let showsIndicators: Bool
    let content: Content

    init(_ axes: Axis.Set = .vertical,
         showsIndicators: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    var body: some View {
        ScrollView(axes, showsIndicators: showsIndicators) {
            VStack(spacing: 0) {
                // Offset tracker — placed at the very top of scroll content
                AMENSheetScrollSpacer()
                content
            }
        }
        .coordinateSpace(name: "sheetScroll")
    }
}
