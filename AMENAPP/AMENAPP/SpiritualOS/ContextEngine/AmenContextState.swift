import Foundation
import CoreLocation

// MARK: - AmenContextState
// Pure value type representing the current detected context for the Spiritual OS.
// Produced by SpiritualOSContextManager and distributed as @EnvironmentObject.
// DORMANT unless spiritualOS_context_engine_enabled flag is ON and user has explicitly opted in.

struct AmenContextState: Equatable {
    var mode: SOContextMode = .default
    var timeOfDay: TimeOfDay = .morning
    var isSundayChurchTime: Bool = false
    var isNearChurch: Bool = false      // only set if user opted in to geofence
    var isDriving: Bool = false
    var isTraveling: Bool = false
    var userPermissions: ContextPermissions = .none
    var lastUpdated: Date = Date()
}

// MARK: - TimeOfDay

enum TimeOfDay: String, Codable {
    case morning, afternoon, evening, night

    static func current() -> TimeOfDay {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default:      return .night
        }
    }
}

// MARK: - ContextPermissions
// Tracks which capabilities the user has explicitly opted into.
// All fields default to false — least privilege.

struct ContextPermissions: Equatable {
    var locationEnabled: Bool = false
    var motionEnabled: Bool = false
    var geofenceOptIn: Bool = false
    var audioAutoPlay: Bool = false

    static let none = ContextPermissions()
}
