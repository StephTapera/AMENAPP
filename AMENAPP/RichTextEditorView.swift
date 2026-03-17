//
//  RichTextEditorView.swift
//  AMENAPP
//
//  Rich text editor with formatting toolbar for church notes
//

import SwiftUI

struct RichTextEditorView: View {
    @Binding var text: String
    @FocusState private var isEditorFocused: Bool
    @State private var selectedRange: Range<String.Index>?
    @State private var showFormattingToolbar = false
    
    var placeholder: String = "Start writing..."
    var minHeight: CGFloat = 200
    
    var body: some View {
        VStack(spacing: 0) {
            // Formatting Toolbar
            if showFormattingToolbar {
                FormattingToolbar(
                    text: $text,
                    selectedRange: $selectedRange
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Text Editor
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                
                TextEditor(text: $text)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: minHeight)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .focused($isEditorFocused)
                    .onChange(of: isEditorFocused) { _, focused in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showFormattingToolbar = focused
                        }
                    }
            }
        }
    }
}

// MARK: - Formatting Toolbar

struct FormattingToolbar: View {
    @Binding var text: String
    @Binding var selectedRange: Range<String.Index>?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Text Style Group
                TextFormatButton(icon: "bold") {
                    applyFormatting(markdown: "**")
                }
                
                TextFormatButton(icon: "italic") {
                    applyFormatting(markdown: "*")
                }
                
                TextFormatButton(icon: "underline") {
                    applyFormatting(markdown: "__")
                }
                
                Divider()
                    .frame(height: 24)
                    .background(Color.white.opacity(0.2))
                
                // Heading Styles
                TextFormatButton(icon: "textformat.size.larger", label: "H1") {
                    applyHeading(level: 1)
                }
                
                TextFormatButton(icon: "textformat.size", label: "H2") {
                    applyHeading(level: 2)
                }
                
                Divider()
                    .frame(height: 24)
                    .background(Color.white.opacity(0.2))
                
                // List Styles
                TextFormatButton(icon: "list.bullet") {
                    applyBulletPoint()
                }
                
                TextFormatButton(icon: "list.number") {
                    applyNumberedList()
                }
                
                Divider()
                    .frame(height: 24)
                    .background(Color.white.opacity(0.2))
                
                // Quote/Indent
                TextFormatButton(icon: "quote.opening") {
                    applyBlockQuote()
                }
                
                TextFormatButton(icon: "increase.indent") {
                    applyIndent()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.white.opacity(0.05))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
    
    // Apply markdown formatting to selected text or at cursor
    private func applyFormatting(markdown: String) {
        // For now, insert at the end - in a production app, you'd track cursor position
        let formattedText = "\(markdown)text\(markdown)"
        text += formattedText
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func applyHeading(level: Int = 2) {
        let prefix = String(repeating: "#", count: level)
        text += "\n\(prefix) Heading\n"
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func applyBulletPoint() {
        text += "\n• "
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func applyNumberedList() {
        text += "\n1. "
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func applyBlockQuote() {
        text += "\n> "
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func applyIndent() {
        text += "    "
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
}

// MARK: - Text Format Button

struct TextFormatButton: View {
    let icon: String
    var label: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                if let label = label {
                    Text(label)
                        .font(.custom("OpenSans-Bold", size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Markdown Rendering Helper

extension String {
    /// Convert markdown to attributed string for display
    func markdownToAttributedString() -> AttributedString {
        do {
            return try AttributedString(markdown: self, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(self)
        }
    }
}
