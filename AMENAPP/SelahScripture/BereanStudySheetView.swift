//
//  BereanStudySheetView.swift
//  AMENAPP
//
//  The 4-layer Berean study sheet. Presented as a sheet from the Selah Lens
//  "Understand" action. Loads on appear if not already cached in the ViewModel.
//
//  Design rules:
//  - Sheet background: .regularMaterial (glass for chrome only)
//  - Scripture text is NEVER behind glass — the verse header is rendered matte
//    in a solid, opaque container.
//  - Each layer is a DisclosureGroup in a ScrollView.
//  - Key terms open popovers with their note.
//  - Cross-reference chips call onCrossRefTapped so the reader navigates.
//  - AI provenance footer with transparent labeling.
//

import SwiftUI

// MARK: - BereanStudySheetView

struct BereanStudySheetView: View {

    // MARK: Inputs

    let verseId: String
    let verseText: String
    let translation: SelahTranslation

    @ObservedObject var viewModel: SelahLensViewModel

    let onCrossRefTapped: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: Section expansion state

    @State private var textExpanded:           Bool = true
    @State private var contextExpanded:        Bool = false
    @State private var interpretExpanded:      Bool = false
    @State private var applicationExpanded:    Bool = false

    // MARK: Popover state

    @State private var selectedKeyTerm: BereanKeyTerm?

    // MARK: Body

    var body: some View {
        ZStack(alignment: .top) {
            // Sheet background — glass is fine for chrome, NOT behind scripture.
            Color.clear
                .background(.regularMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                dragIndicator
                sheetHeader

                Group {
                    if viewModel.studySheetLoading {
                        shimmerSkeleton
                    } else if let sheet = viewModel.studySheet {
                        layerScroll(sheet: sheet)
                    } else if let error = viewModel.studySheetError {
                        errorView(message: error)
                    } else {
                        // Should not normally be reached — onAppear fires the load.
                        Color.clear.frame(height: 1)
                    }
                }
            }
        }
        .onAppear {
            if viewModel.studySheet == nil && !viewModel.studySheetLoading {
                Task {
                    await viewModel.loadStudySheet(
                        verseId: verseId,
                        translation: translation,
                        verseText: verseText
                    )
                }
            }
        }
        .popover(item: $selectedKeyTerm) { term in
            KeyTermPopover(term: term)
        }
    }

    // MARK: - Drag Indicator

    private var dragIndicator: some View {
        Capsule()
            .fill(Color(UIColor.quaternaryLabel))
            .frame(width: 36, height: 4)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    // MARK: - Sheet Header (matte — no glass behind text)

    private var sheetHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(referenceDisplayString)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.amenBlack)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close study sheet")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        // Solid background — scripture reference is matte, never glassed.
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Reference Display

    private var referenceDisplayString: String {
        // verseId is assumed to be "book.chapter.verse" e.g. "john.3.16"
        let parts = verseId.split(separator: ".")
        if parts.count >= 3,
           let chapter = parts[safe: 1],
           let verse   = parts[safe: 2] {
            let bookName = parts[0].capitalized
            return "\(bookName) \(chapter):\(verse) (\(translation.rawValue))"
        }
        return "\(verseId) (\(translation.rawValue))"
    }

    // MARK: - Shimmer Skeleton

    private var shimmerSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    SheetShimmerLine(widthFraction: 0.35)
                    SheetShimmerLine(widthFraction: 0.85)
                    SheetShimmerLine(widthFraction: 0.70)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - Layer Scroll

    private func layerScroll(sheet: BereanStudySheetResponse) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                textLayerSection(sheet.layers.text)
                Divider().padding(.horizontal, 20)
                contextLayerSection(sheet.layers.context)
                Divider().padding(.horizontal, 20)
                interpretationLayerSection(sheet.layers.interpretation)
                Divider().padding(.horizontal, 20)
                applicationLayerSection(sheet.layers.application)
                Divider().padding(.horizontal, 20)
                crossReferencesSection(refs: sheet.crossReferences)
                Divider().padding(.horizontal, 20)
                provenanceFooter(provenance: sheet.provenance, promptVersion: sheet.promptVersion)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Section 1: Text

