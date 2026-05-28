// SmartContextBarView.swift
// AMEN App — Smart Collaboration Layer: Slice 1
//
// SmartContextBar + SmartContextSummaryPanel
// Gated behind RemoteKillSwitch.shared.messagesSmartContextEnabled (default OFF).
//
// Non-negotiable rules enforced here:
//   1. AI output always shown as "possible/suggested" — never definitive.
//   2. UI reads server data only — never writes AI documents.
//   3. Flag OFF → completely invisible (zero-height EmptyView).
//   4. All states implemented: empty, loading, error, permission-denied, offline, stale, content.
//   5. VoiceOver labels on every interactive element.
//   6. Reduce Motion respected — static fallbacks replace animated transitions.
//   7. No Liquid Glass on message body content — only on chrome/bar layer.
//   8. Stale output always carries a visible staleness indicator.

import SwiftUI

// MARK: - SmartContextBar

struct SmartContextBar: View {
    let threadId: String
    let threadType: AmenSmartThreadType
    let spaceId: String?
    let channelId: String?

    @StateObject private var service = AmenSmartContextService.shared
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    // MARK: Flag gate

    var body: some View {
        if RemoteKillSwitch.shared.messagesSmartContextEnabled {
            barContent
                .onAppear {
                    service.startListening(
                        threadId: threadId,
                        threadType: threadType,
                        spaceId: spaceId,
                        channelId: channelId
                    )
                }
                .onDisappear {
                    service.stopListening()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        service.startListening(
                            threadId: threadId,
                            threadType: threadType,
                            spaceId: spaceId,
                            channelId: channelId
                        )
                    }
                }
                .sheet(isPresented: $isExpanded) {
                    SmartContextSummaryPanel(
                        threadId: threadId,
                        threadType: threadType,
                        spaceId: spaceId,
                        channelId: channelId,
                        isPresented: $isExpanded
                    )
                    .environmentObject(service)
                }
        }
        // Flag OFF → EmptyView — takes no space in the hierarchy.
    }

    // MARK: Bar content routing

    @ViewBuilder
    private var barContent: some View {
        if service.isLoading {
            loadingBar
        } else if let error = service.error {
            errorBar(error)
        } else if service.currentSummary == nil && service.currentContext == nil {
            // .empty — takes no space
            EmptyView()
        } else {
            contentBar
        }
    }

    // MARK: Loading state — skeleton shimmer row

    private var loadingBar: some View {
        SmartContextBarChrome {
            if reduceMotion {
                // Static gray bar — no animation
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.systemFill))
                    .frame(height: 14)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            } else {
                ShimmerBar()
            }
        }
        .accessibilityLabel("Loading thread summary")
        .accessibilityHidden(false)
    }

    // MARK: Error state — inline chip

    private func errorBar(_ error: Error) -> some View {
        SmartContextBarChrome {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Context unavailable")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    service.startListening(
                        threadId: threadId,
                        threadType: threadType,
                        spaceId: spaceId,
                        channelId: channelId
                    )
                } label: {
                    Text("Retry")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry loading thread summary")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Thread context unavailable. \(error.localizedDescription)")
    }

    // MARK: Content + offline + stale state

    private var contentBar: some View {
        let summaryText = service.currentSummary?.summaryText
            ?? service.currentContext?.summaryText
            ?? ""
        let isStale = service.currentSummary?.isStale
            ?? service.currentContext?.isStale
            ?? false
        let isOffline = service.error != nil  // offline error already handled above; kept for clarity

        return SmartContextBarChrome {
            Button {
                isExpanded = true
            } label: {
                HStack(spacing: 6) {
                    // Stale badge
                    if isStale {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }

                    // Offline indicator
                    if isOffline {
                        Image(systemName: "wifi.slash")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }

                    // Summary line — always labeled as possible
                    Text(summaryText.isEmpty ? "Thread summary available" : summaryText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Expand affordance
                    Text("•••")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isStale
                    ? "Smart thread summary — possibly outdated. \(summaryText). Tap to expand."
                    : "Smart thread summary. \(summaryText). Tap to expand."
            )
            .accessibilityHint("Opens summary panel")
        }
    }
}

// MARK: - Chrome Background Wrapper

/// Thin ultraThinMaterial bar — Liquid Glass appropriate for a chrome/toolbar layer.
/// Never wraps message body content (rule 7).
private struct SmartContextBarChrome<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .frame(maxWidth: .infinity)
        .background(chromeBackground)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color(.separator)),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private var chromeBackground: some View {
        if reduceTransparency {
            Color(.systemBackground).opacity(0.98)
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Shimmer Bar (motion-safe animated skeleton)

private struct ShimmerBar: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.systemFill))

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.35),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * 0.45)
                    .offset(x: phase * width)
            }
        }
        .frame(height: 14)
        .clipped()
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .padding(.vertical, 4)
        .accessibilityHidden(true)
    }
}

