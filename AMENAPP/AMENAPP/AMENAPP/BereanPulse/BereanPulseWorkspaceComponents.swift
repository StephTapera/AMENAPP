import SwiftUI

struct BereanPulseWorkspaceSection<Content: View>: View {
    let title: String
    let subtitle: String?
    let actionTitle: String?
    let action: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                        .frame(minHeight: 44)
                        .accessibilityHint(Text("Opens controls for this section."))
                }
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BereanPulseTrustPill: View {
    let icon: String
    let title: String
    let value: String
    var isEmphasized = false

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isEmphasized ? Color.white : Color.primary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isEmphasized ? Color.white.opacity(0.82) : Color.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isEmphasized ? Color.white : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(minHeight: 44)
        .background(
            Capsule(style: .continuous)
                .fill(isEmphasized ? Color.primary : Color.white.opacity(0.78))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isEmphasized ? Color.primary.opacity(0.2) : Color.black.opacity(contrast == .increased ? 0.18 : 0.08), lineWidth: contrast == .increased ? 1 : 0.75)
                )
        )
        .accessibilityElement(children: .combine)
    }
}

struct BereanPulseStatusBanner: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.05), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .frame(minHeight: 44)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.75)
        )
        .accessibilityElement(children: .combine)
    }
}

struct BereanPulseSmartComposerDock: View {
    let prompt: String
    let canAskBerean: Bool
    let disabledReason: String
    let onAskBerean: () -> Void
    let onCurate: () -> Void
    let onRefresh: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onCurate) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(BereanPulseGlassIconButtonStyle())
            .accessibilityLabel(Text("Curate Berean Pulse"))

            Button(action: onAskBerean) {
                HStack(spacing: 8) {
                    Image(systemName: canAskBerean ? "sparkles" : "lock")
                        .font(.system(size: 14, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(prompt)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canAskBerean ? .primary : .secondary)
            .disabled(!canAskBerean)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(reduceTransparency ? 0.96 : 0.78))
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.black.opacity(contrast == .increased ? 0.18 : 0.08), lineWidth: contrast == .increased ? 1 : 0.75))
            )
            .accessibilityLabel(Text(prompt))
            .accessibilityHint(Text(canAskBerean ? "Starts a Berean chat from the highest priority card." : disabledReason))

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(BereanPulseGlassIconButtonStyle())
            .accessibilityLabel(Text("Refresh Berean Pulse"))
        }
        .padding(8)
        .background(dockBackground, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.black.opacity(contrast == .increased ? 0.22 : 0.10), lineWidth: contrast == .increased ? 1 : 0.75))
        .shadow(color: .black.opacity(reduceTransparency ? 0.06 : 0.12), radius: 18, y: 8)
        .scaleEffect(reduceMotion ? 1 : 0.995)
    }

    private var dockBackground: AnyShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color(.systemBackground).opacity(0.98)) : AnyShapeStyle(.ultraThinMaterial)
    }
}

struct BereanPulseMiniWorkCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(actionTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.top, 2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

struct BereanPulseActionChip: View {
    let title: String
    let systemImage: String?
    let action: () -> Void
    var isPrimary = false
    var isDisabled = false
    var disabledReason: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .foregroundStyle(isPrimary ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(isPrimary ? Color.primary : Color.white.opacity(0.78))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(isPrimary ? Color.primary.opacity(0.2) : Color.black.opacity(contrast == .increased ? 0.18 : 0.08), lineWidth: contrast == .increased ? 1 : 0.75)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .scaleEffect(isDisabled || reduceMotion ? 1 : 0.998)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(isDisabled ? (disabledReason ?? "This action is unavailable until required context is present.") : "Runs this Berean action."))
    }
}

struct BereanPulseGlassIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(Color.white.opacity(reduceTransparency ? 0.98 : 0.80), in: Circle())
            .overlay(Circle().strokeBorder(Color.black.opacity(contrast == .increased ? 0.20 : 0.08), lineWidth: contrast == .increased ? 1 : 0.75))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
    }
}
