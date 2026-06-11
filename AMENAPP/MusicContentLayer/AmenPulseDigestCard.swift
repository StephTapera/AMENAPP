// AmenPulseDigestCard.swift
// AMENAPP/MusicContentLayer/
// Pulse digest UI components: item card, section view, main digest card, personalization sheet.

import SwiftUI

// MARK: - Helpers

private func glassBackground(reduceTransparency: Bool) -> some View {
    Group {
        if reduceTransparency {
            Color(.systemBackground)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.10))
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
            }
        }
    }
}

// MARK: - Rights Policy Pill

private struct RightsPolicyPill: View {
    let policy: String

    private var label: String {
        switch policy {
        case "paid":        return "Paid"
        case "membersOnly": return "Members"
        default:            return "Free"
        }
    }

    private var pillColor: Color {
        switch policy {
        case "paid":        return Color(red: 0.80, green: 0.60, blue: 0.20)
        case "membersOnly": return Color(red: 0.55, green: 0.38, blue: 0.80)
        default:            return Color(red: 0.25, green: 0.72, blue: 0.45)
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(pillColor.opacity(0.85), in: Capsule())
    }
}

// MARK: - Artwork Fallback

private struct ArtworkFallback: View {
    let type: AmenPulseDigestItemType

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(type.tintColor.opacity(0.18))
            Image(systemName: type.sfSymbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(type.tintColor)
        }
        .frame(width: 52, height: 52)
    }
}

// MARK: - AmenPulseDigestItemCard

struct AmenPulseDigestItemCard: View {
    let item: AmenPulseDigestItem
    let onMuteSource: (String) -> Void
    let onSaveItem: (String) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Leading artwork
            Group {
                if let url = item.artworkURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        default:
                            ArtworkFallback(type: item.type)
                        }
                    }
                } else {
                    ArtworkFallback(type: item.type)
                }
            }

            // Middle content
            VStack(alignment: .leading, spacing: 3) {
                Text(item.sourceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Trailing metadata
            VStack(alignment: .trailing, spacing: 6) {
                Image(systemName: item.type.sfSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.type.tintColor)
                RightsPolicyPill(policy: item.rightsPolicy)
                if item.isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.80, green: 0.60, blue: 0.20))
                }
            }
        }
        .padding(12)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.10))
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                }
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            if let url = URL(string: item.deepLink) {
                openURL(url)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onMuteSource(item.sourceLabel)
            } label: {
                Label("Mute", systemImage: "speaker.slash.fill")
            }
            Button {
                onSaveItem(item.id)
            } label: {
                Label("Save", systemImage: "bookmark")
            }
            .tint(Color(red: 0.80, green: 0.60, blue: 0.20))
        }
        .accessibilityLabel(item.title)
        .accessibilityHint("Double tap to open")
    }
}

// MARK: - AmenPulseDigestSectionView

struct AmenPulseDigestSectionView: View {
    let section: AmenPulseDigestSection
    let onMuteSource: (String) -> Void
    let onSaveItem: (String) -> Void

    @State private var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(section: AmenPulseDigestSection, onMuteSource: @escaping (String) -> Void, onSaveItem: @escaping (String) -> Void) {
        self.section = section
        self.onMuteSource = onMuteSource
        self.onSaveItem = onSaveItem
        _isExpanded = State(initialValue: section.isExpanded)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Section header
            Button {
                let animation: Animation = reduceMotion
                    ? .easeOut(duration: 0.12)
                    : .spring(response: 0.3, dampingFraction: 0.8)
                withAnimation(animation) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(section.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    // Item count badge
                    Text("\(section.items.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.5), in: Capsule())
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .animation(
                            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.8),
                            value: isExpanded
                        )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(section.title), \(section.items.count) items, \(isExpanded ? "expanded" : "collapsed")")
            .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand")")

            // Section items
            if isExpanded {
                LazyVStack(spacing: 8) {
                    ForEach(section.items) { item in
                        AmenPulseDigestItemCard(
                            item: item,
                            onMuteSource: onMuteSource,
                            onSaveItem: onSaveItem
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(
                    reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.8),
                    value: isExpanded
                )
            }
        }
    }
}

// MARK: - Shimmer Placeholder Row

private struct ShimmerPlaceholderRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 12)
                    .frame(maxWidth: .infinity)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 14)
                    .frame(maxWidth: .infinity)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 11)
                    .frame(width: 160)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        }
        .redacted(reason: .placeholder)
    }
}

// MARK: - AmenPulseDigestCard

struct AmenPulseDigestCard: View {
    let digest: AmenPulseDigest
    let onMuteSource: (String) -> Void
    let onSaveItem: (String) -> Void
    let onRefresh: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var showPersonalizationSheet = false
    @State private var showWhySheet = false

    var body: some View {
        ZStack {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white.opacity(0.10))
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                // Header row
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today's Pulse")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                        Text(digest.greeting)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Button(action: onRefresh) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Refresh Pulse")
                        Button {
                            showPersonalizationSheet = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Personalize Pulse")
                    }
                }

                // Sections
                LazyVStack(spacing: 12) {
                    ForEach(digest.sections) { section in
                        AmenPulseDigestSectionView(
                            section: section,
                            onMuteSource: onMuteSource,
                            onSaveItem: onSaveItem
                        )
                    }
                }

