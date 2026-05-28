import SwiftUI

struct AmenDesignStudioView: View {
    private let templates = [
        DesignTemplate(id: "quote-card", name: "Quote Card", symbol: "quote.opening"),
        DesignTemplate(id: "announcement", name: "Announcement", symbol: "megaphone"),
        DesignTemplate(id: "carousel-slide", name: "Carousel Slide", symbol: "rectangle.on.rectangle"),
        DesignTemplate(id: "reflection-card", name: "Reflection", symbol: "sparkles")
    ]

    @State private var selectedTemplateId = "quote-card"
    @State private var title = "Untitled design"
    @State private var primaryText = ""
    @State private var accentColor = Color.accentColor
    @State private var savedDesignId: String?
    @State private var isSaving = false
    @State private var isExporting = false
    @State private var statusMessage = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                templatePicker
                editor
                preview
                saveControls
                statusSection
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
        .navigationTitle("Design Studio")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Template")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                ForEach(templates) { template in
                    Button {
                        selectedTemplateId = template.id
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: template.symbol)
                            Text(template.name)
                                .lineLimit(1)
                        }
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedTemplateId == template.id ? .accentColor : .secondary)
                    .accessibilityLabel("Choose \(template.name) template")
                }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Content")
                .font(.headline)
            TextField("Design title", text: $title)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Design title")
            TextEditor(text: $primaryText)
                .frame(minHeight: 120)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Design text")
            ColorPicker("Accent", selection: $accentColor, supportsOpacity: false)
                .accessibilityLabel("Design accent color")
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.headline)
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accentColor.opacity(0.45), lineWidth: 2)
                VStack(alignment: .leading, spacing: 10) {
                    Text(title.isEmpty ? "Untitled design" : title)
                        .font(.title2.weight(.semibold))
                    Text(primaryText.isEmpty ? "Add text to preview the design." : primaryText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(22)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Design preview")
        }
    }

    private var saveControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await saveProject() }
            } label: {
                Label(isSaving ? "Saving" : "Save Project", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Save design project")

            Button {
                Task { await exportImage() }
            } label: {
                Label(isExporting ? "Exporting" : "Export Image", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(isExporting || primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Export design image")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
        } else if !statusMessage.isEmpty {
            Text(statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func saveProject() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let designId = try await AmenUniversalContentService.shared.saveDesignProject(
                designId: savedDesignId,
                title: title,
                templateId: selectedTemplateId,
                payload: [
                    "primaryText": primaryText,
                    "templateId": selectedTemplateId
                ]
            )
            savedDesignId = designId
            statusMessage = "Design saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportImage() async {
        errorMessage = nil
        isExporting = true
        defer { isExporting = false }
        do {
            let designId = try await ensureSavedDesign()
            _ = try await AmenDesignExportService.exportPNG(
                designId: designId,
                title: title,
                text: primaryText,
                accentColor: accentColor
            )
            statusMessage = "Design image exported."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ensureSavedDesign() async throws -> String {
        if let savedDesignId {
            return savedDesignId
        }
        let designId = try await AmenUniversalContentService.shared.saveDesignProject(
            title: title,
            templateId: selectedTemplateId,
            payload: [
                "primaryText": primaryText,
                "templateId": selectedTemplateId
            ]
        )
        savedDesignId = designId
        return designId
    }
}

private struct DesignTemplate: Identifiable {
    let id: String
    let name: String
    let symbol: String
}
