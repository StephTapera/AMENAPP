// AmenIntegrationOAuthView.swift
// OAuth handoff view — opens provider authorization in ASWebAuthenticationSession
// Never uses WKWebView. All state validated server-side.

import SwiftUI
import AuthenticationServices

struct AmenIntegrationOAuthView: View {
    let provider: AmenIntegrationProvider
    @StateObject private var vm: AmenIntegrationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var authSession: ASWebAuthenticationSession?
    @State private var contextProvider = OAuthPresentationContext()

    private enum Phase {
        case loading, awaitingAuth(URL), completing, success, failed(Error)
    }

    private var isCompleting: Bool {
        if case .completing = phase { true } else { false }
    }

    init(provider: AmenIntegrationProvider, viewModel: AmenIntegrationViewModel) {
        self.provider = provider
        _vm = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    loadingView

                case .awaitingAuth:
                    awaitingView

                case .completing:
                    completingView

                case .success:
                    successView

                case .failed(let error):
                    failedView(error: error)
                }
            }
            .navigationTitle("Connect \(provider.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await beginOAuth() }
        .interactiveDismissDisabled(isCompleting)
    }

    // MARK: - Phases

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
            Text("Preparing authorization…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Preparing \(provider.displayName) authorization")
    }

    private var awaitingView: some View {
        VStack(spacing: 24) {
            Image(systemName: provider.systemIconFallback)
                .font(.system(size: 48))
                .foregroundStyle(.primary)
            Text("Authorize \(provider.displayName)")
                .font(.title3.weight(.semibold))
            Text("A browser window will open. Sign in with your \(provider.displayName) account to continue.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Open Authorization") {
                if case .awaitingAuth(let url) = phase {
                    launchSession(url: url)
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Open \(provider.displayName) authorization in browser")
        }
        .padding()
    }

    private var completingView: some View {
        VStack(spacing: 20) {
            ProgressView()
            Text("Completing connection…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Completing \(provider.displayName) connection")
    }

    private var successView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("\(provider.displayName) Connected")
                .font(.title3.weight(.semibold))
            Text("You can now schedule gatherings and use \(provider.displayName) with AMEN.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .accessibilityElement(children: .contain)
    }

    private func failedView(error: Error) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text("Connection Failed")
                .font(.title3.weight(.semibold))
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack(spacing: 16) {
                Button("Try Again") { Task { await beginOAuth() } }
                    .buttonStyle(.borderedProminent)
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    // MARK: - OAuth Flow

    private func beginOAuth() async {
        phase = .loading
        do {
            let response = try await AmenIntegrationService.shared.startOAuth(provider: provider)
            guard let url = URL(string: response.authUrl) else {
                phase = .failed(AmenIntegrationClientError.unknown("invalid-url"))
                return
            }
            phase = .awaitingAuth(url)
            launchSession(url: url)
        } catch {
            phase = .failed(error)
        }
    }

    private func launchSession(url: URL) {
        guard case .awaitingAuth = phase else { return }

        let scheme = "amenapp"
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
            Task { @MainActor in
                if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        dismiss()
                    } else {
                        phase = .failed(error)
                    }
                    return
                }
                guard let callbackURL else {
                    phase = .failed(AmenIntegrationClientError.unknown("no-callback"))
                    return
                }
                await handleCallback(url: callbackURL)
            }
        }
        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = contextProvider
        authSession = session
        session.start()
    }

    private func handleCallback(url: URL) async {
        phase = .completing
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value else {
            phase = .failed(AmenIntegrationClientError.oauthStateMismatch)
            return
        }
        do {
            _ = try await AmenIntegrationService.shared.completeOAuth(provider: provider, code: code, stateToken: state)
            phase = .success
        } catch {
            phase = .failed(error)
        }
    }
}

// MARK: - Presentation Context

private final class OAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
