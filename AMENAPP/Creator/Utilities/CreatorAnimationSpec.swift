import SwiftUI

enum CreatorAnimationSpec {
    static let quick = Animation.easeOut(duration: 0.18)
    static let smooth = Animation.spring(response: 0.4, dampingFraction: 0.85)
}
