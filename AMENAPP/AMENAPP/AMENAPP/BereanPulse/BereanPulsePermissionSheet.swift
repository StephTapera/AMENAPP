import SwiftUI

struct BereanPulsePermissionSheet: View {
    let context: BereanPulsePermissionPromptContext
    let onAllow: () -> Void
    let onNotNow: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "Context request"), systemImage: "lock.shield")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(context.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(context.explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    permissionPrinciple(String(localized: "Asked only when this card action needs it"), icon: "checkmark.shield")
                    permissionPrinciple(String(localized: "Pulse stays usable if you decline"), icon: "eye.slash")
                    permissionPrinciple(String(localized: "You can change this later in Curate"), icon: "slider.horizontal.3")
                }
                .padding(14)
                .background(surfaceBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.75))

                Spacer(minLength: 0)

                Button(action: onAllow) {
                    Text(String(localized: "Allow access"))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Allows this source for the requested Berean Pulse action."))

                Button(action: onNotNow) {
                    Text(String(localized: "Not now"))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Closes this request and keeps Berean Pulse usable."))
            }
            .padding(22)
            .background(Color(red: 0.985, green: 0.985, blue: 0.975).ignoresSafeArea())
        }
        .presentationDetents([.medium, .large])
    }

    private func permissionPrinciple(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }

    private var surfaceBackground: AnyShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.regularMaterial)
    }
}
