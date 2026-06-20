import SwiftUI

private enum AmenConnectReadinessGlassKitTokens {
    static let amenGold = Color(red: 198 / 255, green: 151 / 255, blue: 63 / 255)
    static let amenPurple = Color(red: 104 / 255, green: 74 / 255, blue: 190 / 255)
    static let amenBlue = Color(red: 43 / 255, green: 124 / 255, blue: 221 / 255)
}

struct AmenConnectReadinessPillGate: View {
    @ObservedObject private var flags = AMENFeatureFlags.shared
    let readiness: AmenConnectReadinessView
    let label: String

    var body: some View {
        if flags.amenConnectEnabled && flags.readinessPillEnabled {
            AmenConnectReadinessPill(readiness: readiness, label: label)
        }
    }
}

struct AmenConnectReadinessPill: View {
    let readiness: AmenConnectReadinessView
    let label: String

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: AmenConnectReadinessPillModel {
        AmenConnectReadinessService().makePillModel(label: label, readinessView: readiness)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: statusSymbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(statusTint)

                    Text(summaryText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AmenConnectReadinessGlassKitTokens.amenPurple)
                }
                .padding(.horizontal, 13)
                .frame(minHeight: 44)
                .amenLiquidGlassCapsuleSurface(isSelected: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)

            if isExpanded {
                readinessBreakdown
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var readinessBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(readiness.teamCoverage) { team in
                HStack(spacing: 8) {
                    Text(team.teamName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Self.percentText(team.coverage))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(team.coverage >= 1 ? AmenConnectReadinessGlassKitTokens.amenBlue : AmenConnectReadinessGlassKitTokens.amenGold)
                }
            }

            if let gap = model.worstOpenGap {
                Label("\(gap.displayName) needs \(gap.openCount)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenConnectReadinessGlassKitTokens.amenGold)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AmenConnectReadinessGlassKitTokens.amenBlue.opacity(0.18), lineWidth: 1)
        }
    }

    private var summaryText: String {
        if let gap = model.worstOpenGap {
            return "\(model.label) · \(Self.percentText(model.coverage)) ready · \(gap.teamName)"
        }
        return "\(model.label) · \(Self.percentText(model.coverage)) ready"
    }

    private var statusSymbol: String {
        model.worstOpenGap == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var statusTint: Color {
        model.worstOpenGap == nil ? AmenConnectReadinessGlassKitTokens.amenBlue : AmenConnectReadinessGlassKitTokens.amenGold
    }

    private var accessibilityLabel: String {
        if let gap = model.worstOpenGap {
            return "\(model.label), \(Self.percentText(model.coverage)) ready, open gap: \(gap.displayName), needs \(gap.openCount)"
        }
        return "\(model.label), \(Self.percentText(model.coverage)) ready, no open gaps"
    }

    private static func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
