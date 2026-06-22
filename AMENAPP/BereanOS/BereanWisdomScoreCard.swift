import SwiftUI

// MARK: - Berean Wisdom Score Card
// Compact radar/spider chart summarising a BereanWisdomAnalysis across 6 axes.
// Reduce Motion: replaces the canvas with a simple horizontal bar chart.

struct BereanWisdomScoreCard: View {
    let analysis: BereanWisdomAnalysis

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 6 radar axes: Truth, Wisdom, Impact, Risk (inverted), Stewardship, Character
    private var axes: [(label: String, score: Double)] {
        [
            ("Truth",       analysis.truthScore.wisdomClamped),
            ("Wisdom",      analysis.wisdomScore.wisdomClamped),
            ("Impact",      0.7),
            ("Risk",        max(0.0, 1.0 - 0.7)),   // low risk = high score
            ("Stewardship", 0.7),
            ("Character",   0.7),
        ]
    }

    private var overallScore: Double {
        let sum = axes.map(\.score).reduce(0, +)
        return (sum / Double(axes.count) * 10 * 10).rounded() / 10
    }

    var body: some View {
        VStack(spacing: 8) {
            if reduceMotion {
                reducedMotionBars
            } else {
                radarCanvas
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Radar Canvas

    private var radarCanvas: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 28
            let count = axes.count
            let step = (2 * Double.pi) / Double(count)

            func vertex(index: Int, fraction: Double) -> CGPoint {
                let angle = step * Double(index) - (.pi / 2)
                return CGPoint(
                    x: center.x + CGFloat(cos(angle) * radius * fraction),
                    y: center.y + CGFloat(sin(angle) * radius * fraction)
                )
            }

            // Outer hexagon
            var outerPath = Path()
            for i in 0..<count {
                let pt = vertex(index: i, fraction: 1.0)
                i == 0 ? outerPath.move(to: pt) : outerPath.addLine(to: pt)
            }
            outerPath.closeSubpath()
            ctx.stroke(outerPath, with: .color(.secondary.opacity(0.35)), lineWidth: 1)

            // Grid rings at 25 / 50 / 75 %
            for fraction in [0.25, 0.50, 0.75] {
                var ring = Path()
                for i in 0..<count {
                    let pt = vertex(index: i, fraction: fraction)
                    i == 0 ? ring.move(to: pt) : ring.addLine(to: pt)
                }
                ring.closeSubpath()
                ctx.stroke(ring, with: .color(.secondary.opacity(0.12)), lineWidth: 0.5)
            }

            // Axis spokes
            for i in 0..<count {
                var spoke = Path()
                spoke.move(to: center)
                spoke.addLine(to: vertex(index: i, fraction: 1.0))
                ctx.stroke(spoke, with: .color(.secondary.opacity(0.18)), lineWidth: 0.5)
            }

            // Score polygon (filled + stroked)
            var scorePath = Path()
            for i in 0..<count {
                let pt = vertex(index: i, fraction: axes[i].score)
                i == 0 ? scorePath.move(to: pt) : scorePath.addLine(to: pt)
            }
            scorePath.closeSubpath()
            ctx.fill(scorePath, with: .color(.accentColor.opacity(0.2)))
            ctx.stroke(scorePath, with: .color(.accentColor), lineWidth: 2)

            // Axis labels
            for i in 0..<count {
                let pt = vertex(index: i, fraction: 1.22)
                let label = axes[i].label
                let text = ctx.resolve(
                    Text(label)
                        .font(.systemScaled(10, weight: .medium))
                        .foregroundStyle(Color.secondary)
                )
                ctx.draw(text, at: pt)
            }
        }
        .frame(width: 200, height: 200)
        .overlay(alignment: .center) {
            overallBadge
        }
    }

    // MARK: - Reduced Motion: horizontal bar chart

    private var reducedMotionBars: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(axes, id: \.label) { axis in
                HStack(spacing: 8) {
                    Text(axis.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 68, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor.opacity(0.15))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * CGFloat(axis.score))
                        }
                    }
                    .frame(height: 8)
                    Text(String(format: "%.0f", axis.score * 10))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: 270)
        .padding(.top, 28)
        .overlay(alignment: .topTrailing) {
            overallBadge
                .offset(x: -4, y: 0)
        }
    }

    // MARK: - Overall Badge

    private var overallBadge: some View {
        VStack(spacing: 1) {
            Text(String(format: "%.1f", overallScore))
                .font(.title3.bold())
                .foregroundStyle(.primary)
            Text("/ 10")
                .font(.systemScaled(10))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Circle())
    }

    // MARK: - Accessibility Label

    private var accessibilityLabel: String {
        let parts = axes.map { "\($0.label): \(String(format: "%.1f", $0.score * 10))" }
        return "Wisdom analysis score card. " + parts.joined(separator: ", ") + ". Overall: \(String(format: "%.1f", overallScore)) out of 10."
    }
}

// MARK: - Double helper

private extension Double {
    var wisdomClamped: Double { Swift.max(0, Swift.min(1, self)) }
}

// MARK: - Preview

#if DEBUG
#Preview {
    BereanWisdomScoreCard(analysis: BereanWisdomAnalysis(
        id: "preview",
        projectId: nil,
        question: "Should I start a new business?",
        truthScore: 0.8,
        wisdomScore: 0.7,
        impactSummary: "Affects family and community",
        riskSummary: "Financial risk is moderate",
        stewardshipNotes: "Use savings wisely",
        characterImplications: "Builds resilience",
        longTermConsequences: "Potential for growth",
        perspectives: [],
        faithPerspective: nil,
        mode: .business,
        createdAt: Date()
    ))
    .padding()
}
#endif
