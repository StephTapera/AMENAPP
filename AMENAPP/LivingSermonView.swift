// LivingSermonView.swift
// AMENAPP
//
// Living Sermon Experience — immersive, context-aware sermon mode.
// Activates when a user is capturing a sermon live. Overlays note-taking
// with a living transcript, worship graph, and contextual community layer.
//
// Design: white background, .ultraThinMaterial glass, AMENFont typography.
// No Firebase imports. No .blur(radius:) — system materials only.

import SwiftUI
import Combine

// MARK: - Data Models

struct SermonNote: Identifiable {
    let id: String
    var text: String
    var timestampSeconds: Int
    var highlightType: HighlightType?
    var detectedVerse: String?
}

enum HighlightType: String, CaseIterable {
    case keyPoint   = "keyPoint"
    case scripture  = "scripture"
    case prayer     = "prayer"
    case revelation = "revelation"

    var icon: String {
        switch self {
        case .keyPoint:   return "star.fill"
        case .scripture:  return "book.fill"
        case .prayer:     return "hands.sparkles.fill"
        case .revelation: return "sparkles"
        }
    }

    var label: String {
        switch self {
        case .keyPoint:   return "Key Point"
        case .scripture:  return "Scripture"
        case .prayer:     return "Prayer"
        case .revelation: return "Revelation"
        }
    }

    var emoji: String {
        switch self {
        case .keyPoint:   return "⭐"
        case .scripture:  return "📖"
        case .prayer:     return "🙏"
        case .revelation: return "✨"
        }
    }

    var color: Color {
        switch self {
        case .keyPoint:   return Color(red: 1.0,  green: 0.85, blue: 0.2).opacity(0.18)
        case .scripture:  return Color(red: 0.4,  green: 0.6,  blue: 1.0).opacity(0.15)
        case .prayer:     return Color(red: 0.6,  green: 0.4,  blue: 1.0).opacity(0.15)
        case .revelation: return Color(red: 0.2,  green: 0.85, blue: 0.7).opacity(0.15)
        }
    }
}

struct LivingTranscriptSegment: Identifiable {
    let id: String
    var text: String
    var timestampSeconds: Int
    var isHighlighted: Bool
}

struct SermonThemeTag: Identifiable {
    let id: String
    let name: String
    var weight: Double // 0.0–1.0 controls chip size
}

enum LivingSermonTab: String, CaseIterable {
    case capture    = "Capture"
    case transcript = "Live Transcript"
    case graph      = "Worship Graph"
    case community  = "Community"

    var icon: String {
        switch self {
        case .capture:    return "pencil"
        case .transcript: return "waveform"
        case .graph:      return "chart.xyaxis.line"
        case .community:  return "person.2"
        }
    }
}

// MARK: - ViewModel

final class LivingSermonViewModel: ObservableObject {
    @Published var notes: [SermonNote] = []
    @Published var transcript: [LivingTranscriptSegment] = []
    @Published var themes: [SermonThemeTag] = []
    @Published var activeTab: LivingSermonTab = .capture
    @Published var elapsedSeconds: Int = 0
    @Published var isCapturing: Bool = true
    @Published var scriptureDensity: Double = 0.62
    @Published var engagementPoints: [Double] = []

    private var timer: Timer?

