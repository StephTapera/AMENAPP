import SwiftUI

// MARK: - Individual Chip

struct BereanProvenanceChip: View {
    let kind: BereanProvenanceChipKind
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: kind.icon)
                    .font(.systemScaled(11, weight: .medium))
                Text(kind.label)
                    .font(.systemScaled(12, weight: .medium))
            }
            .foregroundStyle(kind.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(kind.background, in: Capsule())
            .overlay(Capsule().stroke(kind.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed && !reduceMotion ? 0.94 : 1.0)
        .animation(reduceMotion ? .none : .spring(response: 0.22, dampingFraction: 0.7), value: pressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .accessibilityLabel(kind.accessibilityLabel)
        .accessibilityHint("Double tap to learn more")
    }
}

// MARK: - Chip Kinds

enum BereanProvenanceChipKind: Equatable {
    case bereanChecked
    case scriptureGrounded
    case aiAssisted
    case externalContext
    case needsCaution
    case sensitiveTopic

    var label: String {
        switch self {
        case .bereanChecked:     return "Berean-checked"
        case .scriptureGrounded: return "Scripture-grounded"
        case .aiAssisted:        return "AI-assisted"
        case .externalContext:   return "External context"
        case .needsCaution:      return "Needs caution"
        case .sensitiveTopic:    return "Sensitive topic"
        }
    }

    var icon: String {
        switch self {
        case .bereanChecked:     return "checkmark.shield"
        case .scriptureGrounded: return "book.closed"
        case .aiAssisted:        return "sparkles"
        case .externalContext:   return "globe"
        case .needsCaution:      return "exclamationmark.triangle"
        case .sensitiveTopic:    return "heart.text.square"
        }
    }

    var foreground: Color {
        switch self {
        case .bereanChecked:     return .black
        case .scriptureGrounded: return .black
        case .aiAssisted:        return Color(.systemGray)
        case .externalContext:   return Color(.systemGray)
        case .needsCaution:      return Color(red: 0.6, green: 0.3, blue: 0)
        case .sensitiveTopic:    return Color(.systemGray)
        }
    }

    var background: AnyShapeStyle {
        switch self {
        case .bereanChecked:     return AnyShapeStyle(Color.black.opacity(0.07))
        case .scriptureGrounded: return AnyShapeStyle(Color.black.opacity(0.06))
        case .aiAssisted:        return AnyShapeStyle(Color.black.opacity(0.04))
        case .externalContext:   return AnyShapeStyle(Color.black.opacity(0.04))
        case .needsCaution:      return AnyShapeStyle(Color.orange.opacity(0.10))
        case .sensitiveTopic:    return AnyShapeStyle(Color.black.opacity(0.04))
        }
    }

    var border: Color {
        switch self {
        case .needsCaution: return Color.orange.opacity(0.3)
        default:            return Color.black.opacity(0.08)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .bereanChecked:     return "This response was Berean-checked"
        case .scriptureGrounded: return "This response is grounded in Scripture"
        case .aiAssisted:        return "A helper model assisted with this response"
        case .externalContext:   return "External context was used"
        case .needsCaution:      return "This response needs careful handling"
        case .sensitiveTopic:    return "Sensitive topic detected"
        }
    }
}

// MARK: - Chip Row

struct BereanProvenanceChipRow: View {
    let provenance: BereanProvenanceRecord
    let onChipTap: (BereanProvenanceChipKind) -> Void

    var body: some View {
        let chips = buildChips()
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { chip in
                        BereanProvenanceChip(kind: chip) { onChipTap(chip) }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func buildChips() -> [BereanProvenanceChipKind] {
        var result: [BereanProvenanceChipKind] = []
        if provenance.sensitiveTopicDetected { result.append(.sensitiveTopic) }
        if provenance.bereanVerified == .needsCaution { result.append(.needsCaution) }
        if provenance.bereanVerified == .passed { result.append(.bereanChecked) }
        if provenance.scriptureChecked { result.append(.scriptureGrounded) }
        if provenance.externalContextUsed { result.append(.externalContext) }
        if provenance.helperModelUsed { result.append(.aiAssisted) }
        return result
    }
}

// MARK: - Provenance Sheet

struct BereanProvenanceSheet: View {
    let provenance: BereanProvenanceRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    Divider()
                    checklist
                    if provenance.requiresPastoralCare {
                        pastoralNote
                    }
                    disclaimer
                }
                .padding(20)
            }
            .navigationTitle("How this was prepared")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(reduceTransparency ? .thickMaterial : .regularMaterial)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Every Berean answer goes through a structured review before it reaches you.")
                .font(.body)
                .foregroundStyle(.primary)
            Text("Here's what happened with this response.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var checklist: some View {
        VStack(spacing: 16) {
            provenanceRow(
                icon: "checkmark.shield.fill",
                label: "Berean verification",
                status: verdictText,
                statusColor: verdictColor,
                detail: "The final answer was reviewed and shaped by Berean's safety and Scripture-grounding layer."
            )
            provenanceRow(
                icon: "book.closed",
                label: "Scripture checked",
                status: provenance.scriptureChecked ? "Yes" : "Not required",
                statusColor: .secondary,
                detail: "Relevant passages were checked for alignment before the response was finalized."
            )
            provenanceRow(
                icon: "globe",
                label: "External context used",
                status: provenance.externalContextUsed ? "Yes — labeled separately" : "No",
                statusColor: .secondary,
                detail: "External public discussion is summarized separately from Scripture and clearly labeled."
            )
            provenanceRow(
                icon: "sparkles",
                label: "Helper model used",
                status: provenance.helperModelUsed ? "Yes — drafting/summarization only" : "No",
                statusColor: .secondary,
                detail: "A cost-efficient AI model may have helped compress, draft, or summarize context. It is never the final authority."
            )
            provenanceRow(
                icon: "shield.checkerboard",
                label: "Safety review",
                status: provenance.safetyReviewed ? "Passed" : "Skipped",
                statusColor: .secondary,
                detail: "Content was checked for tone, manipulation, and theological boundary safety."
            )
        }
    }

    private func provenanceRow(
        icon: String, label: String, status: String, statusColor: Color, detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.systemScaled(16))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(status)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(statusColor)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pastoralNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.systemScaled(16))
                .foregroundStyle(.secondary)
            Text("This is not a replacement for pastoral care. If something is weighing on you, consider talking to a trusted pastor, mentor, or counselor.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var disclaimer: some View {
        Text("Berean AI is a study and reflection tool. It is not a replacement for Scripture, your church community, or pastoral guidance.")
            .font(.caption2)
            .foregroundStyle(Color(.tertiaryLabel))
            .multilineTextAlignment(.leading)
    }

    private var verdictText: String {
        switch provenance.bereanVerified {
        case .passed:      return "Passed"
        case .limited:     return "Limited"
        case .needsCaution: return "Needs caution"
        }
    }

    private var verdictColor: Color {
        switch provenance.bereanVerified {
        case .passed:       return .black
        case .limited:      return .secondary
        case .needsCaution: return Color(red: 0.7, green: 0.4, blue: 0)
        }
    }
}
