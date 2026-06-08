import SwiftUI
import FirebaseAnalytics

// MARK: - Link Summary Sheet (Flow 3)
//
// Shown when user pastes a link and taps "Summarize link" or "Extract themes".
// Grok provides the initial parse; "Run Berean Check" routes to Berean verification.

struct BereanLinkSummarySheet: View {
    let url: String
    let onRunBereanCheck: (String) -> Void
    let onAskFollowUp: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var analysis: BereanLinkAnalysis? = nil
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let analysis {
                    contentView(analysis)
                } else {
                    errorView
                }
            }
            .navigationTitle("Link Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(reduceTransparency ? .thickMaterial : .regularMaterial)
        .task { await load() }
        .onAppear {
            let urlDomain = URL(string: url)?.host ?? "unknown"
            Analytics.logEvent("berean_link_detected", parameters: ["url_domain": urlDomain])
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .tint(.secondary)
            Text("Analyzing link…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(urlDomain)
                .font(.caption)
                .foregroundStyle(Color(.tertiaryLabel))
            Spacer()
        }
        .accessibilityLabel("Analyzing link, please wait")
    }

    // MARK: - Error

    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "link.badge.plus")
                .font(.systemScaled(36))
                .foregroundStyle(.secondary)
            Text("Couldn't summarize this link")
                .font(.headline)
            Text("You can still ask Berean about it directly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Ask Berean anyway") {
                onAskFollowUp("Can you help me understand this link? \(url)")
                dismiss()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding(24)
    }

    // MARK: - Content

    private func contentView(_ analysis: BereanLinkAnalysis) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Source card
                sourceCard(analysis)

                // Summary
                sectionBlock(title: "Summary", body: analysis.summary)

                // Key themes
                if !analysis.keyThemes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("Key themes")
                        AMENFlowLayout(spacing: 8) {
                            ForEach(analysis.keyThemes, id: \.self) { theme in
                                Text(theme)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.black.opacity(0.06), in: Capsule())
                            }
                        }
                    }
                }

                // Claims to check
                if !analysis.claimsToCheck.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("Claims that may need Berean review")
                        ForEach(analysis.claimsToCheck, id: \.self) { claim in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "questionmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                                Text(claim)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Scripture found
                if !analysis.scriptureReferencesFound.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("Scripture mentioned in this content")
                        AMENFlowLayout(spacing: 8) {
                            ForEach(analysis.scriptureReferencesFound, id: \.self) { ref in
                                Text(ref)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.black.opacity(0.07), in: Capsule())
                                    .overlay(Capsule().stroke(Color.black.opacity(0.1), lineWidth: 0.5))
                            }
                        }
                    }
                }

                externalContextDisclaimer

                // Actions
                actions(analysis)
            }
            .padding(20)
        }
    }

    private func sourceCard(_ analysis: BereanLinkAnalysis) -> some View {
        HStack(spacing: 12) {
            Image(systemName: contentTypeIcon(analysis.contentType))
                .font(.systemScaled(20))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color(.secondarySystemBackground), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(analysis.title ?? analysis.sourceLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(analysis.sourceLabel + " · " + analysis.contentType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func actions(_ analysis: BereanLinkAnalysis) -> some View {
        VStack(spacing: 10) {
            Button {
                let prompt = buildBereanCheckPrompt(analysis)
                onRunBereanCheck(prompt)
                Analytics.logEvent("berean_scripture_check_started", parameters: nil)
                dismiss()
            } label: {
                Label("Run Berean Check", systemImage: "checkmark.shield")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black)

            if let suggested = analysis.suggestedQuestion {
                Button {
                    onAskFollowUp(suggested)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.subheadline)
                        Text(suggested)
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var externalContextDisclaimer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("This summary is AI-generated from the linked content. It is not a Berean-verified response. Tap \"Run Berean Check\" to verify claims against Scripture.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Helpers

    private func sectionBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(title)
            Text(body)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func contentTypeIcon(_ type: String) -> String {
        switch type.lowercased() {
        case let t where t.contains("video"):   return "film"
        case let t where t.contains("podcast"): return "waveform"
        case let t where t.contains("article"): return "doc.text"
        case let t where t.contains("sermon"):  return "mic"
        default:                                return "link"
        }
    }

    private func buildBereanCheckPrompt(_ analysis: BereanLinkAnalysis) -> String {
        var parts: [String] = []
        parts.append("Please Berean-check this content from \(analysis.sourceLabel).")
        if let title = analysis.title { parts.append("Title: \(title).") }
        parts.append("Summary: \(analysis.summary)")
        if !analysis.claimsToCheck.isEmpty {
            parts.append("Claims to examine: " + analysis.claimsToCheck.joined(separator: "; "))
        }
        if !analysis.scriptureReferencesFound.isEmpty {
            parts.append("Scripture mentioned: " + analysis.scriptureReferencesFound.joined(separator: ", "))
        }
        return parts.joined(separator: " ")
    }

    private var urlDomain: String {
        URL(string: url)?.host ?? url
    }

    private func load() async {
        isLoading = true
        analysis = await BereanGrokService.shared.analyzeLink(url)
        isLoading = false
        if analysis == nil { failed = true }
    }
}
