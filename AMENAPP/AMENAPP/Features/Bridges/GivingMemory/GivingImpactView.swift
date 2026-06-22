// GivingImpactView.swift
// AMEN — Features/Bridges/GivingMemory
//
// Year-end giving impact view with PDF tax statement export.
// Gated behind .givingPortfolio (premium tier).

import SwiftUI
import PDFKit

enum GateFeature {
    case givingPortfolio
    case matchFeedbackExplained
}

private extension View {
    func upsellSurface() -> some View {
        self
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding()
    }
}

struct GateView<Content: View, Locked: View>: View {
    let feature: GateFeature
    @ViewBuilder let content: () -> Content
    @ViewBuilder let locked: (GateFeature) -> Locked

    init(
        _ feature: GateFeature,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder locked: @escaping (GateFeature) -> Locked
    ) {
        self.feature = feature
        self.content = content
        self.locked = locked
    }

    var body: some View {
        if isUnlocked {
            content()
        } else {
            locked(feature)
        }
    }

    private var isUnlocked: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

struct GivingImpactView: View {
    let year: Int
    @State private var summary: GivingSummary?
    @State private var showingPDF = false
    @State private var pdfData: Data?

    var body: some View {
        GateView(.givingPortfolio) {
            content
        } locked: { _ in
            VStack(spacing: 16) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Year-End Impact Report")
                    .font(.headline)
                Text("Upgrade to see your full giving history, cause breakdown, and download a tax statement.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .upsellSurface()
        }
        .task {
            summary = await GivingMemoryService.shared.fetchSummary(year: year)
        }
    }

    // MARK: - Entitled content

    @ViewBuilder
    private var content: some View {
        if let summary {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(year) Impact")
                            .font(.largeTitle.bold())
                        Text("\(summary.formattedTotal) across \(summary.giftCount) gift\(summary.giftCount == 1 ? "" : "s")")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    // Cause breakdown
                    if !summary.causeNames.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Causes Supported")
                                .font(.headline)
                            ForEach(summary.causeNames, id: \.self) { name in
                                Label(name, systemImage: "heart.fill")
                                    .font(.body)
                            }
                        }
                    }

                    // PDF export
                    Button(action: generateAndShowPDF) {
                        Label("Download Tax Statement", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .sheet(isPresented: $showingPDF) {
                if let data = pdfData {
                    NavigationStack {
                        PDFKitView(data: data)
                            .navigationTitle("Tax Statement")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { showingPDF = false }
                                }
                            }
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "No giving recorded for \(year)",
                systemImage: "gift",
                description: Text("Giving you record this year will appear here.")
            )
        }
    }

    // MARK: - PDF generation

    private func generateAndShowPDF() {
        guard let summary else { return }
        pdfData = GivingTaxStatementRenderer().render(summary: summary)
        showingPDF = pdfData != nil
    }
}

// MARK: - PDFKitView (SwiftUI wrapper)

private struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

// MARK: - GivingTaxStatementRenderer

/// PDFKit renderer for an itemized tax statement.
struct GivingTaxStatementRenderer {

    func render(summary: GivingSummary) -> Data? {
        let pdfMetaData: [CFString: Any] = [
            kCGPDFContextCreator: "AMEN App",
            kCGPDFContextTitle: "\(summary.year) Giving Summary"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        return renderer.pdfData { ctx in
            ctx.beginPage()

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.label
            ]
            NSAttributedString(string: "\(summary.year) Giving Summary", attributes: titleAttrs)
                .draw(at: CGPoint(x: 72, y: 72))

            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.label
            ]

            var lines: [String] = [
                "Total Given: \(summary.formattedTotal)",
                "Number of Gifts: \(summary.giftCount)",
                ""
            ]

            if !summary.causeNames.isEmpty {
                lines.append("Causes Supported:")
                lines += summary.causeNames.map { "  \u{2022} \($0)" }
            }

            let disclaimer = "\nThis document is provided for your records. Please consult a tax professional for deductibility guidance."
            lines.append(disclaimer)

            var y: CGFloat = 120
            for line in lines {
                NSAttributedString(string: line, attributes: bodyAttrs)
                    .draw(at: CGPoint(x: 72, y: y))
                y += 20
            }
        }
    }
}
