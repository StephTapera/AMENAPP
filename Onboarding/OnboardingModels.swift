import Foundation
import FirebaseFirestore

enum OnboardingStep: Int, Codable, CaseIterable {
    case welcome = 0, interests = 1, church = 2, featureTour = 3, invite = 4, complete = 5
    var displayName: String {
        switch self {
        case .welcome: return "Welcome"; case .interests: return "Interests"; case .church: return "Church"
        case .featureTour: return "Features"; case .invite: return "Invite"; case .complete: return "Complete"
        }
    }
}

enum UserInterest: String, Codable, CaseIterable {
    case giving, wellness, crisis, community
    var displayName: String { rawValue.capitalized }
    var icon: String {
        switch self { case .giving: return "heart.fill"; case .wellness: return "leaf.fill"; case .crisis: return "lifepreserver.fill"; case .community: return "person.2.fill" }
    }
    var description: String {
        switch self {
        case .giving: return "Support vetted nonprofits and track your giving impact"
        case .wellness: return "Grounding exercises, journaling, and wellness tools"
        case .crisis: return "24/7 crisis resources and peer support community"
        case .community: return "Connect with your church and faith community"
        }
    }
    var accentColor: String {
        switch self { case .giving: return "gold"; case .wellness: return "teal"; case .crisis: return "blue"; case .community: return "purple" }
    }
}

struct OnboardingFunnel: Codable {
    var step: OnboardingStep
    var interests: [UserInterest]
    var churchId: String?
    var startedAt: Timestamp?
    var completedAt: Timestamp?
}