    private func textLayerSection(_ layer: BereanStudySheetTextLayer) -> some View {
        DisclosureGroup(isExpanded: $textExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if !layer.observations.isEmpty {
                    SectionSubheading("Observations")
                    BulletList(items: layer.observations)
                }
                if !layer.keyTerms.isEmpty {
                    SectionSubheading("Key Terms")
                    SelahChipFlowLayout(spacing: 8) {
                        ForEach(layer.keyTerms) { term in
                            Button {
                                selectedKeyTerm = term
                            } label: {
                                Text(term.term)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.amenBlue)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.amenBlue.opacity(0.10), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !layer.uncertaintyNotes.isEmpty {
                    SectionSubheading("Uncertainty Notes")
                    ForEach(layer.uncertaintyNotes, id: \.self) { note in
                        Text(note)
                            .font(.footnote)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 12)
        } label: {
            SectionLabel(title: "Text", icon: "text.alignleft")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .accessibilityIdentifier("studySheet.textSection")
    }

    // MARK: - Section 2: Context

    private func contextLayerSection(_ layer: BereanStudySheetContextLayer) -> some View {
        DisclosureGroup(isExpanded: $contextExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if !layer.historicalNotes.isEmpty {
                    SectionSubheading("Historical")
                    BulletList(items: layer.historicalNotes)
                }
                if !layer.literaryNotes.isEmpty {
                    SectionSubheading("Literary")
                    BulletList(items: layer.literaryNotes)
                }
                if !layer.canonicalLinks.isEmpty {
                    SectionSubheading("Canonical Links")
                    BulletList(items: layer.canonicalLinks)
                }
            }
            .padding(.vertical, 12)
        } label: {
            SectionLabel(title: "Context", icon: "clock.arrow.circlepath")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .accessibilityIdentifier("studySheet.contextSection")
    }

    // MARK: - Section 3: Interpretation

    private func interpretationLayerSection(_ layer: BereanStudySheetInterpretationLayer) -> some View {
        DisclosureGroup(isExpanded: $interpretExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text(layer.summary)
                    .font(.body)
                    .foregroundStyle(.primary)

                if !layer.interpretiveOptions.isEmpty {
                    SectionSubheading("Interpretive Options")
                    ForEach(layer.interpretiveOptions) { option in
                        InterpretiveOptionRow(option: option)
                    }
                }

                if !layer.denominationalPosture.isEmpty {
                    SectionSubheading("Denominational Posture")
                    Text(layer.denominationalPosture)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !layer.uncertaintyNotes.isEmpty {
                    SectionSubheading("Uncertainty Notes")
                    ForEach(layer.uncertaintyNotes, id: \.self) { note in
                        Text(note)
                            .font(.footnote)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 12)
        } label: {
            SectionLabel(title: "Interpretation", icon: "lightbulb")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .accessibilityIdentifier("studySheet.interpretationSection")
    }

    // MARK: - Section 4: Application

    private func applicationLayerSection(_ layer: BereanStudySheetApplicationLayer) -> some View {
        DisclosureGroup(isExpanded: $applicationExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if !layer.prompts.isEmpty {
                    SectionSubheading("Reflection Prompts")
                    BulletList(items: layer.prompts)
                }

                if !layer.cautions.isEmpty {
                    SectionSubheading("Cautions")
                    ForEach(layer.cautions, id: \.self) { caution in
                        Label {
                            Text(caution)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Text("⚠️")
                        }
                    }
                }

                if let prayerSeed = layer.prayerSeed {
                    SectionSubheading("Prayer Seed")
                    Text(prayerSeed)
                        .font(.body.italic())
                        .foregroundStyle(Color.amenGold)
                        .padding(12)
                        .background(Color.amenGold.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.vertical, 12)
        } label: {
            SectionLabel(title: "Application", icon: "heart.fill")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .accessibilityIdentifier("studySheet.applicationSection")
    }

    // MARK: - Cross-References Section

    private func crossReferencesSection(refs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Cross-References", icon: "link")
                .padding(.horizontal, 20)
                .padding(.top, 16)

            if refs.isEmpty {
                Text("No cross-references available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else {
                SelahChipFlowLayout(spacing: 8) {
                    ForEach(refs, id: \.self) { ref in
                        Button {
                            onCrossRefTapped(ref)
                        } label: {
                            Text(ref)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.amenPurple)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.amenPurple.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("studySheet.crossRef.\(ref)")
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Provenance Footer

    private func provenanceFooter(
        provenance: BereanStudySheetProvenance,
        promptVersion: String
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "cpu")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("Generated by Berean · Sources: \(provenance.scriptureSource) · \(promptVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Text("AI")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.amenPurple.opacity(0.7), in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task {
                    await viewModel.loadStudySheet(
                        verseId: verseId,
                        translation: translation,
                        verseText: verseText
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.amenBlue)
        }
        .padding(32)
    }
}

// MARK: - Supporting Views

private struct SectionLabel: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
    }
}

private struct SectionSubheading: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(item)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct InterpretiveOptionRow: View {
    let option: BereanInterpretiveOption

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(option.label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                ConfidenceDots(confidence: option.confidence)
            }
            Text(option.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ConfidenceDots: View {
    let confidence: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(Double(index) < confidence * 5 ? Color.amenBlue : Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel("Confidence: \(Int(confidence * 100))%")
    }
}

private struct KeyTermPopover: View {
    let term: BereanKeyTerm
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(term.term)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text(term.note)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(20)
            .navigationTitle("Key Term")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Shimmer Line

private struct SheetShimmerLine: View {
    let widthFraction: CGFloat
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.secondary.opacity(0.10), location: phase),
                            .init(color: Color.secondary.opacity(0.22), location: phase + 0.4),
                            .init(color: Color.secondary.opacity(0.10), location: phase + 0.8)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: geo.size.width * widthFraction, height: 14)
        }
        .frame(height: 14)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = 1.2
            }
        }
    }
}

// MARK: - SelahChipFlowLayout (wrapping chip row)

private struct SelahChipFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Safe subscript for Collection

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
