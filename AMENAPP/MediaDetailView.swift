import SwiftUI

@available(*, deprecated, message: "Use AmenMediaDetailView via AmenMediaDetailLoaderView for all post-backed media.")
struct MediaDetailView: View {
    let item: EnrichedMediaGridItem
    var onViewFullPost: ((String) -> Void)? = nil

    var body: some View {
        AmenMediaDetailLoaderView(
            postID: item.postId,
            initialMediaIndex: item.indexInPost,
            sourceContext: .profile
        )
    }
}
