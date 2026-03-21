//
//  BereanDynamicIsland.swift
//  AMENAPP
//
//  A Dynamic Island–style overlay for quick Berean AI responses.
//  - Thinking state: fluid aura blob pulses and breathes down from the island
//  - Responded state: card drops and locks below the island, Uber-style
//  - App color palette: deep indigo → blue → soft cyan gradient
//

import SwiftUI
import Combine

// MARK: - State machine

enum BereanIslandState {
    case idle       // hidden
    case thinking   // aura blob animating from island
    case responded  // expanded card anchored below island
}

// MARK: - View Model

@MainActor
final class BereanIslandViewModel: ObservableObject {

    /// Shared instance — PostCard calls trigger() on this directly.
    static let shared = BereanIslandViewModel()

    @Published var state: BereanIslandState = .idle
    @Published var responseText: String = ""
    @Published var thinkingSeconds: Int = 0
    @Published var displayedText: String = ""   // drives typing effect
    /// Set by ContentView so "Open Full" can present the full sheet
    var onOpenFullSheet: (() -> Void)?

    private var thinkingTask: Task<Void, Never>?
    private var typingTask: Task<Void, Never>?

    // Called by PostCard when user taps the Berean button
    func trigger(query: String) {
        responseText = ""
        displayedText = ""
        thinkingSeconds = 0
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
            state = .thinking
        }
        startThinkingClock()
        fetchResponse(query: query)
    }

    /// Extended trigger used by BereanIslandButton — forwards to base trigger.
    func trigger(query: String, postId: String, postContent: String) {
        trigger(query: query)
    }

    /// Instant display from a cached result — skips the API call entirely.
    func triggerWithCachedResult(
        _ cached: BereanCachedResult,
        postId: String,
        query: String,
        postContent: String
    ) {
        thinkingTask?.cancel()
        typingTask?.cancel()
        thinkingSeconds = 0
        let snippet = Self.snippet(from: cached.responseText)
        responseText = snippet
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            state = .responded
        }
        typeText(snippet)
    }

    func dismiss() {
        thinkingTask?.cancel()
        typingTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            state = .idle
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            self?.responseText = ""
            self?.displayedText = ""
        }
    }

    // MARK: Private

    private func startThinkingClock() {
        thinkingTask?.cancel()
        thinkingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !Task.isCancelled { thinkingSeconds += 1 }
            }
        }
    }

    private func fetchResponse(query: String) {
        Task {
            let engine = BereanAnswerEngine.shared
            do {
                let answer = try await engine.answer(
                    query: query,
                    context: nil,
                    mode: nil
                )
                guard !Task.isCancelled else { return }
                thinkingTask?.cancel()
                let snippet = Self.snippet(from: answer.response)
                responseText = snippet
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                    state = .responded
                }
                typeText(snippet)
            } catch {
                guard !Task.isCancelled else { return }
                thinkingTask?.cancel()
                let fallback = "Berean couldn't reach the scriptures right now. Tap \"Open Full\" to try again."
                responseText = fallback
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                    state = .responded
                }
                typeText(fallback)
            }
        }
    }

    private func typeText(_ text: String) {
        typingTask?.cancel()
        displayedText = ""
        typingTask = Task {
            for char in text {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 16_000_000)
                displayedText.append(char)
            }
        }
    }

    private static func snippet(from text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > 280 else { return clean }
        let prefix = String(clean.prefix(280))
        if let dot = prefix.lastIndex(of: ".") {
            return String(prefix[...dot])
        }
        return prefix + "…"
    }
}

// MARK: - App colour palette (Berean theme)

private enum BereanColor {
    /// Deep indigo — island pill / card background base
    static let islandBg     = Color(red: 0.07, green: 0.07, blue: 0.18)
    /// Vivid blue — primary glow / aura centre
    static let auraBlue     = Color(red: 0.10, green: 0.45, blue: 0.95)
    /// Soft indigo-purple — aura outer ring
    static let auraPurple   = Color(red: 0.30, green: 0.18, blue: 0.72)
    /// Icy cyan — highlight spark in aura
    static let auraCyan     = Color(red: 0.40, green: 0.82, blue: 1.00)
    /// Subtle edge for response card
    static let cardBorder   = Color(red: 0.28, green: 0.38, blue: 0.80).opacity(0.35)
}

// MARK: - Main overlay view

