import SwiftUI

struct FeedConflictResolutionOption: Identifiable {
    let id = UUID()
    let label: String
    let description: String
    let resolvedDraft: FeedDirectionDraft
}

struct FeedConflictResolutionSheet: View {
    let conflictDescription: String
    let options: [FeedConflictResolutionOption]
    let onSelect: (FeedDirectionDraft) -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("We noticed a conflict")
                        .font(.title3.bold())
                    Text(conflictDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                ForEach(options) { option in
                    Button {
                        onSelect(option.resolvedDraft)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.label).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(option.description).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Resolve conflict")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss(); dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
