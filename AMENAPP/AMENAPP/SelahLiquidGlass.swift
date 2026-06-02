//
//  SelahLiquidGlass.swift
//  AMENAPP
//
//  Reusable Liquid Glass components for the Selah scripture study experience.
//  Design language: white/neutral background, translucent frosted cards,
//  thin gradient borders, soft shadows, readable black text, subtle blue accents.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - SelahGlassCard

/// Generic translucent frosted card container.
struct SelahGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 16
    let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.55), Color.white.opacity(0.10)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 10, y: 3)
                    .shadow(color: Color.black.opacity(0.02), radius: 2, y: 1)
            )
    }
}

// MARK: - SelahGlassTopShell

/// Top-bar glass container with a subtle frosted bottom edge.
struct SelahGlassTopShell<Content: View>: View {
    let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.30), Color.white.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .ignoresSafeArea(edges: .top)
            )
    }
}

// MARK: - SelahGlassSegmentedControl

/// Horizontal segmented pill control with matchedGeometryEffect lens.
struct SelahGlassSegmentedControl<T: Hashable & CaseIterable & Identifiable>: View
    where T: RawRepresentable, T.RawValue == String {
    @Binding var selection: T
    var iconMap: ((T) -> String)?
    @Namespace private var lensNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(T.allCases as! [T])) { item in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(reduceMotion ? .none
                                        : .spring(response: 0.3, dampingFraction: 0.78)) {
                            selection = item
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if let icon = iconMap?(item) {
                                Image(systemName: icon)
                                    .font(.system(size: 11, weight: selection == item ? .semibold : .regular))
                            }
                            if selection == item {
                                Text(item.rawValue)
                                    .font(.system(size: 12, weight: .semibold))
                                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                            }
                        }
                        .foregroundStyle(selection == item ? .primary : .secondary)
                        .padding(.horizontal, selection == item ? 14 : 12)
                        .padding(.vertical, 7)
                        .background {
                            if selection == item {
                                Capsule()
                                    .fill(.regularMaterial)
                                    .overlay(
                                        Capsule().strokeBorder(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.80), Color.white.opacity(0.20)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                    )
                                    .shadow(color: Color.black.opacity(0.10), radius: 5, y: 2)
                                    .matchedGeometryEffect(id: "glassSegLens", in: lensNS)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.rawValue)
                    .accessibilityAddTraits(selection == item ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
        }
        .frame(height: 44)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.55), Color.white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
                .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 4)
        )
        .clipShape(Capsule())
    }
}

// MARK: - SelahGlassCommandBar

/// 4-button command bar docked at the bottom of the Selah screen.
/// Actions: Save · Reflect · Ask Berean · Continue
struct SelahGlassCommandBar: View {
    let onSave: () -> Void
    let onReflect: () -> Void
    let onBerean: () -> Void
    let onContinue: () -> Void
    var isSaving: Bool = false
    var isContinuing: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            commandButton(
                icon: isSaving ? "checkmark" : "bookmark.fill",
                label: isSaving ? "Saved" : "Save",
                tint: .blue,
                isLoading: isSaving,
                accessibilityLabel: "Save to Selah memory",
                action: onSave
            )
            divider
            commandButton(
                icon: "pencil",
                label: "Reflect",
                tint: .purple,
                accessibilityLabel: "Write a reflection",
                action: onReflect
            )
            divider
            commandButton(
                icon: "sparkles",
                label: "Ask Berean",
                tint: .indigo,
                accessibilityLabel: "Ask Berean a question",
                action: onBerean
            )
            divider
            commandButton(
                icon: isContinuing ? "checkmark.circle.fill" : "arrow.forward.circle.fill",
                label: isContinuing ? "Added" : "Continue",
                tint: .teal,
                isLoading: isContinuing,
                accessibilityLabel: "Create a continuation",
                action: onContinue
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.65), Color.white.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.12), radius: 18, y: 6)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
        )
        .padding(.horizontal, 20)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(width: 1, height: 30)
    }

    @ViewBuilder
    private func commandButton(
        icon: String,
        label: String,
        tint: Color,
        isLoading: Bool = false,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.75)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(tint)
                }
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isLoading ? .secondary : tint.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(accessibilityLabel)
        .frame(minHeight: 44)
    }
}

// MARK: - SelahGlassSheet

/// Consistent sheet container with a frosted drag indicator and title.
struct SelahGlassSheet<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
                .safeAreaInset(edge: .top) {
                    if let sub = subtitle {
                        Text(sub)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }
}

// MARK: - SelahContextPill

