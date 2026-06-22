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
                        .font(.systemScaled(13, weight: .medium))
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
                VStack(alignment: .leading, spacing: 10) {
                    labeledField(
                        title: "Church",
                        icon: "building.2",
                        placeholder: "Search churches by name, city, or denomination",
                        text: $metadata.churchName
                    )
                    .onChange(of: metadata.churchName) { _, _ in onChanged() }

                    labeledField(
                        title: "Pastor",
                        icon: "person",
                        placeholder: "Pastor or speaker",
                        text: $metadata.pastorName
                    )
                    .onChange(of: metadata.pastorName) { _, _ in onChanged() }

                    DatePicker("Date", selection: $metadata.serviceDate, displayedComponents: .date)
                        .onChange(of: metadata.serviceDate) { _, _ in onChanged() }
                }
            }
        }
        .padding(16)
        .churchNotesGlassCard()
    }

    private func labeledField(title: String, icon: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(12)
                .background(
                    Color(.secondarySystemGroupedBackground).opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
    }
}
