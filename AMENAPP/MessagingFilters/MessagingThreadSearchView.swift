//
//  MessagingThreadSearchView.swift
//  AMENAPP
//
//  Phase 2: Thread-level search + filter sheet for UnifiedChatView.
//  Reuses MessagingInboxFilterTray's Liquid Glass aesthetic via a
//  chip strip + search field. All operations are local to the in-memory
//  `[AppMessage]` array — no Firestore queries, no fake counts.
//
//  Jump-to-message: emits the selected message ID via `onJumpToMessage`.
//  The host view is responsible for scrolling/highlighting; this view
//  simply dismisses and forwards the ID.
//

import SwiftUI

@available(iOS 17.0, *)
public struct MessagingThreadSearchView: View {
    let messages: [AppMessage]
    let currentUserId: String
    let onJumpToMessage: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @State private var query: String = ""
    @State private var activeFilter: MessagingThreadFilter = .all
    @FocusState private var searchFocused: Bool

    public init(
        messages: [AppMessage],
        currentUserId: String,
        onJumpToMessage: @escaping (String) -> Void
    ) {
        self.messages = messages
        self.currentUserId = currentUserId
        self.onJumpToMessage = onJumpToMessage
    }

    private var capabilities: MessagingThreadFilterCapabilities {
        MessagingThreadFilterAvailability.capabilities(
            messages: messages,
            currentUserId: currentUserId
        )
    }

    private var availableFilters: [MessagingThreadFilter] {
        MessagingThreadFilter.available(for: capabilities)
    }

    private var results: [AppMessage] {
        MessagingThreadSearch.results(
            messages: messages,
            filter: activeFilter,
            query: query,
            currentUserId: currentUserId
        )
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                chipStrip
                    .padding(.top, 10)
                Divider()
                    .opacity(0.4)
                    .padding(.top, 10)

                if results.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    resultsList
                }
            }
            .background(reduceTransparency ? Color(.systemBackground).ignoresSafeArea() : nil)
            .navigationTitle("Search Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                AMENAnalyticsService.shared.track(.messageSearchOpened(surface: "thread"))
                searchFocused = true
            }
            .onChange(of: activeFilter) { _, newValue in
                AMENAnalyticsService.shared.track(
                    .messageThreadFilterSelected(filter: newValue.analyticsKey)
                )
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search this conversation", text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { trackSubmit() }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(reduceTransparency
                      ? AnyShapeStyle(Color(.secondarySystemBackground))
                      : AnyShapeStyle(.thinMaterial))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(contrast == .increased ? 0.30 : 0.08),
                    lineWidth: contrast == .increased ? 1.0 : 0.5
                )
        )
    }

    // MARK: - Chip Strip

    private var chipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableFilters) { filter in
                    chipButton(filter)
                }
            }
            .padding(.horizontal, 16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Thread filters")
    }

    @ViewBuilder
    private func chipButton(_ filter: MessagingThreadFilter) -> some View {
        let isActive = activeFilter == filter
        Button {
            activeFilter = isActive ? .all : filter
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.symbol)
                    .font(.systemScaled(12, weight: .semibold))
                Text(filter.title)
                    .font(.systemScaled(14, weight: isActive ? .semibold : .medium))
            }
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive
                          ? AnyShapeStyle(Color.accentColor)
                          : AnyShapeStyle(.thinMaterial))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(contrast == .increased ? 0.30 : 0.06),
                        lineWidth: contrast == .increased ? 1.0 : 0.5
                    )
            )
            .frame(minHeight: 28)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "\(filter.title), selected" : filter.title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: query.isEmpty ? "tray" : "magnifyingglass")
                .font(.systemScaled(28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "No messages for this filter" : "No matches for \"\(query)\"")
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(results, id: \.id) { message in
                    Button {
                        onJumpToMessage(message.id)
                        AMENAnalyticsService.shared.track(
                            .messageSearchResultTapped(surface: "thread", kind: kind(of: message))
                        )
                        dismiss()
                    } label: {
                        resultRow(message)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func kind(of message: AppMessage) -> String {
        if MessagingThreadFilterAvailability.isMediaMessage(message) { return "media" }
        if MessagingThreadFilterAvailability.isLinkMessage(message) { return "link" }
        if MessagingThreadFilterAvailability.isFileMessage(message) { return "file" }
        return "message"
    }

    private func resultRow(_ message: AppMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: rowIcon(for: message))
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(message.senderName ?? "Someone")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(displayLine(for: message))
                    .font(.systemScaled(13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(message.formattedTimestamp)
                    .font(.systemScaled(11))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.systemScaled(11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(reduceTransparency
                      ? AnyShapeStyle(Color(.secondarySystemBackground))
                      : AnyShapeStyle(.thinMaterial))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.20 : 0.06),
                              lineWidth: contrast == .increased ? 1.0 : 0.5)
        )
        .contentShape(Rectangle())
    }

    private func rowIcon(for message: AppMessage) -> String {
        if MessagingThreadFilterAvailability.isMediaMessage(message) { return "photo" }
        if MessagingThreadFilterAvailability.isLinkMessage(message) { return "link" }
        if MessagingThreadFilterAvailability.isFileMessage(message) { return "doc" }
        if message.isPinned { return "pin.fill" }
        if message.isStarred { return "star.fill" }
        return "text.bubble"
    }

    private func displayLine(for message: AppMessage) -> String {
        if !message.text.isEmpty { return message.text }
        if let t = message.linkTitle, !t.isEmpty { return t }
        if let n = message.mediaFileName, !n.isEmpty { return n }
        switch message.messageType {
        case .image: return "Photo"
        case .video: return "Video"
        case .file:  return "File"
        case .link:  return "Link"
        case .text:  return ""
        }
    }

    private func trackSubmit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Privacy-safe: only counts, never the query text itself.
        AMENAnalyticsService.shared.track(
            .messageSearchSubmitted(
                surface: "thread",
                hasResults: !results.isEmpty,
                resultBuckets: results.count
            )
        )
    }
}
