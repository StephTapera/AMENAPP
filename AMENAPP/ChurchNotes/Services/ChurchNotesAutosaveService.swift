import Foundation

@MainActor
final class ChurchNotesAutosaveService: ObservableObject {
    enum State: Equatable {
        case idle
        case saving
        case saved(Date)
        case error(String)
    }

    @Published private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    func schedule(after delay: UInt64 = 900_000_000, operation: @escaping @MainActor () async throws -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                state = .saving
                try await operation()
                guard !Task.isCancelled else { return }
                state = .saved(Date())
            } catch is CancellationError {
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }
}