    init() {
        loadSampleData()
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isCapturing else { return }
            self.elapsedSeconds += 1
        }
    }

    func addNote(_ text: String) {
        let note = SermonNote(
            id: UUID().uuidString,
            text: text,
            timestampSeconds: elapsedSeconds,
            highlightType: nil,
            detectedVerse: detectVerse(in: text)
        )
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            notes.append(note)
        }
    }

    func addHighlight(_ type: HighlightType, to noteId: String) {
        guard let idx = notes.firstIndex(where: { $0.id == noteId }) else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
            notes[idx].highlightType = type
        }
    }

    func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func detectVerse(in text: String) -> String? {
        let pattern = #"(\d?\s?[A-Za-z]+)\s(\d+):(\d+)"#
        let range = text.range(of: pattern, options: .regularExpression)
        return range.map { String(text[$0]) }
    }

    private func loadSampleData() {
        // Sample elapsed time — 18 minutes into service
        elapsedSeconds = 1082

        notes = [
            SermonNote(id: "n1", text: "Faith without works is dead — James 2:17",
                       timestampSeconds: 240, highlightType: .scripture,
                       detectedVerse: "James 2:17"),
            SermonNote(id: "n2", text: "God's grace is sufficient for every season",
                       timestampSeconds: 510, highlightType: .keyPoint,
                       detectedVerse: nil),
            SermonNote(id: "n3", text: "Redemption is not earned, it is freely given",
                       timestampSeconds: 720, highlightType: .revelation,
                       detectedVerse: nil),
            SermonNote(id: "n4", text: "Lord, let this word take root in my heart 🙏",
                       timestampSeconds: 900, highlightType: .prayer,
                       detectedVerse: nil),
            SermonNote(id: "n5", text: "Romans 8:28 — all things work together for good",
                       timestampSeconds: 1040, highlightType: .scripture,
                       detectedVerse: "Romans 8:28"),
        ]

        transcript = [
            LivingTranscriptSegment(id: "t1", text: "This morning we're opening in the book of James, chapter two.",
                              timestampSeconds: 60, isHighlighted: false),
            LivingTranscriptSegment(id: "t2", text: "Faith is not passive. Faith moves. Faith acts. Faith produces fruit.",
                              timestampSeconds: 180, isHighlighted: true),
            LivingTranscriptSegment(id: "t3", text: "James writes: 'faith without works is dead.' That's not a suggestion — that's a declaration.",
                              timestampSeconds: 310, isHighlighted: false),
            LivingTranscriptSegment(id: "t4", text: "But here's the good news: grace empowers the works. You are not doing it alone.",
                              timestampSeconds: 530, isHighlighted: false),
            LivingTranscriptSegment(id: "t5", text: "In Romans 8 Paul reminds us — all things. Not some things. ALL things work for the good.",
                              timestampSeconds: 1020, isHighlighted: false),
        ]

        themes = [
            SermonThemeTag(id: "th1", name: "Faith",       weight: 1.0),
            SermonThemeTag(id: "th2", name: "Grace",       weight: 0.88),
            SermonThemeTag(id: "th3", name: "Redemption",  weight: 0.75),
            SermonThemeTag(id: "th4", name: "Works",       weight: 0.62),
            SermonThemeTag(id: "th5", name: "James",       weight: 0.55),
            SermonThemeTag(id: "th6", name: "Romans",      weight: 0.50),
            SermonThemeTag(id: "th7", name: "Hope",        weight: 0.44),
            SermonThemeTag(id: "th8", name: "Obedience",   weight: 0.38),
        ]

        engagementPoints = [0.3, 0.45, 0.5, 0.65, 0.72, 0.6, 0.78, 0.85, 0.9, 0.82, 0.88, 0.95]
    }
}

// MARK: - LivingSermonView (Main Container)

struct LivingSermonView: View {
    @StateObject private var vm = LivingSermonViewModel()
    @State private var inputText: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.white.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top status bar
                    SermonStatusBar(vm: vm)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 8)

                    // Custom tab selector
                    SermonTabSelector(activeTab: $vm.activeTab)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                    // Tab content
                    ZStack {
                        switch vm.activeTab {
                        case .capture:
                            SermonCaptureTab(vm: vm, inputText: $inputText)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        case .transcript:
                            SermonTranscriptTab(vm: vm)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        case .graph:
                            SermonGraphTab(vm: vm)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        case .community:
                            SermonCommunityTab(vm: vm)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.82), value: vm.activeTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Spacer for bottom bar
                    Color.clear.frame(height: 86)
                }

                // Fixed bottom capture bar
                SermonLiveCaptureBar(vm: vm, inputText: $inputText)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            .navigationTitle("Live Sermon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Circle().fill(Color.white.opacity(0.55)))
                                    .overlay(Circle().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                            )
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation { vm.isCapturing.toggle() }
                    } label: {
                        Text(vm.isCapturing ? "Pause" : "Resume")
                            .font(AMENFont.semiBold(13))
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Capsule().fill(Color.white.opacity(0.55)))
                                    .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                            )
                    }
                }
            }
        }
    }
}

