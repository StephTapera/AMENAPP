//
//  ChurchLiveModeView.swift
//  AMENAPP
//
//  Full-screen live church session view — Phase 4 Live Mode.
//  Supports chat, prayer queue, chapter markers, admin controls,
//  moderation, and a post-live AI recap prompt.
//
//  Design system:
//  - Dark base background for live video context
//  - Liquid Glass: .ultraThinMaterial + Color.white.opacity(0.55) overlay
//                  + Color(white: 0.88).opacity(0.5) strokeBorder 0.5pt
//                  + shadow black 0.06-0.08 radius 12-18
//  - Typography: AMENFont
//
//

import SwiftUI
import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - Models

struct LiveChatMessage: Identifiable {
    let id: String
    let authorName: String
    let text: String
    let timestamp: Date
    let isPrayer: Bool
}

struct PrayerQueueEntry: Identifiable {
    let id: String
    let authorName: String
    let request: String
    let submittedAt: Date
    var isAddressed: Bool
}

struct ChapterMarker: Identifiable {
    let id: String
    let title: String
    let timestamp: TimeInterval
}

// MARK: - LiveTab

enum LiveTab: String, CaseIterable {
    case chat    = "Chat"
    case prayers = "Prayers"
    case markers = "Markers"

    var icon: String {
        switch self {
        case .chat:    return "bubble.left.and.bubble.right"
        case .prayers: return "hands.sparkles"
        case .markers: return "bookmark.fill"
        }
    }
}

// MARK: - ViewModel

@MainActor
class ChurchLiveModeViewModel: ObservableObject {

    @Published var isLive: Bool = false
    @Published var chatMessages: [LiveChatMessage] = []
    @Published var prayerQueue: [PrayerQueueEntry] = []
    @Published var chapterMarkers: [ChapterMarker] = []
    @Published var elapsedSeconds: Double = 0
    @Published var viewerCount: Int = 0

    private var timer: AnyCancellable?

    // MARK: Actions

