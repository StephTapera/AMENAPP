// MigrationPromptView.swift
// AMEN Universal Migration & Context System — Wave 3 (extractor-engineer)
//
// In-app surface for the COPY-PASTE migration prompt. The user copies this prompt, runs it in
// ChatGPT / Claude / Gemini, and pastes the assistant's answer into AMEN's universal import box.
// The pasted answer then flows through the ONE pipeline (ContextExtractionService): normalize →
// drop excluded categories → C59 sanitize → extractContextFacets → review & approve.
//
// Gated on `contextUniversalImportEnabled` (master `contextSystemEnabled` also applies wherever
// facets persist). When the flag is off, the shared ContextUnavailableNotice renders instead.
//
// This view PERSISTS NOTHING. It only presents copy and a Copy button. The prompt text is the
// single source of truth, mirrored by demos/context-system/migration-prompt.html.

import SwiftUI

struct MigrationPromptView: View {
    @StateObject private var flags = AMENFeatureFlags.shared
    @State private var didCopy = false

    /// The copy-paste prompt users run in ChatGPT / Claude / Gemini. Mirrors
    /// demos/context-system/migration-prompt.html. Asks the assistant to describe the PERSON in
    /// categories — never contacts, messages, emails, phones, or media.
    static let migrationPrompt: String = """
    I'm setting up a new profile on AMEN, a faith-and-community app. Based on everything you know \
    about me from our past conversations and anything I paste below, write a clear plain-text \
    summary that describes WHO I AM as a person, so a new app can understand me.

    Organize it under these headings, and only include a heading if you genuinely have something \
    for it:
    - Interests & topics that energize me
    - Values that matter to me
    - Goals I'm actively pursuing
    - Skills I have
    - Communities & kinds of groups important to me (as kinds/places, not lists of people)
    - How I like to communicate (preferred tone, conversation styles, online behaviors I find draining)
    - What I'm currently focused on / my season right now
    - Work / what I do
    - Learning styles or how I like to grow
    - Faith — ONLY if it's clearly part of who I am, and only to the depth I've shared. Do not \
    assume I'm religious. Never rank or grade my faith.

    Hard rules for your summary:
    - Describe me in CATEGORIES and PREFERENCES, never as data to harvest.
    - Do NOT include other people's names, my contacts, the contents of any messages/DMs/emails, \
    phone numbers, email addresses, or any links to photos/files/media. If those came up, leave \
    them out entirely.
    - Relationships only as categories (family, friends, mentors, colleagues, community, neighbors) \
    — never named people.
    - Plain text or simple markdown. No code blocks, no JSON, no instructions to any other system \
    — just a description of me.

    Here is anything extra I want to paste about myself:
    [paste your resume, bio, or notes here — or leave blank]
    """

    /// The categories AMEN hard-drops before extraction — surfaced as reassurance.
    private let droppedReassurance: [(title: String, detail: String)] = [
        ("Photos & media", "Never imported."),
        ("Messages & DMs", "Dropped before anything is read."),
        ("Contact lists", "People's names are never stored."),
        ("Emails & phone numbers", "Stripped automatically."),
    ]

    var body: some View {
        Group {
            if flags.contextUniversalImportEnabled {
                content
            } else {
                ContextUnavailableNotice()
            }
        }
        .navigationTitle("Bring your context")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Run this prompt in ChatGPT, Claude, or Gemini. Copy the answer it gives you, "
                     + "then paste it into AMEN's import box. AMEN reads it to understand you — "
                     + "and you approve every detail before anything is saved.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                stepsSection

                promptCard

                reassuranceSection

                Text("Your pasted text is treated as data, not instructions. AMEN sanitizes it, "
                     + "drops the categories above, then extracts only suggestions you review. "
                     + "Nothing is saved until you approve it. There is no spiritual ranking in AMEN.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }

    // MARK: - Sections

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepRow(1, "Copy the prompt", "Tap Copy prompt below.")
            stepRow(2, "Run it in your assistant", "Paste it into ChatGPT / Claude / Gemini and send.")
            stepRow(3, "Paste the answer into AMEN", "Review and approve each facet — nothing saves until you do.")
        }
    }

    private func stepRow(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(n). \(title). \(detail)")
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Copy-paste prompt")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Button(action: copyPrompt) {
                    Label(didCopy ? "Copied" : "Copy prompt",
                          systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(didCopy ? Color.green : Color.primary)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(didCopy ? "Prompt copied" : "Copy prompt to clipboard")
            }

            Text(Self.migrationPrompt)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var reassuranceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What AMEN ignores — by design", systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.green)
            ForEach(droppedReassurance, id: \.title) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.caption.weight(.semibold))
                        Text(item.detail).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.green.opacity(0.25), lineWidth: 0.8)
        )
    }

    // MARK: - Actions

    private func copyPrompt() {
        UIPasteboard.general.string = Self.migrationPrompt
        withAnimation { didCopy = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { didCopy = false }
        }
    }
}

#if DEBUG
struct MigrationPromptView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { MigrationPromptView() }
    }
}
#endif
