import Foundation
import FirebaseFunctions

@MainActor
final class ChurchNotesMemoryService: ObservableObject {
    static let shared = ChurchNotesMemoryService()
    private init() {}

    @Published private(set) var memory: ChurchNoteMemoryResult?
    @Published private(set) var isLoading = false

    private let functions = Functions.functions()

    func loadMemory(excludingNoteId: String? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var params: [String: Any] = ["limit": 30]
            if let id = excludingNoteId { params["currentNoteId"] = id }
            let result = try await functions.httpsCallable("analyzeChurchNoteMemory").call(params)
            if let data = result.data as? [String: Any] {
                memory = ChurchNoteMemoryResult(from: data)
            }
        } catch {
            // Non-fatal — memory intelligence is an enhancement, not required for note editing.
        }
    }
}

struct ChurchNoteMemoryResult {
    let topThemes: [ChurchNoteMemoryTheme]
    let recentScriptures: [ChurchNoteMemoryScripture]
    let growthInsights: [String]
    let relatedNoteIds: [String]
    let notesAnalyzed: Int

    init(from data: [String: Any]) {
        topThemes = (data["topThemes"] as? [[String: Any]] ?? [])
            .compactMap { ChurchNoteMemoryTheme(from: $0) }
        recentScriptures = (data["recentScriptures"] as? [[String: Any]] ?? [])
            .compactMap { ChurchNoteMemoryScripture(from: $0) }
        growthInsights = data["growthInsights"] as? [String] ?? []
        relatedNoteIds = data["relatedNoteIds"] as? [String] ?? []
        notesAnalyzed = data["notesAnalyzed"] as? Int ?? 0
    }
}

struct ChurchNoteMemoryTheme {
    let label: String
    let count: Int
    let exampleNoteIds: [String]

    init?(from data: [String: Any]) {
        guard let label = data["label"] as? String else { return nil }
        self.label = label
        self.count = data["count"] as? Int ?? 1
        self.exampleNoteIds = data["exampleNoteIds"] as? [String] ?? []
    }
}

struct ChurchNoteMemoryScripture {
    let reference: String
    let count: Int

    init?(from data: [String: Any]) {
        guard let ref = data["reference"] as? String else { return nil }
        self.reference = ref
        self.count = data["count"] as? Int ?? 1
    }
}
