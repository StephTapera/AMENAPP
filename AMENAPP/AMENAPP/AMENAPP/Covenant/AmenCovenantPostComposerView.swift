import SwiftUI
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

// MARK: - Post Composer View Model

@MainActor
final class AmenCovenantPostComposerViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var body: String = ""
    @Published var selectedType: MemberComposerType = .post
    @Published var isAnonymous: Bool = false
    @Published var isSending: Bool = false
    @Published var sentSuccessfully: Bool = false
    @Published var moderationState: ModerationBannerState = .safe
    @Published var showToneCheck: Bool = false
    @Published var error: String?
    @Published var visibilityOption: PostVisibilityOption = .allMembers
    @Published var scriptureReference: String = ""
    @Published var isCheckingTone: Bool = false

    enum PostVisibilityOption: String, CaseIterable, Identifiable {
        case allMembers  = "all_members"
        case paidOnly    = "paid_members_only"
        case tierOnly    = "this_tier_only"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .allMembers: return "All Members"
            case .paidOnly:   return "Paid Members Only"
            case .tierOnly:   return "This Tier Only"
            }
        }

        var icon: String {
            switch self {
            case .allMembers: return "person.3.fill"
            case .paidOnly:   return "crown.fill"
            case .tierOnly:   return "circle.hexagongrid.fill"
            }
        }
    }

    private let functions = Functions.functions()

    var isBodyEmpty: Bool {
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSubmit: Bool {
        !isBodyEmpty && !isSending && moderationState != .blocked
    }

    func checkTone() async {
        guard !isCheckingTone else { return }
        isCheckingTone = true
        showToneCheck = false
        defer { isCheckingTone = false }
        // 1-second simulated AI tone check — replace with callable in production
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        moderationState = .safe
        showToneCheck = true
    }

    func submit(covenantId: String) async throws {
        guard canSubmit else { return }
        isSending = true
        defer { isSending = false }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRef = scriptureReference.trimmingCharacters(in: .whitespacesAndNewlines)

        switch selectedType {
        case .post, .announcement:
            var payload: [String: Any] = [
                "covenantId": covenantId,
                "body": trimmedBody,
                "type": selectedType.rawValue,
                "visibility": visibilityOption.rawValue
            ]
            if !trimmedTitle.isEmpty { payload["title"] = trimmedTitle }
            try await functions.httpsCallable("createCovenantPost").call(payload)

        case .prayerRequest:
            try await functions.httpsCallable("createCovenantMessage").call([
                "covenantId": covenantId,
                "body": trimmedBody,
                "messageType": "prayer_request",
                "isAnonymous": isAnonymous,
                "visibility": visibilityOption.rawValue
            ] as [String: Any])

        case .question:
            var payload: [String: Any] = [
                "covenantId": covenantId,
                "body": trimmedBody,
                "messageType": "question",
                "visibility": visibilityOption.rawValue
            ]
            if !trimmedRef.isEmpty { payload["scriptureReference"] = trimmedRef }
            try await functions.httpsCallable("createCovenantMessage").call(payload)

        case .testimony:
            var payload: [String: Any] = [
                "covenantId": covenantId,
                "body": trimmedBody,
                "messageType": "testimony",
                "visibility": visibilityOption.rawValue
            ]
            if !trimmedRef.isEmpty { payload["scriptureReference"] = trimmedRef }
            try await functions.httpsCallable("createCovenantMessage").call(payload)
        }

        sentSuccessfully = true
    }
}

// MARK: - Post Composer View

struct AmenCovenantPostComposerView: View {
    let covenantId: String?
    let preselectedType: MemberComposerType?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vm: AmenCovenantViewModel

    @StateObject private var composerVM = AmenCovenantPostComposerViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var bodyFieldFocused: Bool

    @State private var selectedCovenantId: String?

    private var effectiveCovenantId: String? { covenantId ?? selectedCovenantId }
    private var canShowFullComposer: Bool { effectiveCovenantId != nil }

    private var allowedTypes: [MemberComposerType] {
        AmenCovenantPermissions.memberComposerTypes(membership: vm.currentMembership)
    }

