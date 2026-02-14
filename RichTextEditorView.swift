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
            HStack(spacing: 12) {
                TextFormatButton(icon: "bold", label: "Bold") {
                    applyFormatting(markdown: "**")
                }
                
                TextFormatButton(icon: "italic", label: "Italic") {
                    applyFormatting(markdown: "*")
                }
                
                TextFormatButton(icon: "underline", label: "Underline") {
                    applyFormatting(markdown: "__")
                }
                
                TextFormatButton(icon: "strikethrough", label: "Strike") {
                    applyFormatting(markdown: "~~")
                }
                
                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, 4)
                
                TextFormatButton(icon: "h.square", label: "Heading") {
                    applyHeading()
                }
                
                TextFormatButton(icon: "list.bullet", label: "List") {
                    applyBulletPoint()
                }
                
                TextFormatButton(icon: "quote.opening", label: "Quote") {
                    applyBlockQuote()
                }
                
                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, 4)
                
                TextFormatButton(icon: "link", label: "Link") {
                    applyLink()
                }
                
                TextFormatButton(icon: "checkmark.square", label: "Checkbox") {
                    applyCheckbox()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
    
    // Apply markdown formatting to selected text or at cursor
    private func applyFormatting(markdown: String) {
        // For now, insert at the end - in a production app, you'd track cursor position
        let formattedText = "\(markdown)text\(markdown)"
        text += formattedText
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func applyHeading() {
        text += "\n## Heading\n"
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func applyBulletPoint() {
        text += "\n- "
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func applyBlockQuote() {
        text += "\n> "
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func applyLink() {
        text += "[link text](url)"
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func applyCheckbox() {
        text += "\n- [ ] "
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
}

// MARK: - Text Format Button

struct TextFormatButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 28, height: 28)
                
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
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
