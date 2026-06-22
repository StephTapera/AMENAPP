// OrgAssistantView.swift — AMEN IntegrationOS
// SwiftUI chat interface for the org knowledge assistant.

import SwiftUI

@MainActor
final class OrgAssistantViewModel: ObservableObject {
    @Published var messages: [OrgAssistantMessage] = []
    @Published var input = ""
    @Published var isSending = false
    @Published var errorMessage: String?

    let orgId: String
    private let service = OrgAssistantService.shared

    init(orgId: String) { self.orgId = orgId }

    func send() async {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        input = ""
        let userMsg = OrgAssistantMessage(role: .user, content: q, approved: true, timestamp: Date(), citations: [])
        messages.append(userMsg)
        isSending = true
        do {
            let reply = try await service.ask(orgId: orgId, question: q, history: messages)
            messages.append(reply)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}

struct OrgAssistantView: View {
    @StateObject private var viewModel: OrgAssistantViewModel
    @Environment(\.colorScheme) private var colorScheme

    init(orgId: String) {
        _viewModel = StateObject(wrappedValue: OrgAssistantViewModel(orgId: orgId))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if viewModel.messages.isEmpty {
                            emptyState
                        }
                        ForEach(viewModel.messages) { msg in
                            AssistantMessageBubble(message: msg)
                                .id(msg.id)
                        }
                        if viewModel.isSending {
                            OrgTypingIndicator()
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    if let last = viewModel.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()
            inputBar
        }
        .navigationTitle("Org Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "building.2.crop.circle.fill")
                .font(.systemScaled(48))
                .foregroundStyle(.tint)
            Text("Ask about your organization")
                .font(.headline)
            Text("Get answers from your church's knowledge base.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask a question…", text: $viewModel.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit { Task { await viewModel.send() } }

            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(viewModel.input.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
            }
            .disabled(viewModel.input.isEmpty || viewModel.isSending)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground))
    }
}

private struct AssistantMessageBubble: View {
    let message: OrgAssistantMessage
    @Environment(\.colorScheme) private var colorScheme

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer() }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.accentColor : (colorScheme == .dark ? Color(.systemGray4) : Color(.systemGray6)))
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                if !message.approved && !isUser {
                    Label("Pending human review", systemImage: "clock.badge.exclamationmark")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            if !isUser { Spacer() }
        }
    }
}

private struct OrgTypingIndicator: View {
    @State private var phase = 0
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(phase == i ? 1 : 0.3)
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                Task { @MainActor in
                    phase = (phase + 1) % 3
                }
            }
        }
    }
}
