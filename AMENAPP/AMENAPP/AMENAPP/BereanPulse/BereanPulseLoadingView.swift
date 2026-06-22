import SwiftUI

struct BereanPulseLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.primary)
                .accessibilityHidden(true)

            Text(String(localized: "Preparing Berean Pulse"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(String(localized: "Berean is checking visible context, permissions, and ranked next steps."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 220)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Preparing Berean Pulse. Berean is checking visible context, permissions, and ranked next steps."))
    }
}
