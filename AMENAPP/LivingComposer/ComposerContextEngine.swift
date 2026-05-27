import Foundation
import CoreLocation

// Derives the optimal ComposerMode and PostingContext from the user's current environment,
// post history patterns, and time of day.
@MainActor
final class ComposerContextEngine: ObservableObject {
    static let shared = ComposerContextEngine()

    @Published private(set) var currentContext: PostingContext = .unknown
    @Published private(set) var suggestedMode: ComposerMode = .standard
    @Published private(set) var contextualAudienceRoutes: [AudienceRoute] = [.personalFeed()]

    private init() {}

    func evaluate(locationContext: LocationContext, nearbyGatherings: [NearbyGathering] = []) {
        let derived = derivePostingContext(from: locationContext, gatherings: nearbyGatherings)
        currentContext = derived
        suggestedMode = derived.composerMode
        contextualAudienceRoutes = buildAudienceRoutes(context: derived, location: locationContext, gatherings: nearbyGatherings)
    }

    func evaluateFromCurrentState() {
        let locationContext = LocationContextService.shared.currentContext
        evaluate(locationContext: locationContext)
    }

    // MARK: - Context Derivation

    private func derivePostingContext(from location: LocationContext, gatherings: [NearbyGathering]) -> PostingContext {
        if !gatherings.isEmpty {
            let types = gatherings.map { $0.type }
            if types.contains(.churchService) || types.contains(.worshipNight) || types.contains(.prayerNight) {
                return .church
            }
            if types.contains(.bibleStudy) || types.contains(.smallGroup) {
                return .gathering
            }
            return .gathering
        }

        switch location.environment {
        case .conference:   return .conference
        case .stadium:      return .event
        case .campus:       return .campus
        case .airport, .international: return .traveling
        case .coworking:    return .working
        case .church:       return .church
        case .home:         return .home
        case .hospital, .unknown: return .unknown
        }
    }

    // MARK: - Audience Routes

    private func buildAudienceRoutes(context: PostingContext, location: LocationContext, gatherings: [NearbyGathering]) -> [AudienceRoute] {
        var routes: [AudienceRoute] = [.personalFeed(score: 1.0)]

        switch context {
        case .conference:
            routes.append(AudienceRoute(
                id: "conference_\(location.city)", type: .local,
                label: "\(location.city) Conference", subtitle: "Share with attendees",
                selected: false, score: 0.9
            ))
            routes.append(AudienceRoute(
                id: "global_discovery", type: .global,
                label: "Global Discovery", subtitle: nil, selected: false, score: 0.6
            ))
        case .church, .gathering:
            routes.append(AudienceRoute(
                id: "church_space", type: .churchSpace,
                label: "Church Space", subtitle: "Share with your community",
                selected: false, score: 0.85
            ))
        case .event, .campus:
            routes.append(AudienceRoute(
                id: "event_\(location.city)", type: .nearbyEvent,
                label: "Nearby Event", subtitle: nil, selected: false, score: 0.8
            ))
        case .working:
            routes.append(AudienceRoute(
                id: "community_\(location.city)", type: .communitySpace,
                label: "Community Space", subtitle: nil, selected: false, score: 0.7
            ))
        default:
            break
        }

        for gathering in gatherings.prefix(2) {
            routes.append(.nearbyEvent(eventName: gathering.title, score: 0.88))
        }

        return routes.sorted { $0.score > $1.score }
    }

    // MARK: - Time-of-Day Hint

    var timeOfDayHint: TimeOfDayHint {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 22..., 0..<5: return .lateNight
        case 5..<9:         return .earlyMorning
        case 9..<12:        return .morning
        case 12..<17:       return .afternoon
        case 17..<20:       return .evening
        default:            return .night
        }
    }
}

enum TimeOfDayHint {
    case earlyMorning, morning, afternoon, evening, night, lateNight

    var suggestsReflective: Bool {
        switch self {
        case .earlyMorning, .lateNight: return true
        default: return false
        }
    }

    var composerPlaceholder: String {
        switch self {
        case .earlyMorning: return "Start your morning with a reflection..."
        case .morning:      return "What's on your mind this morning?"
        case .afternoon:    return "What's happening today?"
        case .evening:      return "How was your day?"
        case .night:        return "What are you thinking about tonight?"
        case .lateNight:    return "A quiet moment to reflect..."
        }
    }
}
