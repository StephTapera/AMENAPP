import SwiftUI

// MARK: - EvidenceChunk
//
// Codable model representing a single retrieved evidence chunk from the
// Berean pipeline. Each chunk carries its source category for grouping
// and for rendering the correct SF Symbol / color in the sheet.

struct EvidenceChunk: Codable, Identifiable {
    let id: String
    let citation: String
    let content: String
    let source: String   // "scripture" | "theology" | "church" | "userData" | "platform"

    // MARK: Derived display properties

    var sourceIcon: String {
        switch source {
        case "scripture": return "book.fill"
        case "theology":  return "building.columns"
        case "church":    return "building.2.fill"
        case "userData":  return "person.text.rectangle"
        default:          return "square.grid.2x2"   // "platform" + unknown
        }
    }

    var sourceColor: Color {
        switch source {
        case "scripture": return .indigo
        case "theology":  return .purple
        case "church":    return .green
        case "userData":  return .blue
        default:          return .orange              // "platform" + unknown
        }
    }

    /// Human-readable category title shown as a section header.
    var sourceTitle: String {
        switch source {
        case "scripture": return "Scripture"
        case "theology":  return "Theology"
        case "church":    return "Church"
        case "userData":  return "Your Data"
        default:          return "Platform"
        }
    }
}

// MARK: - EvidenceSection
//
// Groups chunks by their source category so the sheet can render them
// in labeled sections within a single ScrollView.

struct EvidenceSection: Identifiable {
    let id: String          // source category string, e.g. "scripture"
    let title: String       // human-readable, e.g. "Scripture"
    let chunks: [EvidenceChunk]
}

extension EvidenceSection {
    /// Builds an ordered section list from a flat array of chunks.
    /// Sections appear in a fixed canonical order rather than insertion order.
    static func grouped(from chunks: [EvidenceChunk]) -> [EvidenceSection] {
        let order = ["scripture", "theology", "church", "userData", "platform"]
        var map: [String: [EvidenceChunk]] = [:]
        for chunk in chunks {
            map[chunk.source, default: []].append(chunk)
        }
        // Collect in canonical order first, then any unexpected sources alphabetically.
        var sections: [EvidenceSection] = []
        for key in order {
            if let group = map[key], !group.isEmpty {
                sections.append(EvidenceSection(id: key, title: group[0].sourceTitle, chunks: group))
                map.removeValue(forKey: key)
            }
        }
        for key in map.keys.sorted() {
            if let group = map[key], !group.isEmpty {
                sections.append(EvidenceSection(id: key, title: group[0].sourceTitle, chunks: group))
            }
        }
        return sections
    }
}

// MARK: - BereanEvidenceSheet

struct BereanEvidenceSheet: View {
    @Binding var isPresented: Bool
    let evidence: [EvidenceChunk]
    let confidence: String
    let traceId: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var sections: [EvidenceSection] {
        EvidenceSection.grouped(from: evidence)
    }

    var body: some View {
        NavigationStack {
            Group {
                if evidence.isEmpty {
                    emptyState
                } else {
                    evidenceList
                }
            }
            .navigationTitle("Why Berean believes this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { dismissButton }
            .safeAreaInset(edge: .bottom) { footer }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(reduceTransparency ? .thickMaterial : .regularMaterial)
    }

    // MARK: - Header confidence chip

    private var confidenceChip: some View {
        Text(confidence)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.indigo.opacity(0.12), in: Capsule())
            .foregroundStyle(Color.indigo)
    }

    // MARK: - Evidence list

    private var evidenceList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                confidenceChip
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                ForEach(sections) { section in
                    sectionView(section)
                }
            }
            .padding(.bottom, 64) // room for footer
        }
    }

    private func sectionView(_ section: EvidenceSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            Text(section.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            VStack(spacing: 1) {
                ForEach(section.chunks) { chunk in
                    EvidenceChunkRow(chunk: chunk)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No sources retrieved for this response")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
        .accessibilityLabel("No evidence sources available for this response")
    }

    // MARK: - Footer (trace ID)

    private var footer: some View {
        HStack {
            Text("Trace ID: \(String(traceId.prefix(8)))")
                .font(.caption2)
                .foregroundStyle(Color(.tertiaryLabel))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .accessibilityLabel("Audit trace identifier: \(String(traceId.prefix(8)))")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var dismissButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") {
                isPresented = false
            }
            .accessibilityLabel("Close evidence sheet")
        }
    }
}

// MARK: - EvidenceChunkRow
//
// Single row rendered inside each section. Content is collapsed to 3 lines
// by default and expands on tap.

private struct EvidenceChunkRow: View {
    let chunk: EvidenceChunk

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            let animation: Animation? = reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)
            if let animation {
                withAnimation(animation) { isExpanded.toggle() }
            } else {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Source icon
                Image(systemName: chunk.sourceIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(chunk.sourceColor)
                    .frame(width: 22, alignment: .center)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    // Citation
                    Text(chunk.citation)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    // Content (expandable)
                    Text(chunk.content)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)

                    if !isExpanded {
                        Text("Tap to expand")
                            .font(.caption)
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Evidence: \(chunk.citation). \(chunk.content)")
        .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand full text")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - EvidenceChipButton
//
// Small inline chip that displays the source count and opens the
// BereanEvidenceSheet as a sheet when tapped.

struct EvidenceChipButton: View {
    let evidence: [EvidenceChunk]
    let confidence: String
    let traceId: String

    @State private var showEvidence = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sourceCount: Int { evidence.count }

    var body: some View {
        Button {
            showEvidence = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .medium))
                Text(sourceCount == 1 ? "1 source" : "\(sourceCount) sources")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.indigo)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.indigo.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(Color.indigo.opacity(0.20), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(sourceCount) evidence \(sourceCount == 1 ? "source" : "sources")")
        .accessibilityHint("Double tap to view sources Berean used for this response")
        .sheet(isPresented: $showEvidence) {
            BereanEvidenceSheet(
                isPresented: $showEvidence,
                evidence: evidence,
                confidence: confidence,
                traceId: traceId
            )
        }
    }
}

// MARK: - Preview

#Preview("With Evidence") {
    let chunks: [EvidenceChunk] = [
        EvidenceChunk(
            id: "1",
            citation: "John 3:16",
            content: "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.",
            source: "scripture"
        ),
        EvidenceChunk(
            id: "2",
            citation: "Philippians 4:6-7",
            content: "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God. And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus.",
            source: "scripture"
        ),
        EvidenceChunk(
            id: "3",
            citation: "Westminster Confession, Chapter 5",
            content: "God the great Creator of all things doth uphold, direct, dispose, and govern all creatures, actions, and things, from the greatest even to the least.",
            source: "theology"
        ),
        EvidenceChunk(
            id: "4",
            citation: "Pastor James — Sermon on Grace, 2024",
            content: "Your church notes from March 3rd highlight the distinction between earned merit and unmerited favor.",
            source: "church"
        ),
        EvidenceChunk(
            id: "5",
            citation: "Your saved post",
            content: "You previously saved a reflection on perseverance through suffering that resonates with this question.",
            source: "userData"
        ),
    ]

    VStack(spacing: 20) {
        Text("Tap the chip below")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        EvidenceChipButton(
            evidence: chunks,
            confidence: "High Confidence",
            traceId: "abc123de-f456-7890-gh12-ijklmnopqrst"
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}

#Preview("Empty Evidence") {
    @Previewable @State var isPresented = true
    BereanEvidenceSheet(
        isPresented: $isPresented,
        evidence: [],
        confidence: "Low Confidence",
        traceId: "zz000000-0000-0000-0000-000000000000"
    )
}
