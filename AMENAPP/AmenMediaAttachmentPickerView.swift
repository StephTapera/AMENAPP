import SwiftUI

struct AmenMediaAttachmentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedProvider: AmenAttachmentProvider = .appleMusic
    @State private var isLoading = false
    @State private var results: [AmenSmartAttachment] = []
    let onSelect: (AmenSmartAttachment) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Provider", selection: $selectedProvider) {
                    Text("Apple Music").tag(AmenAttachmentProvider.appleMusic)
                    Text("Spotify").tag(AmenAttachmentProvider.spotify)
                    Text("Paste Link").tag(AmenAttachmentProvider.generic)
                }
                .pickerStyle(.segmented)

                TextField("Search or paste a link", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await search() } }

                if isLoading {
                    ProgressView()
                }

                List(results, id: \.id) { attachment in
                    Button {
                        onSelect(attachment)
                        dismiss()
                    } label: {
                        AmenSmartAttachmentCard(attachment: attachment, smartAction: nil, onTap: {})
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .padding()
            .navigationTitle("Add Music / Link")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if let url = URL(string: trimmed), url.scheme?.lowercased() == "https" {
                let attachment = try await AmenSmartAttachmentResolverService.shared.resolve(url: url, source: "musicPicker")
                results = [attachment]
            } else {
                results = []
            }
        } catch {
            results = []
        }
    }
}
