import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class LivingEntryViewModel: ObservableObject {
    @Published private(set) var entries: [LivingEntry] = []
    @Published private(set) var sections: [LivingEntrySection: [LivingEntry]] = [:]
    @Published private(set) var nowEntries: [LivingEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var composerText = ""

    private let service: LivingEntryService
    private let functions = Functions.functions()
    private var listener: ListenerRegistration?

    init(service: LivingEntryService? = nil) {
        self.service = service ?? .shared
    }

    deinit {
        listener?.remove()
    }

    func loadEntries() {
        isLoading = true
        errorMessage = nil
        do {
            listener?.remove()
            listener = try service.observeEntries { [weak self] entries in
                Task { @MainActor in
                    self?.entries = entries
                    self?.rebuildSections()
                    self?.isLoading = false
                }
            }
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func rebuildSections(context: LivingEntryRuntimeContext? = nil) {
        let context = context ?? LivingEntryRuntimeContext.current()
        let sorted = entries.sorted { lhs, rhs in
            let left = LivingEntryContextEngine.evaluate(entry: lhs, context: context).surfaceScore
            let right = LivingEntryContextEngine.evaluate(entry: rhs, context: context).surfaceScore
            return left > right
        }

        nowEntries = sorted.filter {
            LivingEntryContextEngine.evaluate(entry: $0, context: context).shouldSurfaceNow
        }

        let startOfToday = Calendar.current.startOfDay(for: context.now)
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? context.now
        sections = Dictionary(uniqueKeysWithValues: LivingEntrySection.allCases.map { section in
            let sectionEntries: [LivingEntry]
            switch section {
            case .now:
                sectionEntries = nowEntries
            case .today:
                sectionEntries = sorted.filter { entry in
                    guard let dueAt = entry.dueAt else { return false }
                    return dueAt >= startOfToday && dueAt < endOfToday && entry.state == .active
                }
            case .upcoming:
                sectionEntries = sorted.filter { entry in
                    guard let dueAt = entry.dueAt else { return false }
                    return dueAt >= endOfToday && entry.state != .archived
                }
            case .church:
                sectionEntries = sorted.filter { $0.isChurchRelated && $0.state != .archived }
            case .prayer:
                sectionEntries = sorted.filter { $0.type == .prayer && $0.state != .archived }
            case .needsReflection:
                sectionEntries = sorted.filter { $0.state == .needsReflection }
            case .later:
                sectionEntries = sorted.filter { entry in
                    entry.state == .deferred || (entry.dueAt == nil && entry.state == .active)
                }
            }
            return (section, sectionEntries)
        })
    }

    func createQuickEntry(type: LivingEntryType, title: String, sourceSurface: LivingEntrySourceSurface) async {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let userId = FirebaseManager.shared.currentUser?.uid ?? ""
            var entry = LivingEntry(
                userId: userId,
                type: type,
                intent: inferredIntent(for: type),
                title: title,
                body: "",
                priorityScore: 0.45,
                gravityScore: 0.45,
                emotionalWeight: 0.3,
                regretRisk: 0.2,
                spiritualWeight: type == .prayer || type == .churchNote ? 0.75 : 0.38,
                triggerRules: [LivingEntryTriggerRule(type: .manual)],
                contextSnapshot: .current(sourceSurface: sourceSurface)
            )
            if type == .reminder || type == .task {
                entry.dueAt = Calendar.current.date(byAdding: .hour, value: 6, to: Date())
                entry.triggerRules = [LivingEntryTriggerRule(type: .time, scheduledAt: entry.dueAt)]
            }
            _ = try await service.createEntry(entry)
            composerText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func complete(_ entry: LivingEntry) async {
        do {
            _ = try await service.completeEntry(entry)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deferEntry(_ entry: LivingEntry, hours: Int = 24) async {
        guard let date = Calendar.current.date(byAdding: .hour, value: hours, to: Date()) else { return }
        do {
            _ = try await service.deferEntry(entry, until: date)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func archive(_ entry: LivingEntry) async {
        do {
            _ = try await service.archiveEntry(entry)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func classifyLivingEntry(payload: [String: Any]) async throws -> [String: Any] {
        let result = try await functions.httpsCallable("classifyLivingEntry").safeCall(payload)
        return result.data as? [String: Any] ?? [:]
    }

    func evaluateLivingEntryContext(payload: [String: Any]) async throws -> [String: Any] {
        let result = try await functions.httpsCallable("evaluateLivingEntryContext").safeCall(payload)
        return result.data as? [String: Any] ?? [:]
    }

    func completeLivingEntryWithReflection(payload: [String: Any]) async throws -> [String: Any] {
        let result = try await functions.httpsCallable("completeLivingEntryWithReflection").safeCall(payload)
        return result.data as? [String: Any] ?? [:]
    }

    func evolveLivingEntries() async throws -> [String: Any] {
        let result = try await functions.httpsCallable("evolveLivingEntries").safeCall([:])
        return result.data as? [String: Any] ?? [:]
    }

    func calculateIntentGravity(payload: [String: Any]) async throws -> [String: Any] {
        let result = try await functions.httpsCallable("calculateIntentGravity").safeCall(payload)
        return result.data as? [String: Any] ?? [:]
    }

    private func inferredIntent(for type: LivingEntryType) -> LivingEntryIntent {
        switch type {
        case .churchNote:
            return .sermonReflection
        case .prayer:
            return .prayerCare
        case .followUp:
            return .spiritualGrowth
        case .task, .reminder:
            return .personal
        case .note, .reflection, .sermonInsight:
            return .spiritualGrowth
        }
    }
}
