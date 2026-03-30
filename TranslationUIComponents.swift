// TranslationUIComponents.swift
// AMEN App — Translation System
//
// Reusable SwiftUI components for all translation surfaces.
// Follows AMEN's Liquid Glass / premium iOS design language.

import SwiftUI

// MARK: - TranslatableTextBlock
// Drop-in replacement for Text/content areas that gains translation capability.
// Use in PostCard, CommentsView, ProfileView, etc.

struct TranslatableTextBlock: View {
    let text: String
    let contentType: TranslatableContentType
    let contentId: String
    let surface: TranslationSurface
    var isPublicContent: Bool = true
    var font: Font = .body
    var foregroundColor: Color = .primary
    var lineLimit: Int? = nil
    var autoTranslate: Bool = false

    @State private var uiState: TranslationUIState = .available
    @State private var showingOriginal: Bool = false
    @State private var detectedLang: String? = nil
    @State private var hasAttemptedAutoTranslation = false

    @ObservedObject private var settings = TranslationSettingsManager.shared
    @ObservedObject private var flags = TranslationFeatureFlags.shared
    private let service = TranslationService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Main content text
            Group {
                if showingOriginal {
                    Text(text)
                        .font(font)
                        .foregroundColor(foregroundColor)
                        .lineLimit(lineLimit)
                } else if let translated = uiState.translatedText {
                    Text(translated)
                        .font(font)
                        .foregroundColor(foregroundColor)
                        .lineLimit(lineLimit)
                } else {
                    Text(text)
                        .font(font)
                        .foregroundColor(foregroundColor)
                        .lineLimit(lineLimit)
                }
            }

            // Translation affordance row
            translationAffordance
        }
        .task {
            await initializeTranslationState()
        }
    }

    // MARK: - Translation Affordance

    @ViewBuilder
    private var translationAffordance: some View {
        switch uiState {
        case .loading:
            TranslationLoadingChip()

        case .translated(let variant):
            if showingOriginal {
                TranslationActionChip(
                    label: "View translation",
                    icon: "globe",
                    style: .secondary
                ) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        showingOriginal = false
                    }
                }
            } else {
                HStack(spacing: 8) {
                    TranslationSourceLabel(languageCode: variant.sourceLanguage)
                    TranslationActionChip(
                        label: "View original",
                        icon: nil,
                        style: .ghost
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            showingOriginal = true
                        }
                    }
                }
            }

        case .available:
            if let lang = detectedLang,
               settings.shouldOfferTranslation(detectedLang: lang, contentType: contentType) {
                TranslationActionChip(
                    label: "See translation",
                    icon: "globe",
                    style: .primary
                ) {
                    Task { await requestTranslation() }
                }
            }

        case .error(let err):
            TranslationErrorChip(message: err.userFacingMessage) {
                Task { await requestTranslation() }
            }

        case .notNeeded, .disabled:
            EmptyView()
        }
    }

    // MARK: - Logic

    private func initializeTranslationState() async {
        guard !hasAttemptedAutoTranslation else { return }
        hasAttemptedAutoTranslation = true

        // Detect language (on-device, instant)
        let result = await service.detectLanguage(text)
        guard result.isReliable else { return }
        detectedLang = result.languageCode

        // Auto-translate if user preference says so
        if autoTranslate || settings.shouldAutoTranslate(detectedLang: result.languageCode, contentType: contentType) {
            await requestTranslation()
        } else if settings.shouldOfferTranslation(detectedLang: result.languageCode, contentType: contentType) {
            uiState = .available
        } else {
            uiState = .notNeeded
        }
    }

    private func requestTranslation() async {
        guard uiState != .loading else { return }
        uiState = .loading

        let result = await service.translate(
            text: text,
            contentType: contentType,
            contentId: contentId,
            surface: surface,
            isPublicContent: isPublicContent
        )

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            uiState = result
            if case .translated = result {
                showingOriginal = false
            }
        }
    }
}

// MARK: - Inline Comment Translation Row
// Compact single-line affordance for use in comment cells

struct CommentTranslationRow: View {
    let text: String
    let commentId: String
    var isPublicContent: Bool = true

    @State private var uiState: TranslationUIState = .available
    @State private var showingOriginal: Bool = false
    @State private var detectedLang: String? = nil

    @ObservedObject private var settings = TranslationSettingsManager.shared
    private let service = TranslationService.shared

