// SimplificationView.swift
// AMENAPP
//
// A8 — "Understand" readability sheet.
// Presents content transformed by SimplificationService in a Liquid Glass sheet.

import SwiftUI

struct SimplificationView: View {
    let contentId: String
    let originalText: String
    var onDismiss: () -> Void

    @State private var selectedMode: ReadabilityMode = .summarize
    @State private var result: ReadabilityTransform? = nil
    @State private var isLoading = false
    @State private var error: String? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                handle
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Understand")
                        .font(AMENFont.bold(22))
                        .foregroundStyle(.primary)

                    Text(selectedMode.displayLabel)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                        .animation(.amenSnappy, value: selectedMode)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                modePicker
                    .padding(.bottom, 20)

                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                closeButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .padding(.top, 12)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        copyContent()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(AMENFont.regular(16))
                            .foregroundStyle(AmenTheme.Colors.amenPurple)
                    }
                    .disabled(result == nil)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(28)
        .task(id: selectedMode) {
            await loadTransform()
        }
    }

    // MARK: - Subviews

    private var handle: some View {
        Capsule()
            .fill(Color.primary.opacity(0.2))
            .frame(width: 36, height: 4)
    }

    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ReadabilityMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.amenSnappy) {
                            selectedMode = mode
                        }
                    } label: {
                        Text(mode.displayLabel)
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(selectedMode == mode ? .white : AmenTheme.Colors.amenPurple)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedMode == mode
                                          ? AmenTheme.Colors.amenPurple
                                          : AmenTheme.Colors.amenPurple.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if isLoading {
            ProgressView()
                .tint(AmenTheme.Colors.amenPurple)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = error {
            VStack(spacing: 16) {
                Text(errorMessage)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(AmenTheme.Colors.statusError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button {
                    Task { await loadTransform() }
                } label: {
                    Text("Try Again")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(AmenTheme.Colors.amenPurple)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(AmenTheme.Colors.amenPurple.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if selectedMode == .keyTerms, let terms = result?.keyTerms, !terms.isEmpty {
            keyTermsList(terms)
        } else if let transform = result {
            ScrollView {
                Text(transform.transformedText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
        } else {
            Spacer()
        }
    }

    private func keyTermsList(_ terms: [KeyTermDefinition]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(terms) { term in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(term.term)
                            .font(AMENFont.semiBold(15))
                            .foregroundStyle(.primary)

                        Text(term.definition)
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)

                        if let verse = term.relatedVerse {
                            Text(verse)
                                .font(AMENFont.regular(13).italic())
                                .foregroundStyle(AmenTheme.Colors.amenGold)
                                .padding(.top, 2)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
            onDismiss()
        } label: {
            Text("Close")
                .font(AMENFont.semiBold(16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AmenTheme.Colors.amenPurple, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func loadTransform() async {
        error = nil
        isLoading = true
        result = nil

        let transform = await SimplificationService.shared.transform(
            contentId: contentId,
            text: originalText,
            mode: selectedMode
        )

        isLoading = false

        if let transform {
            withAnimation(.amenSpring) {
                result = transform
            }
        } else {
            error = "Something went wrong. Please try again."
        }
    }

    private func copyContent() {
        guard let transform = result else { return }
        if selectedMode == .keyTerms, let terms = transform.keyTerms, !terms.isEmpty {
            let formatted = terms.map { t -> String in
                var line = "\(t.term): \(t.definition)"
                if let verse = t.relatedVerse { line += "\n\(verse)" }
                return line
            }.joined(separator: "\n\n")
            UIPasteboard.general.string = formatted
        } else {
            UIPasteboard.general.string = transform.transformedText
        }
    }
}
