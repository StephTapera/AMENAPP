// PresenceComposeView.swift
// AMENAPP — Post-capture composition: caption, provenance, GUARDIAN gate, publish.
//
// Flow:
//   captured media
//     → edit/AI assist toggle (disclosed; flips Shot Real off)
//     → GUARDIAN safety check on Publish tap
//     → ok   → upload
//     → warn  → show revision sheet
//     → delay → queue for moderation review
//     → escalate → blocked, contact support

import SwiftUI

@MainActor
final class PresenceComposeViewModel: ObservableObject {
    @Published var draft: CSAssetDraft
    @Published var uploadState: CSPublishState = .idle
    @Published var guardianResult: CSGuardianResult? = nil
    @Published var showGuardianWarn = false
    @Published var showDelayNotice = false
    @Published var postSucceeded = false

    enum CSPublishState {
        case idle
        case checkingSafety
        case uploading
        case failed(String)
    }

    private let uploadService = CreatorSpacesUploadService.shared

    init(draft: CSAssetDraft) {
        self.draft = draft
    }

    var canPublish: Bool {
        if case .idle = uploadState {
            return !draft.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    func markAIAssisted(tool: String) {
        draft.editedWithAI = true
        if !draft.aiToolsUsed.contains(tool) {
            draft.aiToolsUsed.append(tool)
        }
    }

    func attemptPublish() async {
        guard canPublish else { return }
        uploadState = .checkingSafety

        let result = await uploadService.runSafetyCheck(draft: draft)
        guardianResult = result

        switch result.decision {
        case .ok:
            await upload()
        case .warn:
            uploadState = .idle
            showGuardianWarn = true
        case .delay:
            uploadState = .idle
            showDelayNotice = true
            await upload(delayed: true)
        case .escalate:
            uploadState = .failed("This post has been flagged for review and cannot be published right now.")
        }
    }

    func publishAfterRevision() async {
        showGuardianWarn = false
        await upload()
    }

    private func upload(delayed: Bool = false) async {
        uploadState = .uploading
        do {
            _ = try await uploadService.upload(draft: draft, delayed: delayed)
            postSucceeded = true
            uploadState = .idle
        } catch {
            uploadState = .failed(error.localizedDescription)
        }
    }
}

// MARK: - View

struct PresenceComposeView: View {
    let draft: CSAssetDraft
    @StateObject private var vm: PresenceComposeViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var captionFocused: Bool
    @State private var showAIDisclaimerSheet = false

    init(draft: CSAssetDraft) {
        self.draft = draft
        _vm = StateObject(wrappedValue: PresenceComposeViewModel(draft: draft))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    mediaPreviewSection
                    provenanceBanner
                    captionSection
                    scriptureSection
                    aiAssistSection
                    reachSection
                }
                .padding(.bottom, 120)
            }
            .background(Color(.systemBackground))
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .overlay(alignment: .bottom) { publishBar }
        }
        .sheet(isPresented: $vm.showGuardianWarn) {
            GuardianWarnSheet(result: vm.guardianResult) {
                Task { await vm.publishAfterRevision() }
            }
        }
        .alert("Post Queued for Review", isPresented: $vm.showDelayNotice) {
            Button("OK") { }
        } message: {
            Text("Your post has been queued. It will appear after a brief safety review.")
        }
        .alert("Post Published", isPresented: $vm.postSucceeded) {
            Button("Done") { dismiss() }
        } message: {
            Text("Your post is live.")
        }
        .alert("Upload Error", isPresented: uploadFailed, actions: {
            Button("OK") { vm.uploadState = .idle }
        }, message: {
            if case .failed(let msg) = vm.uploadState {
                Text(msg)
            }
        })
    }

    private var uploadFailed: Binding<Bool> {
        Binding(
            get: { if case .failed = vm.uploadState { return true } else { return false } },
            set: { _ in }
        )
    }

    // MARK: Media preview

    private var mediaPreviewSection: some View {
        Group {
            if let back = vm.draft.backImage, let front = vm.draft.frontImage {
                dualFramePreview(back: back, front: front)
            } else if let back = vm.draft.backImage {
                singleImagePreview(back)
            } else {
                audioPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .clipped()
    }

    private func dualFramePreview(back: UIImage, front: UIImage) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: back)
                .resizable()
                .scaledToFill()
            Image(uiImage: front)
                .resizable()
                .scaledToFill()
                .frame(width: 90, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white, lineWidth: 1.5))
                .shadow(radius: 4)
                .padding(12)
        }
    }

    private func singleImagePreview(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
    }

    private var audioPlaceholder: some View {
        ZStack {
            Color(.secondarySystemBackground)
            VStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 40))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
                Text("Audio Post")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Provenance banner (the "nutrition label" strip)

    private var provenanceBanner: some View {
        ProvenanceLabelBanner(draft: vm.draft)
            .padding(.horizontal, 16)
            .padding(.top, 12)
    }

    // MARK: Caption

    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Write a caption…", text: $vm.draft.caption, axis: .vertical)
                .font(.body)
                .lineLimit(4...8)
                .focused($captionFocused)
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: Scripture ref

    private var scriptureSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.closed.fill")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.amenGold)
            TextField("Scripture reference (optional)", text: Binding(
                get:  { vm.draft.scriptureRef ?? "" },
                set:  { vm.draft.scriptureRef = $0.isEmpty ? nil : $0 }
            ))
            .font(.subheadline)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: AI Assist disclosure toggle

    private var aiAssistSection: some View {
        Button {
            showAIDisclaimerSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: vm.draft.editedWithAI ? "sparkles" : "sparkles.slash")
                    .font(.subheadline)
                    .foregroundStyle(vm.draft.editedWithAI ? AmenTheme.Colors.amenPurple : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.draft.editedWithAI ? "AI-Assisted Editing — Disclosed" : "Add AI Assistance")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(vm.draft.editedWithAI ? AmenTheme.Colors.amenPurple : .primary)
                    if vm.draft.editedWithAI {
                        Text("Shot Real badge will not display")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .sheet(isPresented: $showAIDisclaimerSheet) {
            AIAssistDisclaimerSheet { tool in
                vm.markAIAssisted(tool: tool)
            }
        }
    }

    // MARK: Reach / visibility

    private var reachSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reach")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            HStack(spacing: 10) {
                ForEach([CSDistribution.dailyPortion, .profileOnly], id: \.self) { option in
                    reachPill(option)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func reachPill(_ option: CSDistribution) -> some View {
        Button {
            vm.draft.distribution = option
        } label: {
            Text(option.displayLabel)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(vm.draft.distribution == option ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    vm.draft.distribution == option ? AmenTheme.Colors.amenBlue : Color(.secondarySystemBackground),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
    }

    // MARK: Publish bar

    private var publishBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                Task { await vm.attemptPublish() }
            } label: {
                Group {
                    switch vm.uploadState {
                    case .checkingSafety:
                        Label("Checking safety…", systemImage: "shield.lefthalf.filled")
                    case .uploading:
                        Label("Publishing…", systemImage: "arrow.up.circle.fill")
                    default:
                        Text("Publish")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(vm.canPublish ? AmenTheme.Colors.amenBlue : Color(.systemGray4), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .disabled(!vm.canPublish)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - GUARDIAN warn sheet

struct GuardianWarnSheet: View {
    let result: CSGuardianResult?
    let onRevise: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .padding(.top, 24)

                Text("Review Before Publishing")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("Your post may contain content worth reviewing. You can revise it or publish anyway.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if let reasons = result?.reasons, !reasons.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(reasons, id: \.self) { reason in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 5)
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button("Publish Anyway") {
                        dismiss()
                        onRevise()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AmenTheme.Colors.amenBlue)

                    Button("Revise Post") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .navigationTitle("Safety Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - AI assist disclaimer sheet

struct AIAssistDisclaimerSheet: View {
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTool = "Caption assistant"

    private let tools = ["Caption assistant", "Framing suggestions", "Lighting adjustment", "Accessibility captions", "Translation"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("AI assistance is always disclosed. Using any AI tool removes the Shot Real badge and adds an AI-Assisted label to your post.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                Section("Select AI Tool Used") {
                    ForEach(tools, id: \.self) { tool in
                        Button {
                            selectedTool = tool
                        } label: {
                            HStack {
                                Text(tool)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedTool == tool {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AmenTheme.Colors.amenBlue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("AI Assistance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        onConfirm(selectedTool)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Convenience extensions

private extension CSDistribution {
    var displayLabel: String {
        switch self {
        case .dailyPortion: return "Daily Portion"
        case .profileOnly:  return "Profile Only"
        case .roomsOnly:    return "Rooms Only"
        }
    }
}

