// AmenGatheringDeepLinkRouter.swift
// AMENAPP — Gathering Deep Link Router
//
// Handles amen://gathering/{id} and https://amen.app/gathering/{id}
// Never drops user directly into a gathering. Always shows landing first.

import Foundation
import SwiftUI

@MainActor
final class AmenGatheringDeepLinkRouter: ObservableObject {
    static let shared = AmenGatheringDeepLinkRouter()

    @Published var pendingGatheringId: String?
    @Published var isPresenting: Bool = false
    @Published var resolvedGathering: AmenGathering?
    @Published var resolveError: AmenGatheringError?
    @Published var isResolving: Bool = false

    private init() {}

    // MARK: - URL Handling

    func canHandle(url: URL) -> Bool {
        guard AMENFeatureFlags.shared.gatheringsEnabled else { return false }
        return extractGatheringId(from: url) != nil
    }

    func handle(url: URL) {
        guard let gatheringId = extractGatheringId(from: url) else { return }
        resolve(gatheringId: gatheringId)
    }

    func resolve(gatheringId: String) {
        guard AMENFeatureFlags.shared.gatheringsEnabled else { return }
        pendingGatheringId = gatheringId
        isPresenting = true
        isResolving = true
        resolvedGathering = nil
        resolveError = nil

        Task {
            do {
                let gathering = try await AmenGatheringService.shared.getGatheringPreview(gatheringId: gatheringId)
                resolvedGathering = gathering
            } catch let e as AmenGatheringError {
                resolveError = e
            } catch {
                resolveError = .unknown(error.localizedDescription)
            }
            isResolving = false
        }
    }

    func dismiss() {
        isPresenting = false
        pendingGatheringId = nil
        resolvedGathering = nil
        resolveError = nil
        isResolving = false
    }

    // MARK: - URL Parsing

    private func extractGatheringId(from url: URL) -> String? {
        // amen://gathering/{id}
        if url.scheme == "amen", url.host == "gathering" {
            let path = url.pathComponents.filter { $0 != "/" }
            return path.first
        }
        // https://amen.app/gathering/{id}
        if (url.host == "amen.app" || url.host == "www.amen.app"),
           url.pathComponents.count >= 3,
           url.pathComponents[1] == "gathering" {
            return url.pathComponents[2]
        }
        return nil
    }
}

// MARK: - View Modifier

struct AmenGatheringDeepLinkHandlerModifier: ViewModifier {
    @ObservedObject private var router = AmenGatheringDeepLinkRouter.shared

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $router.isPresenting) {
                if let gathering = router.resolvedGathering {
                    AmenGatheringDetailView(gathering: gathering)
                } else if router.isResolving {
                    GatheringDeepLinkLoadingView()
                } else if let error = router.resolveError {
                    GatheringDeepLinkErrorView(error: error) {
                        router.dismiss()
                    }
                }
            }
            .onOpenURL { url in
                if router.canHandle(url: url) {
                    router.handle(url: url)
                }
            }
    }
}

extension View {
    func handleGatheringDeepLinks() -> some View {
        modifier(AmenGatheringDeepLinkHandlerModifier())
    }
}

// MARK: - Loading / Error States

private struct GatheringDeepLinkLoadingView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ProgressView()
                    .scaleEffect(1.2)
                    .accessibilityLabel("Loading gathering details")
                Text("Loading gathering...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct GatheringDeepLinkErrorView: View {
    let error: AmenGatheringError
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(error.userFacingTitle)
                        .font(.title3.weight(.semibold))
                    Text(error.localizedDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button("Close") { onDismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }
}