struct BereanDynamicIsland: View {
    @ObservedObject var vm: BereanIslandViewModel
    let onOpenFull: () -> Void

    // Aura animation state
    @State private var auraScale: CGFloat    = 0.0
    @State private var auraOpacity: Double   = 0.0
    @State private var auraOffset: CGFloat   = 0.0
    @State private var auraRotation: Double  = 0.0
    @State private var sparkScale: CGFloat   = 0.4
    @State private var sparkOffset: CGPoint  = .zero
    // Thinking dots
    @State private var pulsing = false
    // Snake logo
    @State private var snakeHead: CGFloat    = 0
    @State private var snakeHead2: CGFloat   = 0

    var body: some View {
        if vm.state != .idle {
            ZStack(alignment: .top) {
                // Layer 1: ambient aura blob (thinking only)
                if vm.state == .thinking {
                    auraBlob
                        .transition(.opacity)
                }

                // Layer 2: island card (both states)
                VStack(spacing: 0) {
                    islandCard
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.75, anchor: .top)
                                .combined(with: .opacity),
                            removal: .scale(scale: 0.75, anchor: .top)
                                .combined(with: .opacity)
                        ))
                    Spacer()
                }
            }
            .ignoresSafeArea(edges: .top)
            .contentShape(Rectangle())
            .onTapGesture { vm.dismiss() }
        }
    }

    // MARK: - Aura blob (thinking state)

    private var auraBlob: some View {
        GeometryReader { geo in
            ZStack {
                // Main blob
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                BereanColor.auraBlue.opacity(0.70),
                                BereanColor.auraPurple.opacity(0.45),
                                BereanColor.auraBlue.opacity(0.12),
                                Color.clear
                            ],
                            center: .init(x: 0.5, y: 0.25),
                            startRadius: 0,
                            endRadius: geo.size.width * 0.55
                        )
                    )
                    .frame(width: geo.size.width * 0.72, height: geo.size.height * 0.65)
                    .scaleEffect(auraScale)
                    .offset(y: auraOffset)
                    .rotationEffect(.degrees(auraRotation))
                    .opacity(auraOpacity)
                    .blur(radius: 28)

                // Inner bright core
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                BereanColor.auraCyan.opacity(0.80),
                                BereanColor.auraBlue.opacity(0.30),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .scaleEffect(sparkScale)
                    .offset(x: sparkOffset.x, y: sparkOffset.y + auraOffset * 0.6)
                    .opacity(auraOpacity * 0.9)
                    .blur(radius: 12)
            }
            .frame(maxWidth: .infinity)
            .offset(x: 0, y: topInset - 10)
        }
        .allowsHitTesting(false)
        .onAppear { startAuraAnimation() }
        .onDisappear { stopAuraAnimation() }
    }

    private func startAuraAnimation() {
        // Breathe in
        withAnimation(.easeOut(duration: 0.55)) {
            auraOpacity = 1.0
            auraScale   = 1.0
            auraOffset  = 30
        }
        // Continuous slow breathe + drift
        withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
            auraScale    = 1.12
            auraOffset   = 55
            auraRotation = 8
        }
        withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true).delay(0.4)) {
            sparkScale  = 1.0
            sparkOffset = CGPoint(x: -18, y: 40)
        }
    }

    private func stopAuraAnimation() {
        withAnimation(.easeIn(duration: 0.3)) {
            auraOpacity = 0
            auraScale   = 0.6
        }
        auraRotation = 0
        auraOffset   = 0
        sparkScale   = 0.4
        sparkOffset  = .zero
    }

    // MARK: - Island card

    private var islandCard: some View {
        ZStack(alignment: .topLeading) {
            // Background
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(BereanColor.islandBg)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(BereanColor.cardBorder, lineWidth: 1)
                )
                // Subtle top glow matching the aura
                .overlay(alignment: .top) {
                    if vm.state == .thinking {
                        LinearGradient(
                            colors: [BereanColor.auraBlue.opacity(0.25), Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.4)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
                }
                .shadow(color: BereanColor.auraBlue.opacity(vm.state == .thinking ? 0.45 : 0.20),
                        radius: vm.state == .thinking ? 28 : 16,
                        y: 6)

            VStack(alignment: .leading, spacing: 0) {
                topRow
                    .padding(.top, 14)
                    .padding(.horizontal, 18)

                if vm.state == .responded {
                    responseContent
                        .padding(.top, 12)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    thinkingContent
                        .padding(.top, 10)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                        .transition(.opacity)
                }
            }
        }
        .frame(width: cardWidth)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, topInset)
        .padding(.horizontal, 20)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: vm.state)
        .onTapGesture {}  // Block tap-outside-to-dismiss inside card
    }

    // MARK: - Top row

    private var topRow: some View {
        HStack(spacing: 10) {
            amenLogoCanvas
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("Berean")
                    .font(.custom("OpenSans-Bold", size: 13))
                    .foregroundStyle(.white)

                if vm.state == .thinking {
                    HStack(spacing: 4) {
                        Text("thinking")
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(BereanColor.auraCyan.opacity(0.75))
                        thinkingDots
                    }
                    .transition(.opacity)
                } else {
                    Text("thought for \(vm.thinkingSeconds)s")
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(BereanColor.auraCyan.opacity(0.65))
                        .transition(.opacity)
                }
            }

            Spacer()

            Button { vm.dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Thinking dots (inline, coloured)

    private var thinkingDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(dotColor(for: i))
                    .frame(width: 5, height: 5)
                    .scaleEffect(pulsing ? 1.0 : 0.45)
                    .animation(
                        .easeInOut(duration: 0.50)
                            .repeatForever()
                            .delay(Double(i) * 0.16),
                        value: pulsing
                    )
            }
        }
        .onAppear { pulsing = true }
        .onDisappear { pulsing = false }
    }

    private func dotColor(for index: Int) -> Color {
        switch index {
        case 0:  return BereanColor.auraCyan
        case 1:  return BereanColor.auraBlue
        default: return BereanColor.auraPurple
        }
    }

    // MARK: - Thinking content (larger dots row below logo)

    private var thinkingContent: some View {
        // Wider dots row as secondary "processing" indicator
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [BereanColor.auraCyan.opacity(0.9), BereanColor.auraPurple.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: i == 2 ? 22 : (i == 1 || i == 3 ? 14 : 8), height: 4)
                    .scaleEffect(x: pulsing ? 1.0 : 0.4, y: 1)
                    .animation(
                        .easeInOut(duration: 0.65)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.10),
                        value: pulsing
                    )
            }
            Spacer()
        }
        .onAppear  { pulsing = true  }
        .onDisappear { pulsing = false }
    }

    // MARK: - Response content

    private var responseContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Thin coloured top rule
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [BereanColor.auraCyan, BereanColor.auraPurple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1.5)
                .cornerRadius(1)

            // Typing text
            Text(vm.displayedText)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.92))
                .lineSpacing(4)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)

            // Action buttons
            HStack(spacing: 10) {
                Button {
                    vm.dismiss()
                    onOpenFull()
                } label: {
                    Text("Open Full")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(BereanColor.cardBorder, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)

                Button {
                    UIPasteboard.general.string = vm.responseText
                    HapticManager.impact(style: .light)
                    vm.dismiss()
                } label: {
                    Text("Copy")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(BereanColor.islandBg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [BereanColor.auraCyan, BereanColor.auraBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - AMEN "A" logo — path-tracing snake canvas

    private let cachedOuterArcPath: Path = {
        Path { p in
            p.move(to: CGPoint(x: 34.5, y: 73.5))
            p.addCurve(to: CGPoint(x: 22.5, y: 52),
                       control1: CGPoint(x: 28.5, y: 68),
                       control2: CGPoint(x: 22.5, y: 59.5))
            p.addCurve(to: CGPoint(x: 50, y: 22),
                       control1: CGPoint(x: 22.5, y: 35.5),
                       control2: CGPoint(x: 33.5, y: 22))
            p.addCurve(to: CGPoint(x: 77.5, y: 52),
                       control1: CGPoint(x: 66.5, y: 22),
                       control2: CGPoint(x: 77.5, y: 35.5))
            p.addCurve(to: CGPoint(x: 67, y: 74),
                       control1: CGPoint(x: 77.5, y: 60.5),
                       control2: CGPoint(x: 73.5, y: 68.5))
        }
    }()

    private let cachedCrossbarPath: Path = {
        Path { p in
            p.move(to: CGPoint(x: 62, y: 49.5))
            p.addCurve(to: CGPoint(x: 43.5, y: 47),
                       control1: CGPoint(x: 57.5, y: 51),
                       control2: CGPoint(x: 48, y: 51))
            p.move(to: CGPoint(x: 63.5, y: 60.5))
            p.addCurve(to: CGPoint(x: 77, y: 58.5),
                       control1: CGPoint(x: 68.5, y: 58.5),
                       control2: CGPoint(x: 73, y: 57.5))
            p.addCurve(to: CGPoint(x: 77.5, y: 62),
                       control1: CGPoint(x: 78.5, y: 59.5),
                       control2: CGPoint(x: 78.5, y: 61))
            p.addCurve(to: CGPoint(x: 67, y: 66.5),
                       control1: CGPoint(x: 76, y: 63.5),
                       control2: CGPoint(x: 71.5, y: 65))
            p.addCurve(to: CGPoint(x: 38, y: 71),
                       control1: CGPoint(x: 60.5, y: 68.5),
                       control2: CGPoint(x: 50.5, y: 70))
            p.addCurve(to: CGPoint(x: 13.5, y: 69.5),
                       control1: CGPoint(x: 25.5, y: 72),
                       control2: CGPoint(x: 16.5, y: 71.5))
            p.move(to: CGPoint(x: 38, y: 71))
            p.addCurve(to: CGPoint(x: 33.5, y: 68),
                       control1: CGPoint(x: 35.5, y: 71),
                       control2: CGPoint(x: 34, y: 70))
            p.addCurve(to: CGPoint(x: 35.5, y: 60),
                       control1: CGPoint(x: 33, y: 66),
                       control2: CGPoint(x: 33.5, y: 63))
            p.addCurve(to: CGPoint(x: 50, y: 43.5),
                       control1: CGPoint(x: 39.5, y: 54.5),
                       control2: CGPoint(x: 44, y: 49))
            p.move(to: CGPoint(x: 35.5, y: 60))
            p.addLine(to: CGPoint(x: 42.5, y: 52.5))
        }
    }()

    private var amenLogoCanvas: some View {
        Canvas { ctx, size in
            let scale = size.width / 100.0
            ctx.scaleBy(x: scale, y: scale)

            let strokeStyle = StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)

            let outer = cachedOuterArcPath
            let inner = cachedCrossbarPath

            if vm.state == .thinking {
                // Faint guide paths
                ctx.stroke(outer, with: .color(BereanColor.auraBlue.opacity(0.15)), style: strokeStyle)
                ctx.stroke(inner, with: .color(BereanColor.auraPurple.opacity(0.15)), style: strokeStyle)

                // Animated cyan snake on outer arc
                let s1 = outer.trimmedPath(from: max(0, snakeHead - 0.28), to: snakeHead)
                ctx.stroke(s1, with: .color(BereanColor.auraCyan), style: strokeStyle)

                // Animated blue snake on inner crossbar
                let s2 = inner.trimmedPath(from: max(0, snakeHead2 - 0.28), to: snakeHead2)
                ctx.stroke(s2, with: .color(BereanColor.auraBlue.opacity(0.85)), style: strokeStyle)
            } else {
                // Static full paths — cyan + blue
                ctx.stroke(outer, with: .color(BereanColor.auraCyan), style: strokeStyle)
                ctx.stroke(inner, with: .color(BereanColor.auraBlue.opacity(0.75)), style: strokeStyle)
            }
        }
        .onAppear { startSnakeLoop() }
        .onChange(of: vm.state) { _, newState in
            if newState != .thinking {
                snakeHead  = 1.0
                snakeHead2 = 1.0
            } else {
                startSnakeLoop()
            }
        }
    }

    private func startSnakeLoop() {
        snakeHead  = 0
        snakeHead2 = 0
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
            snakeHead = 1.0
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard vm.state == .thinking else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                snakeHead2 = 1.0
            }
        }
    }

    // MARK: - Layout helpers

    private var cardWidth: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width ?? 390) - 40
    }
    private var cornerRadius: CGFloat { 26 }
    private var topInset: CGFloat {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first
        return (window?.safeAreaInsets.top ?? 44) - 8
    }
}

// MARK: - ViewModifier

struct BereanIslandModifier: ViewModifier {
    @ObservedObject var vm: BereanIslandViewModel
    @Binding var showFullSheet: Bool

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            BereanDynamicIsland(vm: vm, onOpenFull: { showFullSheet = true })
        }
    }
}

extension View {
    func bereanDynamicIsland(vm: BereanIslandViewModel, showFullSheet: Binding<Bool>) -> some View {
        self.modifier(BereanIslandModifier(vm: vm, showFullSheet: showFullSheet))
    }
}