    var translatedText: String? { uiState.translatedText }
    var isShowingTranslation: Bool { !showingOriginal && uiState.translatedText != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Translation action / status
            switch uiState {
            case .loading:
                TranslationLoadingChip(compact: true)

            case .translated(let variant):
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Translated from \(SupportedLanguage.displayName(for: variant.sourceLanguage))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showingOriginal.toggle()
                        }
                    } label: {
                        Text(showingOriginal ? "Hide original" : "View original")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .underline()
                    }
                }

            case .available:
                if let lang = detectedLang,
                   settings.shouldOfferTranslation(detectedLang: lang, contentType: .comment) {
                    Button {
                        Task { await requestTranslation() }
                    } label: {
                        Label("Translate", systemImage: "globe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

            case .error:
                EmptyView()

            case .notNeeded, .disabled:
                EmptyView()
            }
        }
        .task {
            let result = await service.detectLanguage(text)
            guard result.isReliable else { return }
            detectedLang = result.languageCode
            if settings.shouldAutoTranslate(detectedLang: result.languageCode, contentType: .comment) {
                await requestTranslation()
            } else if settings.shouldOfferTranslation(detectedLang: result.languageCode, contentType: .comment) {
                uiState = .available
            }
        }
    }

    var displayText: String {
        if isShowingTranslation, let t = translatedText { return t }
        return text
    }

    private func requestTranslation() async {
        guard uiState != .loading else { return }
        uiState = .loading
        let result = await service.translate(
            text: text,
            contentType: .comment,
            contentId: commentId,
            surface: .commentSheet,
            isPublicContent: isPublicContent
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            uiState = result
        }
    }
}

// MARK: - Chip Components

struct TranslationActionChip: View {
    enum Style { case primary, secondary, ghost }

    let label: String
    let icon: String?
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2.weight(.medium))
                }
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(chipBackground)
            .foregroundStyle(chipForeground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var chipBackground: some View {
        switch style {
        case .primary:
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        case .secondary:
            Capsule()
                .fill(Color.primary.opacity(0.06))
        case .ghost:
            Color.clear
        }
    }

    private var chipForeground: AnyShapeStyle {
        switch style {
        case .primary:  return AnyShapeStyle(Color.primary.opacity(0.7))
        case .secondary: return AnyShapeStyle(Color.secondary)
        case .ghost:    return AnyShapeStyle(Color.secondary)
        }
    }
}

struct TranslationSourceLabel: View {
    let languageCode: String

    var body: some View {
        Label(
            "Translated from \(SupportedLanguage.displayName(for: languageCode))",
            systemImage: "globe"
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

struct TranslationLoadingChip: View {
    var compact: Bool = false

    @State private var opacity: Double = 0.4

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "globe")
                .font(compact ? .caption2 : .caption)
            Text("Translating…")
                .font(compact ? .caption2 : .caption)
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 3 : 5)
        .background(
            Capsule().fill(Color.primary.opacity(0.06))
        )
        .foregroundStyle(.secondary)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                opacity = 1.0
            }
        }
    }
}

struct TranslationErrorChip: View {
    let message: String
    let retryAction: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Retry", action: retryAction)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .underline()
        }
    }
}

// MARK: - Translation Info Sheet (long-press on "Translated" label)

struct TranslationInfoSheet: View {
    let variant: TranslationVariant
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("About this translation")
                    .font(.headline)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                infoRow(label: "Source language",
                        value: SupportedLanguage.displayName(for: variant.sourceLanguage))
                infoRow(label: "Target language",
                        value: SupportedLanguage.displayName(for: variant.targetLanguage))
                infoRow(label: "Engine",
                        value: variant.engineVersion == .gcpV3
                            ? "Google Cloud Translation"
                            : "Apple on-device Translation")
                infoRow(label: "Translated",
                        value: RelativeDateTimeFormatter().localizedString(for: variant.translatedAt, relativeTo: Date()))
            }

            Text("Translations are machine-generated and may not perfectly capture the original tone or intent. Biblical references, names, and scripture verses are preserved as authored.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
        }
    }
}

// MARK: - PulsingOpacityModifier (used in PostCard loading chip)

struct PulsingOpacityModifier: ViewModifier {
    @State private var opacity: Double = 0.4
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    opacity = 1.0
                }
            }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Translatable Text Block") {
    VStack(alignment: .leading, spacing: 20) {
        TranslatableTextBlock(
            text: "Dios es bueno todo el tiempo. Agradecido por Su gracia y misericordia en este día.",
            contentType: .post,
            contentId: "preview-post-1",
            surface: .feed
        )
        .padding()
    }
    .background(Color(.systemBackground))
}
#endif
