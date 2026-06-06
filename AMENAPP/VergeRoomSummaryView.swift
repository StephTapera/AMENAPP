//
//  VergeRoomSummaryView.swift
//  AMENAPP
//
//  Post-room summary shown after a Verge room ends. Displays AI summary,
//  key moments, top questions, and earnings (if host).
//

import SwiftUI
import FirebaseAuth

struct VergeRoomSummaryView: View {

    let room: VergeRoom
    let messages: [VergeMessage]

    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet   = false
    @State private var shareText        = ""

    private let bg         = Color(.systemGroupedBackground)
    private let amenViolet = Color(hex: "C084FC")
    private let vergeGradient = LinearGradient(
        colors: [Color(hex: "06B6D4"), Color(hex: "6B48FF")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private var currentUID: String? { Auth.auth().currentUser?.uid }
    private var isHost: Bool { room.hostId == currentUID }

    private var durationLabel: String {
        guard let start = room.startedAt, let end = room.endedAt else { return "—" }
        let diff    = end.timeIntervalSince(start)
        let hours   = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes) min"
    }

    private var topQuestions: [VergeMessage] {
        messages.filter { $0.type == .question }.prefix(5).map { $0 }
    }

    private var keyMoments: [String] {
        // Derive up to 3 moments from messages — use pinned or first high-reacted messages
        let pinned    = messages.filter { $0.isPinned }.prefix(3).map { $0.content }
        let remainder = 3 - pinned.count
        let fallback  = messages
            .filter { !$0.isPinned && $0.type == .text }
            .prefix(remainder)
            .map { $0.content }
        return Array(pinned + fallback)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection
                    aiSummaryCard
                    keyMomentsSection
                    topQuestionsSection
                    if isHost { earningsSection }
                    actionButtons
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [shareText])
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.systemScaled(44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(amenViolet)

            Text(room.title)
                .font(AMENFont.bold(24))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Duration: \(durationLabel)  ·  \(room.participantCount) attended")
                .font(AMENFont.regular(14))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - AI Summary Card

    private var aiSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.systemScaled(15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(amenViolet)
                Text("AI Summary")
                    .font(AMENFont.bold(15))
                    .foregroundStyle(.white)
            }

            Text(room.aiSummary ?? "No AI summary available for this room.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(amenViolet.opacity(0.3), lineWidth: 0.8)
                )
        )
    }

    // MARK: - Key Moments

    @ViewBuilder
    private var keyMomentsSection: some View {
        if !keyMoments.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Key Moments")
                LazyVStack(spacing: 10) {
                    ForEach(Array(keyMoments.enumerated()), id: \.offset) { index, moment in
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(vergeGradient)
                                    .frame(width: 30, height: 30)
                                Text("\(index + 1)")
                                    .font(AMENFont.bold(13))
                                    .foregroundStyle(.white)
                            }
                            Text(moment)
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.white.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(3)
                            Spacer()
                        }
                        .padding(14)
                        .background(glassCard)
                    }
                }
            }
        }
    }

    // MARK: - Top Questions

    @ViewBuilder
    private var topQuestionsSection: some View {
        if !topQuestions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Top Questions")
                LazyVStack(spacing: 8) {
                    ForEach(topQuestions) { msg in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.systemScaled(16, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color(hex: "06B6D4"))
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(msg.content)
                                    .font(AMENFont.regular(14))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(msg.authorName)
                                    .font(AMENFont.regular(11))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(glassCard)
                    }
                }
            }
        }
    }

    // MARK: - Earnings (host only)

    private var earningsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Earnings Breakdown")

            VStack(spacing: 0) {
                earningsRow(label: "Ticket Revenue",   value: "$0.00", icon: "ticket.fill",       color: Color.accentColor)
                Divider().background(Color.white.opacity(0.06))
                earningsRow(label: "Tips Received",    value: "$0.00", icon: "gift.fill",         color: amenViolet)
                Divider().background(Color.white.opacity(0.06))
                earningsRow(label: "New Subscribers",  value: "0",     icon: "person.badge.plus",  color: Color(hex: "06B6D4"))
                Divider().background(Color.white.opacity(0.06))
                earningsRow(label: "Total Revenue",    value: "$0.00", icon: "dollarsign.circle.fill", color: Color.green, bold: true)
            }
            .background(glassCard)
        }
    }

    private func earningsRow(label: String, value: String, icon: String, color: Color, bold: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(16, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 22)
            Text(label)
                .font(bold ? AMENFont.bold(14) : AMENFont.regular(14))
                .foregroundStyle(bold ? .white : .white.opacity(0.75))
            Spacer()
            Text(value)
                .font(bold ? AMENFont.bold(16) : AMENFont.semiBold(14))
                .foregroundStyle(bold ? Color.accentColor : .white.opacity(0.65))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Share
            Button {
                shareText = buildShareText()
                showShareSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.systemScaled(15, weight: .semibold))
                    Text("Share Summary")
                        .font(AMENFont.bold(16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(vergeGradient)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 12, y: 4)
                )
            }
            .buttonStyle(CoCreationPressStyle())

            // Return
            Button {
                dismiss()
            } label: {
                Text("Return to Verge")
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(CoCreationPressStyle())
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AMENFont.bold(17))
            .foregroundStyle(.white)
    }

    private var glassCard: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
            )
    }

    private func buildShareText() -> String {
        var parts: [String] = []
        parts.append("Verge Room: \(room.title)")
        parts.append("Duration: \(durationLabel) · \(room.participantCount) attended")
        if let summary = room.aiSummary {
            parts.append("\nSummary:\n\(summary)")
        }
        if !topQuestions.isEmpty {
            parts.append("\nTop Questions:")
            topQuestions.forEach { parts.append("• \($0.content)") }
        }
        parts.append("\n— Shared from AMEN Verge")
        return parts.joined(separator: "\n")
    }
}
