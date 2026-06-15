// DiscoveryCardView.swift
// AMEN Connect Discovery Engine — Wave 3, Lane I
// Adaptive card renderer — switches on CardPayload to morph shape per type.
// Every card shows its WhyShown on long-press via DiscoveryPreviewSheet.

import SwiftUI

// MARK: - Main card view

struct DiscoveryCardView: View {
    let card: DiscoveryCard
    let onTap: (DiscoveryCard) -> Void
    let onPreview: (DiscoveryCard) -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button { onTap(card) } label: {
            cardContent
                .glassEffect(
                    reduceTransparency
                        ? .regular
                        : .regular
                            .tint(Color(hex: card.glassTint.hex).opacity(card.glassTint.intensity))
                            .interactive(),
                    in: .rect(cornerRadius: 20)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.97 : 1))
        .animation(
            reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.24, dampingFraction: 0.82),
            value: isPressed
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .onLongPressGesture(minimumDuration: 0.4) {
            onPreview(card)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to open. Long press to preview.")
    }

    // MARK: - Card content by type

    @ViewBuilder
    private var cardContent: some View {
        switch card.payload {
        case .bibleStudy(let data):
            DiscBibleStudyPayloadContent(card: card, data: data)
        case .prayerRoom(let data):
            DiscPrayerRoomPayloadContent(card: card, data: data)
        case .church(let data):
            DiscChurchPayloadContent(card: card, data: data)
        case .event(let data):
            DiscEventPayloadContent(card: card, data: data)
        case .discussion(let data):
            DiscDiscussionPayloadContent(card: card, data: data)
        case .space(let data):
            DiscSpacePayloadContent(card: card, data: data)
        case .audioRoom(let data):
            DiscAudioRoomPayloadContent(card: card, data: data)
        }
    }

    private var accessibilityLabel: String {
        var parts = [card.title]
        if let sub = card.subtitle { parts.append(sub) }
        parts.append(card.reason.detail)
        if !card.safety.isValid { parts.append("Safety status unavailable") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Card chrome (shared layout shell)

private struct DiscoveryCardChrome<Detail: View>: View {
    let card: DiscoveryCard
    let icon: String
    let accentHex: String
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(hex: accentHex).opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: accentHex))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if let sub = card.subtitle {
                        Text(sub)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
            }

            detail()

            // WhyShown reason pill
            reasonPill
        }
        .padding(14)
        .frame(width: 260)
    }

    private var reasonPill: some View {
        HStack(spacing: 4) {
            Image(systemName: card.reason.kind.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(card.reason.detail)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1), in: Capsule())
    }
}

// MARK: - Bible Study card

private struct DiscBibleStudyPayloadContent: View {
    let card: DiscoveryCard
    let data: DiscBibleStudyPayload

    var body: some View {
        DiscoveryCardChrome(card: card, icon: "book.closed.fill", accentHex: "7B5EA7") {
            VStack(alignment: .leading, spacing: 6) {
                Text(data.verseRef)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: "7B5EA7"))

                Text(data.passagePreview)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let progress = data.readingProgress {
                    ProgressView(value: progress)
                        .tint(Color(hex: "7B5EA7"))
                        .frame(height: 3)
                        .accessibilityLabel("Reading progress \(Int(progress * 100))%")
                }
            }
        }
    }
}

// MARK: - Prayer Room card

private struct DiscPrayerRoomPayloadContent: View {
    let card: DiscoveryCard
    let data: DiscPrayerRoomPayload

    var body: some View {
        DiscoveryCardChrome(card: card, icon: "hands.sparkles.fill", accentHex: "D9A441") {
            HStack(spacing: 16) {
                statView(value: "\(data.liveCount)", label: "praying")
                statView(value: "\(data.activeRequests)", label: "requests")
                liveBadge
            }
        }
    }

    private func statView(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold)).foregroundStyle(Color(hex: "D9A441"))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(.green).frame(width: 6, height: 6)
            Text("LIVE").font(.system(size: 9, weight: .bold)).foregroundStyle(.green)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.green.opacity(0.12), in: Capsule())
    }
}

// MARK: - Church card

