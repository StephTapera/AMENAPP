import SwiftUI

#if DEBUG

// MARK: - Preview fixtures

private let shortPost = Post.previewPost(
    content: "He gives strength to the weary and increases the power of the weak.",
    verseRef: "Isaiah 40:29"
)

private let longPost = Post.previewPost(
    content: "When everything around you is crumbling, there is a peace that passes all understanding. Not a peace the world can give, but a peace that holds you steady even when the storm doesn't stop. I've been through seasons where prayer was all I had left, and somehow that was enough. It always has been.",
    verseRef: "Philippians 4:7"
)

private let noVersePost = Post.previewPost(
    content: "Grateful for the community here. You all have been such a blessing.",
    verseRef: nil
)

private let longNamePost = Post.previewPost(
    content: "Walk in love, as Christ loved us.",
    verseRef: "Ephesians 5:2",
    authorName: "Christopher Benjamin Okonkwo-Williams",
    authorUsername: "chrisokonkwowilliams"
)

// MARK: - Story previews

#Preview("Story – Short") {
    ShareCard(post: shortPost, size: .story)
        .ignoresSafeArea()
}

#Preview("Story – Long (>500 chars)") {
    ShareCard(post: longPost, size: .story)
        .ignoresSafeArea()
}

#Preview("Story – No verse") {
    ShareCard(post: noVersePost, size: .story)
        .ignoresSafeArea()
}

#Preview("Story – Override pull quote") {
    ShareCard(
        post: shortPost,
        size: .story,
        pullQuote: "Not a peace the world can give.",
        verseRef: "John 14:27"
    )
    .ignoresSafeArea()
}

#Preview("Story – Long author name") {
    ShareCard(post: longNamePost, size: .story)
        .ignoresSafeArea()
}

// MARK: - Square previews

#Preview("Square – Short") {
    ShareCard(post: shortPost, size: .square)
        .ignoresSafeArea()
}

#Preview("Square – Long") {
    ShareCard(post: longPost, size: .square)
        .ignoresSafeArea()
}

// MARK: - Preview fixture factory

private extension Post {
    // Decodes a minimal Post fixture from JSON so previews don't require a real initializer.
    static func previewPost(
        content: String,
        verseRef: String? = nil,
        authorName: String = "Sarah Mitchell",
        authorUsername: String = "sarahmitchell"
    ) -> Post {
        var dict: [String: Any] = [
            "id": UUID().uuidString,
            "authorId": "preview-user",
            "authorName": authorName,
            "authorUsername": authorUsername,
            "authorInitials": String(authorName.prefix(1)),
            "content": content,
            "amenCount": 0,
            "commentCount": 0,
        ]
        if let verse = verseRef {
            dict["verseReference"] = verse
        }
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Post.self, from: data)
    }
}

#endif
