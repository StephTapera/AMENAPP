// BereanResearchReportCard.swift
// AMENAPP - BereanOS
// Compact expandable card summarising a BereanResearchReport.

import SwiftUI

// MARK: - BereanResearchReportCard

struct BereanResearchReportCard: View {
    let report: BereanResearchReport

    @State private var isExpanded: Bool = false

    // MARK: Formatters

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(16)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)
                expandedContent
                    .padding(16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Research report: \(report.query)")
        .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")
    }

    // MARK: Header

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                modeBadge
                Spacer()
                chevron
            }

            Text(report.query)
                .font(.headline)
                .lineLimit(2)
                .foregroundStyle(.primary)

            confidenceBar

            if let completed = report.completedAt {
                Text(Self.dateFormatter.string(from: completed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Mode Badge (pill)

    private var modeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: report.researchMode.systemIcon)
                .font(.system(size: 11, weight: .semibold))
            Text(report.researchMode.displayName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(modeColor, in: Capsule())
    }

    private var modeColor: Color {
        switch report.researchMode {
        case .quick:      return Color.blue
        case .deep:       return Color.indigo
        case .academic:   return Color(red: 0.4, green: 0.2, blue: 0.8)
        case .biblical:   return Color(red: 0.6, green: 0.3, blue: 0.1)
        case .market:     return Color.green
        case .community:  return Color.teal
        case .multiAgent: return Color(red: 0.2, green: 0.2, blue: 0.6)
        }
    }

    // MARK: Confidence bar

    private var confidenceBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Confidence")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(report.confidenceScore * 100))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(confidenceColor)
                        .frame(width: geo.size.width * CGFloat(report.confidenceScore), height: 6)
                }
            }
            .frame(height: 6)
        }
        .accessibilityLabel("Confidence: \(Int(report.confidenceScore * 100)) percent")
    }

    private var confidenceColor: Color {
        switch report.confidenceScore {
        case 0.75...: return Color.green
        case 0.5..<0.75: return Color.orange
        default: return Color.red
        }
    }

    // MARK: Chevron

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
            .animation(.spring(response: 0.3), value: isExpanded)
    }

    // MARK: Expanded content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !report.executiveSummary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Summary", systemImage: "doc.text.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(report.executiveSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !report.keyFindings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Key Findings", systemImage: "list.bullet.clipboard.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    ForEach(Array(report.keyFindings.prefix(3).enumerated()), id: \.element.id) { index, finding in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(index + 1).")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .leading)
                            Text(finding.content)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            BereanConfidenceBadge(level: finding.confidence, compact: true)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            BereanResearchReportCard(
                report: BereanResearchReport(
                    id: "preview-1",
                    projectId: nil,
                    ownerUid: "uid-123",
                    query: "What are the most effective church growth strategies for urban communities?",
                    researchMode: .deep,
                    status: .complete,
                    executiveSummary: "Urban church growth hinges on community engagement, authentic discipleship, and leveraging local networks.",
                    keyFindings: [
                        BereanResearchFinding(
                            id: "f1",
                            content: "Relational evangelism is 3x more effective than event-based outreach.",
                            confidence: .certain,
                            sourceIds: []
                        ),
                        BereanResearchFinding(
                            id: "f2",
                            content: "Small groups increase retention by up to 60%.",
                            confidence: .probable,
                            sourceIds: []
                        ),
                    ],
                    supportingEvidence: [],
                    counterarguments: [],
                    openQuestions: [],
                    confidenceScore: 0.82,
                    sources: [],
                    actionableRecommendations: [],
                    createdAt: Date(),
                    completedAt: Date()
                )
            )
        }
        .padding()
    }
    .background(Color(UIColor.systemGroupedBackground))
}
