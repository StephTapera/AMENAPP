import SwiftUI

enum ChurchNotesAnimationTokens {
    static let quickTap = Animation.easeOut(duration: 0.16)
    static let sectionExpand = Animation.spring(response: 0.4, dampingFraction: 0.82)
    static let stickyHeader = Animation.easeInOut(duration: 0.24)
    static let chipInsert = Animation.spring(response: 0.28, dampingFraction: 0.84)
    static let reviewMode = Animation.spring(response: 0.34, dampingFraction: 0.86)
    static let autosavePulse = Animation.easeInOut(duration: 0.55)
}
