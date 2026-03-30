
//  BereanTabSwitcherView.swift
//  AMENAPP
//
//  Option C — Featured layout, white background.
//  Safari-style multi-session switcher for Berean AI.
//  Does NOT touch BereanInteractiveUI, BereanOrchestrator, or BereanRAGService.
//  Does NOT change BereanChatSessionManager.

import SwiftUI
import FirebaseFunctions
import FirebaseAuth

// MARK: - Main Tab Switcher

struct BereanTabSwitcherView: View {
    @Binding var isShowing: Bool
    @ObservedObject var sessionManager: BereanChatSessionManager
    let namespace: Namespace.ID          // open/close transition namespace passed from parent
    let profilePhotoURL: String?         // current user's photo URL (or nil → initials)
    let onSelectSession: (UUID) -> Void
    let onNewSession: () -> Void
    let onNewSessionWithPrompt: (String) -> Void   // chip tap: new session + auto-send

    // Featured card is whichever session is currently being previewed
    // (starts at the active session; mini-card tap promotes a different session)
    @State private var localFeaturedID: UUID
    @Namespace private var featuredNS

    // Topic chip state
    @State private var suggestedTopics: [String] = []
    @State private var topicsLoaded = false
    @State private var activeChip: String?
    @State private var chipsVisible: [String: Bool] = [:]

    // Removal animation
    @State private var removingIDs: Set<UUID> = []

    private let spring: Animation = .spring(response: 0.45, dampingFraction: 0.75)
    private let chipSpring: Animation = .spring(response: 0.28, dampingFraction: 0.72)

    private var featuredSession: BereanChatSession? {
        sessionManager.sessions.first(where: { $0.id == localFeaturedID })
    }

    private var miniSessions: [BereanChatSession] {
        sessionManager.sessions.filter { $0.id != localFeaturedID && !removingIDs.contains($0.id) }
    }

    private static let fallbackChips = [
        "🙏 Prayer life",
        "📖 Scripture study",
        "💼 Faith & work",
        "❤️ Relationships",
        "🌱 Spiritual growth"
    ]

    init(
        isShowing: Binding<Bool>,
        sessionManager: BereanChatSessionManager,
        namespace: Namespace.ID,
        profilePhotoURL: String?,
        onSelectSession: @escaping (UUID) -> Void,
        onNewSession: @escaping () -> Void,
        onNewSessionWithPrompt: @escaping (String) -> Void
    ) {
        self._isShowing = isShowing
        self.sessionManager = sessionManager
        self.namespace = namespace
        self.profilePhotoURL = profilePhotoURL
        self.onSelectSession = onSelectSession
        self.onNewSession = onNewSession
        self.onNewSessionWithPrompt = onNewSessionWithPrompt
        self._localFeaturedID = State(initialValue: sessionManager.activeSessionID)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── White background ─────────────────────────────────────────
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)

