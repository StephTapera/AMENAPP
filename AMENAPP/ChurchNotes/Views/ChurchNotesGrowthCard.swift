import SwiftUI

struct ChurchNotesGrowthCard: View {
    @Binding var actionStep: String
    @Binding var prayer: String
    @Binding var revisitMidweek: Bool
    @Binding var isExpanded: Bool
    let onChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(ChurchNotesAnimationTokens.sectionExpand) { isExpanded.toggle() }
            } label: {
                HStack {
                    Label("Personal Growth", systemImage: "leaf.fill")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Action step this week", text: $actionStep, axis: .vertical)
                        .onChange(of: actionStep) { _, _ in onChanged() }
                    TextField("Prayer from sermon", text: $prayer, axis: .vertical)
                        .onChange(of: prayer) { _, _ in onChanged() }
                    Toggle("Revisit this note midweek", isOn: $revisitMidweek)
                        .onChange(of: revisitMidweek) { _, _ in onChanged() }
                }
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(16)
        .churchNotesGlassCard()
    }
}
