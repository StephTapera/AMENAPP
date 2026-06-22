import SwiftUI

struct AmenUniversalLinkDetailView: View {
    let attachment: AmenSmartAttachment
    let postText: String
    let onOpenOriginal: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showMentionedLinks = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AmenUniversalLinkCard(attachment: attachment, mode: .expandedDetail, onTap: nil)
                    if let description = attachment.description, !description.isEmpty {
                        Text(description)
                            .font(.systemScaled(14))
                            .foregroundStyle(.secondary)
                    }
                    if let transcriptStatus = attachment.transcriptStatus {
                        Text("Transcript: \(transcriptStatus)")
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                    }
                    if let aiContextStatus = attachment.aiContextStatus {
                        Text("AI context: \(aiContextStatus)")
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                    }
                    Button("Open Original", action: onOpenOriginal)
                        .buttonStyle(.borderedProminent)
                    if let links = attachment.extractedLinks, !links.isEmpty {
                        Button("View Mentioned Links (\(links.count))") {
                            showMentionedLinks = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Link Detail")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showMentionedLinks) {
                AmenMentionedLinksTray(links: attachment.extractedLinks ?? [])
                    .presentationDetents([.medium, .large])
            }
        }
    }
}
