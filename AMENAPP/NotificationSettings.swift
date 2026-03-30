import Foundation

struct NotificationSettings: Codable {
    var prayerIntercessors:  Bool = true
    var prayerAnswered:      Bool = true
    var prayerMilestone:     Bool = true
    var prayerInsights:      Bool = true
    var testimonyStrength:   Bool = true
    var testimonyRipple:     Bool = true
    var testimonyNeededThis: Bool = true
    var scriptureConfirmed:  Bool = true
    var weeklyDigest:        Bool = true
}
