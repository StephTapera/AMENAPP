import SwiftUI
import Observation
import FirebaseAuth

// MARK: - View model

@MainActor
@Observable
final class DiscoverViewModel {

    enum Phase {
        case loading
        case loaded(featured: [FeaturedItem], continueItems: [CarouselItem])
        case empty
        case failed(String)

        var featured: [FeaturedItem]? {
            if case .loaded(let f, _) = self { return f }
            return nil
        }
        var continueItems: [CarouselItem]? {
            if case .loaded(_, let c) = self { return c }
            return nil
        }
    }

    private(set) var phase: Phase = .loading

    private var featuredTask: Task<Void, Never>?
    private var continueTask: Task<Void, Never>?
    private let service: DiscoverServing

    init(service: DiscoverServing = DiscoverService.shared) {
        self.service = service
    }

    // MARK: - Lifecycle

    func start() {
        featuredTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await entries in service.featuredStream() {
                    guard !Task.isCancelled else { break }
                    if entries.isEmpty {
                        if case .loading = phase { phase = .empty }
                    } else {
                        let items = entries.map { $0.asFeaturedItem() }
                        let existing = phase.continueItems ?? []
                        phase = .loaded(featured: items, continueItems: existing)
                    }
                }
            } catch {
                if case .loading = phase {
                    phase = .failed(error.localizedDescription)
                }
            }
        }

        guard let uid = Auth.auth().currentUser?.uid else { return }
        continueTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await entries in service.continueStream(uid: uid) {
                    guard !Task.isCancelled else { break }
                    let items = entries.map { $0.asCarouselItem() }
                    if let existing = phase.featured {
                        phase = .loaded(featured: existing, continueItems: items)
                    }
                }
            } catch { }
        }
    }

    func stop() {
        featuredTask?.cancel()
        continueTask?.cancel()
        featuredTask = nil
        continueTask = nil
    }

    // MARK: - Actions

    func play(_ item: FeaturedItem) {
        // TODO: route to content player via app coordinator
    }

    func add(_ item: FeaturedItem) {
        // TODO: add to saved library
    }
}
