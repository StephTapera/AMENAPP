// AmenUniversalComposer.swift
// AMEN App — Community OS
//
// A3: The single modal creation surface for all intents.
// Every creation flow (discuss, pray, share, study, etc.) routes through here.
// Opens as a bottom sheet with .medium / .large detents.
//
// Design rules (C3-design-tokens.md):
//   • System semantic colors only — no amenGold, no hex, no dark backgrounds
//   • Primary action button: Color.accentColor background, white text, 56pt height
//   • All labels and text use Dynamic Type only
//   • Provenance attribution chip for source-derived objects

import SwiftUI
import FirebaseAuth
import FirebaseFunctions

// MARK: - Audience levels

private enum AudienceLevel: String, CaseIterable, Identifiable {
    case `private`      = "private"
    case trustedCircle  = "trustedCircle"
    case spaceMembers   = "spaceMembers"
    case publicFeed     = "publicFeed"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .private:      return "Only Me"
        case .trustedCircle: return "Trusted Circle"
        case .spaceMembers: return "Space Members"
        case .publicFeed:   return "Public"
        }
    }
}

// MARK: - CommunityOSService

private struct CommunityOSService {
    static let shared = CommunityOSService()

    private let functions = Functions.functions()

    private init() {}

    /// Transforms a source object using the server-owned `transformObject` callable.
    func transform(
        sourceRef: String?,
        sourceType: String?,
        intent: String,
        actorId: String,
        audience: String,
        title: String
    ) async throws -> (objectId: String, objectType: String) {
        var payload: [String: Any] = [
            "intent": intent,
            "actorId": actorId,
            "audienceOverride": audience,
            "title": title
        ]
        if let sourceRef, !sourceRef.isEmpty { payload["sourceRef"] = sourceRef }
        if let sourceType, !sourceType.isEmpty { payload["sourceType"] = sourceType }

        let result = try await functions.httpsCallable("transformObject").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw CommunityOSServiceError.invalidResponse
        }

        if let objectId = data["newObjectId"] as? String,
           let objectType = data["newObjectType"] as? String {
            return (objectId, objectType)
        }
        if let objectId = data["objectId"] as? String,
           let objectType = data["objectType"] as? String {
            return (objectId, objectType)
        }
        throw CommunityOSServiceError.invalidResponse
    }
}

private enum CommunityOSServiceError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "CommunityOS returned an invalid transform response."
    }
}

// MARK: - AmenUniversalComposer