private struct DiscChurchPayloadContent: View {
    let card: DiscoveryCard
    let data: DiscChurchPayload

    var body: some View {
        DiscoveryCardChrome(card: card, icon: "building.columns.fill", accentHex: "245B8F") {
            VStack(alignment: .leading, spacing: 4) {
                if let den = data.denomination {
                    Text(den)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(hex: "245B8F"))
                }
                if let first = data.serviceTimes.first {
                    Label(first, systemImage: "clock")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if let dist = data.distanceMeters {
                    let km = dist / 1000
                    Label(String(format: "%.1f km away", km), systemImage: "location")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Event card

private struct DiscEventPayloadContent: View {
    let card: DiscoveryCard
    let data: DiscEventPayload

    var body: some View {
        DiscoveryCardChrome(card: card, icon: "calendar.badge.plus", accentHex: "4A7C59") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.startsAt, style: .date)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "4A7C59"))
                    Text(data.startsAt, style: .time)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                rsvpBadge
            }
        }
    }

    private var rsvpBadge: some View {
        Text(data.rsvpState == .going ? "Going ✓" : "RSVP")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(data.rsvpState == .going ? Color(hex: "4A7C59") : .secondary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(
                data.rsvpState == .going
                    ? Color(hex: "4A7C59").opacity(0.15)
                    : Color.secondary.opacity(0.1),
                in: Capsule()
            )
    }
}

// MARK: - Discussion card

private struct DiscDiscussionPayloadContent: View {
    let card: DiscoveryCard
    let data: DiscDiscussionPayload

    var body: some View {
        DiscoveryCardChrome(card: card, icon: "bubble.left.and.bubble.right.fill", accentHex: "6B7280") {
            HStack(spacing: 12) {
                Label("\(data.replyCount) replies", systemImage: "text.bubble")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(data.lastActivityAt, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Space card

private struct DiscSpacePayloadContent: View {
    let card: DiscoveryCard
    let data: DiscSpacePayload

    var body: some View {
        DiscoveryCardChrome(card: card, icon: "rectangle.3.group.fill", accentHex: "7B5EA7") {
            HStack(spacing: 16) {
                statView(value: formattedCount(data.memberCount), label: "members")
                if data.growth7d > 0 {
                    statView(value: "+\(data.growth7d)", label: "this week")
                }
            }
        }
    }

    private func statView(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 16, weight: .bold)).foregroundStyle(Color(hex: "7B5EA7"))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func formattedCount(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fK", Double(n) / 1000) : "\(n)"
    }
}

// MARK: - Audio Room card

private struct DiscAudioRoomPayloadContent: View {
    let card: DiscoveryCard
    let data: DiscAudioRoomPayload

    @State private var wavePhase: CGFloat = 0

    var body: some View {
        DiscoveryCardChrome(card: card, icon: "waveform.circle.fill", accentHex: "D9A441") {
            HStack(spacing: 12) {
                waveform
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("\(data.liveCount)").font(.system(size: 14, weight: .bold)).foregroundStyle(.primary)
                    }
                    Text("listening").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                wavePhase = .pi * 2
            }
        }
    }

    private var waveform: some View {
        // Deterministic wave from waveformSeed
        HStack(spacing: 2) {
            ForEach(0..<6, id: \.self) { i in
                let angle = Double(i + data.waveformSeed % 7) * 0.6 + Double(wavePhase)
                let height = CGFloat(8.0 + 12.0 * abs(sin(angle)))
                Capsule()
                    .fill(Color(hex: "D9A441").opacity(0.7))
                    .frame(width: 3, height: height)
                    .animation(
                        .linear(duration: 1.8).repeatForever(autoreverses: false).delay(Double(i) * 0.1),
                        value: wavePhase
                    )
            }
        }
        .frame(height: 28)
    }
}

// MARK: - ReasonKind icon

extension ReasonKind {
    var icon: String {
        switch self {
        case .followedInterest:  return "tag"
        case .nearYou:           return "location"
        case .friendJoined:      return "person.2"
        case .trending:          return "chart.line.uptrend.xyaxis"
        case .freshForYou:       return "sparkles"
        case .continueReading:   return "bookmark"
        }
    }
}
