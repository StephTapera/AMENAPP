import SwiftUI

struct CreatorExportSheet: View {
    let presets: [CreatorExportPreset]

    var body: some View {
        VStack(spacing: 12) {
            CreatorTopBar(title: "Export", subtitle: "Choose a format")

            ForEach(presets) { preset in
                CreatorGlassCard {
                    Text(preset.title)
                        .font(AMENFont.semiBold(14))
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
    }
}