/// The single creation surface for all C2 intents.
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showComposer) {
///     AmenUniversalComposer(
///         sourceRef: "posts/abc123",
///         sourceType: "post",
///         initialIntent: "discuss",
///         isPresented: $showComposer
///     ) { newId, newType in
///         print("Created \(newType): \(newId)")
///     }
/// }
/// ```
struct AmenUniversalComposer: View {

    // MARK: Inputs

    /// Firestore path of the source object (nil = new standalone object).
    let sourceRef: String?

    /// AmenObjectType raw value of the source (nil = new object).
    let sourceType: String?

    /// AmenIntent raw value to pre-select (nil = user chooses).
    let initialIntent: String?

    @Binding var isPresented: Bool

    /// Called after successful creation: (newObjectId, newObjectType).
    var onCreated: ((String, String) -> Void)?

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Internal state

    @State private var selectedIntent: String?
    @State private var title: String = ""
    @State private var audienceLevel: String = AudienceLevel.private.rawValue
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false

    // MARK: Computed

    /// Intents available for the given source type — filtered from the full 11-intent set.
    /// In production these would be filtered by the C2 transform matrix lookup.
    private var availableIntents: [String] {
        availableIntentsFor(sourceType: sourceType)
    }

    private var primaryButtonLabel: String {
        guard let intent = selectedIntent else { return "Select an Intent" }
        switch intent {
        case "share":     return "Share"
        case "discuss":   return "Open Discussion"
        case "pray":      return "Create Prayer"
        case "study":     return "Start Study"
        case "teach":     return "Create Teaching"
        case "ask":       return "Send Question"
        case "invite":    return "Send Invite"
        case "volunteer": return "Volunteer"
        case "hire":      return "Post Role"
        case "mentor":    return "Request Mentor"
        case "announce":  return "Announce"
        default:          return "Create"
        }
    }

    private var composerPlaceholder: String {
        guard let intent = selectedIntent else { return "What would you like to create?" }
        switch intent {
        case "share":     return "Add a thought before sharing…"
        case "discuss":   return "What should the discussion focus on?"
        case "pray":      return "What is this prayer about?"
        case "study":     return "What aspect do you want to study?"
        case "teach":     return "What is the main teaching point?"
        case "ask":       return "What would you like to ask?"
        case "invite":    return "Add a personal note to the invite…"
        case "volunteer": return "What can you offer?"
        case "hire":      return "Describe the role and opportunity…"
        case "mentor":    return "What area of mentorship are you seeking?"
        case "announce":  return "What would you like to announce?"
        default:          return "Describe what you're creating…"
        }
    }

    /// True when the selected intent involves AI (study/teach/berean-related).
    private var intentUsesAI: Bool {
        guard let intent = selectedIntent else { return false }
        return ["study", "teach", "ask"].contains(intent)
    }

    private var canSubmit: Bool {
        selectedIntent != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Provenance banner — shown when composing from a source object
                    if let ref = sourceRef, let type = sourceType {
                        provenanceBanner(ref: ref, type: type)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                    }

                    // Intent picker
                    intentSection
                        .padding(.top, sourceRef != nil ? 0 : 16)

                    Divider()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                    // Title / body input
                    titleSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    // Audience selector
                    audienceSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)

                    // AI disclosure
                    if intentUsesAI {
                        aiDisclosureSection
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }

                    // Primary action button
                    primaryActionButton
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Create")
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: .label))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Cancel creation")
                }
            }
            .alert("Something went wrong", isPresented: $showError) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .onAppear {
            if let initial = initialIntent, availableIntents.contains(initial) {
                selectedIntent = initial
            } else if availableIntents.count == 1 {
                selectedIntent = availableIntents.first
            }
        }
    }

    // MARK: - Provenance banner

    private func provenanceBanner(ref: String, type: String) -> some View {
        let shortRef: String = {
            let parts = ref.split(separator: "/")
            if parts.count >= 2 {
                return "\(parts[parts.count - 2])/\(String(parts.last ?? Substring(ref)).prefix(8))…"
            }
            return String(ref.prefix(20))
        }()
        let typeDisplay = type.replacingOccurrences(of: "_", with: " ").capitalized

        return HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.caption2)
            Text("From \(typeDisplay) · \(shortRef)")
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(Color(uiColor: .secondaryLabel))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
        )
        .accessibilityLabel("Source: \(typeDisplay), reference \(shortRef)")
    }

    // MARK: - Intent section

    private var intentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What would you like to do?")
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .padding(.horizontal, 16)

            IntentPickerRow(
                availableIntents: availableIntents,
                selectedIntent: $selectedIntent
            )
        }
    }

    // MARK: - Title / body input

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if selectedIntent != nil {
                Text("Details")
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            TextField(composerPlaceholder, text: $title, axis: .vertical)
                .font(.body)
                .foregroundStyle(Color(uiColor: .label))
                .tint(Color.accentColor)
                .lineLimit(3...8)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .accessibilityLabel("Content field")
                .accessibilityHint(composerPlaceholder)
        }
    }

    // MARK: - Audience selector

    private var audienceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Who can see this?")
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))

            Picker("Audience", selection: $audienceLevel) {
                ForEach(AudienceLevel.allCases) { level in
                    Text(level.displayName).tag(level.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Audience selector")
            .accessibilityHint("Choose who can see this content")
        }
    }

    // MARK: - AI disclosure

    private var aiDisclosureSection: some View {
        AmenAIUsageLabel(text: "AI-assisted — verify before sharing")
            .accessibilityLabel("AI usage disclosure: content is AI-assisted, verify before sharing")
    }

    // MARK: - Primary action button

    private var primaryActionButton: some View {
        Button {
            submitIntent()
        } label: {
            ZStack {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(primaryButtonLabel)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(canSubmit ? Color.white : Color(uiColor: .tertiaryLabel))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                canSubmit
                    ? Color.accentColor
                    : Color(uiColor: .tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.84),
            value: canSubmit
        )
        .accessibilityLabel(primaryButtonLabel)
        .accessibilityHint(canSubmit ? "Tap to create" : "Add content and select an intent first")
    }

    // MARK: - Submit

    private func submitIntent() {
        guard let intent = selectedIntent, canSubmit else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        isSubmitting = true

        Task {
            defer { isSubmitting = false }
            do {
                let actorId = Auth.auth().currentUser?.uid ?? ""
                let result = try await CommunityOSService.shared.transform(
                    sourceRef: sourceRef,
                    sourceType: sourceType,
                    intent: intent,
                    actorId: actorId,
                    audience: audienceLevel,
                    title: trimmedTitle
                )
                onCreated?(result.objectId, result.objectType)
                isPresented = false
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Intent filter helper

    /// Returns the available intents for a given source type.
    /// In production this delegates to the C2 transform matrix.
    /// Blocked combinations (marked `–` in the matrix) are omitted.
    private func availableIntentsFor(sourceType: String?) -> [String] {
        guard let sourceType else {
            // No source — all creation intents are available
            return ["share", "discuss", "pray", "study", "teach", "ask",
                    "invite", "volunteer", "hire", "mentor", "announce"]
        }
        switch sourceType {
        case "post":
            return ["share", "discuss", "pray", "study", "teach", "ask",
                    "invite", "mentor", "announce"]
        case "prayer_request":
            return ["discuss", "pray", "ask", "mentor"]
        case "church_note", "sermon", "berean_insight", "scripture_reference":
            return ["share", "discuss", "pray", "study", "teach", "ask", "mentor", "announce"]
        case "event":
            return ["share", "discuss", "pray", "teach", "ask",
                    "invite", "volunteer", "announce"]
        case "space_object", "organization_object":
            return ["share", "discuss", "pray", "study", "teach", "ask",
                    "invite", "volunteer", "announce"]
        case "job":
            return ["share", "discuss", "ask", "invite", "hire", "announce"]
        case "message":
            return ["discuss", "pray", "ask", "mentor"]
        case "mentorship_request":
            return ["pray", "study", "ask", "mentor"]
        case "media_object":
            return ["share", "discuss", "pray", "teach", "ask", "announce"]
        default:
            return ["share", "discuss", "pray", "study", "ask"]
        }
    }
}

// MARK: - Preview

#Preview("Composer — from Post") {
    struct PreviewWrapper: View {
        @State private var shown = true
        var body: some View {
            Color(uiColor: .systemGroupedBackground)
                .sheet(isPresented: $shown) {
                    AmenUniversalComposer(
                        sourceRef: "posts/abc123xyz",
                        sourceType: "post",
                        initialIntent: "discuss",
                        isPresented: $shown
                    ) { id, type in
                        print("Created \(type): \(id)")
                    }
                }
        }
    }
    return PreviewWrapper()
}

#Preview("Composer — standalone") {
    struct PreviewWrapper: View {
        @State private var shown = true
        var body: some View {
            Color(uiColor: .systemGroupedBackground)
                .sheet(isPresented: $shown) {
                    AmenUniversalComposer(
                        sourceRef: nil,
                        sourceType: nil,
                        initialIntent: nil,
                        isPresented: $shown
                    )
                }
        }
    }
    return PreviewWrapper()
}
