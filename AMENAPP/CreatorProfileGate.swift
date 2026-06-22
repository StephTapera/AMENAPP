// CreatorProfileGate.swift — AMEN App
// Routing wrapper for profile surfaces.
//
// The richer creator-public profile surface (CreatorPublicProfileView and its
// view model) is being rebuilt separately. Until it lands, this gate renders the
// standard profile content. Creator-profile routing is therefore inert by default;
// the dedicated public-profile path can be reintroduced here once available.

import SwiftUI

struct CreatorProfileGate<StandardContent: View>: View {
    let userId: String
    let showsDismissButton: Bool
    @ViewBuilder let standardContent: () -> StandardContent

    var body: some View {
        standardContent()
    }
}
