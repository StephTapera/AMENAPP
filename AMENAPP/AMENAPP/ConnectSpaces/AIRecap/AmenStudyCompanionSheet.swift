// AmenStudyCompanionSheet.swift
// AMEN Connect + Spaces — Study Companion
// Built 2026-06-02

import SwiftUI
import FirebaseFunctions

// MARK: - Local message model

struct StudyCompanionMessage: Identifiable {
    let id: UUID
    var role: Role
    var text: String
    var citations: [String]

    enum Role {
        case user
        case assistant
    }
}

// MARK: - ViewModel

@MainActor
private final class AmenStudyCompanionViewModel: ObservableObject {
    @Published var messages: [StudyCompanionMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var sendError: String?

    let spaceId: String
    let videoId: String
    let hostName: String

    private let functions = Functions.functions()

    init(spaceId: String, videoId: String, hostName: String) {
        self.spaceId = spaceId
        self.videoId = videoId
        self.hostName = hostName
    }

    func send() {
        let question = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isLoading else { return }

        let userMessage = StudyCompanionMessage(id: UUID(), role: .user, text: question, citations: [])
        messages.append(userMessage)
        inputText = ""
        isLoading = true
        sendError = nil

        Task {
            defer { isLoading = false }
            do {
                let callable = functions.httpsCallable(AmenSpacesPhase1Callable.studyCompanionQuery.rawValue)
                let result = try await callable.call([
                    "spaceId": spaceId,
                    "videoId": videoId,
                    "question": question
                ])
                guard let data = result.data as? [String: Any] else {
                    appendUngroundedResponse()
                    return
                }

                let answerText = data["answer"] as? String ?? ""
                let citations = data["citations"] as? [String] ?? []

                // Hard rule: if AI returns no citations, never surface the answer
                if citations.isEmpty {
                    appendUngroundedResponse()
                    return
                }

                let response = StudyCompanionMessage(
                    id: UUID(),
                    role: .assistant,
                    text: answerText,
                    citations: citations
                )
                messages.append(response)
            } catch {
                sendError = error.localizedDescription
                // Remove the user message so the input can be retried
                messages.removeLast()
                inputText = question
            }
        }
    }

    // Hard rule: ungrounded AI responses are never shown as answers
    private func appendUngroundedResponse() {
        let ungrounded = StudyCompanionMessage(
            id: UUID(),
            role: .assistant,
            text: "",
            citations: []
        )
        messages.append(ungrounded)
    }
}

// MARK: - Message bubbles

private struct UserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(.systemScaled(15))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: "6E4BB5"))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel("You: \(text)")
        }
    }
}

private struct AssistantBubble: View {
    let message: StudyCompanionMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.systemScaled(14))
                .foregroundStyle(Color(hex: "D9A441"))
                .frame(width: 28, height: 28)
                .background {
                    Circle().fill(.ultraThinMaterial)
                        .overlay { Circle().strokeBorder(Color(hex: "D9A441").opacity(0.3), lineWidth: 1) }
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                // Hard rule: if no citations, never show the answer text
                if message.citations.isEmpty {
                    Text("This answer could not be grounded in the source material.")
                        .font(.systemScaled(14).italic())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Answer could not be grounded in source material")
                } else {
                    // Content is matte per glass design rule
                    Text(message.text)
                        .font(.systemScaled(14))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Citation provenance footer
                    VStack(alignment: .leading, spacing: 4) {
                        Text("From this teaching:")
                            .font(.systemScaled(10, weight: .semibold))
                            .textCase(.uppercase)
                            .kerning(0.5)
                            .foregroundStyle(.tertiary)
                        ForEach(message.citations, id: \.self) { citation in
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.systemScaled(10))
                                    .foregroundStyle(Color(hex: "D9A441").opacity(0.8))
                                    .accessibilityHidden(true)
                                Text(citation)
                                    .font(.systemScaled(11))
                                    .foregroundStyle(Color(hex: "D9A441").opacity(0.85))
                            }
                            .accessibilityLabel("Source citation: \(citation)")
                        }
                    }
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                            }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(hex: "111111"))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            }

            Spacer(minLength: 24)
        }
    }
}

private struct ThinkingBubble: View {
    @State private var dotOpacities: [Double] = [0.3, 0.3, 0.3]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.systemScaled(14))
                .foregroundStyle(Color(hex: "D9A441"))
                .frame(width: 28, height: 28)
                .background {
                    Circle().fill(.ultraThinMaterial)
                }
                .accessibilityHidden(true)

            HStack(spacing: 6) {
                if reduceMotion {
                    Text("Thinking…")
                        .font(.systemScaled(14).italic())
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.white.opacity(dotOpacities[i]))
                            .frame(width: 7, height: 7)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(hex: "111111"))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer(minLength: 48)
        }
        .onAppear {
            guard !reduceMotion else { return }
            animateDots()
        }
        .accessibilityLabel("Thinking")
    }

    private func animateDots() {
        for i in 0..<3 {
            withAnimation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
                .delay(Double(i) * 0.18)
            ) {
                dotOpacities[i] = 1.0
            }
        }
    }
}