// MARK: - Status Bar

private struct SermonStatusBar: View {
    @ObservedObject var vm: LivingSermonViewModel
    @State private var recPulse = false

    var body: some View {
        HStack(spacing: 10) {
            // Church + speaker pill
            HStack(spacing: 6) {
                Image(systemName: "building.columns.fill")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundColor(Color(white: 0.45))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Grace Community Church")
                        .font(AMENFont.semiBold(12))
                        .foregroundColor(.black)
                        .lineLimit(1)
                    Text("Pastor David Williams")
                        .font(AMENFont.regular(10))
                        .foregroundColor(Color(white: 0.45))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.55)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
            )

            Spacer()

            // Elapsed time
            Text(vm.formatTime(vm.elapsedSeconds))
                .font(AMENFont.semiBold(13))
                .foregroundColor(.black)
                .monospacedDigit()

            // REC indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                    .opacity(recPulse ? 0.3 : 1.0)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: recPulse)
                Text("REC")
                    .font(AMENFont.bold(11))
                    .foregroundColor(Color.red)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.white.opacity(0.55)))
                    .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
            )
            .onAppear { recPulse = true }
        }
    }
}

// MARK: - Tab Selector

private struct SermonTabSelector: View {
    @Binding var activeTab: LivingSermonTab

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LivingSermonTab.allCases, id: \.self) { tab in
                    SermonTabPill(tab: tab, isActive: activeTab == tab) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            activeTab = tab
                        }
                    }
                }
            }
        }
    }
}

private struct SermonTabPill: View {
    let tab: LivingSermonTab
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.systemScaled(11, weight: .medium))
                Text(tab.rawValue)
                    .font(AMENFont.semiBold(12))
            }
            .foregroundColor(isActive ? .white : .black)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isActive ? Color.black : Color.clear)
                    .overlay(
                        Capsule()
                            .fill(isActive ? Color.clear : Color.white.opacity(0.55))
                            .background(isActive ? AnyView(EmptyView()) : AnyView(Capsule().fill(.ultraThinMaterial)))
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            isActive ? Color.clear : Color(white: 0.88).opacity(0.5),
                            lineWidth: 0.5
                        )
                    )
                    .shadow(color: .black.opacity(isActive ? 0.12 : 0.06), radius: isActive ? 8 : 6, x: 0, y: 2)
            )
        }
        .buttonStyle(GlassPressStyle())
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isActive)
    }
}

// MARK: - SermonLiveCaptureBar

struct SermonLiveCaptureBar: View {
    @ObservedObject var vm: LivingSermonViewModel
    @Binding var inputText: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Waveform strip
            SermonWaveformStrip(isActive: vm.isCapturing)
                .frame(width: 32)

            // Text field
            TextField("Type your notes...", text: $inputText, axis: .vertical)
                .font(AMENFont.regular(14))
                .foregroundColor(.black)
                .lineLimit(1...4)
                .focused($isFocused)

            Spacer(minLength: 0)

            // Timestamp button
            Button {
                inputText += " [\(vm.formatTime(vm.elapsedSeconds))]"
            } label: {
                Text("📍")
                    .font(.systemScaled(16))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().fill(Color.white.opacity(0.55)))
                            .overlay(Circle().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                    )
            }
            .buttonStyle(GlassPressStyle())

            // Send button
            Button {
                let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                vm.addNote(text)
                inputText = ""
                isFocused = false
            } label: {
                Image(systemName: "arrow.up")
                    .font(.systemScaled(14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  ? Color.black.opacity(0.25)
                                  : Color.black)
                            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
                    )
            }
            .buttonStyle(GlassPressStyle())
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 6)
        )
    }
}

