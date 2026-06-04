import SwiftUI
import FirebaseAnalytics
import FirebaseFunctions

private enum BroadcastState: Equatable {
    case idle
    case sending
    case success
    case error(String)
}

struct AmenBroadcastComposerView: View {
    let spaceId: String
    let spaceName: String
    let events: [AmenSpaceEvent]
    let onSend: (String, String?) async -> Void
    let onDismiss: () -> Void

    @State private var messageText = ""
    @State private var attachedEvent: AmenSpaceEvent?
    @State private var showEventPicker = false
    @State private var broadcastState: BroadcastState = .idle

    private let charLimit = 500

    var body: some View {
        ZStack {
            Color(hex: "070607").ignoresSafeArea()

            VStack(spacing: 0) {
                navBar
                ScrollView {
                    VStack(spacing: 16) {
                        messageCard
                        attachEventSection
                        sendAsRow
                        if let attached = attachedEvent {
                            attachedEventPreview(attached)
                        }
                    }
                    .padding(16)
                }
                broadcastButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            Analytics.logEvent("broadcast_composer_viewed", parameters: nil)
        }
        .sheet(isPresented: $showEventPicker) {
            EventPickerSheet(
                events: events,
                selected: attachedEvent,
                onSelect: { attachedEvent = $0; showEventPicker = false },
                onClear: { attachedEvent = nil; showEventPicker = false }
            )
        }
    }

    // MARK: - Sub-views

    private var navBar: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Dismiss")
            Spacer()
            Text("Broadcast")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            // Balance the leading close button
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial)
    }

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $messageText)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .foregroundStyle(.white)
                .font(.body)
                .frame(minHeight: 130)
                .padding(12)
                .onChange(of: messageText) { _, new in
                    if new.count > charLimit {
                        messageText = String(new.prefix(charLimit))
                    }
                }

            Divider().background(.white.opacity(0.08))

            HStack {
                Text(messageText.isEmpty ? "Write your message to all members…" : "")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.3))
                    .allowsHitTesting(false)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .opacity(messageText.isEmpty ? 1 : 0)
                Spacer()
                Text("\(messageText.count)/\(charLimit)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(messageText.count > Int(Double(charLimit) * 0.9) ? Color(hex: "FF3B30") : .secondary)
                    .padding(10)
            }
        }
        .background(Color(hex: "1A1820"), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var attachEventSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attach Event")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button(action: { showEventPicker = true }) {
                HStack {
                    Image(systemName: attachedEvent == nil ? "calendar.badge.plus" : "calendar.badge.checkmark")
                        .foregroundStyle(Color(hex: "D9A441"))
                    Text(attachedEvent.map(\.title) ?? "Select an event (optional)")
                        .font(.subheadline)
                        .foregroundStyle(attachedEvent == nil ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(attachedEvent.map { "Attached event: \($0.title). Tap to change." } ?? "Select event to attach")
        }
    }

    private var sendAsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Send as")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                channelBadge(icon: "bell.fill", label: "Push")
                channelBadge(icon: "envelope.fill", label: "Email")
                channelBadge(icon: "app.fill", label: "In-App")
            }
        }
    }

    private func channelBadge(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "D9A441"))
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(hex: "D9A441").opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(Color(hex: "D9A441").opacity(0.3), lineWidth: 1))
    }

    private func attachedEventPreview(_ event: AmenSpaceEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 18))
                .foregroundStyle(Color(hex: "D9A441"))
                .frame(width: 36, height: 36)
                .background(Color(hex: "D9A441").opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(event.scheduledAt.shortLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 3) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 9))
                        Text(".ics will be auto-attached")
                            .font(.caption2)
                    }
                    .foregroundStyle(Color(hex: "D9A441").opacity(0.8))
                }
            }
            Spacer()
            Button(action: { attachedEvent = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove attached event")
        }
        .padding(12)
        .background(Color(hex: "1A1820"), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(hex: "D9A441").opacity(0.25), lineWidth: 1)
        )
    }

    private var broadcastButton: some View {
        Button(action: handleBroadcast) {
            HStack(spacing: 8) {
                if broadcastState == .sending {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color(hex: "070607"))
                    Text("Calling sendEventBroadcast…")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color(hex: "070607"))
                } else if broadcastState == .success {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Broadcast Sent")
                        .font(.headline.weight(.bold))
                } else {
                    Image(systemName: "megaphone.fill")
                    Text("Broadcast")
                        .font(.headline.weight(.bold))
                }
            }
            .foregroundStyle(
                broadcastState == .success
                    ? Color.white
                    : Color(hex: "070607")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                broadcastState == .success
                    ? Color(hex: "245B8F")
                    : (messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color(hex: "D9A441").opacity(0.35)
                        : Color(hex: "D9A441")),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
        .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || broadcastState == .sending)
        .accessibilityLabel("Send broadcast to all members")
        .overlay(errorToast, alignment: .top)
    }

    @ViewBuilder
    private var errorToast: some View {
        if case .error(let msg) = broadcastState {
            Text(msg)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(hex: "FF3B30").opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                .offset(y: -52)
                .transition(.opacity)
        }
    }

    // MARK: - Actions

    private func handleBroadcast() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            withAnimation { broadcastState = .sending }
            do {
                await onSend(trimmed, attachedEvent?.id)
                withAnimation { broadcastState = .success }
                try await Task.sleep(nanoseconds: 2_000_000_000)
                onDismiss()
            } catch {
                withAnimation { broadcastState = .error(error.localizedDescription) }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation { broadcastState = .idle }
            }
        }
    }
}