                // ── Divider under top bar ─────────────────────────────────
                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)

                // ── Scrollable content ───────────────────────────────────
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {

                        // ── Featured card ─────────────────────────────────
                        if let featured = featuredSession {
                            FeaturedChatCard(
                                session: featured,
                                namespace: featuredNS
                            ) {
                                // Continue → activate + dismiss
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                onSelectSession(featured.id)
                                withAnimation(spring) { isShowing = false }
                            } onClose: {
                                removeCard(featured.id)
                            }
                            .padding(.horizontal, 16)
                            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                        }

                        // ── Mini cards ────────────────────────────────────
                        if !miniSessions.isEmpty {
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())],
                                spacing: 12
                            ) {
                                ForEach(miniSessions) { session in
                                    MiniChatCard(
                                        session: session,
                                        namespace: featuredNS
                                    ) {
                                        // Promote to featured
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        withAnimation(spring) { localFeaturedID = session.id }
                                    } onClose: {
                                        removeCard(session.id)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .animation(spring, value: miniSessions.map(\.id))
                        }

                        // ── Topic chips ───────────────────────────────────
                        suggestedTopicsSection
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }

            // ── Bottom toolbar ────────────────────────────────────────────
            bottomToolbar
        }
        .task { await loadSuggestedTopics() }
        .onDisappear {
            removingIDs = []
            activeChip = nil
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 0) {
            // Profile photo
            profileAvatar
                .padding(.leading, 20)

            Spacer()

            Text("Chats")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.black)

            Spacer()

            // "···" menu
            Menu {
                Button(role: .destructive) {
                    withAnimation(spring) {
                        let others = sessionManager.sessions.filter { $0.id != localFeaturedID }
                        for s in others { sessionManager.delete(s.id) }
                    }
                } label: {
                    Label("Close Other Chats", systemImage: "xmark.circle")
                }

                Button(role: .destructive) {
                    withAnimation(spring) {
                        let ids = sessionManager.sessions.map(\.id)
                        ids.forEach { sessionManager.delete($0) }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(spring) { isShowing = false }
                        onNewSession()
                    }
                } label: {
                    Label("Close All Chats", systemImage: "trash")
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.06))
                        .frame(width: 30, height: 30)
                    Text("···")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.7))
                        .offset(y: -2)
                }
            }
            .padding(.trailing, 20)
        }
        .frame(height: 52)
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let urlStr = profilePhotoURL, !urlStr.isEmpty, let url = URL(string: urlStr) {
            CachedAsyncImage(url: url) { image in
                image.resizable().scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.black.opacity(0.07), lineWidth: 0.5))
            } placeholder: {
                initialsCircle
            }
        } else {
            initialsCircle
        }
    }

    private var initialsCircle: some View {
        let name = Auth.auth().currentUser?.displayName ?? ""
        let initials = name.split(separator: " ").prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        return ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(hex: "#7A6FFF"), Color(hex: "#4FA3FF")],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 34, height: 34)
            Text(initials.isEmpty ? "?" : initials)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Suggested Topics

    private var suggestedTopicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("START A NEW CHAT")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.gray)
                .kerning(0.6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let chips = topicsLoaded ? suggestedTopics : Self.fallbackChips
                    ForEach(Array(chips.enumerated()), id: \.element) { index, chip in
                        BereanTopicChip(
                            label: chip,
                            isActive: activeChip == chip,
                            isVisible: chipsVisible[chip] ?? false
                        ) {
                            activeChip = chip
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(chipSpring.delay(0.15)) {
                                withAnimation(spring) { isShowing = false }
                                let msg = stripEmoji(chip)
                                onNewSessionWithPrompt(msg)
                            }
                        }
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.05) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    chipsVisible[chip] = true
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.07))
                .frame(height: 0.5)

            HStack(spacing: 0) {
                toolbarButton(icon: "waveform") {
                    withAnimation(spring) { isShowing = false }
                }

                Spacer()

                toolbarButton(icon: "square.grid.2x2") { }

                Spacer()

                // Tab count — closes switcher
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(spring) { isShowing = false }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.black.opacity(0.5), lineWidth: 1.2)
                            )
                            .frame(width: 22, height: 22)
                        Text("\(sessionManager.sessions.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.black)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                toolbarButton(icon: "square.on.square") {
                    if let s = featuredSession {
                        withAnimation(spring) { sessionManager.duplicate(s.id) }
                    }
                }

                Spacer()

                // New chat
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(spring) { isShowing = false }
                    onNewSession()
                } label: {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(hex: "#7A6FFF"), Color(hex: "#4FA3FF")],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 40, height: 40)
                            .shadow(color: Color(hex: "#7A6FFF").opacity(0.35), radius: 8, y: 3)
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.top, 10)
            .padding(.bottom, 42)
            .background(Color.white)
        }
    }

    @ViewBuilder
    private func toolbarButton(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.gray.opacity(0.6))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func removeCard(_ id: UUID) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(spring) { removingIDs.insert(id) }
        // If we're removing the featured session, promote the next available
        if id == localFeaturedID {
            let next = sessionManager.sessions.first(where: { $0.id != id })
            if let next { withAnimation(spring) { localFeaturedID = next.id } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            sessionManager.delete(id)
            removingIDs.remove(id)
        }
    }

    // MARK: - AI Topic Suggestions

    private func loadSuggestedTopics() async {
        guard !sessionManager.sessions.isEmpty else {
            setFallback(); return
        }
        let titles = sessionManager.sessions.map(\.displayTitle).joined(separator: ", ")
        let prompt = """
        Based on these past Berean AI chat titles: \(titles), suggest 5 short spiritual topic ideas the user might want to explore next. Return ONLY a JSON array of strings, max 4 words each, include a relevant emoji prefix.
        """
        do {
            let callable = Functions.functions().httpsCallable("smartSuggestionsProxy")
            let result = try await callable.call(["prompt": prompt, "maxTokens": 150] as [String: Any])
            let text = (result.data as? [String: Any])?["text"] as? String ?? ""
            // Parse JSON array from response text
            if let data = text.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [String],
               !arr.isEmpty {
                await MainActor.run {
                    suggestedTopics = Array(arr.prefix(5))
                    topicsLoaded = true
                }
            } else {
                setFallback()
            }
        } catch {
            setFallback()
        }
    }

    @MainActor
    private func setFallback() {
        suggestedTopics = Self.fallbackChips
        topicsLoaded = true
    }

    // MARK: - Helpers

    /// Strip leading emoji + space from chip label ("🙏 Prayer life" → "Prayer life")
    private func stripEmoji(_ text: String) -> String {
        guard let first = text.unicodeScalars.first,
              first.properties.isEmoji else { return text }
        let dropped = text.drop(while: { $0.unicodeScalars.first?.properties.isEmoji == true || $0 == " " })
        return dropped.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Featured Chat Card

private struct FeaturedChatCard: View {
    let session: BereanChatSession
    let namespace: Namespace.ID
    let onContinue: () -> Void
    let onClose: () -> Void

    @State private var dotScale: CGFloat = 1.0
    @State private var dotOpacity: Double = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                // ── Active now badge ──────────────────────────────────────
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "#7A6FFF"))
                        .frame(width: 7, height: 7)
                        .scaleEffect(dotScale)
                        .opacity(dotOpacity)
                        .onAppear {
                            withAnimation(
                                .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
                            ) {
                                dotScale = 0.7
                                dotOpacity = 0.5
                            }
                        }

                    Text("Active now")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "#7A6FFF"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color(hex: "#7A6FFF").opacity(0.10))
                )

                // ── Title ─────────────────────────────────────────────────
                Text(session.displayTitle)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundStyle(Color(hex: "#2A1A6E"))
                    .lineLimit(2)

                // ── Preview ───────────────────────────────────────────────
                if let last = session.lastAssistantMessage, !last.content.isEmpty {
                    Text(last.content)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.gray.opacity(0.7))
                        .lineLimit(2)
                        .lineSpacing(1.55)
                }

                // ── Footer ────────────────────────────────────────────────
                HStack {
                    Text(session.relativeTimestamp)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.gray)

                    Spacer()

                    Button(action: onContinue) {
                        Text("Continue →")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(hex: "#7A6FFF"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hex: "#F0EEFF"), Color(hex: "#E8F4FF")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color(hex: "#7A6FFF").opacity(0.2), lineWidth: 0.5)
                    )
            )
            .matchedGeometryEffect(id: session.id, in: namespace)

            // ── Close X ───────────────────────────────────────────────────
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.5))
                    .frame(width: 20, height: 20)
                    .background(Color.black.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
        }
    }
}

