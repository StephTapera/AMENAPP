import SwiftUI

// MARK: - GroupCatchUpView
// "You missed N messages" → Berean summarises the gist + open prayers + decisions.
// Triggered from the channel header via a missed-message count tap.

struct GroupCatchUpView: View {
    let channelId: String
    let groupId: String
    let unreadCount: Int
    let groupName: String
    var onDismiss: () -> Void

    @State private var summary: String?
    @State private var openPrayers: [ChannelPrayerRequest] = []
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Gist summary
                    GlassSection(title: "What you missed", icon: "text.magnifyingglass") {
                        if isLoading {
                            HStack {
                                ProgressView()
                                Text("Berean is summarising…")
                                    .font(.subheadline)
                                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                            }
                            .padding(.vertical, 8)
                        } else if failed {
                            Text("Summary unavailable — scroll up to catch up manually.")
                                .font(.subheadline)
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                        } else if let s = summary {
                            Text(s)
                                .font(.body)
                                .foregroundStyle(AmenTheme.Colors.textPrimary)
                        }
                    }

                    // Open prayer requests
                    if !openPrayers.isEmpty {
                        GlassSection(title: "Open Prayers", icon: "hands.sparkles") {
                            ForEach(openPrayers) { req in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(AmenColor.accent.opacity(0.5))
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 7)
                                    Text(req.text)
                                        .font(.subheadline)
                                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                                }
                            }
                        }
                    }

                    // CTA
                    Button("Got it, show me the chat") { onDismiss() }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AmenTheme.Colors.accentPrimary)
                        }
                }
                .padding()
            }
            .navigationTitle("\(unreadCount) new in \(groupName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                }
            }
            .background(AmenTheme.Colors.backgroundPrimary.ignoresSafeArea())
        }
        .task { await load() }
    }

    private func load() async {
        async let catchUp = BereanSmartChannelHook.shared.generateCatchUp(
            channelId: channelId, unreadCount: unreadCount)
        async let prayers = (try? BereanSmartChannelHook.shared.fetchOpenChannelPrayerRequests(groupId: groupId)) ?? []

        do {
            summary = try await catchUp
        } catch {
            failed = true
        }
        openPrayers = await prayers
        isLoading = false
    }
}

// MARK: - GlassSection helper

private struct GlassSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                }
        }
    }
}

// MARK: - MissedMessageBadge
// Tap target shown in the channel header when there are unread messages.

struct MissedMessageBadge: View {
    let count: Int
    let groupName: String
    let channelId: String
    let groupId: String

    @State private var showCatchUp = false

    var body: some View {
        Button {
            showCatchUp = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.caption2)
                Text("\(count) new — tap to catch up")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(AmenTheme.Colors.accentPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .strokeBorder(AmenTheme.Colors.accentPrimary.opacity(0.35), lineWidth: 0.5)
                    }
            }
        }
        .sheet(isPresented: $showCatchUp) {
            GroupCatchUpView(
                channelId: channelId,
                groupId: groupId,
                unreadCount: count,
                groupName: groupName
            ) { showCatchUp = false }
        }
    }
}
