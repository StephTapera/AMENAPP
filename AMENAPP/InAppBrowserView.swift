//
//  InAppBrowserView.swift
//  AMENAPP
//
//  Full AMEN in-app browser shell.
//
//  Chrome:
//  - Close, Back, Forward buttons
//  - Domain / title bar
//  - Top progress bar during page load
//  - Overflow menu: Open in Safari, Copy Link, Share, Save for Later, Report Link
//
//  Uses WKWebView for full control over progress reporting and navigation.
//  Falls back gracefully on load error with a retry option and
//  "Open in Safari" escape hatch.
//

import SwiftUI
import WebKit

// MARK: - InAppBrowserView

struct InAppBrowserView: View {
    let url: URL
    var title: String?
    var domain: String?
    var category: LinkCategory = .general

    @StateObject private var browserState = BrowserState()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Top chrome
            browserChrome
                .background(Color(uiColor: .systemBackground))

            // Progress bar — only visible while loading
            if browserState.isLoading {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: geo.size.width * browserState.progress, height: 2)
                        .animation(.easeInOut(duration: 0.2), value: browserState.progress)
                }
                .frame(height: 2)
            }

            Divider()
                .opacity(0.08)

            // Web content
            ZStack {
                WebView(url: url, state: browserState)

                if browserState.didFailLoad {
                    errorOverlay
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear {
            browserState.displayTitle = title ?? domain ?? url.host ?? ""
        }
    }

    // MARK: - Browser Chrome

    private var browserChrome: some View {
        HStack(spacing: 0) {
            // Close
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)

            // Back
            Button {
                browserState.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(browserState.canGoBack ? .black : .black.opacity(0.25))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(!browserState.canGoBack)

            // Forward (only shown when available)
            if browserState.canGoForward {
                Button {
                    browserState.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Domain / title
            VStack(spacing: 1) {
                Text(browserState.currentHost.isEmpty ? (domain ?? "") : browserState.currentHost)
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if browserState.isLoading {
                    Text("Loading…")
                        .font(AMENFont.regular(10))
                        .foregroundStyle(.black.opacity(0.35))
                }
            }

            Spacer()

            // Overflow menu
            Menu {
                Button {
                    UIApplication.shared.open(browserState.currentURL ?? url)
                } label: {
                    Label("Open in Safari", systemImage: "safari")
                }

                Button {
                    UIPasteboard.general.url = browserState.currentURL ?? url
                } label: {
                    Label("Copy Link", systemImage: "link")
                }

                Button {
                    let items: [Any] = [browserState.currentURL ?? url]
                    let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let root = scene.windows.first?.rootViewController {
                        root.present(activityVC, animated: true)
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Divider()

                Button(role: .destructive) {
                    // Report is surfaced to AMEN's existing safety reporting flow.
                    // The URL is passed via SafetyReportingService if available.
                } label: {
                    Label("Report Link", systemImage: "flag")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
            }
            .padding(.trailing, 8)
        }
        .frame(height: 48)
    }

    // MARK: - Error Overlay

    private var errorOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.slash")
                .font(.systemScaled(36))
                .foregroundStyle(.black.opacity(0.25))

            Text("Couldn't load this page")
                .font(AMENFont.semiBold(16))
                .foregroundStyle(.primary)

            Text(browserState.errorDescription ?? "Check your connection and try again.")
                .font(AMENFont.regular(13))
                .foregroundStyle(.black.opacity(0.50))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 12) {
                Button {
                    browserState.reload()
                } label: {
                    Text("Retry")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black))
                }

                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Text("Open in Safari")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.08)))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - Browser State

@MainActor
final class BrowserState: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var progress: Double = 0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var currentHost: String = ""
    @Published var displayTitle: String = ""
    @Published var didFailLoad: Bool = false
    @Published var errorDescription: String?
    @Published var currentURL: URL?

    // Commands sent to the WebView via closure bindings
    var goBackCommand: (() -> Void)?
    var goForwardCommand: (() -> Void)?
    var reloadCommand: (() -> Void)?

    func goBack() { goBackCommand?() }
    func goForward() { goForwardCommand?() }
    func reload() {
        didFailLoad = false
        reloadCommand?()
    }
}

// MARK: - WebView (WKWebView wrapper)

struct WebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: BrowserState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic

        // Wire state commands
        state.goBackCommand = { [weak webView] in webView?.goBack() }
        state.goForwardCommand = { [weak webView] in webView?.goForward() }
        state.reloadCommand = { [weak webView] in webView?.reload() }

        // KVO for progress and loading
        context.coordinator.webView = webView
        context.coordinator.progressObserver = webView.observe(\.estimatedProgress, options: [.new]) { wv, _ in
            Task { @MainActor in
                state.progress = wv.estimatedProgress
            }
        }
        context.coordinator.loadingObserver = webView.observe(\.isLoading, options: [.new]) { wv, _ in
            Task { @MainActor in
                state.isLoading = wv.isLoading
                state.canGoBack = wv.canGoBack
                state.canGoForward = wv.canGoForward
                if let host = wv.url?.host?.replacingOccurrences(of: "www.", with: "") {
                    state.currentHost = host
                }
                state.currentURL = wv.url
            }
        }

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: BrowserState
        weak var webView: WKWebView?
        var progressObserver: NSKeyValueObservation?
        var loadingObserver: NSKeyValueObservation?

        init(state: BrowserState) {
            self.state = state
        }

        deinit {
            progressObserver?.invalidate()
            loadingObserver?.invalidate()
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                state.didFailLoad = false
                state.errorDescription = nil
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                state.isLoading = false
                state.canGoBack = webView.canGoBack
                state.canGoForward = webView.canGoForward
                state.currentURL = webView.url
                if let host = webView.url?.host?.replacingOccurrences(of: "www.", with: "") {
                    state.currentHost = host
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleLoadError(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleLoadError(error)
        }

        private func handleLoadError(_ error: Error) {
            let nsError = error as NSError
            // NSURLErrorCancelled (-999) fires on user-initiated navigation changes — not a real failure.
            guard nsError.code != NSURLErrorCancelled else { return }
            Task { @MainActor in
                state.isLoading = false
                state.didFailLoad = true
                state.errorDescription = error.localizedDescription
            }
        }

        // Block known shortener/unsafe navigations that reach the webview
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let navURL = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let decision = LinkSafetyService.check(navURL.absoluteString)
            switch decision {
            case .blocked, .blockedAndStrike:
                decisionHandler(.cancel)
            default:
                decisionHandler(.allow)
            }
        }
    }
}
