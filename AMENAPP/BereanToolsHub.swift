// BereanToolsHub.swift
// AMEN Berean — Tools hub.
// A curated grid of AI capabilities that immediately start a Berean conversation
// in the appropriate mode with a pre-seeded prompt.

import SwiftUI

// MARK: - Tool Model

struct BereanToolItem: Identifiable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let accent: Color
    let seedPrompt: String    // pre-fills the Berean input
    let modeID: String        // launches in this mode
    let cluster: String
}

extension BereanToolItem {
    static let catalog: [BereanToolItem] = [
        // ── Study ──
        BereanToolItem(id: "study_scripture",  name: "Study Scripture",       icon: "book.pages",
                   description: "Deep dive into any passage",
                   accent: Color(red: 0.30, green: 0.30, blue: 0.82),
                   seedPrompt: "Help me study ", modeID: "study", cluster: "Study"),
        BereanToolItem(id: "explain_verse",    name: "Explain a Verse",        icon: "quote.opening",
                   description: "Meaning, context, application",
                   accent: Color(red: 0.25, green: 0.40, blue: 0.85),
                   seedPrompt: "Explain this verse: ", modeID: "scripture", cluster: "Study"),
        BereanToolItem(id: "compare_trans",    name: "Compare Translations",   icon: "arrow.left.arrow.right",
                   description: "Side-by-side versions",
                   accent: Color(red: 0.18, green: 0.38, blue: 0.78),
                   seedPrompt: "Compare translations of ", modeID: "study", cluster: "Study"),
        BereanToolItem(id: "orig_language",    name: "Original Language",      icon: "character.magnify",
                   description: "Greek/Hebrew word study",
                   accent: Color(red: 0.20, green: 0.35, blue: 0.72),
                   seedPrompt: "What does the original Greek or Hebrew say in ", modeID: "study", cluster: "Study"),

        // ── Prayer ──
        BereanToolItem(id: "write_prayer",     name: "Write a Prayer",         icon: "hands.sparkles",
                   description: "Personal or intercessory",
                   accent: Color(red: 0.55, green: 0.20, blue: 0.85),
                   seedPrompt: "Write a prayer for ", modeID: "prayer", cluster: "Prayer"),
        BereanToolItem(id: "prayer_guidance",  name: "Prayer Guidance",        icon: "heart.text.square",
                   description: "How to pray through something",
                   accent: Color(red: 0.60, green: 0.22, blue: 0.80),
                   seedPrompt: "Help me pray through ", modeID: "prayer", cluster: "Prayer"),

        // ── Writing ──
        BereanToolItem(id: "rewrite_post",     name: "Rewrite My Post",        icon: "pencil.and.sparkles",
                   description: "Clearer, kinder, more honest",
                   accent: Color(red: 0.88, green: 0.38, blue: 0.28),
                   seedPrompt: "Rewrite this with more grace and clarity: ", modeID: "rewrite", cluster: "Writing"),
        BereanToolItem(id: "draft_post",       name: "Draft a Post",           icon: "square.and.pencil",
                   description: "Faith-native social content",
                   accent: Color(red: 0.80, green: 0.35, blue: 0.25),
                   seedPrompt: "Help me draft a post about ", modeID: "creator", cluster: "Writing"),
        BereanToolItem(id: "reply_help",       name: "Reply Assistant",        icon: "arrowshape.turn.up.left",
                   description: "Thoughtful reply drafts",
                   accent: Color(red: 0.72, green: 0.30, blue: 0.22),
                   seedPrompt: "Help me reply to this message kindly: ", modeID: "rewrite", cluster: "Writing"),
        BereanToolItem(id: "check_tone",       name: "Check My Tone",          icon: "dial.medium",
                   description: "Safety + civility review",
                   accent: Color(red: 0.78, green: 0.32, blue: 0.22),
                   seedPrompt: "Review the tone of this message before I send it: ", modeID: "safety", cluster: "Writing"),

        // ── Church ──
        BereanToolItem(id: "sermon_notes",     name: "Church Notes",           icon: "doc.plaintext",
                   description: "Summarize or structure sermons",
                   accent: Color(red: 0.18, green: 0.55, blue: 0.40),
                   seedPrompt: "Help me organize my church notes: ", modeID: "church", cluster: "Church"),
        BereanToolItem(id: "church_companion", name: "Church Companion",       icon: "building.columns",
                   description: "Visiting, connecting, serving",
                   accent: Color(red: 0.14, green: 0.50, blue: 0.35),
                   seedPrompt: "Help me with ", modeID: "church", cluster: "Church"),

        // ── Wisdom ──
        BereanToolItem(id: "get_wisdom",       name: "Get Wisdom",             icon: "lightbulb",
                   description: "Biblical perspective on anything",
                   accent: Color(red: 0.65, green: 0.45, blue: 0.10),
                   seedPrompt: "What does Scripture say about ", modeID: "standard", cluster: "Wisdom"),
        BereanToolItem(id: "discern",          name: "Help Me Discern",        icon: "scale.3d",
                   description: "Decision clarity and guidance",
                   accent: Color(red: 0.58, green: 0.40, blue: 0.10),
                   seedPrompt: "Help me discern the right decision about ", modeID: "deep", cluster: "Wisdom"),
        BereanToolItem(id: "summarize",        name: "Summarize",              icon: "text.and.command.macwindow",
                   description: "Thread, sermon, or conversation",
                   accent: Color(red: 0.30, green: 0.45, blue: 0.60),
                   seedPrompt: "Summarize this for me: ", modeID: "standard", cluster: "Wisdom"),
    ]

