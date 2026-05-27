import SwiftUI

// MARK: - PrayerRequestOfferBanner
// Non-intrusive offer shown to the sender after Berean detects a prayer need.
// User can accept (saves to prayerRequests) or dismiss. Never forced.

struct PrayerRequestOfferBanner: View {
    let offer: PrayerRequestOffer
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hands.sparkles.fill")
                .font(.title3)
                .foregroundStyle(AmenColor.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Track as a prayer request?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text("Berean will follow up with you")
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Yes") { onAccept() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AmenColor.accent)
                    .clipShape(Capsule())

                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(AmenColor.accent.opacity(0.35), lineWidth: 0.5)
                }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - PrayerRequestCard
// Displayed in group channel sidebar / prayer list.

struct PrayerRequestCard: View {
    let request: PrayerRequest
    let onMarkAnswered: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hands.sparkles")
                    .font(.caption)
                    .foregroundStyle(AmenColor.accent)
                Text("Prayer Request")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenColor.accent)
                Spacer()
                if request.status == .open {
                    Button("Answered ✓") { onMarkAnswered() }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                } else {
                    Label("Answered", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }

            Text(request.text)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            if let followUp = request.followUpAt, request.status == .open {
                HStack(spacing: 4) {
                    Image(systemName: "bell").font(.caption2)
                    Text("Follow-up \(followUp.formatted(date: .abbreviated, time: .omitted))")
                }
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AmenColor.accent.opacity(0.25), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - GroupPrayerListView
// Full-screen list of open prayer requests for a group.

struct GroupPrayerListView: View {
    let groupId: String

    @State private var requests: [PrayerRequest] = []
    @State private var listener: ListenerRegistration?

    var body: some View {
        Group {
            if requests.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "hands.sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                    Text("No open prayer requests")
                        .font(.subheadline)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(requests) { req in
                            PrayerRequestCard(request: req) {
                                Task { try? await BereanSmartChannelHook.shared.markAnswered(requestId: req.id ?? "") }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Prayer Requests")
        .navigationBarTitleDisplayMode(.inline)
        .background(AmenTheme.Colors.backgroundPrimary.ignoresSafeArea())
        .onAppear {
            listener = BereanSmartChannelHook.shared.listenPrayerRequests(groupId: groupId) { reqs in
                withAnimation { requests = reqs }
            }
        }
        .onDisappear { listener?.remove() }
    }
}
