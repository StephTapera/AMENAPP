import SwiftUI

struct CreatorTemplatePickerView: View {
    let templates: [CreatorTemplate]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(templates) { template in
                    CreatorGlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(template.title)
                                .font(AMENFont.semiBold(15))
                            if let subtitle = template.subtitle {
                                Text(subtitle)
                                    .font(AMENFont.medium(12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
    }
}