    private var isCreatorOrAdmin: Bool {
        AmenCovenantPermissions.isCreatorOrAdmin(membership: vm.currentMembership)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if covenantId == nil {
                        covenantPickerSection
                    }

                    if canShowFullComposer {
                        composerContent
                    } else {
                        covenantRequiredPlaceholder
                    }
                }
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("New Post")
            .toolbar { navToolbar }
            .onAppear {
                if let preselected = preselectedType, allowedTypes.contains(preselected) {
                    composerVM.selectedType = preselected
                } else if let first = allowedTypes.first {
                    composerVM.selectedType = first
                }
            }
            .onChange(of: composerVM.sentSuccessfully) { _, success in
                if success { dismiss() }
            }
            .alert("Posting Error", isPresented: Binding(
                get: { composerVM.error != nil },
                set: { if !$0 { composerVM.error = nil } }
            )) {
                Button("OK", role: .cancel) { composerVM.error = nil }
            } message: {
                Text(composerVM.error ?? "")
            }
        }
    }

    // MARK: - Nav Toolbar

    @ToolbarContentBuilder
    private var navToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") { dismiss() }
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Covenant Picker Section

    private var covenantPickerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Post to Community")

            let covenants = CovenantService.shared.covenants
            if covenants.isEmpty {
                Text("Join a Covenant community to start posting.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(covenants.enumerated()), id: \.element.id) { index, covenant in
                        Button {
                            selectedCovenantId = covenant.id
                            Task { await vm.loadMembership(for: covenant.id ?? "") }
                        } label: {
                            HStack(spacing: 14) {
                                AsyncImage(url: URL(string: covenant.avatarURL ?? "")) { phase in
                                    if case .success(let img) = phase {
                                        img.resizable().scaledToFill()
                                    } else {
                                        Color.purple.opacity(0.2)
                                    }
                                }
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(covenant.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(covenant.tagline)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if selectedCovenantId == covenant.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.purple)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "\(covenant.name)\(selectedCovenantId == covenant.id ? ", selected" : "")"
                        )

                        if index < covenants.count - 1 {
                            Divider().padding(.leading, 66)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Covenant Required Placeholder

    private var covenantRequiredPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Select a community above to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: - Full Composer Content

    private var composerContent: some View {
        VStack(spacing: 0) {
            if !allowedTypes.isEmpty {
                typeSelector
            }

            contentFields

            if isCreatorOrAdmin {
                visibilitySection
            }

            toneCheckSection

            submitSection
        }
    }

    // MARK: - Type Selector

    private var typeSelector: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Post Type")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(allowedTypes) { type in
                        Button {
                            withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8)) {
                                composerVM.selectedType = type
                                composerVM.showToneCheck = false
                                composerVM.moderationState = .safe
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: type.icon)
                                    .font(.system(size: 13, weight: .medium))
                                Text(type.displayName)
                                    .font(.subheadline.weight(.medium))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(
                                Capsule()
                                    .fill(
                                        composerVM.selectedType == type
                                            ? Color.purple
                                            : Color(uiColor: .secondarySystemGroupedBackground)
                                    )
                            )
                            .foregroundStyle(composerVM.selectedType == type ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "\(type.displayName)\(composerVM.selectedType == type ? ", selected" : "")"
                        )
                        .accessibilityAddTraits(composerVM.selectedType == type ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: - Content Fields (type-gated)

    @ViewBuilder
    private var contentFields: some View {
        switch composerVM.selectedType {
        case .post, .announcement:
            postFields
        case .prayerRequest:
            prayerRequestFields
        case .question:
            questionFields
        case .testimony:
            testimonyFields
        }
    }

    private var postFields: some View {
        VStack(spacing: 0) {
            sectionHeader("Content")
            VStack(spacing: 0) {
                TextField("Title (optional)", text: $composerVM.title)
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                    .accessibilityLabel("Post title, optional")

                Divider().padding(.horizontal, 16)

                textEditorField(
                    binding: $composerVM.body,
                    placeholder: "Share something with the community…",
                    minHeight: 150,
                    accessibilityLabel: "Post body"
                )
            }
            .composerGlassCard()
        }
    }

    private var prayerRequestFields: some View {
        VStack(spacing: 0) {
            sectionHeader("Prayer Request")
            VStack(spacing: 0) {
                textEditorField(
                    binding: $composerVM.body,
                    placeholder: "Share your prayer request with the community…",
                    minHeight: 150,
                    accessibilityLabel: "Prayer request"
                )

                Divider().padding(.horizontal, 16)

                Toggle(isOn: $composerVM.isAnonymous) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill.questionmark")
                            .foregroundStyle(.secondary)
                        Text("Post Anonymously")
                            .font(.subheadline)
                    }
                }
                .tint(.purple)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .accessibilityLabel("Post anonymously")
            }
            .composerGlassCard()
        }
    }

    private var questionFields: some View {
        VStack(spacing: 0) {
            sectionHeader("Your Question")
            VStack(spacing: 0) {
                textEditorField(
                    binding: $composerVM.body,
                    placeholder: "What's your question for the community?",
                    minHeight: 150,
                    accessibilityLabel: "Question"
                )

                Divider().padding(.horizontal, 16)

                TextField("Attach a scripture reference (optional)", text: $composerVM.scriptureReference)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .accessibilityLabel("Scripture reference, optional")
            }
            .composerGlassCard()
        }
    }

    private var testimonyFields: some View {
        VStack(spacing: 0) {
            sectionHeader("Your Testimony")
            VStack(spacing: 0) {
                textEditorField(
                    binding: $composerVM.body,
                    placeholder: "Share what God has done…",
                    minHeight: 150,
                    accessibilityLabel: "Testimony"
                )

                Divider().padding(.horizontal, 16)

                TextField("Scripture reference (optional)", text: $composerVM.scriptureReference)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .accessibilityLabel("Scripture reference, optional")
            }
            .composerGlassCard()
        }
    }

    // MARK: - Text Editor Helper

    private func textEditorField(
        binding: Binding<String>,
        placeholder: String,
        minHeight: CGFloat,
        accessibilityLabel: String
    ) -> some View {
        TextEditor(text: binding)
            .font(.body)
            .frame(minHeight: minHeight)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .focused($bodyFieldFocused)
            .accessibilityLabel(accessibilityLabel)
            .overlay(alignment: .topLeading) {
                if binding.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 16)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: - Visibility Section

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Visibility")

            VStack(spacing: 0) {
                let options = AmenCovenantPostComposerViewModel.PostVisibilityOption.allCases
                ForEach(Array(options.enumerated()), id: \.element) { index, option in
                    Button {
                        composerVM.visibilityOption = option
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: option.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(.purple)
                                .frame(width: 28)

                            Text(option.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.primary)

                            Spacer()

                            if composerVM.visibilityOption == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.purple)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(option.displayName)\(composerVM.visibilityOption == option ? ", selected" : "")"
                    )
                    .accessibilityAddTraits(composerVM.visibilityOption == option ? .isSelected : [])

                    if index < options.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .composerGlassCard()
        }
    }

    // MARK: - Tone Check Section

    private var toneCheckSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await composerVM.checkTone() }
            } label: {
                HStack(spacing: 8) {
                    if composerVM.isCheckingTone {
                        ProgressView()
                            .tint(.purple)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.purple)
                    }
                    Text(composerVM.isCheckingTone ? "Checking tone…" : "Check tone before posting")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.purple)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.purple.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            .disabled(composerVM.isBodyEmpty || composerVM.isCheckingTone)
            .padding(.horizontal, 20)
            .accessibilityLabel("Check the tone of your post with AI before posting")

            if composerVM.showToneCheck {
                CovenantModerationBanner(state: composerVM.moderationState)
                    .padding(.horizontal, 20)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.bottom, 20)
        .animation(
            reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.85),
            value: composerVM.showToneCheck
        )
    }

    // MARK: - Submit Section

    private var submitSection: some View {
        CovenantCapsuleButton(
            title: "Post",
            variant: composerVM.isSending ? .quiet : .primary,
            isLoading: composerVM.isSending
        ) {
            guard let cid = effectiveCovenantId else { return }
            Task {
                do {
                    try await composerVM.submit(covenantId: cid)
                } catch {
                    composerVM.error = error.localizedDescription
                }
            }
        }
        .disabled(!composerVM.canSubmit || effectiveCovenantId == nil)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }
}

// MARK: - Glass Card Modifier (composer-scoped)

private extension View {
    func composerGlassCard() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
    }
}
