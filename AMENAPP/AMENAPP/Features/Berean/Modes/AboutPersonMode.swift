// AboutPersonMode.swift
// AMEN App — Berean "About This Person" chat mode.
//
// Self-contained view.  Calls bereanChatProxy with mode:"aboutPerson" +
// contextUserId.  Handles the opt-in 403 gracefully.
// Do NOT modify BereanChatView.swift or bereanChatProxy.

import SwiftUI
import FirebaseFunctions

// MARK: - Avatar helper (initials fallback)

private struct AboutPersonAvatar: View {
    let displayName: String
    let profileImageURL: String?
    private let size: CGFloat = 48

    var body: some View {
        Group {
            if let urlString = profileImageURL,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.amenGold.opacity(0.85), Color.amenGold.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

// MARK: - Response bubble

private struct AboutPersonResponseBubble: View {
    let text: String
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isLoading {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.primary.opacity(0.35))
                            .frame(width: 7, height: 7)
                            .scaleEffect(isLoading ? 1.0 : 0.6)
                            .animation(
                                .easeInOut(duration: 0.55)
                                .repeatForever()
                                .delay(Double(index) * 0.18),
                                value: isLoading
                            )
                    }
                }
                .padding(.vertical, 4)
            } else if !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Main View

public struct BereanAboutPersonView: View {
    public let targetUserId: String
    public let targetDisplayName: String
    public let targetProfileImageURL: String?

    @State private var message = ""
    @State private var response = ""
    @State private var isLoading = false
    @State private var showOptInError = false
    @Environment(\.dismiss) private var dismiss

    private let functions = Functions.functions()

    public init(
        targetUserId: String,
        targetDisplayName: String,
        targetProfileImageURL: String? = nil
    ) {
        self.targetUserId = targetUserId
        self.targetDisplayName = targetDisplayName
        self.targetProfileImageURL = targetProfileImageURL
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                backgroundLayer
                VStack(spacing: 0) {
                    headerSection
                    Divider().opacity(0.2)
                    responseSection
                    Divider().opacity(0.2)
                    inputSection
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.amenGold)
                }
            }
        }
        .alert(
            "\(targetDisplayName) hasn't enabled this yet.",
            isPresented: $showOptInError
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("They haven't opted in to Berean conversations about them.")
        }
    }

    // MARK: - Subviews

    private var backgroundLayer: some View {
        ZStack {
            Color(red: 0.956, green: 0.956, blue: 0.936)
                .ignoresSafeArea()
            LinearGradient(
                colors: [
                    Color.white.opacity(0.72),
                    Color(red: 0.94, green: 0.95, blue: 0.93).opacity(0.60)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 10) {
            AboutPersonAvatar(
                displayName: targetDisplayName,
                profileImageURL: targetProfileImageURL
            )
            .padding(.top, 20)

            Text("Learning about \(targetDisplayName)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text("Ask anything about \(targetDisplayName)'s faith journey, guided by their public testimony and pinned posts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Berean conversation about \(targetDisplayName)'s faith journey")
    }

    private var responseSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if response.isEmpty && !isLoading {
                    emptyStatePrompt
                } else {
                    AboutPersonResponseBubble(text: response, isLoading: isLoading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: response)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: isLoading)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyStatePrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(Color.amenGold.opacity(0.7))
                .padding(.top, 40)
            Text("Ask a question below to begin")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("No response yet. Ask a question to begin.")
    }

    private var inputSection: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                "Ask about their faith journey…",
                text: $message,
                axis: .vertical
            )
            .lineLimit(1...5)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .disabled(isLoading)
            .accessibilityLabel("Message input")
            .onSubmit {
                Task { await sendMessage() }
            }

            Button {
                Task { await sendMessage() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.amenGold : Color.secondary.opacity(0.4))
                    .scaleEffect(canSend ? 1.0 : 0.9)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSend)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Rectangle())
    }

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespaces).isEmpty && !isLoading
    }

    // MARK: - Actions

    private func sendMessage() async {
        guard !message.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        response = ""
        let userMessage = message
        message = ""

        do {
            let payload: [String: Any] = [
                "message": userMessage,
                "mode": "aboutPerson",
                "contextUserId": targetUserId,
            ]
            let result = try await functions.httpsCallable("bereanChatProxy").call(payload)
            if let data = result.data as? [String: Any],
               let text = data["response"] as? String {
                response = text
            } else {
                response = "Berean wasn't able to respond right now. Please try again."
            }
        } catch let error as NSError {
            // Firebase Functions maps permission-denied → FIRFunctionsErrorCodePermissionDenied (9)
            if error.domain == FunctionsErrorDomain && error.code == FunctionsErrorCode.permissionDenied.rawValue {
                showOptInError = true
            } else {
                response = "Something went wrong. Please try again."
            }
        }

        isLoading = false
    }
}

// MARK: - amenGold fallback (safe if already defined elsewhere in the module)

private extension Color {
    // Using a file-private extension avoids redeclaration conflicts when
    // amenGold is already defined in the broader module target.
    static var amenGold: Color { Color("amenGold", bundle: .main) }
}
