//
//  CoCreationSummaryView.swift
//  AMENAPP
//
//  Full-screen session summary shown when a co-creation session ends.
//

import SwiftUI

// MARK: - CoCreationSummaryView

struct CoCreationSummaryView: View {

    let session: CoCreationSession
    @ObservedObject var vm: CoCreationViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var showShareSheet = false
    @State private var didPost        = false
    @State private var showSuccessToast = false

    private let amenPurple = Color(red: 0.42, green: 0.28, blue: 1.00)
    private let amenGold   = Color(red: 0.96, green: 0.62, blue: 0.04)
    private let amenDark   = Color(red: 0.06, green: 0.06, blue: 0.09)

    private let avatarColors: [Color] = [
        Color(red: 0.42, green: 0.28, blue: 1.00),
        Color(red: 0.94, green: 0.28, blue: 0.64),
        Color(red: 0.96, green: 0.62, blue: 0.04),
        Color(red: 0.20, green: 0.70, blue: 0.50),
        Color(red: 0.20, green: 0.55, blue: 0.95),
        Color(red: 0.90, green: 0.40, blue: 0.20),
    ]

    private var wordCount: Int {
        vm.canvasText
            .split { $0.isWhitespace }
            .count
    }

    private var highlight: String {
        let trimmed = vm.canvasText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 150 else { return trimmed }
        return String(trimmed.prefix(150)) + "…"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                amenDark.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 22) {

                        // ── Header ────────────────────────────────────
                        headerSection

                        // ── Stats Row ─────────────────────────────────
                        statsRow

                        // ── AI Highlight ──────────────────────────────
                        if !highlight.isEmpty {
                            aiHighlightCard
                        }

                        // ── Full Canvas Preview ───────────────────────
                        canvasPreviewCard

                        // ── Contributors ──────────────────────────────
                        if !session.collaboratorIds.isEmpty {
                            contributorsSection
                        }

                        // ── Actions ───────────────────────────────────
                        actionButtons

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }

                // Toast
                if showSuccessToast {
                    VStack {
                        Spacer()
                        ToastBanner(message: "Posted to your feed!")
                            .padding(.bottom, 32)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.system(size: 22))
                    }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [vm.canvasText])
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .semibold))
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(amenGold)

            Text("Session Complete")
                .font(AMENFont.bold(30))
                .foregroundStyle(.white)

            Text("\(session.title)")
                .font(AMENFont.regular(16))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(
                value: vm.elapsedFormatted,
                label: "Duration",
                icon: "clock.fill",
                color: amenPurple
            )
            statCard(
                value: "\(session.collaboratorIds.count)",
                label: "Co-authors",
                icon: "person.2.fill",
                color: Color(red: 0.20, green: 0.70, blue: 0.50)
            )
            statCard(
                value: "\(wordCount)",
                label: "Words",
                icon: "text.alignleft",
                color: amenGold
            )
        }
    }

    @ViewBuilder
    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
            Text(value)
                .font(AMENFont.bold(20))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(label)
                .font(AMENFont.regular(12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - AI Highlight

    private var aiHighlightCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(amenPurple)
                Text("Highlight from this session")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.white.opacity(0.65))
            }

            Text(highlight)
                .font(AMENFont.regular(15))
                .foregroundStyle(.white.opacity(0.88))
                .lineSpacing(5)
                .italic()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(amenPurple.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Canvas Preview

    private var canvasPreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.55))
                Text("Full Canvas")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.white.opacity(0.55))
            }

            ScrollView(showsIndicators: false) {
                Text(vm.canvasText.isEmpty ? "No content was written." : vm.canvasText)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(vm.canvasText.isEmpty ? 0.3 : 0.85))
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Contributors

    private var contributorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contributors")
                .font(AMENFont.bold(16))
                .foregroundStyle(.white)

            LazyVStack(spacing: 10) {
                ForEach(Array(session.collaboratorIds.enumerated()), id: \.offset) { idx, uid in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(avatarColors[idx % avatarColors.count])
                                .frame(width: 38, height: 38)
                            Text(String(uid.prefix(2)).uppercased())
                                .font(AMENFont.bold(13))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(uid)
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("Co-author")
                                .font(AMENFont.regular(12))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
                            )
                    )
                }
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Post to Feed
            Button {
                guard !didPost else { return }
                didPost = true
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    showSuccessToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { showSuccessToast = false }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: didPost ? "checkmark.circle.fill" : "square.and.arrow.up.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                    Text(didPost ? "Posted!" : "Post to Feed")
                        .font(AMENFont.bold(16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            didPost
                                ? LinearGradient(colors: [Color.green.opacity(0.8), Color.green.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [amenPurple, Color(red: 0.60, green: 0.28, blue: 0.90)], startPoint: .leading, endPoint: .trailing)
                        )
                        .shadow(
                            color: didPost ? Color.green.opacity(0.3) : amenPurple.opacity(0.4),
                            radius: 14, y: 5
                        )
                )
            }
            .disabled(didPost)
            .buttonStyle(CoCreationPressStyle())

            // Save as Draft
            Button {
                // Placeholder — wire up to DraftsService when ready
            } label: {
                Text("Save as Draft")
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            }
            .buttonStyle(CoCreationPressStyle())

            // Share Session
            Button {
                showShareSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                    Text("Share Session")
                        .font(AMENFont.semiBold(15))
                }
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .buttonStyle(CoCreationPressStyle())
        }
    }
}

// MARK: - Toast Banner

private struct ToastBanner: View {
    let message: String
    private let amenPurple = Color(red: 0.42, green: 0.28, blue: 1.00)

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
            Text(message)
                .font(AMENFont.semiBold(15))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        )
    }
}
