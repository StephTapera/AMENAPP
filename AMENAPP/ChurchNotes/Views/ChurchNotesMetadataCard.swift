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
                VStack(spacing: 8) {
                    TextField("Church", text: $metadata.churchName)
                        .font(.systemScaled(15, weight: .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.50)))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.75))
                        )
                        .onChange(of: metadata.churchName) { _, _ in onChanged() }

                    TextField("Pastor", text: $metadata.pastorName)
                        .font(.systemScaled(15, weight: .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.50)))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.75))
                        )
                        .onChange(of: metadata.pastorName) { _, _ in onChanged() }

                    DatePicker("Date", selection: $metadata.serviceDate, displayedComponents: .date)
                        .font(.systemScaled(15, weight: .regular))
                        .onChange(of: metadata.serviceDate) { _, _ in onChanged() }
                }
            }
        }
        .padding(16)
        .churchNotesGlassCard()
    }
}
