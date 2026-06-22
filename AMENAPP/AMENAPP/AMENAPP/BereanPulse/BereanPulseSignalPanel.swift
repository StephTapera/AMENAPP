import SwiftUI

struct BereanPulseSignalPanel: View {
    let signals: [BereanPulseSignal]
    @Binding var isCollapsed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var visibleSignals: [BereanPulseSignal] {
        signals.filter(\.isUserVisible)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerButton
            expandedContent
        }
        .background(surfaceBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }

    private var headerButton: some View {
        Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.34, dampingFraction: 0.88)) {
                isCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Signals Berean used"))
                            .font(.subheadline.weight(.semibold))
                        Text(String(localized: "Visible context behind today’s cards"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "sparkles")
                        .font(.systemScaled(15, weight: .semibold))
                }
                .foregroundStyle(.primary)

                Spacer()

                Text("\(visibleSignals.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary))

                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Signals Berean used"))
        .accessibilityValue(Text(isCollapsed ? "Collapsed" : "Expanded"))
        .accessibilityHint(Text("Shows the visible signals that informed today's cards."))
    }

    @ViewBuilder
    private var expandedContent: some View {
        if !isCollapsed {
            if visibleSignals.isEmpty {
                emptySignalsView
            } else {
                signalScrollView
            }
        }
    }

    private var emptySignalsView: some View {
        Text(String(localized: "No visible signals are attached to the current Pulse."))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var signalScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleSignals) { signal in
                    BereanPulseSignalChip(signal: signal)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var surfaceBackground: AnyShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.regularMaterial)
    }
}

private struct BereanPulseSignalChip: View {
    let signal: BereanPulseSignal

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(signal.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text(signal.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 220, alignment: .leading)
        .frame(minHeight: 44)
        .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.75))
        .accessibilityElement(children: .combine)
    }
}
