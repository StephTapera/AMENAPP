// InlineReplyComposer.swift
// AMENAPP — Replies/
//
// Bottom-pinned reply bar that collapses to a one-line placeholder and
// expands into a full multi-line composer with attachment icon row and
// a "Post" pill button.
//
// Types used: ComposerDraft, ComposerAttachmentKind  (ComposerContract.swift)
// Motion:     Motion.springPress, Motion.adaptive()  (Motion.swift)

import SwiftUI

// MARK: - InlineReplyComposer

struct InlineReplyComposer: View {

    @Binding var draft: ComposerDraft
    @Binding var isPresented: Bool
    var parentId: String?
    var onSubmit: (String, String?) -> Void

    // MARK: Local state

    @FocusState private var isFocused: Bool
    @State private var showStickerPicker = false
    @State private var showPhotoPicker   = false
    @State private var showGIFPicker     = false

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AmenTheme.Colors.separatorSubtle)

            if isPresented {
                expandedComposer
                    .transition(
                        .asymmetric(
                            insertion:  .push(from: .bottom).combined(with: .opacity),
                            removal:    .push(from: .top).combined(with: .opacity)
                        )
                    )
            } else {
                collapsedBar
                    .transition(
                        .asymmetric(
                            insertion:  .push(from: .top).combined(with: .opacity),
                            removal:    .push(from: .bottom).combined(with: .opacity)
                        )
                    )
            }
        }
        .background(composerBackground)
        .animation(Motion.adaptive(Motion.springPress), value: isPresented)
        // Sheet stubs — wired at integration
        .sheet(isPresented: $showStickerPicker) { stickerPickerPlaceholder }
        .sheet(isPresented: $showPhotoPicker)   { photoPickerPlaceholder   }
        .sheet(isPresented: $showGIFPicker)     { gifPickerPlaceholder     }
        .accessibilityLabel(
            "Reply composer. \(draft.text.isEmpty ? "Empty" : draft.text)"
        )
    }

    // MARK: - Collapsed bar

    private var collapsedBar: some View {
        HStack(spacing: 12) {
            // Current-user avatar placeholder
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            AmenTheme.Colors.amenBlue.opacity(0.35),
                            AmenTheme.Colors.amenPurple.opacity(0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                )
                .accessibilityHidden(true)

            // Tappable placeholder
            Button {
                withAnimation(Motion.adaptive(Motion.springPress)) {
                    isPresented = true
                    isFocused   = true
                }
            } label: {
                Text("Add your reply…")
                    .font(AMENFont.regular(15))
                    .foregroundStyle(AmenTheme.Colors.textPlaceholder)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Attachment icon row (collapsed)
            HStack(spacing: 14) {
                attachmentIconButton(symbol: "face.smiling",     action: { showStickerPicker = true }, label: "Sticker")
                attachmentIconButton(symbol: "photo",            action: { showPhotoPicker   = true }, label: "Photo")
                attachmentIconButton(symbol: "film.stack",       action: { showGIFPicker     = true }, label: "GIF")
                attachmentIconButton(symbol: "arrow.up.left.and.arrow.down.right",
                                     action: { withAnimation(Motion.adaptive(Motion.springPress)) { isPresented = true } },
                                     label: "Expand composer")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Expanded composer

    private var expandedComposer: some View {
        VStack(spacing: 0) {
            // Text input area
            HStack(alignment: .top, spacing: 10) {
                // Avatar
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                AmenTheme.Colors.amenBlue.opacity(0.35),
                                AmenTheme.Colors.amenPurple.opacity(0.25)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    )
                    .accessibilityHidden(true)
                    .padding(.top, 2)

                ZStack(alignment: .topLeading) {
                    // Placeholder
                    if draft.text.isEmpty {
                        Text("Add your reply…")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(AmenTheme.Colors.textPlaceholder)
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $draft.text)
                        .font(AMENFont.regular(15))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 56, maxHeight: 140)
                        .focused($isFocused)
                        .onAppear { isFocused = true }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            // Bottom row: attachment icons + Post button
            HStack(spacing: 14) {
                attachmentIconButton(symbol: "face.smiling",    action: { showStickerPicker = true }, label: "Sticker")
                attachmentIconButton(symbol: "photo",           action: { showPhotoPicker   = true }, label: "Photo")
                attachmentIconButton(symbol: "film.stack",      action: { showGIFPicker     = true }, label: "GIF")
                attachmentIconButton(symbol: "arrow.up.left.and.arrow.down.right",
                                     action: { /* full-screen composer — integration at call site */ },
                                     label: "Expand to full composer")

                Spacer()

                // Dismiss / cancel
                Button {
                    withAnimation(Motion.adaptive(Motion.springPress)) {
                        isPresented     = false
                        isFocused       = false
                        draft.text      = ""
                    }
                } label: {
                    Text("Cancel")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel reply")

                // Post pill
                Button {
                    let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    onSubmit(text, parentId)
                    withAnimation(Motion.adaptive(Motion.springRelease)) {
                        draft       = ComposerDraft()
                        isPresented = false
                        isFocused   = false
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Text("Post")
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      ? AmenTheme.Colors.amenBlue.opacity(0.35)
                                      : AmenTheme.Colors.amenBlue)
                        )
                }
                .buttonStyle(AmenPressStyle(scale: 0.96))
                .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .animation(Motion.adaptive(Motion.popToggle), value: draft.text.isEmpty)
                .accessibilityLabel("Post reply")
                .accessibilityHint("Double-tap to submit your reply")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // MARK: - Background

    private var composerBackground: some View {
        AmenTheme.Colors.surfaceElevated
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .top) {
                // Subtle top separator already drawn by Divider()
                Color.clear
            }
    }

    // MARK: - Attachment icon button helper

    private func attachmentIconButton(symbol: String, action: @escaping () -> Void, label: String) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(AmenPressStyle(scale: 0.90))
        .accessibilityLabel(label)
    }

    // MARK: - Picker placeholder sheets

    private var stickerPickerPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "face.smiling.inverse")
                .font(.system(size: 48))
                .foregroundStyle(AmenTheme.Colors.amenGold)
            Text("Sticker Picker")
                .font(AMENFont.semiBold(18))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("Sticker integration coming soon.")
                .font(AMENFont.regular(14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .padding(.top, 40)
        .presentationDetents([.medium])
    }

    private var photoPickerPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 48))
                .foregroundStyle(AmenTheme.Colors.amenBlue)
            Text("Photo Picker")
                .font(AMENFont.semiBold(18))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("Photo attachment integration coming soon.")
                .font(AMENFont.regular(14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .padding(.top, 40)
        .presentationDetents([.medium])
    }

    private var gifPickerPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack.fill")
                .font(.system(size: 48))
                .foregroundStyle(AmenTheme.Colors.amenPurple)
            Text("GIF Picker")
                .font(AMENFont.semiBold(18))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("GIF integration coming soon.")
                .font(AMENFont.regular(14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .padding(.top, 40)
        .presentationDetents([.medium])
    }
}