// MARK: - Waveform Strip

private struct SermonWaveformStrip: View {
    let isActive: Bool
    @State private var heights: [CGFloat] = [0.4, 0.7, 0.5, 0.9, 0.6, 0.8, 0.45, 0.65]
    private let barCount = 8

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: 2.5, height: isActive ? heights[i] * 22 : 6)
                    .animation(
                        isActive
                            ? .easeInOut(duration: 0.45 + Double(i) * 0.07)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.06)
                            : .default,
                        value: heights[i]
                    )
            }
        }
        .onAppear { animateWaveform() }
        .onChange(of: isActive) { active in
            if active { animateWaveform() }
        }
    }

    private func animateWaveform() {
        guard isActive else { return }
        for i in 0..<barCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                withAnimation(.easeInOut(duration: 0.45 + Double(i) * 0.07)
                    .repeatForever(autoreverses: true)) {
                    heights[i] = CGFloat.random(in: 0.2...1.0)
                }
            }
        }
    }
}

// MARK: - Capture Tab

private struct SermonCaptureTab: View {
    @ObservedObject var vm: LivingSermonViewModel
    @Binding var inputText: String
    @State private var lastNoteId: String? = nil
    @State private var showScriptureBadge: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Scripture detection badge
            if showScriptureBadge {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.systemScaled(11))
                    Text("Auto-detecting scripture...")
                        .font(AMENFont.regular(12))
                }
                .foregroundColor(Color(white: 0.45))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(Color.white.opacity(0.55)))
                        .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
                )
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Notes list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.notes) { note in
                            NoteCardRow(note: note, vm: vm)
                                .id(note.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .onChange(of: vm.notes.count) { _ in
                    if let last = vm.notes.last {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Highlight bar
            AddHighlightBar(vm: vm)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
        .onChange(of: inputText) { text in
            let hasVersePattern = text.range(of: #"(\d?\s?[A-Za-z]+)\s(\d+):(\d+)"#, options: .regularExpression) != nil
            withAnimation(.easeInOut(duration: 0.25)) {
                showScriptureBadge = hasVersePattern && !text.isEmpty
            }
        }
    }
}

// MARK: - Note Card Row

private struct NoteCardRow: View {
    let note: SermonNote
    @ObservedObject var vm: LivingSermonViewModel
    @State private var showHighlightPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                // Timestamp pill
                Text(vm.formatTime(note.timestampSeconds))
                    .font(AMENFont.semiBold(10))
                    .foregroundColor(Color(white: 0.45))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().fill(Color.white.opacity(0.55)))
                            .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                    )

                Spacer()

                // Highlight icon if present
                if let ht = note.highlightType {
                    Image(systemName: ht.icon)
                        .font(.systemScaled(12))
                        .foregroundColor(Color(white: 0.45))
                }

                // Long-press to add highlight
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        showHighlightPicker.toggle()
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.systemScaled(14))
                        .foregroundColor(Color(white: 0.65))
                }
                .buttonStyle(GlassPressStyle())
            }

            Text(note.text)
                .font(AMENFont.regular(14))
                .foregroundColor(.black)
                .fixedSize(horizontal: false, vertical: true)

            // Detected verse badge
            if let verse = note.detectedVerse {
                HStack(spacing: 4) {
                    Image(systemName: "book.closed.fill")
                        .font(.systemScaled(10))
                    Text(verse)
                        .font(AMENFont.semiBold(11))
                }
                .foregroundColor(Color(red: 0.4, green: 0.5, blue: 0.9))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(red: 0.4, green: 0.5, blue: 0.9).opacity(0.10))
                        .overlay(Capsule().strokeBorder(Color(red: 0.4, green: 0.5, blue: 0.9).opacity(0.2), lineWidth: 0.5))
                )
            }

            // Highlight type picker inline
            if showHighlightPicker {
                HStack(spacing: 8) {
                    ForEach(HighlightType.allCases, id: \.self) { type in
                        HighlightPickerChip(type: type) {
                            vm.addHighlight(type, to: note.id)
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                showHighlightPicker = false
                            }
                        }
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(
                    note.highlightType != nil ? note.highlightType!.color : Color.white.opacity(0.55)
                ))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 3)
        )
    }
}

