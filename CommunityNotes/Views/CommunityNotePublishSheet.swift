// CommunityNotePublishSheet.swift
// AMENAPP — Community Notes publish flow
//
// Glass sheet for composing and publishing a community note.
// amenGlassSheet(tint: amenGold) from SpacesDesignSystem applied.
// Visibility picker, category chips, tag input, char-count validation.
// Reuses AMENGlassPillButton, ChurchBadgeChip from SpacesDesignSystem.

import SwiftUI

@MainActor
struct CommunityNotePublishSheet: View {

    @Binding var isPresented: Bool
    var sourceNoteId: String? = nil   // optional link to a private Smart Church Note

    @State private var title: String = ""
    @State private var body_: String = ""
    @State private var selectedCategory: NoteCategory = .study
    @State private var visibility: NoteVisibility = .public_
    @State private var tagInput: String = ""
    @State private var tags: [String] = []
    @State private var isPublishing: Bool = false
    @State private var publishError: String? = nil
    @State private var showSuccessToast: Bool = false
    @State private var shakeTrigger: Bool = false

    @StateObject private var service = CommunityNotesService.shared
    @FocusState private var bodyFocused: Bool

    // MARK: - Validation constants

    private let maxTitleLength   = 140
    private let maxBodyLength    = 20_000
    private let maxTags          = 12

    private var isPublishDisabled: Bool {
        title.trimmingCharacters(in: .whitespaces).isEmpty ||
        body_.trimmingCharacters(in: .whitespaces).isEmpty ||
        isPublishing
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    headerRow
                    Divider().background(AmenTheme.Colors.separatorSubtle)

                    titleField
                    bodyField
                    categoryPicker
                    visibilityPicker
                    tagSection

                    if let err = publishError {
                        errorBanner(message: err)
                    }

                    publishButton
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }

