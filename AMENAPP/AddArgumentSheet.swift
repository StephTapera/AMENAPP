import SwiftUI
import UIKit

struct AddArgumentSheet: View {
    @ObservedObject var vm: ReasoningViewModel
    var parentNodeId: String? = nil
    var preferredType: DiscussionNode.NodeType = .argument

    @State private var claimText = ""
    @State private var evidenceText = ""
    @State private var selectedType: DiscussionNode.NodeType = .argument
    @State private var isScreening = false
    @State private var showFlagWarning = false
    @State private var showDiscardAlert = false
    @State private var guidanceMessage = ""
    @State private var sourceSuggestion = ""

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.black.opacity(0.14))
                    .frame(width: 42, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                header

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        topicContextCard
                        typeSelector
                        primaryInputCard
                        evidenceInputCard
                        smartGuidanceCard

                        if showFlagWarning && !vm.manipulationFlags.isEmpty {
                            flagWarningCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 100)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
        }
        .onAppear {
            selectedType = preferredType
            refreshGuidance()
        }
        .onChange(of: selectedType) { _, _ in
            dlog("[DiscussionThread] contribution_type_switched type=\(selectedType.rawValue) postId=\(vm.postId)")
            refreshGuidance()
        }
        .onChange(of: claimText) { _, _ in
            detectEvidenceCandidate()
            refreshGuidance()
        }
        .onChange(of: evidenceText) { _, _ in
            refreshGuidance()
        }
        .alert("Discard Draft?", isPresented: $showDiscardAlert) {
            Button("Keep Editing", role: .cancel) { }
            Button("Discard", role: .destructive) {
                dlog("[DiscussionThread] draft_discarded postId=\(vm.postId)")
                dismiss()
            }
        } message: {
            Text("You have a draft in progress. Do you want to discard it?")
        }
    }

    private var header: some View {
        AmenGlassCard(cornerRadius: 24, padding: 12) {
            HStack {
                Button(action: handleDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.6))
                        )
                }
                .buttonStyle(.plain)

                VStack(spacing: 2) {
                    Text("Add Your View")
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(selectedTypeTitle)
                        .font(.systemScaled(11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 16)
    }

    private var topicContextCard: some View {
        AmenGlassCard(cornerRadius: 22, padding: 14, tint: Color.purple.opacity(0.6)) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Responding to")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(vm.discussion.claim.isEmpty ? vm.postText : vm.discussion.claim)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }
        }
    }

    private var typeSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contribution type")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                ForEach([DiscussionNode.NodeType.argument, .counterargument, .evidence, .viewUpdate], id: \.self) { type in
                    typeTile(for: type)
                }
            }
        }
    }

    private func typeTile(for type: DiscussionNode.NodeType) -> some View {
        let selected = selectedType == type
        let tint = accentColor(for: type)

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedType = type
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: type.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? tint : .secondary)
                Text(type.label)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(typeHint(for: type))
                    .font(.systemScaled(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(selected ? tint.opacity(0.10) : Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(selected ? tint.opacity(0.35) : Color.black.opacity(0.05), lineWidth: selected ? 1 : 0.6)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.label)
    }

    private var primaryInputCard: some View {
        AmenGlassCard(cornerRadius: 22, padding: 14, tint: accentColor(for: selectedType).opacity(0.6)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(primaryFieldTitle)
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(claimText.trimmingCharacters(in: .whitespacesAndNewlines).count)")
                        .font(.systemScaled(11))
                        .foregroundStyle(.tertiary)
                }

                ZStack(alignment: .topLeading) {
                    if claimText.isEmpty {
                        Text(primaryPlaceholder)
                            .font(.systemScaled(15))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                    }

                    TextEditor(text: $claimText)
                        .font(.systemScaled(15))
                        .foregroundStyle(.primary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 150)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.clear)
                }
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.62))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(accentColor(for: selectedType).opacity(claimText.isEmpty ? 0.08 : 0.25), lineWidth: 0.8)
                        )
                )
            }
        }
    }

    private var evidenceInputCard: some View {
        AmenGlassCard(cornerRadius: 22, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Evidence / Sources")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.secondary)

                ZStack(alignment: .topLeading) {
                    if evidenceText.isEmpty {
                        Text("Add links, citations, scripture, or supporting detail.")
                            .font(.systemScaled(14))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }

                    TextEditor(text: $evidenceText)
                        .font(.systemScaled(14))
                        .foregroundStyle(.primary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 92)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.clear)
                }
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.58))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.8)
                        )
                )

                if !sourceSuggestion.isEmpty {
                    Label(sourceSuggestion, systemImage: "link.badge.plus")
                        .font(.systemScaled(11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var smartGuidanceCard: some View {
        AmenGlassCard(cornerRadius: 20, padding: 14, tint: accentColor(for: selectedType).opacity(0.45)) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Smart guidance", systemImage: "lightbulb")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(guidanceMessage)
                    .font(.systemScaled(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var flagWarningCard: some View {
        AmenGlassCard(cornerRadius: 20, padding: 14, tint: Color.orange.opacity(0.6)) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Check Argument found a few concerns", systemImage: "exclamationmark.triangle.fill")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(Color.orange.opacity(0.92))

                AMENFlowLayout(spacing: 6) {
                    ForEach(vm.manipulationFlags, id: \.self) { flag in
                        AmenGlassPill(
                            title: flag.replacingOccurrences(of: "_", with: " ").capitalized,
                            icon: "exclamationmark.circle",
                            tint: Color.orange.opacity(0.92)
                        )
                    }
                }

                Text("You can still post, but it may help to refine tone, fairness, or support.")
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                Task { await runScreening() }
            } label: {
                HStack(spacing: 8) {
                    if isScreening {
                        ProgressView().controlSize(.small).tint(.primary)
                    } else {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(isScreening ? "Checking..." : "Check Argument")
                        .font(.systemScaled(13, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.8))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canCheck)
            .opacity(canCheck ? 1 : 0.45)

            Button {
                Task { await submit() }
            } label: {
                HStack(spacing: 8) {
                    if vm.isPostingNode {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(postButtonTitle)
                        .font(.systemScaled(14, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Capsule(style: .continuous).fill(Color.black))
            }
            .buttonStyle(.plain)
            .disabled(!canPost)
            .opacity(canPost ? 1 : 0.45)
        }
    }

    private var selectedTypeTitle: String {
        switch selectedType {
        case .argument: return "Make the clearest case you can"
        case .counterargument: return "Respond to the strongest opposing claim"
        case .evidence: return "Add supporting detail or a source"
        case .viewUpdate: return "Explain what changed your perspective"
        }
    }

    private var primaryFieldTitle: String {
        switch selectedType {
        case .argument: return "Your argument"
        case .counterargument: return "Your counterargument"
        case .evidence: return "Your evidence"
        case .viewUpdate: return "What changed"
        }
    }

    private var primaryPlaceholder: String {
        switch selectedType {
        case .argument:
            return "State your argument clearly…"
        case .counterargument:
            return "Respond to the strongest opposing claim…"
        case .evidence:
            return "Add a fact, source, verse, or supporting detail…"
        case .viewUpdate:
            return "What changed your thinking, and why?"
        }
    }

    private var postButtonTitle: String {
        switch vm.submissionState {
        case .posting:
            return "Posting..."
        default:
            return "Post"
        }
    }

    private var canCheck: Bool {
        !claimText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isScreening && !vm.isPostingNode
    }

    private var canPost: Bool {
        validationMessage == nil && !vm.isPostingNode && !isScreening
    }

    private var validationMessage: String? {
        let trimmed = claimText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch selectedType {
        case .argument:
            return trimmed.count >= 24 ? nil : "Add a bit more substance before posting."
        case .counterargument:
            return trimmed.count >= 24 ? nil : "Counterarguments should address a real claim with enough detail."
        case .evidence:
            return trimmed.count >= 10 ? nil : "Add at least one meaningful piece of support."
        case .viewUpdate:
            return trimmed.count >= 18 ? nil : "Explain what changed your perspective."
        }
    }

    private func typeHint(for type: DiscussionNode.NodeType) -> String {
        switch type {
        case .argument: return "Make the strongest positive case."
        case .counterargument: return "Address the best opposing idea."
        case .evidence: return "Support a claim with specifics."
        case .viewUpdate: return "Reflect on what changed."
        }
    }

    private func accentColor(for type: DiscussionNode.NodeType) -> Color {
        switch type {
        case .argument: return Color(red: 0.55, green: 0.25, blue: 1.0)
        case .counterargument: return Color(red: 0.87, green: 0.63, blue: 0.22)
        case .evidence: return Color(red: 0.24, green: 0.72, blue: 0.52)
        case .viewUpdate: return Color.black.opacity(0.72)
        }
    }

    private func handleDismiss() {
        if isDirty {
            showDiscardAlert = true
        } else {
            dismiss()
        }
    }

    private var isDirty: Bool {
        !claimText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !evidenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func refreshGuidance() {
        let trimmed = claimText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let validationMessage {
            guidanceMessage = validationMessage
            return
        }

        if selectedType == .counterargument {
            guidanceMessage = "Address the strongest version of the other view. Keep the focus on the claim, not the person."
        } else if selectedType == .evidence && evidenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guidanceMessage = "If this is a factual claim, add a source, verse, or concrete supporting detail."
        } else if trimmed.contains("http") || trimmed.contains("www.") || trimmed.contains(":") && trimmed.contains(" ") == false {
            guidanceMessage = "This looks source-like. Consider duplicating it into the Evidence / Sources field for clarity."
        } else if selectedType == .viewUpdate {
            guidanceMessage = "Explain what changed your mind and what helped you see the issue differently."
        } else if trimmed.count < 60 {
            guidanceMessage = "Aim for clarity and substance. Thoughtful, concise responses work best here."
        } else {
            guidanceMessage = "Keep the tone charitable, specific, and focused on the idea being discussed."
        }
    }

    private func detectEvidenceCandidate() {
        let trimmed = claimText.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksLikeVerse = trimmed.range(of: #"\b[1-3]?\s?[A-Za-z]+\s\d+:\d+\b"#, options: .regularExpression) != nil
        let looksLikeLink = trimmed.contains("http://") || trimmed.contains("https://") || trimmed.contains("www.")
        sourceSuggestion = (looksLikeVerse || looksLikeLink) && evidenceText.isEmpty
            ? "You can also place that source in Evidence / Sources to make the thread easier to scan."
            : ""
    }

    private func runScreening() async {
        isScreening = true
        showFlagWarning = false
        vm.manipulationFlags = []
        await vm.screenArgument(claimText)
        isScreening = false
        withAnimation(.easeInOut(duration: 0.18)) {
            showFlagWarning = !vm.manipulationFlags.isEmpty
        }
    }

    private func submit() async {
        guard validationMessage == nil else { return }
        let evidenceItems = evidenceText
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let result = await vm.postNode(
            claim: claimText.trimmingCharacters(in: .whitespacesAndNewlines),
            evidence: evidenceItems,
            type: selectedType,
            parentId: parentNodeId
        )

        switch result {
        case .success, .pendingModeration:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        case .failed:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .idle, .posting:
            break
        }
    }
}