                // Footer
                Button {
                    showWhySheet = true
                } label: {
                    Label("Why am I seeing this?", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Why am I seeing this? Learn about how your Pulse is personalized.")
            }
            .padding(20)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
        .sheet(isPresented: $showWhySheet) {
            AmenPulseWhySheet(isPresented: $showWhySheet)
        }
        .sheet(isPresented: $showPersonalizationSheet) {
            AmenPulsePersonalizationSheet(
                isPresented: $showPersonalizationSheet,
                mutedSources: [],
                mutedTopics: [],
                onUnmuteSource: { _ in },
                onUnmuteTopic: { _ in }
            )
        }
    }
}

// MARK: - Loading Digest Card

struct AmenPulseDigestLoadingCard: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        ZStack {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white.opacity(0.10))
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Today's Pulse")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                VStack(spacing: 10) {
                    ShimmerPlaceholderRow()
                    ShimmerPlaceholderRow()
                    ShimmerPlaceholderRow()
                }
            }
            .padding(20)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
    }
}

// MARK: - Empty Digest Card

struct AmenPulseDigestEmptyCard: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        ZStack {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white.opacity(0.10))
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                }
            }

            VStack(spacing: 14) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Nothing new right now")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Check back later for updates from your churches and community.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
    }
}

// MARK: - Why Sheet

private struct AmenPulseWhySheet: View {
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Your Pulse is built from your church follows, prayer activity, community memberships, and listening history. We never sell your data or use it for advertising. You can mute any source or topic at any time.")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text("Content marked Members Only is only visible to members of that community. Paid content requires an active subscription.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("About Your Pulse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}

// MARK: - AmenPulsePersonalizationSheet

struct AmenPulsePersonalizationSheet: View {
    @Binding var isPresented: Bool
    let mutedSources: Set<String>
    let mutedTopics: Set<String>
    let onUnmuteSource: (String) -> Void
    let onUnmuteTopic: (String) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var digestFrequency: DigestFrequency = .daily
    @State private var notifyNewMusic = true
    @State private var notifySermons = true
    @State private var notifyPrayerUpdates = true
    @State private var notifyEvents = true
    @State private var notifyCommunity = true

    enum DigestFrequency: String, CaseIterable, Identifiable {
        case daily = "Daily"
        case weekly = "Weekly"
        case off = "Off"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Muted Sources
                Section("Muted Sources") {
                    if mutedSources.isEmpty {
                        Text("Nothing muted yet")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("No muted sources")
                    } else {
                        ForEach(Array(mutedSources).sorted(), id: \.self) { source in
                            HStack {
                                Text(source)
                                Spacer()
                                Button("Unmute") {
                                    onUnmuteSource(source)
                                }
                                .foregroundStyle(Color(red: 0.25, green: 0.72, blue: 0.45))
                                .accessibilityLabel("Unmute \(source)")
                            }
                        }
                    }
                }

                // Muted Topics
                Section("Muted Topics") {
                    if mutedTopics.isEmpty {
                        Text("Nothing muted yet")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("No muted topics")
                    } else {
                        ForEach(Array(mutedTopics).sorted(), id: \.self) { topic in
                            HStack {
                                Text(topic)
                                Spacer()
                                Button("Unmute") {
                                    onUnmuteTopic(topic)
                                }
                                .foregroundStyle(Color(red: 0.25, green: 0.72, blue: 0.45))
                                .accessibilityLabel("Unmute topic \(topic)")
                            }
                        }
                    }
                }

                // Digest Frequency
                Section("Digest Frequency") {
                    Picker("Frequency", selection: $digestFrequency) {
                        ForEach(DigestFrequency.allCases) { freq in
                            Text(freq.rawValue).tag(freq)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Digest frequency: \(digestFrequency.rawValue)")
                }

                // Notification Preferences
                Section("Notification Preferences") {
                    Toggle("New Music", isOn: $notifyNewMusic)
                        .accessibilityLabel("Notify me about new music releases")
                    Toggle("Sermons", isOn: $notifySermons)
                        .accessibilityLabel("Notify me about new sermons")
                    Toggle("Prayer Updates", isOn: $notifyPrayerUpdates)
                        .accessibilityLabel("Notify me about prayer updates")
                    Toggle("Events", isOn: $notifyEvents)
                        .accessibilityLabel("Notify me about upcoming events")
                    Toggle("Community", isOn: $notifyCommunity)
                        .accessibilityLabel("Notify me about community activity")
                }
            }
            .navigationTitle("Personalize Your Pulse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                        .accessibilityLabel("Done, dismiss personalization sheet")
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Digest Card — Loaded") {
    let service = AmenPulseDigestService()
    return ScrollView {
        VStack(spacing: 20) {
            if let digest = service.currentDigest {
                AmenPulseDigestCard(
                    digest: digest,
                    onMuteSource: { _ in },
                    onSaveItem: { _ in },
                    onRefresh: {}
                )
            } else {
                AmenPulseDigestLoadingCard()
            }
        }
        .padding()
    }
    .task {
        await service.loadDailyDigest()
    }
    .environmentObject(service)
}

#Preview("Digest Card — Empty") {
    AmenPulseDigestEmptyCard()
        .padding()
}

#Preview("Personalization Sheet") {
    AmenPulsePersonalizationSheet(
        isPresented: .constant(true),
        mutedSources: ["Elevation Church", "Bethel Music"],
        mutedTopics: ["trending"],
        onUnmuteSource: { _ in },
        onUnmuteTopic: { _ in }
    )
}