// MARK: - Highlight Picker Chip

private struct HighlightPickerChip: View {
    let type: HighlightType
    let action: () -> Void
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                scale = 1.08
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                    scale = 1.0
                }
                action()
            }
        } label: {
            HStack(spacing: 4) {
                Text(type.emoji)
                    .font(.systemScaled(12))
                Text(type.label)
                    .font(AMENFont.semiBold(11))
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(type.color))
                    .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            )
        }
        .scaleEffect(scale)
        .buttonStyle(.plain)
    }
}

// MARK: - Add Highlight Bar

private struct AddHighlightBar: View {
    @ObservedObject var vm: LivingSermonViewModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(HighlightType.allCases, id: \.self) { type in
                HighlightCircleButton(type: type) {
                    if let last = vm.notes.last {
                        vm.addHighlight(type, to: last.id)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 3)
        )
    }
}

private struct HighlightCircleButton: View {
    let type: HighlightType
    let action: () -> Void
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { scale = 1.08 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { scale = 1.0 }
                action()
            }
        } label: {
            VStack(spacing: 4) {
                Text(type.emoji)
                    .font(.systemScaled(18))
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().fill(type.color))
                            .overlay(Circle().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                    )
                Text(type.label)
                    .font(AMENFont.regular(10))
                    .foregroundColor(Color(white: 0.45))
                    .lineLimit(1)
            }
        }
        .scaleEffect(scale)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Transcript Tab

private struct SermonTranscriptTab: View {
    @ObservedObject var vm: LivingSermonViewModel
    @State private var selectedSegmentId: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            HStack(spacing: 8) {
                Text("Live Transcript")
                    .font(AMENFont.bold(16))
                    .foregroundColor(.black)

                Spacer()

                // AI badge
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.systemScaled(10))
                    Text("AI-Assisted")
                        .font(AMENFont.semiBold(11))
                }
                .foregroundColor(Color(white: 0.45))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(Color.white.opacity(0.55)))
                        .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            // Transcript list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.transcript) { segment in
                            LivingTranscriptSegmentRow(
                                segment: segment,
                                vm: vm,
                                isSelected: selectedSegmentId == segment.id
                            ) {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                    selectedSegmentId = selectedSegmentId == segment.id ? nil : segment.id
                                }
                            }
                            .id(segment.id)
                        }

                        // Listening indicator
                        if vm.isCapturing {
                            ListeningDotsRow()
                                .id("listening")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .onChange(of: vm.transcript.count) { _ in
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("listening", anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Transcript Segment Row

private struct LivingTranscriptSegmentRow: View {
    let segment: LivingTranscriptSegment
    @ObservedObject var vm: LivingSermonViewModel
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(vm.formatTime(segment.timestampSeconds))
                        .font(AMENFont.semiBold(10))
                        .foregroundColor(Color(white: 0.65))
                        .monospacedDigit()

                    Text(segment.text)
                        .font(AMENFont.regular(14))
                        .foregroundColor(.black)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(
                            segment.isHighlighted
                            ? Color(red: 0.4, green: 0.5, blue: 0.9).opacity(0.08)
                            : (isSelected ? Color.black.opacity(0.04) : Color.white.opacity(0.55))
                        ))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(
                            isSelected ? Color.black.opacity(0.15) : Color(white: 0.88).opacity(0.5),
                            lineWidth: isSelected ? 1.0 : 0.5
                        ))
                        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 3)
                )
            }
            .buttonStyle(.plain)

            // "Add to Notes" action row
            if isSelected {
                HStack {
                    Spacer()
                    Button {
                        vm.addNote(segment.text)
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                            // deselect handled by parent
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus.circle.fill")
                                .font(.systemScaled(12))
                            Text("Add to Notes")
                                .font(AMENFont.semiBold(12))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.black)
                                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
                        )
                    }
                    .buttonStyle(GlassPressStyle())
                    .padding(.top, 6)
                    .padding(.trailing, 2)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Listening Dots Row

