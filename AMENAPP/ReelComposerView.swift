//
//  ReelComposerView.swift
//  AMENAPP
//
//  Feature 3 — Reel Composer.
//  Full-screen sheet to design and export a shareable quote card / story
//  reel from church notes.
//
//  Layout:
//    1. Live canvas preview (9:16 aspect) of the selected reel style
//    2. Style selector — paged TabView of CNReelStyle cards
//    3. Font mood pills (Serif · Script · Clean)
//    4. Music mood pills (Worship · Acoustic · Orchestral)
//    5. Export / Share action row (coming soon)
//

import SwiftUI

// MARK: - ReelComposerView

struct ReelComposerView: View {
    @StateObject var viewModel: QuoteForgeViewModel
    /// The quote to feature — pass the detected quote from QuoteForgeViewModel.detectedQuote,
    /// or any hand-picked line from the note body.
    let quote: String

    @Environment(\.dismiss) private var dismiss

    // MARK: - Local state

    @State private var selectedFont: ReelFontMood = .serif
    @State private var selectedMusic: ReelMusicMood = .worship
    @State private var showComingSoon = false
    @State private var previewScale: CGFloat = 0.92
    @State private var glowOpacity: Double = 0.15

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "050508").ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {

                        // ── 1. Live canvas preview ─────────────────────────
                        canvasPreview
                            .scaleEffect(previewScale)
                            .onAppear {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                    previewScale = 1.0
                                }
                                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                                    glowOpacity = 0.45
                                }
                            }

                        // ── 2. Style selector ──────────────────────────────
                        styleSelector

                        // ── 3. Font mood ───────────────────────────────────
                        moodPillRow(
                            label: "FONT",
                            options: ReelFontMood.allCases.map(\.label),
                            selected: selectedFont.rawValue,
                            action: { idx in selectedFont = ReelFontMood(rawValue: idx) ?? .serif }
                        )

                        // ── 4. Music mood ──────────────────────────────────
                        moodPillRow(
                            label: "VIBE",
                            options: ReelMusicMood.allCases.map(\.label),
                            selected: selectedMusic.rawValue,
                            action: { idx in selectedMusic = ReelMusicMood(rawValue: idx) ?? .worship }
                        )

                        // ── 5. Action row ──────────────────────────────────
                        actionRow
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Reel Composer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showComingSoon = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.cnGold)
                    }
                }
            }
            .alert("Coming Soon", isPresented: $showComingSoon) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Reel export and sharing will be available in a future update.")
            }
        }
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(28)
    }

    // MARK: - Canvas Preview

    private var canvasPreview: some View {
        let style = viewModel.reelStyles[safe: viewModel.selectedStyleIndex]
            ?? viewModel.reelStyles[0]

        return ZStack(alignment: .topTrailing) {
            // Background gradient
            LinearGradient(
                colors: style.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: [])

            // Decorative glow
            Circle()
                .fill(style.gradientColors.first ?? .amenPurple)
                .opacity(glowOpacity * 0.35)
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: 60, y: -40)

            // Emoji accent
            Text(style.emoji)
                .font(.system(size: 44))
                .padding(18)
                .shadow(color: .black.opacity(0.25), radius: 8)

            // Quote text
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                Text(displayQuote)
                    .font(selectedFont.font(size: 18))
                    .italic(selectedFont == .serif)
                    .foregroundColor(.white)
                    .lineSpacing(5)
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .shadow(color: .black.opacity(0.4), radius: 6)
            }

            // AMEN watermark
            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AMEN")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white.opacity(0.45))
                        Text(selectedMusic.label)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                    Spacer()
                }
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: (style.gradientColors.first ?? .amenPurple).opacity(glowOpacity), radius: 28)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Style Selector

    private var styleSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("STYLE")

            TabView(selection: $viewModel.selectedStyleIndex) {
                ForEach(Array(viewModel.reelStyles.enumerated()), id: \.element.id) { idx, style in
                    styleCard(style: style, isSelected: viewModel.selectedStyleIndex == idx)
                        .tag(idx)
                        .padding(.horizontal, 4)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 110)
        }
    }

    private func styleCard(style: CNReelStyle, isSelected: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: style.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 6) {
                Text(style.emoji)
                    .font(.title3)
                Text(style.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? Color.cnGold : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: isSelected ? Color.cnGold.opacity(0.35) : .clear, radius: 10)
        .scaleEffect(isSelected ? 1.0 : 0.96)
        .animation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.72)), value: isSelected)
    }

    // MARK: - Mood Pill Row

    private func moodPillRow(label: String, options: [String], selected: Int, action: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(label)

            HStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                            action(idx)
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(option)
                            .font(.caption.weight(.semibold))
                            .tracking(0.5)
                            .foregroundColor(selected == idx ? .cnGold : .white.opacity(0.5))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selected == idx
                                          ? Color.cnGold.opacity(0.15)
                                          : Color.white.opacity(0.05))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(
                                                selected == idx
                                                    ? Color.cnGold.opacity(0.5)
                                                    : Color.white.opacity(0.08),
                                                lineWidth: 1
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                showComingSoon = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save to Photos")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)

            Button {
                showComingSoon = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundColor(.cnGold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.cnGold.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.cnGold.opacity(0.4), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(2)
            .foregroundColor(.white.opacity(0.35))
    }

    private var displayQuote: String {
        let q = quote.isEmpty ? viewModel.detectedQuote : quote
        return q.isEmpty
            ? "Your most powerful line will appear here."
            : String(q.prefix(180))
    }
}

// MARK: - Supporting Enums

enum ReelFontMood: Int, CaseIterable {
    case serif, script, clean

    var label: String {
        switch self {
        case .serif:  return "Serif"
        case .script: return "Script"
        case .clean:  return "Clean"
        }
    }

    func font(size: CGFloat) -> Font {
        switch self {
        case .serif:  return .custom("Georgia-BoldItalic", size: size)
        case .script: return .custom("SnellRoundhand-Bold", size: size + 2)
        case .clean:  return .system(size: size, weight: .semibold, design: .rounded)
        }
    }
}

enum ReelMusicMood: Int, CaseIterable {
    case worship, acoustic, orchestral

    var label: String {
        switch self {
        case .worship:     return "Worship"
        case .acoustic:    return "Acoustic"
        case .orchestral:  return "Orchestral"
        }
    }
}

// MARK: - Safe Collection Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
