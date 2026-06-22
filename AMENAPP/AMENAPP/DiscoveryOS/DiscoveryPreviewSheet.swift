// DiscoveryPreviewSheet.swift
// AMEN Connect Discovery Engine — Wave 3, Lane N
// Long-press preview sheet — opens without navigation.
// Shows WhyShown, live details, active speakers, current topic.
// Adaptive background tints from card's AdaptiveBackground.

import SwiftUI

struct DiscoveryPreviewSheet: View {
    let card: DiscoveryCard

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            // Subtle adaptive background tint
            backgroundTint

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    handle

                    // Card identity
                    headerSection

                    Divider().opacity(0.3)

                    // Why you're seeing this
                    whyShownSection

                    Divider().opacity(0.3)

                    // Type-specific live details
                    detailSection

                    // Open button
                    openButton
                        .padding(.top, 8)
                }
                .padding(24)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .accessibilityLabel("Preview: \(card.title)")
    }

    // MARK: - Handle

    private var handle: some View {
        HStack {
            Spacer()
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(hex: card.type.accentHex).opacity(0.15))
                    .frame(width: 54, height: 54)
                Image(systemName: card.type.systemIcon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(hex: card.type.accentHex))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(2)
                if let sub = card.subtitle {
                    Text(sub)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            Spacer()
        }
    }

    // MARK: - Why shown

    private var whyShownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Why you're seeing this", systemImage: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: card.reason.kind.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: card.type.accentHex))
                Text(card.reason.detail)
                    .font(.system(size: 14))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
    }

    // MARK: - Type-specific detail

    @ViewBuilder
    private var detailSection: some View {
        switch card.payload {
        case .prayerRoom(let data):
            prayerRoomDetail(data)
        case .audioRoom(let data):
            audioRoomDetail(data)
        case .church(let data):
            churchDetail(data)
        case .event(let data):
            eventDetail(data)
        case .discussion(let data):
            discussionDetail(data)
        case .bibleStudy(let data):
            bibleStudyDetail(data)
        case .space(let data):
            spaceDetail(data)
        }
    }

    private func prayerRoomDetail(_ data: DiscPrayerRoomPayload) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Live Prayer Room", systemImage: "dot.radiowaves.left.and.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "D9A441"))

            HStack(spacing: 24) {
                statBlock(value: "\(data.liveCount)", label: "praying now", icon: "person.2.fill")
                statBlock(value: "\(data.activeRequests)", label: "active requests", icon: "text.bubble.fill")
            }
        }
    }

    private func audioRoomDetail(_ data: DiscAudioRoomPayload) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Live Audio Room", systemImage: "waveform")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "D9A441"))

            statBlock(value: "\(data.liveCount)", label: "listening now", icon: "ear.fill")

            if !data.speakerIds.isEmpty {
                Text("\(data.speakerIds.count) speaker\(data.speakerIds.count == 1 ? "" : "s") live")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func churchDetail(_ data: DiscChurchPayload) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let den = data.denomination {
                Label(den, systemImage: "building.columns")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "245B8F"))
            }
            if !data.serviceTimes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Service Times").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(data.serviceTimes.prefix(3), id: \.self) { t in
                        Label(t, systemImage: "clock").font(.system(size: 13)).foregroundStyle(.primary)
                    }
                }
            }
            if let dist = data.distanceMeters {
                Label(String(format: "%.1f km away", dist / 1000), systemImage: "location.fill")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }

    private func eventDetail(_ data: DiscEventPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(data.startsAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "4A7C59"))
            if !data.speakerIds.isEmpty {
                Text("\(data.speakerIds.count) speaker\(data.speakerIds.count == 1 ? "" : "s")")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }

    private func discussionDetail(_ data: DiscDiscussionPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            statBlock(value: "\(data.replyCount)", label: "replies", icon: "text.bubble.fill")
            if !data.topicTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(data.topicTags.prefix(5), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .glassEffect(.regular, in: .capsule)
                        }
                    }
                }
            }
        }
    }

    private func bibleStudyDetail(_ data: DiscBibleStudyPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(data.verseRef)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: "7B5EA7"))
            Text(data.passagePreview)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(4)
            if let progress = data.readingProgress {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your progress: \(Int(progress * 100))%")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    ProgressView(value: progress).tint(Color(hex: "7B5EA7"))
                }
            }
        }
    }

    private func spaceDetail(_ data: DiscSpacePayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 24) {
                statBlock(value: formattedCount(data.memberCount), label: "members", icon: "person.2.fill")
                if data.growth7d > 0 {
                    statBlock(value: "+\(data.growth7d)", label: "joined this week", icon: "chart.line.uptrend.xyaxis")
                }
            }
            if let topic = data.latestTopic {
                Label("Latest: " + topic, systemImage: "bubble.left")
                    .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    // MARK: - Open button

    private var openButton: some View {
        Button {
            dismiss()
            // Navigation to full detail happens via onTap in the parent list
        } label: {
            Text("Open \(card.type.rawValue.capitalized)")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassEffect(.regular.interactive())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(card.title)")
    }

    // MARK: - Background tint

    @ViewBuilder
    private var backgroundTint: some View {
        if !reduceTransparency {
            let (r, g, b) = adaptiveBackground.color
            Color(red: r * 0.15, green: g * 0.12, blue: b * 0.20)
                .opacity(0.4)
                .ignoresSafeArea()
        }
    }

    private var adaptiveBackground: AdaptiveBackground {
        switch card.type {
        case .prayerRoom:  return .prayerWarm
        case .bibleStudy:  return .parchment
        case .event:       return .eventBrand
        case .audioRoom:   return .worshipGradient
        default:           return .neutral
        }
    }

    // MARK: - Helpers

    private func statBlock(value: String, label: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: card.type.accentHex))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 16, weight: .bold))
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func formattedCount(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fK", Double(n) / 1000) : "\(n)"
    }
}
