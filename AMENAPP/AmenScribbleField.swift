// AmenScribbleField.swift
// AMENAPP
// Apple Pencil / Scribble-optimized multiline text field.
// On iPad, Scribble converts handwriting to text automatically via UITextView.
// On iPhone, behaves as a standard multiline input.

import SwiftUI
import UIKit

struct AmenScribbleField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = "Write or type here…"
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var returnKeyType: UIReturnKeyType = .default

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = font
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        tv.isScrollEnabled = false
        tv.dataDetectorTypes = []
        tv.autocorrectionType = .yes
        tv.spellCheckingType = .yes
        tv.returnKeyType = returnKeyType
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Pencil double-tap / squeeze — focus the field
        if UIDevice.current.userInterfaceIdiom == .pad {
            let pencil = UIPencilInteraction()
            pencil.delegate = context.coordinator
            tv.addInteraction(pencil)
        }

        context.coordinator.textView = tv
        setPlaceholder(tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        guard !context.coordinator.isEditing else { return }
        if text.isEmpty {
            setPlaceholder(tv)
        } else if tv.text != text {
            tv.text = text
            tv.textColor = .label
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func setPlaceholder(_ tv: UITextView) {
        tv.text = placeholder
        tv.textColor = .placeholderText
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate, UIPencilInteractionDelegate {
        var parent: AmenScribbleField
        weak var textView: UITextView?
        var isEditing = false

        init(_ parent: AmenScribbleField) { self.parent = parent }

        func textViewDidBeginEditing(_ tv: UITextView) {
            isEditing = true
            if tv.textColor == .placeholderText {
                tv.text = ""
                tv.textColor = .label
            }
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text ?? ""
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            isEditing = false
            if (tv.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tv.text = parent.placeholder
                tv.textColor = .placeholderText
                parent.text = ""
            }
        }

        // Double-tap or squeeze on Pencil Pro → focus immediately
        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            textView?.becomeFirstResponder()
        }
    }
}

// MARK: - SwiftUI wrapper with matching background

struct AmenScribbleCard: View {
    @Binding var text: String
    var placeholder: String = "Write or type…"
    var minHeight: CGFloat = 120

    var body: some View {
        AmenScribbleField(text: $text, placeholder: placeholder)
            .frame(minHeight: minHeight)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                if text.isEmpty {
                    // iPad pencil hint
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Label("Pencil supported", systemImage: "pencil.tip")
                                    .font(.caption2)
                                    .foregroundStyle(.quaternary)
                                    .padding(8)
                            }
                        }
                    }
                }
            }
    }
}