private struct ListeningDotsRow: View {
    @State private var d1: Bool = false
    @State private var d2: Bool = false
    @State private var d3: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.systemScaled(11))
                .foregroundColor(Color(white: 0.65))
            Text("Listening")
                .font(AMENFont.regular(12))
                .foregroundColor(Color(white: 0.65))
            HStack(spacing: 3) {
                dot(active: d1)
                dot(active: d2)
                dot(active: d3)
            }
        }
        .onAppear { startDots() }
    }

    @ViewBuilder
    private func dot(active: Bool) -> some View {
        Circle()
            .fill(Color(white: active ? 0.3 : 0.75))
            .frame(width: 4, height: 4)
            .animation(.easeInOut(duration: 0.4), value: active)
    }

    private func startDots() {
        let interval = 0.5
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            DispatchQueue.main.async {
                withAnimation { d1.toggle() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation { d2.toggle() }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                    withAnimation { d3.toggle() }
                }
            }
        }
    }
}

// MARK: - Worship Graph Tab

private struct SermonGraphTab: View {
    @ObservedObject var vm: LivingSermonViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Sermon Arc card
                SermonArcCard(engagementPoints: vm.engagementPoints)
                    .padding(.horizontal, 16)

                // Theme cloud
                SermonThemeCloud(themes: vm.themes)
                    .padding(.horizontal, 16)

                // Scripture density
                ScriptureDensityBar(density: vm.scriptureDensity)
                    .padding(.horizontal, 16)

                // Key moments
                KeyMomentsCard(
                    notes: vm.notes.filter { $0.highlightType == .keyPoint || $0.highlightType == .revelation },
                    vm: vm
                )
                .padding(.horizontal, 16)

                Color.clear.frame(height: 20)
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Sermon Arc Card

private struct SermonArcCard: View {
    let engagementPoints: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sermon Arc")
                    .font(AMENFont.bold(15))
                    .foregroundColor(.black)
                Spacer()
                Text("Engagement Over Time")
                    .font(AMENFont.regular(11))
                    .foregroundColor(Color(white: 0.65))
            }

            // Line chart via Canvas
            Canvas { context, size in
                guard engagementPoints.count >= 2 else { return }
                let stepX = size.width / CGFloat(engagementPoints.count - 1)
                var path = Path()
                for (i, val) in engagementPoints.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = size.height - (size.height * val * 0.85) - 8
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(.black.opacity(0.7)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // Fill below line
                var fillPath = path
                fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                fillPath.addLine(to: CGPoint(x: 0, y: size.height))
                fillPath.closeSubpath()
                context.fill(fillPath, with: .color(.black.opacity(0.05)))

                // Dots at each point
                for (i, val) in engagementPoints.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = size.height - (size.height * val * 0.85) - 8
                    let dotRect = CGRect(x: x - 3, y: y - 3, width: 6, height: 6)
                    context.fill(Path(ellipseIn: dotRect), with: .color(.black.opacity(0.6)))
                }
            }
            .frame(height: 90)
            .padding(.vertical, 4)

            // Labels
            HStack {
                Text("Start")
                    .font(AMENFont.regular(10))
                    .foregroundColor(Color(white: 0.65))
                Spacer()
                Text("Now")
                    .font(AMENFont.regular(10))
                    .foregroundColor(Color(white: 0.65))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 5)
        )
    }
}

// MARK: - Theme Cloud