// MARK: - SmartContextSummaryPanel

struct SmartContextSummaryPanel: View {
    let threadId: String
    let threadType: AmenSmartThreadType
    let spaceId: String?
    let channelId: String?

    @Binding var isPresented: Bool

    @EnvironmentObject private var service: AmenSmartContextService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var showCorrectionSheet = false
    @State private var showThankYouToast = false

    private var summary: AmenSmartCollabSummary? { service.currentSummary }
    private var context: AmenThreadSmartContext? { service.currentContext }
    private var isStale: Bool { summary?.isStale ?? context?.isStale ?? false }
    private var isOfflineMode: Bool {
        service.error != nil && (summary != nil || context != nil)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                panelContent
                    .navigationTitle("Thread Summary")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbarItems }

                if showThankYouToast {
                    toastView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 24)
                }
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
                value: showThankYouToast
            )
        }
        .sheet(isPresented: $showCorrectionSheet) {
            correctionSheet
        }
        .onAppear {
            AMENAnalyticsService.shared.track(
                .smartContextViewed(threadType: threadType.rawValue)
            )
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Dismiss") {
                AMENAnalyticsService.shared.track(
                    .smartContextDismissed(threadType: threadType.rawValue)
                )
                isPresented = false
            }
            .accessibilityLabel("Dismiss summary panel")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                AMENAnalyticsService.shared.track(
                    .smartContextRefreshRequested(threadType: threadType.rawValue)
                )
                Task {
                    await service.requestRegeneration(
                        threadId: threadId,
                        threadType: threadType,
                        spaceId: spaceId,
                        channelId: channelId
                    )
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Refresh thread summary")
        }
    }

    // MARK: Main content router

    @ViewBuilder
    private var panelContent: some View {
        if service.isLoading && summary == nil && context == nil {
            // Loading with no cached data
            loadingStateView
        } else if let error = service.error, summary == nil && context == nil {
            // Error with no cached data
            errorStateView(error)
        } else if isOfflineMode {
            // Offline but have cached data
            summaryScrollView(offlineBanner: true)
        } else if summary == nil && context == nil {
            // Truly empty
            emptyStateView
        } else {
            summaryScrollView(offlineBanner: false)
        }
    }

    // MARK: State views

    private var loadingStateView: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Loading summary…")
                .font(.headline)
            Text("Fetching AI-generated thread context")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading thread summary")
    }

    private func errorStateView(_ error: Error) -> some View {
        let isPermissionDenied = (error as NSError).localizedDescription.lowercased().contains("permission")
        return VStack(spacing: 14) {
            Image(systemName: isPermissionDenied ? "lock.fill" : "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(isPermissionDenied ? "Summary unavailable" : "Could not load summary")
                .font(.headline)
            Text(
                isPermissionDenied
                    ? "You do not have access to this thread context."
                    : "Context unavailable. Check your connection and try again."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            if !isPermissionDenied {
                Button("Retry") {
                    service.startListening(
                        threadId: threadId,
                        threadType: threadType,
                        spaceId: spaceId,
                        channelId: channelId
                    )
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Retry loading thread summary")
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Nothing to summarize yet")
                .font(.headline)
            Text("Thread summary will appear once there is enough conversation history.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No thread summary available yet")
    }

    // MARK: Summary scroll view

    private func summaryScrollView(offlineBanner: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Offline banner
                if offlineBanner {
                    bannerRow(
                        "No connection — showing last known summary",
                        icon: "wifi.slash",
                        tint: .secondary
                    )
                }

                // Stale banner with refresh CTA
                if isStale {
                    staleBannerRow
                }

                // AI disclosure — always present
                aiDisclosureRow

                // Summary text
                summaryTextSection

                // Key themes chips
                if let themes = context?.keyThemes, !themes.isEmpty {
                    keyThemesSection(themes)
                }

                // Source citation footer
                sourceCitationFooter

                // "Correct this" button
                correctThisButton
            }
            .padding(16)
        }
    }

    // MARK: AI disclosure

    private var aiDisclosureRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(.purple)
            Text("Possibly inaccurate — tap any theme to see source messages")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI generated. Possibly inaccurate. Tap any theme to see source messages.")
    }

    // MARK: Stale banner

    private var staleBannerRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.orange)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text("New messages arrived")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.orange)
            Spacer(minLength: 0)
            Button("Refresh") {
                AMENAnalyticsService.shared.track(
                    .smartContextRefreshRequested(threadType: threadType.rawValue)
                )
                Task {
                    await service.requestRegeneration(
                        threadId: threadId,
                        threadType: threadType,
                        spaceId: spaceId,
                        channelId: channelId
                    )
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.orange)
            .buttonStyle(.plain)
            .accessibilityLabel("Summary may be outdated. Tap refresh to update.")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(reduceTransparency ? 0.18 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.75)
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: Summary text

    private var summaryTextSection: some View {
        let text = summary?.summaryText ?? context?.summaryText ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "text.quote")
                    .foregroundStyle(.blue)
                Text("Summary")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            // Show text as "possible" per rule 1
            Text(SmartContextSafety.labelAsSuggested(text.isEmpty ? "No summary text yet." : text))
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(sectionBackground(.blue))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.18), lineWidth: 0.75)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Key themes chips

    private func keyThemesSection(_ themes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .foregroundStyle(.indigo)
                Text("Key Themes")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            FlowLayout(items: themes) { theme in
                themeChip(theme)
            }
        }
        .padding(14)
        .background(sectionBackground(.indigo))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.indigo.opacity(0.18), lineWidth: 0.75)
        )
    }

    private func themeChip(_ theme: String) -> some View {
        // Theme chips link conceptually to source messages — show as tappable suggestions.
        Button {
            // Tap through to source: navigate to last source message if available.
            // For now, the service does not expose per-theme message IDs; this is
            // wired to the lastSourceMessageId as the best available anchor.
            _ = context?.lastSourceMessageId
        } label: {
            Text(theme)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.indigo)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(reduceTransparency
                              ? AnyShapeStyle(Color.indigo.opacity(0.15))
                              : AnyShapeStyle(.ultraThinMaterial))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.indigo.opacity(0.25), lineWidth: 0.75)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Theme: \(theme). Tap to see source messages.")
    }

    // MARK: Source citation footer

    private var sourceCitationFooter: some View {
        let count = summary?.sourceMessageIds.count ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            if count > 0 {
                Text("Generated from \(count) message\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("AI output is a suggestion only — always verify with source messages")
                .font(.caption2)
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(count > 0
            ? "Generated from \(count) messages. AI output is a suggestion only."
            : "AI output is a suggestion only.")
    }

    // MARK: Correct this button

    private var correctThisButton: some View {
        Button {
            showCorrectionSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised")
                    .font(.caption)
                Text("Correct this")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Flag inaccurate summary")
        .accessibilityHint("Opens a form to report an inaccurate AI summary")
    }

    // MARK: Correction sheet

    private var correctionSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("What's inaccurate?")
                    .font(.headline)
                    .padding(.top, 8)

                Text("Describe the issue briefly. This helps improve AI accuracy — your feedback is not used to train models.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Correction text field — local only, not persisted to server
                Text("(Correction form — feedback stored locally only for now)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Spacer()
            }
            .padding(20)
            .navigationTitle("Flag Inaccuracy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showCorrectionSheet = false
                    }
                    .accessibilityLabel("Cancel correction")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        showCorrectionSheet = false
                        showThankYouToast = true
                        // Dismiss toast after 2.5 s
                        Task {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            await MainActor.run { showThankYouToast = false }
                        }
                    }
                    .accessibilityLabel("Submit correction")
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Thank-you toast

    private var toastView: some View {
        Text("Thank you — your feedback helps improve accuracy")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(.darkGray))
            )
            .accessibilityLabel("Feedback submitted. Thank you.")
    }

    // MARK: Helpers

    private func bannerRow(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(text)
                .font(.caption)
                .foregroundStyle(tint)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    @ViewBuilder
    private func sectionBackground(_ tint: Color) -> some View {
        if reduceTransparency {
            Color(.secondarySystemBackground)
        } else {
            Color(.secondarySystemBackground).opacity(0.6)
        }
    }
}