// MARK: - Event Picker Sheet

private struct EventPickerSheet: View {
    let events: [AmenSpaceEvent]
    let selected: AmenSpaceEvent?
    let onSelect: (AmenSpaceEvent) -> Void
    let onClear: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "070607").ignoresSafeArea()
                List {
                    if selected != nil {
                        Button(role: .destructive, action: onClear) {
                            Label("Remove attachment", systemImage: "xmark.circle")
                        }
                        .listRowBackground(Color(hex: "1A1820"))
                    }
                    ForEach(events.sorted { $0.scheduledAt < $1.scheduledAt }) { event in
                        Button(action: { onSelect(event) }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .foregroundStyle(.white)
                                        .font(.subheadline.weight(.medium))
                                    Text(event.scheduledAt.shortLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selected?.id == event.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color(hex: "D9A441"))
                                }
                            }
                        }
                        .listRowBackground(Color(hex: "1A1820"))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Select Event")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

private extension Date {
    var shortLabel: String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(self) {
            f.dateFormat = "'Today' h:mma"
        } else if cal.isDateInTomorrow(self) {
            f.dateFormat = "'Tomorrow' h:mma"
        } else {
            f.dateFormat = "EEE, MMM d 'at' h:mma"
        }
        return f.string(from: self)
    }
}

#Preview {
    AmenBroadcastComposerView(
        spaceId: "s1",
        spaceName: "Grace Church",
        events: [
            AmenSpaceEvent(
                id: "e1", spaceId: "s1", hostUserId: "u1",
                title: "Sunday Evening Worship",
                eventDescription: "Join us.",
                type: .livestream,
                scheduledAt: Date().addingTimeInterval(86400),
                durationMinutes: 90,
                isRecurring: true,
                recurrenceRule: "FREQ=WEEKLY;BYDAY=SU",
                rsvpUserIds: [],
                maxAttendees: nil,
                requiredTierId: nil,
                isLive: false,
                liveRoomId: nil,
                replayRef: nil,
                calendarInviteSentAt: nil,
                createdAt: Date(),
                updatedAt: Date()
            ),
        ],
        onSend: { _, _ in },
        onDismiss: {}
    )
}