private struct SermonThemeCloud: View {
    let themes: [SermonThemeTag]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Detected Themes")
                .font(AMENFont.bold(15))
                .foregroundColor(.black)

            SermonFlowLayout(spacing: 8) {
                ForEach(themes) { tag in
                    SermonThemeChip(tag: tag)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 5)
        )
    }
}

private struct SermonThemeChip: View {
    let tag: SermonThemeTag

    var body: some View {
        Text(tag.name)
            .font(AMENFont.semiBold(CGFloat(11 + tag.weight * 4)))
            .foregroundColor(Color(white: 0.1 + (1 - tag.weight) * 0.35))
            .padding(.horizontal, CGFloat(10 + tag.weight * 4))
            .padding(.vertical, CGFloat(5 + tag.weight * 2))
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.white.opacity(0.55)))
                    .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            )
    }
}

// MARK: - Flow Layout

private struct SermonFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                y += rowH + spacing; x = 0; rowH = 0
            }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowH: CGFloat = 0
        var rowViews: [(Subviews.Element, CGSize, CGFloat)] = []

        func placeRow() {
            for (sv, size, xPos) in rowViews {
                sv.place(at: CGPoint(x: xPos, y: y), proposal: .unspecified)
                _ = size
            }
            rowViews.removeAll()
        }

        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && !rowViews.isEmpty {
                placeRow()
                y += rowH + spacing; x = bounds.minX; rowH = 0
            }
            rowViews.append((sv, size, x))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        placeRow()
    }
}

// MARK: - Scripture Density Bar

private struct ScriptureDensityBar: View {
    let density: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Scripture Density")
                    .font(AMENFont.bold(15))
                    .foregroundColor(.black)
                Spacer()
                Text("\(Int(density * 100))%")
                    .font(AMENFont.semiBold(14))
                    .foregroundColor(.black)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.55)))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.75))
                        .frame(width: geo.size.width * density, height: 8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: density)
                }
            }
            .frame(height: 8)

            Text("High scripture usage compared to average sermon")
                .font(AMENFont.regular(11))
                .foregroundColor(Color(white: 0.65))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 5)
        )
    }
}

// MARK: - Key Moments Card

private struct KeyMomentsCard: View {
    let notes: [SermonNote]
    @ObservedObject var vm: LivingSermonViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Key Moments")
                    .font(AMENFont.bold(15))
                    .foregroundColor(.black)
                Spacer()
                Text("\(notes.count) starred")
                    .font(AMENFont.regular(12))
                    .foregroundColor(Color(white: 0.65))
            }

            if notes.isEmpty {
                Text("Star notes in the Capture tab to track key moments.")
                    .font(AMENFont.regular(13))
                    .foregroundColor(Color(white: 0.65))
                    .padding(.vertical, 8)
            } else {
                ForEach(notes) { note in
                    HStack(alignment: .top, spacing: 10) {
                        Text(vm.formatTime(note.timestampSeconds))
                            .font(AMENFont.semiBold(11))
                            .foregroundColor(Color(white: 0.65))
                            .monospacedDigit()
                            .frame(width: 42, alignment: .leading)

                        Text(note.text)
                            .font(AMENFont.regular(13))
                            .foregroundColor(.black)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 4)

                        if let ht = note.highlightType {
                            Image(systemName: ht.icon)
                                .font(.systemScaled(11))
                                .foregroundColor(Color(white: 0.5))
                        }
                    }
                    .padding(.vertical, 4)

                    if note.id != notes.last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 5)
        )
    }
}

// MARK: - Community Tab

private struct SermonCommunityTab: View {
    @ObservedObject var vm: LivingSermonViewModel
    @State private var thoughtText: String = ""