            if showSuccessToast {
                successToast
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .amenGlassSheet(tint: AmenTheme.Colors.amenGold)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .background(AmenTheme.Colors.backgroundPrimary.ignoresSafeArea())
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack {
            Text("Share a Note")
                .font(.headline.bold())
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Spacer()
            Button("Cancel") {
                isPresented = false
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel and close sheet")
        }
    }

    // MARK: - Title Field

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Title")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(title.count)/\(maxTitleLength)")
                    .font(.caption2)
                    .foregroundStyle(
                        title.count > maxTitleLength
                            ? AmenTheme.Colors.statusError
                            : AmenTheme.Colors.textTertiary
                    )
            }

            TextField("Give your note a title", text: $title)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .onChange(of: title) { _, newValue in
                    if newValue.count > maxTitleLength {
                        title = String(newValue.prefix(maxTitleLength))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AmenTheme.Colors.surfaceInput)
                .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                        .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.75)
                }
        }
    }

    // MARK: - Body Field

    private var bodyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Note")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(body_.count)/\(maxBodyLength)")
                    .font(.caption2)
                    .foregroundStyle(
                        body_.count > maxBodyLength
                            ? AmenTheme.Colors.statusError
                            : AmenTheme.Colors.textTertiary
                    )
            }

            ZStack(alignment: .topLeading) {
                if body_.isEmpty {
                    Text("What is God speaking to you?")
                        .font(.subheadline)
                        .foregroundStyle(AmenTheme.Colors.textPlaceholder)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $body_)
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .focused($bodyFocused)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .onChange(of: body_) { _, newValue in
                        if newValue.count > maxBodyLength {
                            body_ = String(newValue.prefix(maxBodyLength))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .background(AmenTheme.Colors.surfaceInput)
            .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.75)
            }
        }
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Category")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NoteCategory.allCases) { cat in
                        categoryChip(cat)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func categoryChip(_ cat: NoteCategory) -> some View {
        let isSelected = selectedCategory == cat
        Button {
            withAnimation(Motion.popToggle) { selectedCategory = cat }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: cat.icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? AmenTheme.Colors.amenBlack : cat.tint)
                Text(cat.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? AmenTheme.Colors.amenBlack : AmenTheme.Colors.textPrimary)
                    .lineLimit(1)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background {
                if isSelected {
                    Capsule(style: .continuous).fill(AmenTheme.Colors.amenGold)
                } else {
                    Capsule(style: .continuous)
                        .fill(AmenTheme.Colors.surfaceChip)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.75)
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .amenPress(scale: 0.96)
        .accessibilityLabel(cat.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Visibility Picker

    private var visibilityPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Visibility")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .textCase(.uppercase)

            HStack(spacing: 0) {
                ForEach([NoteVisibility.public_, .followers, .private_], id: \.rawValue) { option in
                    visibilitySegment(option)
                }
            }
            .background(AmenTheme.Colors.surfaceInput)
            .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.75)
            }

            // Description caption
            Text(visibility.description)
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func visibilitySegment(_ option: NoteVisibility) -> some View {
        let isSelected = visibility == option
        Button {
            withAnimation(Motion.springPress) { visibility = option }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: option.icon)
                    .font(.caption.weight(.semibold))
                Text(option.displayName)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(
                isSelected ? AmenTheme.Colors.amenBlack : AmenTheme.Colors.textSecondary
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall - 2, style: .continuous)
                        .fill(AmenTheme.Colors.amenGold)
                        .padding(3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Tag Section

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .textCase(.uppercase)

            // Input field
            HStack {
                TextField(
                    tags.count >= maxTags
                        ? "Max \(maxTags) tags reached"
                        : "Add a tag, press Return",
                    text: $tagInput
                )
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .disabled(tags.count >= maxTags)
                .submitLabel(.done)
                .onSubmit { commitTag() }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                Text("\(tags.count)/\(maxTags)")
                    .font(.caption2)
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AmenTheme.Colors.surfaceInput)
            .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.75)
            }

            // Existing tag chips
            if !tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        tagChip(tag)
                    }
                }
            }
        }
    }

    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text("#\(tag)")
                .font(.caption.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.amenGold)
            Button {
                withAnimation(Motion.popToggle) {
                    tags.removeAll { $0 == tag }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove tag \(tag)")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(
            Capsule(style: .continuous)
                .fill(AmenTheme.Colors.amenGold.opacity(0.12))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(AmenTheme.Colors.amenGold.opacity(0.30), lineWidth: 0.75)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tag: \(tag)")
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AmenTheme.Colors.statusError)
            Text(message)
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.statusError)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                .fill(AmenTheme.Colors.statusError.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                        .strokeBorder(AmenTheme.Colors.statusError.opacity(0.30), lineWidth: 0.75)
                }
        )
        .shakeOnError(shakeTrigger)
    }

    // MARK: - Publish Button

    private var publishButton: some View {
        Button {
            guard !isPublishDisabled else { return }
            Task { await handlePublish() }
        } label: {
            HStack(spacing: 8) {
                if isPublishing {
                    ProgressView()
                        .tint(AmenTheme.Colors.amenBlack)
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                }
                Text(isPublishing ? "Publishing…" : "Publish Note")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isPublishDisabled ? AmenTheme.Colors.textTertiary : AmenTheme.Colors.amenBlack)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(isPublishDisabled
                          ? AmenTheme.Colors.surfaceChip
                          : AmenTheme.Colors.amenGold)
            }
            .overlay {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .strokeBorder(
                        isPublishDisabled ? AmenTheme.Colors.borderSoft : AmenTheme.Colors.glassStroke,
                        lineWidth: 0.75
                    )
            }
            .shadow(
                color: isPublishDisabled ? .clear : AmenTheme.Colors.amenGold.opacity(0.30),
                radius: 10, y: 4
            )
        }
        .buttonStyle(.plain)
        .amenPress(scale: isPublishDisabled ? 1.0 : 0.96)
        .disabled(isPublishDisabled)
        .accessibilityLabel("Publish note")
        .accessibilityHint(isPublishDisabled ? "Add a title and body to publish." : "Publishes your note to the community.")
    }

    // MARK: - Success Toast

    private var successToast: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AmenTheme.Colors.statusSuccess)
            Text("Note published! It will appear after review.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay { Capsule(style: .continuous).fill(AmenTheme.Colors.glassFill) }
                .overlay { Capsule(style: .continuous).strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.75) }
        )
        .shadow(color: AmenTheme.Colors.shadowFloating, radius: 18, y: 8)
        .padding(.bottom, 40)
    }

    // MARK: - Actions

    private func handlePublish() async {
        isPublishing = true
        publishError = nil

        do {
            try await service.publishNote(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: body_.trimmingCharacters(in: .whitespacesAndNewlines),
                category: selectedCategory,
                tags: tags,
                visibility: visibility,
                sourceNoteId: sourceNoteId
            )

            // Show success toast briefly then dismiss
            withAnimation(Motion.appearEase) { showSuccessToast = true }
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 s
            withAnimation(Motion.appearEase) { showSuccessToast = false }
            isPresented = false

        } catch {
            publishError = error.localizedDescription
            shakeTrigger.toggle()
        }

        isPublishing = false
    }

    private func commitTag() {
        let cleaned = tagInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "#", with: "")
        guard !cleaned.isEmpty,
              !tags.contains(cleaned),
              tags.count < maxTags else {
            tagInput = ""
            return
        }
        withAnimation(Motion.popToggle) {
            tags.append(cleaned)
        }
        tagInput = ""
    }
}

// MARK: - FlowLayout (simple wrapping HStack for tag chips)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > width, currentX > 0 {
                currentY += rowHeight + spacing
                totalHeight = currentY
                currentX = 0
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: totalHeight + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentY += rowHeight + spacing
                currentX = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("CommunityNotePublishSheet") {
    struct PreviewWrapper: View {
        @State private var show = true
        var body: some View {
            ZStack {
                AmenTheme.Colors.backgroundPrimary.ignoresSafeArea()
                Button("Open Sheet") { show = true }
            }
            .sheet(isPresented: $show) {
                CommunityNotePublishSheet(isPresented: $show)
            }
        }
    }
    return PreviewWrapper()
}
#endif