// MARK: - Disabled state

private struct StudyCompanionDisabledView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical")
                .font(.systemScaled(44))
                .foregroundStyle(Color.white.opacity(0.2))
                .accessibilityHidden(true)
            Text("Study Companion Not Available")
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("The host has not enabled the study companion for this content.")
                .font(.systemScaled(14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Study companion not enabled by host")
    }
}

// MARK: - Main sheet

struct AmenStudyCompanionSheet: View {
    let spaceId: String
    let videoId: String
    let isHostEnabled: Bool
    var hostName: String = "the Host"

    @StateObject private var viewModel: AmenStudyCompanionViewModel
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(spaceId: String, videoId: String, isHostEnabled: Bool, hostName: String = "the Host") {
        self.spaceId = spaceId
        self.videoId = videoId
        self.isHostEnabled = isHostEnabled
        self.hostName = hostName
        _viewModel = StateObject(wrappedValue: AmenStudyCompanionViewModel(
            spaceId: spaceId,
            videoId: videoId,
            hostName: hostName
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider().opacity(0.2)

            if !isHostEnabled {
                StudyCompanionDisabledView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                disclaimerBanner
                messageList
                Divider().opacity(0.15)
                composer
            }
        }
        .background(Color(hex: "0D0D0D"))
    }

    // MARK: - Sheet header

    private var sheetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Study Companion")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Grounded in \(hostName)'s teaching")
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "sparkles")
                .font(.systemScaled(18))
                .foregroundStyle(Color(hex: "D9A441"))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Disclaimer banner

    private var disclaimerBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.systemScaled(13))
                .foregroundStyle(Color(hex: "D9A441").opacity(0.8))
                .accessibilityHidden(true)
            Text("Answers are grounded in \(hostName)'s teaching only. Not a substitute for scripture study.")
                .font(.systemScaled(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "D9A441").opacity(0.08))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.15)
        }
        .accessibilityLabel("Disclaimer: Answers are grounded in \(hostName)'s teaching only. Not a substitute for scripture study.")
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        Group {
                            if message.role == .user {
                                UserBubble(text: message.text)
                            } else {
                                AssistantBubble(message: message)
                            }
                        }
                        .id(message.id)
                    }

                    if viewModel.isLoading {
                        ThinkingBubble()
                            .id("thinking")
                    }

                    if viewModel.messages.isEmpty && !viewModel.isLoading {
                        emptyConversationState
                    }
                }
                .padding(16)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isLoading) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        let anim: Animation = reduceMotion
            ? .easeInOut(duration: 0.01)
            : .easeInOut(duration: 0.22)
        withAnimation(anim) {
            if viewModel.isLoading {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let last = viewModel.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var emptyConversationState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.systemScaled(36))
                .foregroundStyle(Color.white.opacity(0.2))
                .accessibilityHidden(true)
            Text("Ask a question about this teaching")
                .font(.systemScaled(14))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .accessibilityLabel("Ask a question about this teaching to get started")
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 0) {
            if let error = viewModel.sendError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .accessibilityLabel("Error: \(error)")
            }

            HStack(spacing: 10) {
                TextField("Ask about this teaching…", text: $viewModel.inputText, axis: .vertical)
                    .font(.systemScaled(15))
                    .foregroundStyle(.primary)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                            }
                    }
                    .focused($inputFocused)
                    .accessibilityLabel("Question input")

                Button {
                    viewModel.send()
                    inputFocused = false
                } label: {
                    Group {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.systemScaled(15, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(Color(hex: "6E4BB5"))
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    viewModel.isLoading ||
                    viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityLabel("Send question")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Preview

#Preview("Enabled") {
    AmenStudyCompanionSheet(
        spaceId: "s1",
        videoId: "v1",
        isHostEnabled: true,
        hostName: "Pastor James"
    )
    .frame(height: 600)
    .preferredColorScheme(.dark)
}

#Preview("Disabled by host") {
    AmenStudyCompanionSheet(
        spaceId: "s1",
        videoId: "v1",
        isHostEnabled: false,
        hostName: "Pastor James"
    )
    .frame(height: 400)
    .preferredColorScheme(.dark)
}
