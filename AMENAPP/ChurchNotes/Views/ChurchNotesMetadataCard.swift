import SwiftUI

struct ChurchNotesMetadataCard: View {
    @Binding var metadata: ChurchNoteMetadata
    @Binding var isExpanded: Bool
    var summary: String
    var onChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(ChurchNotesAnimationTokens.sectionExpand) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(summary.isEmpty ? "Sermon Details" : summary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 10) {
                    TextField("Church", text: $metadata.churchName)
                        .onChange(of: metadata.churchName) { _, _ in onChanged() }
                    TextField("Pastor", text: $metadata.pastorName)
                        .onChange(of: metadata.pastorName) { _, _ in onChanged() }
                    DatePicker("Date", selection: $metadata.serviceDate, displayedComponents: .date)
                        .onChange(of: metadata.serviceDate) { _, _ in onChanged() }
                }
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(16)
        .churchNotesGlassCard()
    }
}
