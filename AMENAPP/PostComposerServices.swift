import Foundation
import SwiftUI
import FirebaseFunctions

// MARK: - Color Design Tokens

extension Color {
    /// Thread connector line color (Threads-style)
    static let amenThreadLine = Color.primary.opacity(0.1)

    /// Glass fill for liquid glass surfaces
    static let amenGlassFill = Color.white.opacity(0.08)

    /// Glass border highlight
    static let amenGlassBorder = Color.white.opacity(0.18)
}

// MARK: - OpenGraphService

/// Fetches Open Graph metadata for URL link previews.
/// Used by ComposerLinkPreviewController to enrich auto-detected URLs.
actor OpenGraphService {
    static let shared = OpenGraphService()
    private init() {}

    struct Metadata {
        let title: String?
        let description: String?
        let imageURL: URL?
        let siteName: String?
        let url: URL
    }

    private var cache: [URL: Metadata] = [:]

    func fetchMetadata(for url: URL) async -> Metadata? {
        if let cached = cache[url] { return cached }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (compatible; AMENBot/1.0)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return nil }

        let title       = ogContent(from: html, property: "og:title") ?? htmlTitle(from: html)
        let description = ogContent(from: html, property: "og:description")
        let imageStr    = ogContent(from: html, property: "og:image")
        let siteName    = ogContent(from: html, property: "og:site_name")
        let imageURL    = imageStr.flatMap { URL(string: $0) }

        let meta = Metadata(
            title: title,
            description: description,
            imageURL: imageURL,
            siteName: siteName,
            url: url
        )
        cache[url] = meta
        return meta
    }

    // MARK: - Private helpers

    private func ogContent(from html: String, property: String) -> String? {
        // <meta property="og:title" content="...">  or  <meta content="..." property="og:title">
        let patterns = [
            "property=\"\(property)\"[^>]*content=\"([^\"]+)\"",
            "content=\"([^\"]+)\"[^>]*property=\"\(property)\""
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range]).htmlDecoded
            }
        }
        return nil
    }

    private func htmlTitle(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<title>([^<]+)</title>", options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html)
        else { return nil }
        return String(html[range]).htmlDecoded
    }
}

private extension String {
    var htmlDecoded: String {
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " ")
        ]
        return entities.reduce(self) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}

// MARK: - AIAssistService

/// Provides AI writing continuation for the post composer.
/// Routes all Claude calls through `bereanGenericProxy` — no API key on device.
actor AIAssistService {
    static let shared = AIAssistService()
    private init() {}

    struct Suggestion {
        let continuation: String
        let tone: String        // "encouraging" | "reflective" | "prayerful"
    }

    enum AIAssistError: Error {
        case emptyInput
        case networkError
        case parseError
    }

    /// Returns a faith-aligned writing continuation for the given draft text.
    /// - Parameter draft: The partial post text typed so far.
    /// - Parameter category: The post category (openTable, testimonies, prayer, etc.)
    func suggestContinuation(for draft: String, category: String = "openTable") async throws -> Suggestion {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIAssistError.emptyInput }

        let prompt = """
        You are a compassionate writing assistant for AMEN, a Christian community app.

        A user is writing a \(category) post and has typed:
        "\(trimmed.prefix(300))"

        Provide a brief, natural continuation (1-3 sentences) that:
        - Flows naturally from what they wrote
        - Is authentic and personal in tone
        - Is faith-aligned and uplifting
        - Does NOT sound AI-generated or formulaic

        Respond with JSON only:
        {"continuation": "...", "tone": "encouraging|reflective|prayerful"}
        """

        let payload: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 200,
            "messages": [["role": "user", "content": prompt]]
        ]

        do {
            let result = try await Functions.functions()
                .httpsCallable("bereanGenericProxy")
                .call(payload)

            guard
                let dict = result.data as? [String: Any],
                let textContent = dict["text"] as? String,
                let data = textContent.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let continuation = json["continuation"] as? String
            else {
                throw AIAssistError.parseError
            }

            let tone = json["tone"] as? String ?? "encouraging"
            return Suggestion(continuation: continuation, tone: tone)
        } catch {
            throw AIAssistError.networkError
        }
    }
}

// MARK: - GrowingTextEditor (UIViewRepresentable)

/// Auto-growing UITextView wrapper that doesn't need a fixed height frame.
/// Drop-in enhancement — CreatePostView uses it optionally via `textEditorView`.
struct GrowingTextEditor: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: UIFont = UIFont(name: "OpenSans-Regular", size: 17) ?? .systemFont(ofSize: 17)
    var onTextChange: ((String) -> Void)?

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = font
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.isScrollEnabled = false
        tv.text = text.isEmpty ? placeholder : text
        tv.textColor = text.isEmpty ? .placeholderText : .label
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard !context.coordinator.isEditing else { return }
        if text.isEmpty {
            uiView.text = placeholder
            uiView.textColor = .placeholderText
        } else {
            uiView.text = text
            uiView.textColor = .label
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: GrowingTextEditor
        var isEditing = false

        init(_ parent: GrowingTextEditor) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
            if textView.textColor == .placeholderText {
                textView.text = ""
                textView.textColor = .label
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            if textView.text.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = .placeholderText
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.textColor == .placeholderText ? "" : textView.text
            parent.onTextChange?(parent.text)
        }
    }
}

// MARK: - AI Assist Popup

/// Popup sheet shown when AI writing assist returns a suggestion.
struct AIAssistPopup: View {
    let suggestion: AIAssistService.Suggestion
    let onApply: (String) -> Void
    let onDismiss: () -> Void

    private var toneIcon: String {
        switch suggestion.tone {
        case "prayerful":   return "hands.sparkles.fill"
        case "reflective":  return "bubble.left.fill"
        default:            return "heart.fill"
        }
    }

    private var toneColor: Color {
        switch suggestion.tone {
        case "prayerful":   return .blue
        case "reflective":  return .purple
        default:            return Color(red: 0.78, green: 0.45, blue: 0.16)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.primary.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(toneColor.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: toneIcon)
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(toneColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Writing Assist")
                        .font(.systemScaled(15, weight: .semibold))
                    Text(suggestion.tone.capitalized + " tone")
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(20))
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            Divider().padding(.horizontal, 20)

            // Suggestion text
            ScrollView {
                Text(suggestion.continuation)
                    .font(AMENFont.regular(16))
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .frame(maxHeight: 160)

            Divider().padding(.horizontal, 20)

            // Actions
            HStack(spacing: 12) {
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.systemGray6))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    onApply(suggestion.continuation)
                } label: {
                    Text("Append")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(toneColor)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemBackground))
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
    }
}
