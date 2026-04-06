import SwiftUI

struct CreatorLayerInspectorView: View {
    let layers: [CreatorLayer]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(layers) { layer in
                CreatorInspectorSection(title: layer.kind.rawValue.capitalized) {
                    Text(layer.payloadRef ?? "No payload")
                        .font(AMENFont.medium(12))
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
    }
}