/// Small tappable tag pill for section-level contextual actions.
struct SelahContextPill: View {
    let label: String
    var icon: String? = nil
    var tint: Color = .blue
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) { pillBody }
                    .buttonStyle(.plain)
            } else {
                pillBody
            }
        }
        .accessibilityLabel(label)
        .frame(minHeight: 44)
    }

    private var pillBody: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(tint.opacity(0.10))
                .overlay(
                    Capsule().strokeBorder(tint.opacity(0.20), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - SelahReflectionService

/// Client-side write service for private Selah reflections.
/// Writes to `users/{uid}/selah_reflections` with no AI enrichment.
@MainActor
final class SelahReflectionService {
    static let shared = SelahReflectionService()
    private let db = Firestore.firestore()

    private var userId: String { Auth.auth().currentUser?.uid ?? "" }

    struct SelahReflection {
        let text: String
        let verseReference: String?
        let studyTitle: String
        let themes: [String]
        let sectionType: String?
    }

    @discardableResult
    func saveReflection(_ reflection: SelahReflection) async throws -> String {
        guard !userId.isEmpty else { throw SelahReflectionError.notAuthenticated }
        guard !reflection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SelahReflectionError.emptyText
        }
        let ref = try await db.collection("users").document(userId)
            .collection("selah_reflections")
            .addDocument(data: [
                "userId": userId,
                "text": String(reflection.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000)),
                "verseReference": reflection.verseReference ?? "",
                "studyTitle": String(reflection.studyTitle.prefix(100)),
                "themes": reflection.themes,
                "sectionType": reflection.sectionType ?? "",
                "createdAt": Timestamp(date: Date()),
                "updatedAt": Timestamp(date: Date()),
            ])
        return ref.documentID
    }

    enum SelahReflectionError: LocalizedError {
        case notAuthenticated
        case emptyText

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Sign in to save reflections."
            case .emptyText: return "Please write something before saving."
            }
        }
    }
}

// MARK: - SelahScriptureBereanService

/// Calls the askBereanAboutSelahScripture Cloud Function.
@MainActor
final class SelahScriptureBereanService {
    static let shared = SelahScriptureBereanService()
    private let functions = Functions.functions()

    struct BereanRequest {
        let question: String
        let verseReference: String?
        let studyContent: String
        let studyTitle: String
    }

    func ask(_ request: BereanRequest) async throws -> String {
        let callable = functions.httpsCallable("askBereanAboutSelahScripture")
        let data: [String: Any] = [
            "question": String(request.question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)),
            "verseReference": request.verseReference ?? "",
            "studyTitle": String(request.studyTitle.prefix(100)),
            // Pass first 800 chars of study content as context only
            "studyContext": String(request.studyContent.prefix(800)),
        ]
        let result = try await callable.safeCall(data)
        guard let dict = result.data as? [String: Any],
              let response = dict["response"] as? String else {
            throw BereanError.unexpectedResponse
        }
        return response
    }

    enum BereanError: LocalizedError {
        case unexpectedResponse
        var errorDescription: String? { "Berean couldn't respond right now. Try again." }
    }
}

// MARK: - SelahMemoryCallableService

/// Calls the saveSelahMemory Cloud Function for server-side AI enrichment.
@MainActor
final class SelahMemoryCallableService {
    static let shared = SelahMemoryCallableService()
    private let functions = Functions.functions()

    struct MemoryRequest {
        let title: String
        let bodyText: String
        let linkedScriptureRefs: [String]
        let themes: [String]
        let intentSignal: String
    }

    func save(_ request: MemoryRequest) async throws -> String {
        let callable = functions.httpsCallable("saveSelahMemory")
        let data: [String: Any] = [
            "title": String(request.title.prefix(100)),
            "bodyText": String(request.bodyText.prefix(500)),
            "linkedMediaIds": [] as [String],
            "linkedScriptureRefs": request.linkedScriptureRefs,
            "meaningTags": request.themes.map { ["category": $0, "label": $0, "confidence": 1.0] },
            "intentSignal": request.intentSignal,
        ]
        let result = try await callable.safeCall(data)
        if let dict = result.data as? [String: Any], let id = dict["memoryId"] as? String {
            return id
        }
        return ""
    }
}

// MARK: - SelahContinuationCallableService

/// Calls the createSelahContinuation Cloud Function.
@MainActor
final class SelahContinuationCallableService {
    static let shared = SelahContinuationCallableService()
    private let functions = Functions.functions()

    struct ContinuationRequest {
        let promptText: String
        let contextSummary: String
        let action: String
        let scriptureRef: String?
        let relevanceScore: Double
    }

    func create(_ request: ContinuationRequest) async throws -> String {
        let callable = functions.httpsCallable("createSelahContinuation")
        var data: [String: Any] = [
            "promptText": String(request.promptText.prefix(300)),
            "contextSummary": String(request.contextSummary.prefix(200)),
            "action": request.action,
            "relevanceScore": request.relevanceScore,
        ]
        if let ref = request.scriptureRef { data["scriptureRef"] = ref }
        let result = try await callable.safeCall(data)
        if let dict = result.data as? [String: Any], let id = dict["continuationId"] as? String {
            return id
        }
        return ""
    }
}