// MARK: - Mini Chat Card

private struct MiniChatCard: View {
    let session: BereanChatSession
    let namespace: Namespace.ID
    let onTap: () -> Void
    let onClose: () -> Void

    @State private var showConfirmDelete = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "#7A6FFF").opacity(0.7))
                    Text(session.displayTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.8))
                        .lineLimit(1)
                }

                // Preview
                if let last = session.lastAssistantMessage, !last.content.isEmpty {
                    Text(last.content)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.gray.opacity(0.75))
                        .lineLimit(2)
                        .lineSpacing(1.2)
                }

                Spacer(minLength: 0)

                // Timestamp
                Text(session.relativeTimestamp)
                    .font(.system(size: 8, weight: .light))
                    .foregroundStyle(Color.gray.opacity(0.55))
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: 120, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: "#F7F7FB"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                    )
            )
            .matchedGeometryEffect(id: session.id, in: namespace)
            .onTapGesture { onTap() }
            .onLongPressGesture(minimumDuration: 0.45) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showConfirmDelete = true
            }
            .confirmationDialog(session.displayTitle, isPresented: $showConfirmDelete, titleVisibility: .visible) {
                Button("Delete Chat", role: .destructive) { onClose() }
                Button("Cancel", role: .cancel) {}
            }

            // Close X
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.4))
                    .frame(width: 16, height: 16)
                    .background(Color.black.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(7)
        }
    }
}

// MARK: - Topic Chip

private struct BereanTopicChip: View {
    let label: String
    let isActive: Bool
    let isVisible: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isActive ? Color(hex: "#6450FF") : Color(hex: "#555555"))
                .padding(.vertical, 5)
                .padding(.horizontal, 11)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isActive ? Color(hex: "#EDE9FF") : Color(hex: "#F2F2F7"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(
                                    isActive
                                        ? Color(hex: "#7A6FFF").opacity(0.4)
                                        : Color.black.opacity(0.08),
                                    lineWidth: 0.5
                                )
                        )
                )
        }
        .buttonStyle(_ChipPress())
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.85)
        .animation(isVisible ? .easeOut(duration: 0.3) : .none, value: isVisible)
    }
}

private struct _ChipPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - Tab Count Trigger Button (unchanged public API)

/// Small Safari-style tab count button shown in the Berean header's top-trailing area.
struct BereanTabCountButton: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                    )
                    .frame(width: 28, height: 28)

                Text("\(count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.2))
                    .contentTransition(.numericText())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) Berean chat\(count == 1 ? "" : "s"), tap to switch")
    }
}
