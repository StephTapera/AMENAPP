import Foundation
import CoreGraphics

struct PostQuoteMetadata: Codable, Equatable, Hashable {
    let sourcePostId: String
    let sourceAuthorId: String
    let sourceAuthorName: String
    let sourceAuthorUsername: String?
    let sourceExcerpt: String
    let selectionStart: Int
    let selectionLength: Int
    let quoteType: QuoteType?
    let createdAt: Date

    enum QuoteType: String, Codable {
        case verse
        case sentence
        case fragment
    }
}

struct QuoteComposerContext: Identifiable {
    let id: UUID = UUID()
    let sourcePost: Post
    let sourceAuthorId: String
    let sourceAuthorName: String
    let sourceAuthorUsername: String?
    let selection: PostTextSelection
}

struct PostTextSelection: Equatable {
    let text: String
    let range: NSRange
    let rect: CGRect
    let suggestedQuoteType: PostQuoteMetadata.QuoteType
}

struct SavedExcerpt: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let postId: String
    let authorId: String
    let authorName: String
    let excerpt: String
    let createdAt: Date

    init(postId: String, authorId: String, authorName: String, excerpt: String) {
        self.id = UUID().uuidString
        self.postId = postId
        self.authorId = authorId
        self.authorName = authorName
        self.excerpt = excerpt
        self.createdAt = Date()
    }
}

@MainActor
final class ExcerptStore {
    static let shared = ExcerptStore()
    private let storageKey = "saved_excerpts_v1"

    func save(_ excerpt: SavedExcerpt) {
        var all = loadAll()
        all.insert(excerpt, at: 0)
        persist(all)
    }

    func loadAll() -> [SavedExcerpt] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([SavedExcerpt].self, from: data)) ?? []
    }

    private func persist(_ excerpts: [SavedExcerpt]) {
        guard let data = try? JSONEncoder().encode(excerpts) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