    func startLive() {
        isLive = true
        elapsedSeconds = 0
        viewerCount = Int.random(in: 12...48)
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.elapsedSeconds += 1
                // Simulate occasional viewer count drift
                if Int(self.elapsedSeconds) % 15 == 0 {
                    self.viewerCount += Int.random(in: -2...5)
                    self.viewerCount = max(0, self.viewerCount)
                }
            }
    }

    func endLive() {
        isLive = false
        timer?.cancel()
        timer = nil
    }

    func sendMessage(_ text: String, authorName: String, isPrayer: Bool) {
        let msg = LiveChatMessage(
            id: UUID().uuidString,
            authorName: authorName,
            text: text,
            timestamp: Date(),
            isPrayer: isPrayer
        )
        chatMessages.append(msg)
        if isPrayer {
            submitPrayerRequest(text, authorName: authorName)
        }
    }

    func submitPrayerRequest(_ request: String, authorName: String) {
        let entry = PrayerQueueEntry(
            id: UUID().uuidString,
            authorName: authorName,
            request: request,
            submittedAt: Date(),
            isAddressed: false
        )
        prayerQueue.append(entry)
    }

    func addChapterMarker(title: String) {
        let marker = ChapterMarker(
            id: UUID().uuidString,
            title: title,
            timestamp: elapsedSeconds
        )
        chapterMarkers.append(marker)
    }

    func markPrayerAddressed(id: String) {
        guard let index = prayerQueue.firstIndex(where: { $0.id == id }) else { return }
        prayerQueue[index].isAddressed = true
    }

    func flagMessage(id: String, churchId: String) {
        chatMessages.removeAll { $0.id == id }
        Task {
            try? await Functions.functions(region: "us-central1")
                .httpsCallable("flagLiveContent")
                .call([
                    "churchId": churchId,
                    "reason": "live_flag",
                    "uid": Auth.auth().currentUser?.uid ?? ""
                ])
        }
    }

    // MARK: Helpers

    var formattedElapsed: String {
        let total = Int(elapsedSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    var unansweredPrayerCount: Int {
        prayerQueue.filter { !$0.isAddressed }.count
    }
}

// MARK: - ChurchLiveModeView

struct ChurchLiveModeView: View {

    // MARK: Parameters

    let churchName: String
    let isAdmin: Bool

    // MARK: Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: State

    @StateObject private var vm = ChurchLiveModeViewModel()
    @StateObject private var entitlements = AmenAccountEntitlementService.shared
    @State private var showLivePaywall: Bool = false
    @State private var showPrayerQueue: Bool = false
    @State private var showEndConfirm: Bool = false
    @State private var messageText: String = ""
    @State private var activeTab: LiveTab = .chat
    @State private var showAIRecapSheet: Bool = false
    @State private var chapterMarkerTitle: String = ""
    @State private var showChapterInput: Bool = false
    @State private var bottomSheetDetent: PresentationDetent = .medium

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── 1. Background ───────────────────────────────────────────────
            Color.black.ignoresSafeArea()

            // ── 2. Video placeholder + gradient overlay ─────────────────────
            videoArea

            // ── 3. Top overlay: LIVE badge + elapsed + viewer count ─────────
            topOverlay

            // ── 4. Admin controls bar (isAdmin only) ───────────────────────
            if isAdmin {
                adminControlsBar
            }

            // ── 5. Right-side floating prayer button (admin only) ───────────
            if isAdmin && vm.isLive {
                prayerQueueButton
            }

            // ── 6. Bottom panel (tabbed sheet) ──────────────────────────────
            bottomPanel

            // ── 7. Post-live AI recap button ─────────────────────────────────
            if !vm.isLive && vm.elapsedSeconds > 0 {
                aiRecapButton
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.dark)
        .onAppear {
            if isAdmin {
                if entitlements.currentTier.canGoLive {
                    vm.startLive()
                } else {
                    showLivePaywall = true
                }
            } else {
                vm.startLive()
            }
        }
        .sheet(isPresented: $showLivePaywall) {
            AmenAccountPaywallView(
                requiredTier: .creatorPro,
                feature: "Live Streaming"
            ) {
                showLivePaywall = false
                dismiss()
            }
        }
        // Chapter marker input alert
        .alert("Add Chapter Marker", isPresented: $showChapterInput) {
            TextField("Marker title...", text: $chapterMarkerTitle)
            Button("Add") {
                let t = chapterMarkerTitle.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { vm.addChapterMarker(title: t) }
                chapterMarkerTitle = ""
            }
            Button("Cancel", role: .cancel) { chapterMarkerTitle = "" }
        } message: {
            Text("Label this moment in the stream.")
        }
        // End live confirmation
        .confirmationDialog("End this live session?", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("End Live", role: .destructive) { vm.endLive() }
            Button("Cancel", role: .cancel) { }
        }
        // AI recap sheet
        .sheet(isPresented: $showAIRecapSheet) {
            aiRecapSheet
        }
        // Prayer queue sheet
        .sheet(isPresented: $showPrayerQueue) {
            prayerQueueSheet
        }
    }

    // MARK: - Video Area

    private var videoArea: some View {
        VStack(spacing: 0) {
            ZStack {
                // Simulated dark video background
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color(white: 0.08))
                    .ignoresSafeArea()

                if vm.isLive {
                    VStack(spacing: 12) {
                        Image(systemName: "video.fill")
                            .font(.systemScaled(44))
                            .foregroundColor(.white.opacity(0.2))
                        Text("Live Stream Active")
                            .font(AMENFont.semiBold(15))
                            .foregroundColor(.white.opacity(0.25))
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash.fill")
                            .font(.systemScaled(44))
                            .foregroundColor(.white.opacity(0.2))
                        Text("Stream Ended")
                            .font(AMENFont.semiBold(15))
                            .foregroundColor(.white.opacity(0.25))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: ScreenMetrics.bounds.height * 0.42)

            // Gradient fade into bottom panel area
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)
        }
    }

    // MARK: - Top Overlay

    private var topOverlay: some View {
        VStack {
            HStack(alignment: .top) {
                // LIVE badge
                if vm.isLive {
                    Text("LIVE")
                        .font(AMENFont.bold(11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .clipShape(Capsule())
                }

                Spacer()

                // Elapsed time
                if vm.isLive || vm.elapsedSeconds > 0 {
                    Text(vm.formattedElapsed)
                        .font(AMENFont.semiBold(13))
                        .foregroundColor(.white.opacity(0.85))
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 52)

            Spacer()
        }
    }

    // MARK: - Admin Controls Bar

    private var adminControlsBar: some View {
        VStack {
            HStack(spacing: 12) {
                // Viewer count
                HStack(spacing: 5) {
                    Image(systemName: "eye.fill")
                        .font(.systemScaled(12))
                    Text("\(vm.viewerCount)")
                        .font(AMENFont.semiBold(13))
                        .monospacedDigit()
                }
                .foregroundColor(.white.opacity(0.85))

                Spacer()

                // Add Chapter button
                Button {
                    showChapterInput = true
                } label: {
                    Label("Chapter", systemImage: "bookmark.badge.plus")
                        .font(AMENFont.semiBold(13))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }

                // End Live button
                Button {
                    showEndConfirm = true
                } label: {
                    Label("End Live", systemImage: "stop.circle.fill")
                        .font(AMENFont.semiBold(13))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.red.opacity(0.85))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Spacer()
        }
        .padding(.top, 104)
    }

    // MARK: - Prayer Queue Floating Button

    private var prayerQueueButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    showPrayerQueue = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "hands.sparkles.fill")
                            .font(.systemScaled(22))
                            .foregroundColor(.white)
                            .frame(width: 52, height: 52)
                            .background(.ultraThinMaterial)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)

                        if vm.unansweredPrayerCount > 0 {
                            Text("\(vm.unansweredPrayerCount)")
                                .font(AMENFont.bold(10))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.orange)
                                .clipShape(Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 460)
            }
        }
    }

    // MARK: - Bottom Panel

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                // Tab selector
                HStack(spacing: 0) {
                    ForEach(LiveTab.allCases, id: \.rawValue) { tab in
                        Button {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                                activeTab = tab
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: tab.icon)
                                    .font(.systemScaled(14, weight: .semibold))
                                Text(tab.rawValue)
                                    .font(AMENFont.semiBold(11))
                            }
                            .foregroundColor(activeTab == tab ? .white : .white.opacity(0.45))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                    }
                }
                .background(.ultraThinMaterial)

                Divider().background(Color.white.opacity(0.12))

                // Tab content
                Group {
                    switch activeTab {
                    case .chat:
                        chatPanel
                    case .prayers:
                        prayersPanel
                    case .markers:
                        markersPanel
                    }
                }
                .frame(height: 260)
            }
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: -4)
            .padding(.horizontal, 0)
        }
    }

    // MARK: - Chat Panel

    private var chatPanel: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(vm.chatMessages) { msg in
                            chatMessageRow(msg)
                                .id(msg.id)
                                .contextMenu {
                                    if isAdmin {
                                        Button(role: .destructive) {
                                            vm.flagMessage(id: msg.id, churchId: churchName)
                                        } label: {
                                            Label("Flag & Remove", systemImage: "flag.fill")
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: vm.chatMessages.count) { _ in
                    if let last = vm.chatMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            // Input bar
            chatInputBar
        }
    }

    @ViewBuilder
    private func chatMessageRow(_ msg: LiveChatMessage) -> some View {
        if msg.isPrayer {
            // Amber glass pill for prayer requests
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "hands.sparkles.fill")
                    .font(.systemScaled(13))
                    .foregroundColor(Color.orange)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(msg.authorName)
                        .font(AMENFont.semiBold(12))
                        .foregroundColor(Color.orange.opacity(0.9))
                    Text(msg.text)
                        .font(AMENFont.regular(13))
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.18))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.5)
            )
        } else {
            HStack(alignment: .top, spacing: 6) {
                Text(msg.authorName)
                    .font(AMENFont.semiBold(12))
                    .foregroundColor(.white.opacity(0.75))
                Text(msg.text)
                    .font(AMENFont.regular(13))
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 2)
        }
    }

    private var chatInputBar: some View {
        HStack(spacing: 10) {
            TextField("Say something...", text: $messageText)
                .font(.systemScaled(14))
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial)
                .background(Color.white.opacity(0.55))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                )

            Button {
                let trimmed = messageText.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                vm.sendMessage(trimmed, authorName: "You", isPrayer: false)
                messageText = ""
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.systemScaled(30))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Prayers Panel

    private var prayersPanel: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if vm.prayerQueue.isEmpty {
                    Text("No prayer requests yet.")
                        .font(AMENFont.regular(14))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.top, 32)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(vm.prayerQueue) { entry in
                        prayerQueueEntryCard(entry)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func prayerQueueEntryCard(_ entry: PrayerQueueEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hands.sparkles.fill")
                .font(.systemScaled(15))
                .foregroundColor(entry.isAddressed ? .white.opacity(0.3) : Color.orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.authorName)
                    .font(AMENFont.semiBold(13))
                    .foregroundColor(entry.isAddressed ? .white.opacity(0.4) : .white.opacity(0.85))
                Text(entry.request)
                    .font(AMENFont.regular(13))
                    .foregroundColor(entry.isAddressed ? .white.opacity(0.3) : .white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if isAdmin {
                Button {
                    vm.markPrayerAddressed(id: entry.id)
                } label: {
                    Image(systemName: entry.isAddressed ? "checkmark.circle.fill" : "circle")
                        .font(.systemScaled(20))
                        .foregroundColor(entry.isAddressed ? .white.opacity(0.4) : .white)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    // MARK: - Markers Panel

    private var markersPanel: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if vm.chapterMarkers.isEmpty {
                    Text("No chapter markers yet.")
                        .font(AMENFont.regular(14))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.top, 32)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(vm.chapterMarkers) { marker in
                        chapterMarkerRow(marker)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func chapterMarkerRow(_ marker: ChapterMarker) -> some View {
        HStack(spacing: 10) {
            Text(formattedTimestamp(marker.timestamp))
                .font(AMENFont.bold(12))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black)
                .clipShape(Capsule())

            Text(marker.title)
                .font(AMENFont.semiBold(14))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)

            Spacer()

            Image(systemName: "bookmark.fill")
                .font(.systemScaled(13))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - AI Recap Button

    private var aiRecapButton: some View {
        VStack {
            Spacer()
            Button {
                showAIRecapSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.systemScaled(15, weight: .semibold))
                    Text("Generate AI Recap")
                        .font(AMENFont.semiBold(15))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(Color.black)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
            }
            .padding(.bottom, 52)
        }
    }

    // MARK: - AI Recap Sheet

    private var aiRecapSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "sparkles")
                    .font(.systemScaled(44))
                    .foregroundColor(.black.opacity(0.4))
                    .padding(.top, 32)

                Text("AI Recap")
                    .font(AMENFont.bold(22))
                    .foregroundColor(.black)

                Text("AI recap will be generated shortly.")
                    .font(AMENFont.regular(16))
                    .foregroundColor(.black.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Session Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showAIRecapSheet = false }
                        .font(AMENFont.semiBold(15))
                        .foregroundColor(.black)
                }
            }
        }
    }

    // MARK: - Prayer Queue Full Sheet

    private var prayerQueueSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if vm.prayerQueue.isEmpty {
                        Text("No prayer requests yet.")
                            .font(AMENFont.regular(15))
                            .foregroundColor(.black.opacity(0.4))
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(vm.prayerQueue) { entry in
                            prayerQueueEntryCard(entry)
                                .colorScheme(.light)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Prayer Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showPrayerQueue = false }
                        .font(AMENFont.semiBold(15))
                        .foregroundColor(.black)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formattedTimestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Preview

struct ChurchLiveModeView_Previews: PreviewProvider {
    static var previews: some View {
        ChurchLiveModeViewPreviewContainer()
            .previewDisplayName("Live Mode — Admin (Sample Data)")
    }
}

// Wrapper that pre-populates sample data
private struct ChurchLiveModeViewPreviewContainer: View {
    @StateObject private var vm: ChurchLiveModeViewModel = {
        let m = ChurchLiveModeViewModel()
        m.isLive = true
        m.elapsedSeconds = 754
        m.viewerCount = 38
        m.chatMessages = [
            LiveChatMessage(id: "1", authorName: "Sarah M.", text: "Amen! So powerful 🙏", timestamp: Date(), isPrayer: false),
            LiveChatMessage(id: "2", authorName: "David K.", text: "This scripture is speaking to me right now", timestamp: Date(), isPrayer: false),
            LiveChatMessage(id: "3", authorName: "Grace T.", text: "Please pray for my mother's healing", timestamp: Date(), isPrayer: true),
            LiveChatMessage(id: "4", authorName: "Marcus J.", text: "Worship was amazing today!", timestamp: Date(), isPrayer: false),
            LiveChatMessage(id: "5", authorName: "Ruth B.", text: "Lift up my family going through a hard season", timestamp: Date(), isPrayer: true),
        ]
        m.prayerQueue = [
            PrayerQueueEntry(id: "p1", authorName: "Grace T.", request: "Please pray for my mother's healing", submittedAt: Date(), isAddressed: false),
            PrayerQueueEntry(id: "p2", authorName: "Ruth B.", request: "Lift up my family going through a hard season", submittedAt: Date(), isAddressed: false),
            PrayerQueueEntry(id: "p3", authorName: "John E.", request: "Praying for a new job opportunity", submittedAt: Date(), isAddressed: true),
        ]
        m.chapterMarkers = [
            ChapterMarker(id: "c1", title: "Opening Worship", timestamp: 0),
            ChapterMarker(id: "c2", title: "Scripture Reading — Psalm 23", timestamp: 312),
            ChapterMarker(id: "c3", title: "Main Message", timestamp: 620),
        ]
        return m
    }()

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            // Replicate the inner layout using a preview wrapper
            ChurchLiveModeView(churchName: "Grace Community Church", isAdmin: true)
        }
        .preferredColorScheme(.dark)
    }
}