    static var clusters: [String] {
        var seen = Set<String>()
        return catalog.compactMap { seen.insert($0.cluster).inserted ? $0.cluster : nil }
    }
}

// MARK: - BereanToolsHub

/// Present as a sheet from the Berean composer or landing page.
///
/// Provide `onToolTap` to receive the selected tool's seedPrompt.
/// The caller should apply tool.modeID to BereanModeStore.shared before sending.
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showTools) {
///     BereanToolsHub { tool in
///         BereanModeStore.shared.selectedMode = BereanMode.catalog.first { $0.id == tool.modeID } ?? .standard
///         sendMessage(tool.seedPrompt)
///     }
/// }
/// ```
struct BereanToolsHub: View {
    var onToolTap: (BereanToolItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.975, green: 0.975, blue: 0.975).ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        ForEach(BereanToolItem.clusters, id: \.self) { cluster in
                            clusterSection(cluster)
                        }
                        Spacer().frame(height: 60)
                    }
                    .padding(.top, 10)
                }
            }
            .navigationTitle("Tools")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(white: 0.50))
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    @ViewBuilder
    private func clusterSection(_ cluster: String) -> some View {
        let tools = BereanToolItem.catalog.filter { $0.cluster == cluster }
        VStack(alignment: .leading, spacing: 10) {
            Text(cluster.uppercased())
                .font(.system(size: 11, weight: .semibold)).kerning(0.8)
                .foregroundStyle(Color(white: 0.60))
                .padding(.horizontal, 20)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(tools) { tool in toolCard(tool) }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func toolCard(_ tool: BereanToolItem) -> some View {
        Button {
            onToolTap(tool)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tool.accent.opacity(0.10))
                        .frame(width: 36, height: 36)
                    Image(systemName: tool.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(tool.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(white: 0.10))
                        .lineLimit(2)
                    Text(tool.description)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.52))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(white: 0, opacity: 0.06), lineWidth: 0.5))
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - BereanToolsButton

/// Compact grid-icon button for the composer toolbar.
struct BereanToolsButton: View {
    var onToolTap: (BereanToolItem) -> Void
    @State private var showHub = false

    var body: some View {
        Button { showHub = true } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(white: 0.45))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showHub) {
            BereanToolsHub(onToolTap: onToolTap)
        }
    }
}