    private let communityMembers: [(name: String, initials: String, note: String)] = [
        ("Marcus T.",   "MT", "Taking notes on James 2"),
        ("Kezia A.",    "KA", "Highlighted the grace message ✨"),
        ("Jemima R.",   "JR", "Praying through Romans 8 🙏"),
        ("David O.",    "DO", "Scripture density is high today 📖"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Live reactions strip
                LiveReactionsStrip()
                    .padding(.horizontal, 16)

                // Others in service
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Others in This Service")
                            .font(AMENFont.bold(15))
                            .foregroundColor(.black)
                        Spacer()
                        Text("\(communityMembers.count + 7)")
                            .font(AMENFont.semiBold(12))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black))
                    }

                    ForEach(communityMembers, id: \.name) { member in
                        CommunityMemberRow(
                            initials: member.initials,
                            name: member.name,
                            note: member.note
                        )
                    }
                }
                .padding(14)
                .background(glassCard)

                // Share a thought
                VStack(alignment: .leading, spacing: 10) {
                    Text("Share a Thought")
                        .font(AMENFont.bold(15))
                        .foregroundColor(.black)

                    HStack(spacing: 10) {
                        TextField("Post to service...", text: $thoughtText)
                            .font(AMENFont.regular(14))
                            .foregroundColor(.black)

                        Button {
                            thoughtText = ""
                        } label: {
                            Text("Post")
                                .font(AMENFont.semiBold(13))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.black))
                        }
                        .buttonStyle(GlassPressStyle())
                        .disabled(thoughtText.isEmpty)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.55)))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                    )
                }
                .padding(14)
                .background(glassCard)

                // Smart Invite
                SmartInviteCard()
                    .padding(.horizontal, 16)

                Color.clear.frame(height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private var glassCard: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 5)
    }
}

// MARK: - Live Reactions Strip

private struct LiveReactionsStrip: View {
    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            reactionPill(emoji: "🙏", count: 12)
            reactionPill(emoji: "✨", count: 8)
            reactionPill(emoji: "💛", count: 5)
            Spacer()
        }
    }

    @ViewBuilder
    private func reactionPill(emoji: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Text(emoji)
                .font(.systemScaled(15))
            Text("\(count)")
                .font(AMENFont.semiBold(13))
                .foregroundColor(.black)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.55)))
                .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 3)
        )
    }
}

// MARK: - Community Member Row

private struct CommunityMemberRow: View {
    let initials: String
    let name: String
    let note: String

    var body: some View {
        HStack(spacing: 10) {
            // Avatar
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.55)))
                    .overlay(Circle().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                    .frame(width: 38, height: 38)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                Text(initials)
                    .font(AMENFont.bold(13))
                    .foregroundColor(.black)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(AMENFont.semiBold(13))
                    .foregroundColor(.black)
                Text(note)
                    .font(AMENFont.regular(12))
                    .foregroundColor(Color(white: 0.45))
                    .lineLimit(1)
            }

            Spacer()

            // Active indicator
            Circle()
                .fill(Color.green.opacity(0.7))
                .frame(width: 7, height: 7)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Smart Invite Card

private struct SmartInviteCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.plus")
                    .font(.systemScaled(13))
                    .foregroundColor(Color(white: 0.45))
                Text("Invite to This Sermon")
                    .font(AMENFont.bold(15))
                    .foregroundColor(.black)
            }

            Text("Share this live sermon with someone who needs to hear it today.")
                .font(AMENFont.regular(13))
                .foregroundColor(Color(white: 0.45))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                // Copy link button
                Button {
                    UIPasteboard.general.string = "https://amenapp.com/live/grace-community"
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.systemScaled(12))
                        Text("Copy Link")
                            .font(AMENFont.semiBold(13))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.55)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                    )
                }
                .buttonStyle(GlassPressStyle())

                // Share button
                ShareLink(item: URL(string: "https://amenapp.com/live/grace-community")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.systemScaled(12))
                        Text("Share")
                            .font(AMENFont.semiBold(13))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black)
                            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
                    )
                }
                .buttonStyle(GlassPressStyle())
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 5)
        )
    }
}

// MARK: - Preview

struct LivingSermonView_Previews: PreviewProvider {
    static var previews: some View {
        LivingSermonView()
    }
}
