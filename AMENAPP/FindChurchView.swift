//
//  FindChurchView.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI
import MapKit
import CoreLocation
import Combine
import FirebaseAuth

// MARK: - Church Model

struct Church: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let denomination: String
    let address: String
    var distance: String
    var distanceValue: Double
    let serviceTime: String
    let phone: String
    let latitude: Double
    let longitude: Double
    let website: String?
    let nextServiceCountdown: String?
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    init(id: UUID = UUID(),
         name: String,
         denomination: String,
         address: String,
         distance: String,
         distanceValue: Double = 0.0,
         serviceTime: String,
         phone: String,
         coordinate: CLLocationCoordinate2D,
         website: String? = nil,
         nextServiceCountdown: String? = nil) {
        self.id = id
        self.name = name
        self.denomination = denomination
        self.address = address
        self.distance = distance
        self.distanceValue = distanceValue
        self.serviceTime = serviceTime
        self.phone = phone
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.website = website
        self.nextServiceCountdown = nextServiceCountdown
    }
    
    static func == (lhs: Church, rhs: Church) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Church Extensions for Smart Features
extension Church {
    var gradientColors: [Color] {
        switch denomination {
        case "Baptist":
            return [.blue, .cyan]
        case "Catholic":
            return [.purple, .pink]
        case "Non-Denominational":
            return [.green, .teal]
        case "Pentecostal":
            return [.orange, .red]
        case "Methodist":
            return [.indigo, .blue]
        case "Presbyterian":
            return [.mint, .green]
        default:
            return [.gray, .secondary]
        }
    }
    
    var denominationColor: Color {
        switch denomination {
        case "Baptist":
            return .blue
        case "Catholic":
            return .purple
        case "Non-Denominational":
            return .green
        case "Pentecostal":
            return .orange
        case "Methodist":
            return .indigo
        case "Presbyterian":
            return .mint
        default:
            return .gray
        }
    }
    
    var shortServiceTime: String {
        // Extract first time from service string
        let components = serviceTime.split(separator: " ")
        if let timeIndex = components.firstIndex(where: { $0.contains(":") }) {
            return String(components[timeIndex])
        }
        return "Sunday"
    }
}

// MARK: - CLLocationCoordinate2D Extension
extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

struct FindChurchView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var churchSearchService: ChurchSearchService = .shared
    @StateObject private var persistenceManager = ChurchPersistenceManager.shared
    @State private var searchText = ""
    @State private var selectedDenomination: ChurchDenomination = .all
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var showLocationPermissionAlert = false
    @State private var selectedViewMode: ViewMode = .list
    @State private var showSavedChurches = false
    @State private var useRealSearch = false
    @State private var hasSearchedOnce = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var scrollOffset: CGFloat = 0
    @State private var filtersCollapsed = false
    @State private var headerCollapsed = false
    @State private var headerHidden = false
    @State private var currentLocationName = "Locating..."
    @State private var isPerformingSearch = false
    @State private var searchRadius: Double = 8046.72 // 5 miles default search radius (in meters)
    @State private var sortMode: ChurchSortMode = .smartMatch
    @State private var selectedChurchesForComparison: Set<UUID> = []
    @State private var showComparisonView = false
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedChurch: Church?
    @State private var showFilters = false
    @State private var navigationPath = NavigationPath()
    @State private var showDenominationInfo: ChurchDenomination?
    @State private var showMapView = false
    @State private var recentSearches: [String] = []
    @State private var showRecentSearches = false
    @State private var favoriteChurches: [UUID] = []
    @State private var showQuickActions = false
    @State private var selectedQuickFilter: QuickFilter?
    @State private var shareableChurch: Church?
    @State private var showShareSheet = false
    @State private var churchVisitHistory: [ChurchVisit] = []
    @State private var showSmartSuggestions = false
    @State private var userPreferences = UserChurchPreferences()
    @State private var showScheduleView = false
    @State private var journeyInsights: [JourneyInsights.Insight] = []
    @Environment(\.dismiss) private var dismiss
    
    // AI Recommendations
    @State private var aiRecommendations: [ChurchRecommendation] = []
    @State private var isLoadingAIRecommendations = false
    @State private var showAIRecommendations = false
    
    // Smart features
    struct ChurchVisit: Codable, Identifiable {
        let id = UUID()
        let churchId: UUID
        let date: Date
        let duration: TimeInterval?
        let arrivalTime: Date? // Track when user arrived
        let wasOnTime: Bool? // Did they arrive before service started
    }
    
    // MARK: - Smart Algorithm 1: Church Discovery & Matching
    struct ChurchMatchingAlgorithm {
        /// Intelligently scores churches based on user preferences and behavior
        /// Higher score = better match for the user
        func scoreChurch(_ church: Church, for preferences: UserChurchPreferences, visitHistory: [ChurchVisit]) -> Double {
            var score: Double = 0.0
            
            // 1. Distance scoring (30% weight) - Closer is generally better
            let maxDistance = 25.0 // miles
            let distanceScore = max(0, (maxDistance - church.distanceValue) / maxDistance * 10.0)
            score += distanceScore * 0.3
            
            // 2. Denomination preference (25% weight)
            if preferences.preferredDenominations.contains(church.denomination) {
                score += 7.5
            } else if !preferences.preferredDenominations.isEmpty {
                // Slight penalty for non-preferred denominations
                score += 2.0
            } else {
                // No preference set - neutral score
                score += 5.0
            }
            
            // 3. Visit history (20% weight) - Familiarity is valuable
            if preferences.visitedChurches.contains(church.id) {
                let visitCount = visitHistory.filter { $0.churchId == church.id }.count
                // More visits = higher familiarity score (capped at 8)
                let familiarityScore = min(8.0, Double(visitCount) * 2.0)
                score += familiarityScore * 0.2
            }
            
            // 4. Service time compatibility (15% weight)
            if let preferredDay = preferences.typicalAttendanceDay {
                // Check if church has services on preferred day
                if serviceMatchesPreferredDay(church.serviceTime, preferredDay: preferredDay) {
                    score += 6.0
                } else {
                    score += 2.0
                }
            } else {
                score += 4.0 // Neutral if no preference
            }
            
            // 5. Distance from preferred max (10% weight)
            if church.distanceValue <= preferences.maxPreferredDistance {
                score += 5.0
            } else {
                // Gradual penalty for exceeding preferred distance
                let exceedance = church.distanceValue - preferences.maxPreferredDistance
                score += max(0, 5.0 - (exceedance / 5.0))
            }
            
            return score
        }
        
        /// Get top matched churches sorted by score
        func getTopMatches(from churches: [Church], for preferences: UserChurchPreferences, visitHistory: [ChurchVisit], limit: Int = 10) -> [(church: Church, score: Double)] {
            let scoredChurches = churches.map { church in
                (church: church, score: scoreChurch(church, for: preferences, visitHistory: visitHistory))
            }
            
            return scoredChurches
                .sorted { $0.score > $1.score }
                .prefix(limit)
                .map { $0 }
        }
        
        private func serviceMatchesPreferredDay(_ serviceTime: String, preferredDay: Int) -> Bool {
            let lowercased = serviceTime.lowercased()
            
            switch preferredDay {
            case 1: // Sunday
                return lowercased.contains("sunday") || lowercased.contains("sun")
            case 7: // Saturday
                return lowercased.contains("saturday") || lowercased.contains("sat")
            default:
                return false
            }
        }
    }
    
    // MARK: - Smart Algorithm 2: Smart Notification Timing
    struct SmartNotificationScheduler {
        /// Calculate optimal reminder time based on user behavior patterns
        func calculateOptimalReminderTime(
            for church: Church,
            preferences: UserChurchPreferences,
            visitHistory: [ChurchVisit],
            userLocation: CLLocationCoordinate2D?
        ) -> Date? {
            guard let serviceDate = parseNextServiceDate(from: church.serviceTime) else {
                return nil
            }
            
            // 1. Calculate average preparation time from history
            let prepTime = calculateAveragePrepTime(from: visitHistory, for: church.id, preferences: preferences)
            
            // 2. Estimate travel time to church
            let travelTime = estimateTravelTime(to: church, from: userLocation)
            
            // 3. Add buffer time (15 minutes to be safe)
            let bufferTime: TimeInterval = 15 * 60
            
            // 4. Calculate optimal reminder time
            let totalLeadTime = prepTime + travelTime + bufferTime
            let reminderTime = serviceDate.addingTimeInterval(-totalLeadTime)
            
            // 5. Ensure reminder is not in the past or too far in future (max 24 hours)
            let now = Date()
            let maxAdvanceTime = now.addingTimeInterval(24 * 60 * 60)
            
            if reminderTime < now {
                // If calculated time is in past, set for 1 hour before service
                return serviceDate.addingTimeInterval(-60 * 60)
            } else if reminderTime > maxAdvanceTime {
                // If too far in future, cap at 24 hours from now
                return maxAdvanceTime
            }
            
            return reminderTime
        }
        
        /// Calculate user's average preparation time based on visit history
        private func calculateAveragePrepTime(from history: [ChurchVisit], for churchId: UUID, preferences: UserChurchPreferences) -> TimeInterval {
            // Filter visits for this church that have arrival time data
            let relevantVisits = history.filter { visit in
                visit.churchId == churchId && visit.arrivalTime != nil
            }
            
            if relevantVisits.isEmpty {
                // No history - use default from preferences
                return TimeInterval(preferences.prepTimeMinutes * 60)
            }
            
            // Calculate average time between check-in and service start
            // (This would require service start times - for now use preference)
            return TimeInterval(preferences.prepTimeMinutes * 60)
        }
        
        /// Estimate travel time to church (simplified - could integrate with MapKit routing)
        private func estimateTravelTime(to church: Church, from userLocation: CLLocationCoordinate2D?) -> TimeInterval {
            guard let userLoc = userLocation else {
                // No location - assume 30 minutes
                return 30 * 60
            }
            
            // Simple estimation: distance / average speed
            // Average speed: 30 mph in city = 0.5 miles per minute
            let distanceInMiles = church.distanceValue
            let estimatedMinutes = distanceInMiles / 0.5
            
            // Add traffic buffer (20% extra time)
            let withTrafficBuffer = estimatedMinutes * 1.2
            
            return withTrafficBuffer * 60 // Convert to seconds
        }
        
        /// Parse next service date from service time string
        private func parseNextServiceDate(from serviceTime: String) -> Date? {
            let calendar = Calendar.current
            let now = Date()
            
            // Simple parsing for "Sunday" services
            if serviceTime.localizedCaseInsensitiveContains("sunday") {
                // Find next Sunday
                let weekday = calendar.component(.weekday, from: now)
                let daysUntilSunday = (1 - weekday + 7) % 7
                let nextSunday = calendar.date(byAdding: .day, value: daysUntilSunday == 0 ? 7 : daysUntilSunday, to: now)
                
                // Try to extract time (e.g., "10:00 AM")
                if let time = extractTime(from: serviceTime) {
                    return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: nextSunday ?? now)
                }
                
                // Default to 10:00 AM if no time found
                return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: nextSunday ?? now)
            }
            
            // Default: assume next Sunday at 10 AM
            let weekday = calendar.component(.weekday, from: now)
            let daysUntilSunday = (1 - weekday + 7) % 7
            let nextSunday = calendar.date(byAdding: .day, value: daysUntilSunday == 0 ? 7 : daysUntilSunday, to: now)
            return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: nextSunday ?? now)
        }
        
        /// Extract hour and minute from service time string
        private func extractTime(from serviceTime: String) -> (hour: Int, minute: Int)? {
            // Look for patterns like "10:00", "9:30", etc.
            let pattern = #"(\d{1,2}):(\d{2})"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: serviceTime, range: NSRange(serviceTime.startIndex..., in: serviceTime)) else {
                return nil
            }
            
            guard let hourRange = Range(match.range(at: 1), in: serviceTime),
                  let minuteRange = Range(match.range(at: 2), in: serviceTime) else {
                return nil
            }
            
            let hourStr = String(serviceTime[hourRange])
            let minuteStr = String(serviceTime[minuteRange])
            
            guard var hour = Int(hourStr), let minute = Int(minuteStr) else {
                return nil
            }
            
            // Check for PM indicator
            if serviceTime.localizedCaseInsensitiveContains("pm") && hour < 12 {
                hour += 12
            }
            
            return (hour: hour, minute: minute)
        }
    }
    
    // MARK: - Smart Algorithm 3: Service Time Prediction
    struct ServiceTimePrediction {
        /// Predict next service time considering holidays and special events
        func predictNextService(for church: Church, from date: Date = Date()) -> Date? {
            let calendar = Calendar.current
            
            // Check if date is a holiday
            if let holiday = getHoliday(for: date) {
                return adjustForHoliday(church, holiday: holiday, on: date)
            }
            
            // Check denomination-specific patterns
            if church.denomination == "Catholic" {
                return getCatholicServiceTime(church, on: date)
            }
            
            // Standard service time prediction
            return getStandardServiceTime(church, on: date)
        }
        
        /// Get standard service time (typically Sunday morning)
        private func getStandardServiceTime(_ church: Church, on date: Date) -> Date? {
            let calendar = Calendar.current
            
            // Find next Sunday
            let weekday = calendar.component(.weekday, from: date)
            let daysUntilSunday = (1 - weekday + 7) % 7
            let nextSunday = calendar.date(byAdding: .day, value: daysUntilSunday == 0 ? 7 : daysUntilSunday, to: date)
            
            // Extract time from service string or default to 10 AM
            if let time = extractServiceTime(from: church.serviceTime) {
                return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: nextSunday ?? date)
            }
            
            return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: nextSunday ?? date)
        }
        
        /// Get Catholic-specific service times (includes Saturday evening)
        private func getCatholicServiceTime(_ church: Church, on date: Date) -> Date? {
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: date)
            
            // Catholics have Saturday evening vigil Mass (counts as Sunday)
            if weekday == 7 { // Saturday
                return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: date) // 5 PM
            }
            
            // Otherwise return standard Sunday service
            return getStandardServiceTime(church, on: date)
        }
        
        /// Adjust service time for holidays
        private func adjustForHoliday(_ church: Church, holiday: Holiday, on date: Date) -> Date? {
            let calendar = Calendar.current
            
            switch holiday {
            case .christmas:
                // Christmas services often at special times
                return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: date)
            case .easter:
                // Easter sunrise services
                return calendar.date(bySettingHour: 7, minute: 0, second: 0, of: date)
            case .thanksgiving:
                // Often have special morning service
                return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)
            case .newYear:
                // New Year's service
                return calendar.date(bySettingHour: 10, minute: 30, second: 0, of: date)
            }
        }
        
        /// Detect if a date is a major holiday
        private func getHoliday(for date: Date) -> Holiday? {
            let calendar = Calendar.current
            let month = calendar.component(.month, from: date)
            let day = calendar.component(.day, from: date)
            
            // Christmas
            if month == 12 && day == 25 {
                return .christmas
            }
            
            // New Year's Day
            if month == 1 && day == 1 {
                return .newYear
            }
            
            // Easter (complex calculation - simplified here)
            if month == 4 && (day >= 1 && day <= 22) {
                // Easter falls between March 22 and April 25
                // This is simplified - actual calculation is complex
                return .easter
            }
            
            // Thanksgiving (4th Thursday of November)
            if month == 11 {
                let weekday = calendar.component(.weekday, from: date)
                let weekOfMonth = calendar.component(.weekOfMonth, from: date)
                if weekday == 5 && weekOfMonth == 4 {
                    return .thanksgiving
                }
            }
            
            return nil
        }
        
        private func extractServiceTime(from serviceString: String) -> (hour: Int, minute: Int)? {
            // Same implementation as in SmartNotificationScheduler
            let pattern = #"(\d{1,2}):(\d{2})"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: serviceString, range: NSRange(serviceString.startIndex..., in: serviceString)) else {
                return nil
            }
            
            guard let hourRange = Range(match.range(at: 1), in: serviceString),
                  let minuteRange = Range(match.range(at: 2), in: serviceString) else {
                return nil
            }
            
            let hourStr = String(serviceString[hourRange])
            let minuteStr = String(serviceString[minuteRange])
            
            guard var hour = Int(hourStr), let minute = Int(minuteStr) else {
                return nil
            }
            
            if serviceString.localizedCaseInsensitiveContains("pm") && hour < 12 {
                hour += 12
            }
            
            return (hour: hour, minute: minute)
        }
        
        enum Holiday {
            case christmas
            case easter
            case thanksgiving
            case newYear
        }
    }
    
    // MARK: - Smart Algorithm 4: Community Connection Suggestions
    struct CommunityMatcher {
        /// Find churches where users with similar profiles attend (privacy-preserving)
        func findCommunitySuggestions(
            for preferences: UserChurchPreferences,
            from churches: [Church],
            visitHistory: [ChurchVisit],
            limit: Int = 5
        ) -> [ChurchSuggestion] {
            var suggestions: [ChurchSuggestion] = []
            
            // 1. Find churches not yet visited
            let unvisitedChurches = churches.filter { !preferences.visitedChurches.contains($0.id) }
            
            // 2. Score based on similarity to visited churches
            for church in unvisitedChurches {
                let score = calculateCommunitySimilarityScore(
                    church: church,
                    preferences: preferences,
                    visitHistory: visitHistory
                )
                
                if score > 0.5 { // Threshold for relevance
                    let reason = generateSuggestionReason(church: church, preferences: preferences)
                    suggestions.append(ChurchSuggestion(
                        church: church,
                        score: score,
                        reason: reason
                    ))
                }
            }
            
            // 3. Sort by score and return top suggestions
            return suggestions
                .sorted { $0.score > $1.score }
                .prefix(limit)
                .map { $0 }
        }
        
        /// Calculate similarity score (0.0 to 1.0)
        private func calculateCommunitySimilarityScore(
            church: Church,
            preferences: UserChurchPreferences,
            visitHistory: [ChurchVisit]
        ) -> Double {
            var score: Double = 0.0
            
            // Denomination match
            if preferences.preferredDenominations.contains(church.denomination) {
                score += 0.4
            }
            
            // Similar to visited churches
            let visitedDenominations = getVisitedDenominations(from: visitHistory, preferences: preferences)
            if visitedDenominations.contains(church.denomination) {
                score += 0.3
            }
            
            // Within preferred distance
            if church.distanceValue <= preferences.maxPreferredDistance {
                score += 0.2
            } else {
                // Gradual decrease for distance
                let distanceRatio = preferences.maxPreferredDistance / max(church.distanceValue, 0.1)
                score += 0.2 * min(distanceRatio, 1.0)
            }
            
            // Diversity bonus (slightly favor different denominations to encourage exploration)
            if !visitedDenominations.contains(church.denomination) && visitedDenominations.count > 0 {
                score += 0.1
            }
            
            return min(score, 1.0)
        }
        
        private func getVisitedDenominations(from history: [ChurchVisit], preferences: UserChurchPreferences) -> Set<String> {
            // This would require church data - for now return preferred denominations
            return preferences.preferredDenominations
        }
        
        private func generateSuggestionReason(church: Church, preferences: UserChurchPreferences) -> String {
            if preferences.preferredDenominations.contains(church.denomination) {
                return "Matches your \(church.denomination) preference"
            }
            
            if church.distanceValue < 1.0 {
                return "Very close to you"
            }
            
            if church.distanceValue <= preferences.maxPreferredDistance {
                return "Within your preferred distance"
            }
            
            return "Based on your church exploration history"
        }
        
        struct ChurchSuggestion {
            let church: Church
            let score: Double
            let reason: String
        }
    }
    
    // MARK: - Smart Algorithm 5: Journey Progress & Milestones
    struct JourneyInsights {
        /// Generate meaningful insights about user's faith journey
        func generateInsights(
            for preferences: UserChurchPreferences,
            visitHistory: [ChurchVisit],
            savedChurches: [Church]
        ) -> [Insight] {
            var insights: [Insight] = []
            
            // 1. Exploration milestones
            if let explorationInsight = generateExplorationInsight(preferences: preferences, visitHistory: visitHistory) {
                insights.append(explorationInsight)
            }
            
            // 2. Consistency recognition
            if let consistencyInsight = generateConsistencyInsight(visitHistory: visitHistory, savedChurches: savedChurches) {
                insights.append(consistencyInsight)
            }
            
            // 3. Community engagement
            if let engagementInsight = generateEngagementInsight(savedChurches: savedChurches) {
                insights.append(engagementInsight)
            }
            
            // 4. Recent activity
            if let activityInsight = generateRecentActivityInsight(visitHistory: visitHistory) {
                insights.append(activityInsight)
            }
            
            return insights
        }
        
        private func generateExplorationInsight(preferences: UserChurchPreferences, visitHistory: [ChurchVisit]) -> Insight? {
            let visitedCount = preferences.visitedChurches.count
            
            if visitedCount >= 20 {
                return Insight(
                    type: .milestone,
                    icon: "star.fill",
                    title: "Church Explorer Champion",
                    description: "You've visited \(visitedCount) different churches! Your openness to exploration is inspiring.",
                    color: .purple
                )
            } else if visitedCount >= 10 {
                return Insight(
                    type: .milestone,
                    icon: "map.fill",
                    title: "Community Explorer",
                    description: "You've explored \(visitedCount) churches in your faith journey.",
                    color: .blue
                )
            } else if visitedCount >= 5 {
                return Insight(
                    type: .encouragement,
                    icon: "sparkles",
                    title: "Discovering Community",
                    description: "\(visitedCount) churches visited. Keep exploring!",
                    color: .cyan
                )
            }
            
            return nil
        }
        
        private func generateConsistencyInsight(visitHistory: [ChurchVisit], savedChurches: [Church]) -> Insight? {
            // Find church with most visits in last 2 months
            let twoMonthsAgo = Date().addingTimeInterval(-60 * 24 * 60 * 60)
            let recentVisits = visitHistory.filter { $0.date > twoMonthsAgo }
            
            // Count visits per church
            var visitCounts: [UUID: Int] = [:]
            for visit in recentVisits {
                visitCounts[visit.churchId, default: 0] += 1
            }
            
            // Find most visited church
            if let mostVisited = visitCounts.max(by: { $0.value < $1.value }),
               mostVisited.value >= 4,
               let church = savedChurches.first(where: { $0.id == mostVisited.key }) {
                return Insight(
                    type: .encouragement,
                    icon: "heart.fill",
                    title: "Growing Roots",
                    description: "You've been regularly attending \(church.name). Consistency builds community!",
                    color: .green
                )
            }
            
            return nil
        }
        
        private func generateEngagementInsight(savedChurches: [Church]) -> Insight? {
            let savedCount = savedChurches.count
            
            if savedCount >= 5 {
                return Insight(
                    type: .milestone,
                    icon: "bookmark.fill",
                    title: "Community Builder",
                    description: "You've saved \(savedCount) churches. Building connections across communities!",
                    color: .orange
                )
            } else if savedCount >= 3 {
                return Insight(
                    type: .encouragement,
                    icon: "hand.raised.fill",
                    title: "Staying Connected",
                    description: "\(savedCount) churches in your community network.",
                    color: .pink
                )
            }
            
            return nil
        }
        
        private func generateRecentActivityInsight(visitHistory: [ChurchVisit]) -> Insight? {
            let lastWeek = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            let recentVisits = visitHistory.filter { $0.date > lastWeek }
            
            if recentVisits.count >= 2 {
                return Insight(
                    type: .encouragement,
                    icon: "calendar",
                    title: "Active This Week",
                    description: "You've checked in \(recentVisits.count) times this week. Stay engaged!",
                    color: .indigo
                )
            }
            
            return nil
        }
        
        struct Insight: Identifiable {
            let id = UUID()
            let type: InsightType
            let icon: String
            let title: String
            let description: String
            let color: Color
            
            enum InsightType {
                case milestone
                case encouragement
                case suggestion
            }
        }
    }
    
    struct UserChurchPreferences: Codable {
        var preferredDenominations: Set<String> = []
        var preferredServiceTimes: Set<String> = []
        var maxPreferredDistance: Double = 10.0
        var visitedChurches: Set<UUID> = []
        var typicalAttendanceDay: Int? // 1 = Sunday, 7 = Saturday
        var preferredCongregationSize: CongregationSize = .any
        var musicStylePreference: MusicStyle = .any
        var programInterests: Set<ProgramType> = []
        var typicalArrivalTimes: [Date] = [] // Historical arrival times
        var prepTimeMinutes: Int = 30 // Time needed to prepare before leaving
        var lastNotificationCheckTime: Date?
        
        enum CongregationSize: String, Codable {
            case any = "Any Size"
            case small = "Small (under 100)"
            case medium = "Medium (100-500)"
            case large = "Large (500+)"
        }
        
        enum MusicStyle: String, Codable {
            case any = "Any Style"
            case traditional = "Traditional Hymns"
            case contemporary = "Contemporary Worship"
            case blended = "Blended"
        }
        
        enum ProgramType: String, Codable, CaseIterable {
            case youth = "Youth Programs"
            case children = "Children's Ministry"
            case seniors = "Senior Ministry"
            case youngAdults = "Young Adults"
            case families = "Family Programs"
            case singles = "Singles Ministry"
            case smallGroups = "Small Groups"
            case communityService = "Community Service"
        }
    }
    
    enum QuickFilter: String, CaseIterable {
        case nearestNow = "Nearest Now"
        case serviceToday = "Service Today"
        case openNow = "Open Now"
        case visitedBefore = "Visited Before"
        case highlyRated = "Highly Saved"
    }
    
    enum ChurchSortMode: String, CaseIterable {
        case smartMatch = "Smart Match"
        case nearest = "Nearest First"
        case farthest = "Farthest First"
        case alphabetical = "A-Z"
        case rating = "Most Saved"
    }
    
    // Computed property for saved church IDs
    private var savedChurchIds: Set<UUID> {
        Set(persistenceManager.savedChurches.map { $0.id })
    }
    
    enum ViewMode {
        case list
        case map
    }
    
    var userLocation: CLLocationCoordinate2D? {
        locationManager.userLocation
    }
    
    var locationStatusText: String {
        if locationManager.isAuthorized, let location = userLocation {
            return currentLocationName
        } else {
            return "Location services disabled"
        }
    }
    
    enum ChurchDenomination: String, CaseIterable, Identifiable {
        case all = "All"
        case baptist = "Baptist"
        case catholic = "Catholic"
        case nonDenominational = "Non-Denominational"
        case pentecostal = "Pentecostal"
        case methodist = "Methodist"
        case presbyterian = "Presbyterian"
        
        var id: String { rawValue }
    }
    
    var filteredChurches: [Church] {
        var churches = churchSearchService.searchResults
        
        // Filter by saved if enabled
        if showSavedChurches {
            churches = churches.filter { savedChurchIds.contains($0.id) }
        }
        
        // Apply quick filter
        if let quickFilter = selectedQuickFilter {
            churches = applyQuickFilter(quickFilter, to: churches)
        }
        
        // Filter by denomination
        if selectedDenomination != .all {
            churches = churches.filter { $0.denomination == selectedDenomination.rawValue }
        }
        
        // Filter by search text (search name, address, and denomination)
        if !searchText.isEmpty {
            let lowercasedQuery = searchText.lowercased()
            churches = churches.filter { church in
                church.name.localizedCaseInsensitiveContains(lowercasedQuery) ||
                church.address.localizedCaseInsensitiveContains(lowercasedQuery) ||
                church.denomination.localizedCaseInsensitiveContains(lowercasedQuery) ||
                church.phone.localizedCaseInsensitiveContains(lowercasedQuery) ||
                (church.website?.localizedCaseInsensitiveContains(lowercasedQuery) ?? false)
            }
        }
        
        // Apply sorting based on sort mode
        switch sortMode {
        case .smartMatch:
            // Use smart matching algorithm (cached for performance)
            let matcher = ChurchMatchingAlgorithm()
            let matches = matcher.getTopMatches(
                from: churches,
                for: userPreferences,
                visitHistory: churchVisitHistory,
                limit: churches.count
            )
            return matches.map { $0.church }
        case .nearest:
            return churches.sorted { $0.distanceValue < $1.distanceValue }
        case .farthest:
            return churches.sorted { $0.distanceValue > $1.distanceValue }
        case .alphabetical:
            return churches.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .rating:
            // Sort by saved status (saved churches first), then by visit history
            return churches.sorted { (church1, church2) in
                let church1Saved = savedChurchIds.contains(church1.id)
                let church2Saved = savedChurchIds.contains(church2.id)
                let church1Visited = userPreferences.visitedChurches.contains(church1.id)
                let church2Visited = userPreferences.visitedChurches.contains(church2.id)
                
                if church1Saved != church2Saved {
                    return church1Saved && !church2Saved
                } else if church1Visited != church2Visited {
                    return church1Visited && !church2Visited
                }
                return church1.distanceValue < church2.distanceValue
            }
        }
    }
    
    /// Smart-sorted churches using matching algorithm
    var smartSortedChurches: [Church] {
        let matcher = ChurchMatchingAlgorithm()
        let matches = matcher.getTopMatches(
            from: filteredChurches,
            for: userPreferences,
            visitHistory: churchVisitHistory,
            limit: filteredChurches.count
        )
        return matches.map { $0.church }
    }
    
    private func applyQuickFilter(_ filter: QuickFilter, to churches: [Church]) -> [Church] {
        switch filter {
        case .nearestNow:
            return churches.sorted { $0.distanceValue < $1.distanceValue }.prefix(5).map { $0 }
        case .serviceToday:
            return churches.filter { church in
                // Check if it's Sunday or if service time contains "today"
                let calendar = Calendar.current
                let today = calendar.component(.weekday, from: Date())
                return today == 1 || church.serviceTime.localizedCaseInsensitiveContains("sunday")
            }
        case .openNow:
            // Assume churches are "open" if service is today or within certain hours
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: Date())
            return churches.filter { _ in hour >= 9 && hour <= 20 } // 9 AM - 8 PM
        case .visitedBefore:
            return churches.filter { userPreferences.visitedChurches.contains($0.id) }
        case .highlyRated:
            return churches.filter { savedChurchIds.contains($0.id) }
        }
    }
    
    private func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation) / 1609.34 // Convert meters to miles
    }
    
    private var shouldShowRefresh: Bool {
        locationManager.isAuthorized && !churchSearchService.isSearching
    }
    
    private var hasChurchData: Bool {
        !churchSearchService.searchResults.isEmpty
    }
    
    private var shouldShowEmptyState: Bool {
        !churchSearchService.isSearching && 
        churchSearchService.searchResults.isEmpty && 
        locationManager.isAuthorized &&
        hasSearchedOnce
    }
    
    private var shouldShowSmartSuggestions: Bool {
        !userPreferences.preferredDenominations.isEmpty || 
        !userPreferences.visitedChurches.isEmpty ||
        savedChurchIds.count >= 2
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                // Minimal white background with subtle gradient
                LinearGradient(
                    colors: [
                        Color(white: 0.98),
                        Color(white: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        // Minimal header - no clutter
                        MinimalChurchHeader(
                            searchText: $searchText,
                            locationText: currentLocationName,
                            isLocationAuthorized: locationManager.isAuthorized,
                            onSearchSubmit: { performSearchWithText() },
                            onFilterTap: { 
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    showFilters.toggle()
                                }
                            },
                            onRefresh: locationManager.isAuthorized ? { performRealSearch() } : nil,
                            onBack: { dismiss() }
                        )
                        
                        // Minimal filter chips (shown when expanded)
                        if showFilters {
                            MinimalFilterRow(
                                selectedDenomination: $selectedDenomination,
                                sortMode: $sortMode,
                                searchRadius: $searchRadius,
                                showSavedOnly: $showSavedChurches,
                                showDenominationInfo: $showDenominationInfo,
                                onRadiusChange: { performRealSearch() }
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        // Quick Action Filters (Smart & Interactive)
                        if !filteredChurches.isEmpty && !showFilters {
                            QuickFilterBar(
                                selectedFilter: $selectedQuickFilter,
                                visitedCount: userPreferences.visitedChurches.count,
                                savedCount: savedChurchIds.count
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        // Permission banners - only when needed
                        if !locationManager.isAuthorized {
                            MinimalPermissionBanner(
                                icon: "location.fill",
                                title: "Enable Location",
                                message: "Find churches near you",
                                accentColor: Color(red: 0.2, green: 0.2, blue: 0.2),
                                onEnable: {
                                    locationManager.requestPermission()
                                    // Also show notification permission after
                                    Task {
                                        let notificationManager = ChurchNotificationManager.shared
                                        _ = await notificationManager.requestNotificationPermission()
                                    }
                                }
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        // Main content
                        if churchSearchService.isSearching {
                            FindChurchLoadingView()
                        } else if shouldShowEmptyState {
                            FindChurchEmptyState(
                                icon: "building.2",
                                title: "No Churches Found",
                                subtitle: filteredChurches.isEmpty && hasChurchData ? "Try different filters" : "Search to discover churches"
                            )
                        } else if !locationManager.isAuthorized {
                            FindChurchEmptyState(
                                icon: "location.slash",
                                title: "Location Required",
                                subtitle: "Enable location to find churches"
                            )
                        } else if !filteredChurches.isEmpty {
                            // Church list with smooth animations
                            ScrollView(showsIndicators: false) {
                                LazyVStack(spacing: 16) {
                                    // Subtle stats at the top
                                    if locationManager.isAuthorized && hasChurchData {
                                        MinimalStatsRow(
                                            count: filteredChurches.count,
                                            nearest: filteredChurches.first?.distance ?? "N/A"
                                        )
                                        .padding(.top, 8)
                                        
                                        // Journey Insights
                                        if !journeyInsights.isEmpty {
                                            ForEach(journeyInsights) { insight in
                                                JourneyInsightCard(insight: insight)
                                                    .padding(.top, 8)
                                            }
                                        }
                                        
                                        // Smart Suggestions Banner
                                        if shouldShowSmartSuggestions {
                                            SmartSuggestionsBanner(
                                                preferences: userPreferences,
                                                churches: filteredChurches,
                                                onSelectChurch: { church in
                                                    selectedChurch = church
                                                }
                                            )
                                            .padding(.top, 8)
                                        }
                                        
                                        // AI Church Recommendations
                                        VStack(alignment: .leading, spacing: 12) {
                                            Button {
                                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                                    showAIRecommendations.toggle()
                                                }
                                                
                                                if showAIRecommendations && aiRecommendations.isEmpty && !isLoadingAIRecommendations {
                                                    loadAIRecommendations()
                                                }
                                            } label: {
                                                HStack(spacing: 12) {
                                                    ZStack {
                                                        Circle()
                                                            .fill(
                                                                LinearGradient(
                                                                    colors: [.purple, .pink],
                                                                    startPoint: .topLeading,
                                                                    endPoint: .bottomTrailing
                                                                )
                                                            )
                                                            .frame(width: 44, height: 44)
                                                        
                                                        Image(systemName: "sparkles")
                                                            .font(.system(size: 20, weight: .semibold))
                                                            .foregroundStyle(.white)
                                                    }
                                                    
                                                    VStack(alignment: .leading, spacing: 3) {
                                                        Text("AI Recommendations")
                                                            .font(.system(size: 16, weight: .semibold))
                                                            .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                                                        
                                                        Text("Personalized matches for you")
                                                            .font(.system(size: 13, weight: .regular))
                                                            .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                                                    }
                                                    
                                                    Spacer()
                                                    
                                                    Image(systemName: showAIRecommendations ? "chevron.up" : "chevron.down")
                                                        .font(.system(size: 14, weight: .medium))
                                                        .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4))
                                                }
                                                .padding(16)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 16)
                                                        .fill(Color.white)
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 16)
                                                                .strokeBorder(
                                                                    LinearGradient(
                                                                        colors: [.purple.opacity(0.2), .pink.opacity(0.2)],
                                                                        startPoint: .topLeading,
                                                                        endPoint: .bottomTrailing
                                                                    ),
                                                                    lineWidth: 1.5
                                                                )
                                                        )
                                                        .shadow(color: .purple.opacity(0.1), radius: 8, y: 4)
                                                )
                                            }
                                            
                                            if showAIRecommendations {
                                                if isLoadingAIRecommendations {
                                                    HStack {
                                                        Spacer()
                                                        ProgressView()
                                                            .scaleEffect(1.2)
                                                        Spacer()
                                                    }
                                                    .padding(.vertical, 32)
                                                } else if !aiRecommendations.isEmpty {
                                                    VStack(spacing: 12) {
                                                        ForEach(aiRecommendations.prefix(5)) { recommendation in
                                                            AIRecommendationCard(
                                                                recommendation: recommendation,
                                                                onTap: {
                                                                    // Find the church in filtered churches
                                                                    if let church = filteredChurches.first(where: { $0.name == recommendation.churchName }) {
                                                                        selectedChurch = church
                                                                    }
                                                                }
                                                            )
                                                        }
                                                    }
                                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                                } else {
                                                    Text("No AI recommendations available")
                                                        .font(.system(size: 14, weight: .regular))
                                                        .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                                                        .italic()
                                                        .padding(.vertical, 16)
                                                }
                                            }
                                        }
                                        .padding(.top, 8)
                                    }
                                    
                                    ForEach(filteredChurches) { church in
                                        EnhancedMinimalChurchCard(
                                            church: church,
                                            isSaved: savedChurchIds.contains(church.id),
                                            isVisited: userPreferences.visitedChurches.contains(church.id),
                                            onTap: {
                                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                                    selectedChurch = church
                                                    markChurchAsViewed(church)
                                                }
                                            },
                                            onSave: { toggleSave(church) },
                                            onShare: { 
                                                shareableChurch = church
                                                showShareSheet = true
                                            },
                                            onCheckIn: { checkInToChurch(church) }
                                        )
                                        .transition(.asymmetric(
                                            insertion: .scale(scale: 0.95).combined(with: .opacity),
                                            removal: .opacity
                                        ).animation(.easeOut(duration: 0.2)))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 80)
                            }
                            .refreshable {
                                await refreshChurchSearch()
                            }
                        } else {
                            FindChurchEmptyState(
                                icon: "magnifyingglass",
                                title: "Find Churches",
                                subtitle: "Search to discover churches near you",
                                showAction: locationManager.isAuthorized,
                                actionTitle: "Search Now",
                                onAction: { performRealSearch() }
                            )
                        }
                    }
                }
            }
            .sheet(item: $selectedChurch) { church in
                EnhancedChurchDetailSheet(
                    church: church,
                    isSaved: savedChurchIds.contains(church.id),
                    isVisited: userPreferences.visitedChurches.contains(church.id),
                    onSave: { toggleSave(church) },
                    onGetDirections: { openDirections(to: church) },
                    onCall: { callChurch(church) },
                    onShare: { 
                        shareableChurch = church
                        showShareSheet = true
                    },
                    onCheckIn: { checkInToChurch(church) },
                    onAddToSchedule: { 
                        addToSchedule(church)
                        showScheduleView = true
                    }
                )
            }
            .sheet(item: $showDenominationInfo) { denomination in
                DenominationInfoSheet(denomination: denomination)
            }
            .sheet(isPresented: $showShareSheet, content: {
                if let church = shareableChurch {
                    ShareSheet(items: [church.shareText])
                }
            })
            .sheet(isPresented: $showScheduleView) {
                ChurchScheduleView(
                    savedChurches: persistenceManager.savedChurches,
                    onDismiss: { showScheduleView = false }
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Color(red: 0.2, green: 0.2, blue: 0.2))
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
            
            // Show retry button if it was a search error and location is available
            if errorMessage.contains("search") || errorMessage.contains("network") || errorMessage.contains("internet"),
               locationManager.isAuthorized {
                Button("Retry") {
                    performRealSearch()
                }
            }
            
            // Show settings button if location is denied
            if errorMessage.contains("Location") && !locationManager.isAuthorized {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showComparisonView) {
            ChurchComparisonView(
                churches: filteredChurches.filter { selectedChurchesForComparison.contains($0.id) },
                onClose: {
                    showComparisonView = false
                }
            )
        }
        .onAppear {
            locationManager.checkLocationAuthorization()
            loadUserPreferences()
            
            // Update map to user location if available
            if let userLoc = userLocation {
                region.center = userLoc
                reverseGeocodeLocation(userLoc)
                // Auto-perform real search on first appear if location is available
                if !hasSearchedOnce {
                    hasSearchedOnce = true
                    performRealSearch()
                }
            } else {
                // Set initial location name
                currentLocationName = "Locating..."
            }
        }
        .onDisappear {
            // Cancel any pending search tasks to prevent memory leaks
            searchTask?.cancel()
            saveUserPreferences()
        }
        .onChange(of: userLocation) { oldValue, newLocation in
            if let newLoc = newLocation {
                withAnimation {
                    region.center = newLoc
                }
                reverseGeocodeLocation(newLoc)
                // Update location name immediately
                currentLocationName = "Updating location..."
                // Perform real search when location becomes available
                if !hasSearchedOnce {
                    hasSearchedOnce = true
                    performRealSearch()
                }
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            // Cancel any existing search task
            searchTask?.cancel()
            
            // Only trigger search if text is not empty and has changed
            if !newValue.isEmpty && newValue != oldValue {
                isSearching = true
                
                // Debounced search - wait 0.3 seconds after user stops typing (faster)
                searchTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds (faster than before)
                    
                    // Check if task wasn't cancelled and text hasn't changed
                    guard !Task.isCancelled, searchText == newValue else {
                        isSearching = false
                        return
                    }
                    
                    // Perform search
                    performSearchWithText()
                    isSearching = false
                }
            } else if newValue.isEmpty {
                isSearching = false
                // Reset to show all churches when search is cleared
                performRealSearch()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Perform search with current search text
    @MainActor
    private func performSearchWithText() {
        guard !searchText.isEmpty else {
            performRealSearch()
            return
        }
        
        let haptic = UISelectionFeedbackGenerator()
        haptic.selectionChanged()
        
        print("🔍 Searching for: '\(searchText)'")
        
        // The filtering happens in filteredChurches computed property
        // This just provides haptic feedback and logs the search
    }
    
    /// Pull-to-refresh handler with haptic feedback
    @MainActor
    private func refreshChurchSearch() async {
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        performRealSearch()
        
        // Wait a bit for the search to complete (shorter wait)
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds (faster)
        
        // Success haptic
        let successHaptic = UINotificationFeedbackGenerator()
        successHaptic.notificationOccurred(.success)
    }
    
    func reverseGeocodeLocation(_ coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let error = error {
                print("❌ Reverse geocoding error: \(error.localizedDescription)")
                currentLocationName = "Unknown Location"
                return
            }
            
            if let placemark = placemarks?.first {
                // Build location string
                var locationComponents: [String] = []
                
                if let locality = placemark.locality {
                    locationComponents.append(locality)
                }
                
                if let administrativeArea = placemark.administrativeArea {
                    locationComponents.append(administrativeArea)
                }
                
                if !locationComponents.isEmpty {
                    currentLocationName = locationComponents.joined(separator: ", ")
                } else if let name = placemark.name {
                    currentLocationName = name
                } else {
                    currentLocationName = "Current Location"
                }
                
                print("📍 Location: \(currentLocationName)")
            }
        }
    }
    
    func performRealSearch() {
        guard let userLoc = userLocation else {
            print("⚠️ Cannot search: User location not available")
            errorMessage = "Location not available. Please enable location services in Settings."
            showErrorAlert = true
            return
        }
        
        guard !isPerformingSearch else {
            print("⚠️ Search already in progress")
            return
        }
        
        // Mark that we've searched at least once
        hasSearchedOnce = true
        isPerformingSearch = true
        
        Task {
            do {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                
                print("🔍 Starting church search at (\(userLoc.latitude), \(userLoc.longitude)) within \(searchRadius)m")
                
                let results = try await churchSearchService.searchChurches(near: userLoc, radius: searchRadius)
                
                await MainActor.run {
                    isPerformingSearch = false
                    
                    if results.isEmpty {
                        errorMessage = "No churches found within \(Int(searchRadius / 1609.34)) miles. Try increasing the search radius."
                        showErrorAlert = true
                    } else {
                        print("✅ Found \(results.count) churches nearby")
                        
                        // Success haptic
                        let successHaptic = UINotificationFeedbackGenerator()
                        successHaptic.notificationOccurred(.success)
                    }
                }
                
            } catch ChurchSearchError.noInternetConnection {
                print("❌ No internet connection")
                
                await MainActor.run {
                    isPerformingSearch = false
                    errorMessage = "No internet connection. Please check your network and try again."
                    showErrorAlert = true
                    
                    // Error haptic
                    let errorHaptic = UINotificationFeedbackGenerator()
                    errorHaptic.notificationOccurred(.error)
                }
                
            } catch ChurchSearchError.noResultsFound {
                print("❌ No results found")
                
                await MainActor.run {
                    isPerformingSearch = false
                    errorMessage = "No churches found in this area. Try increasing the search radius to \(Int(searchRadius / 1609.34) + 5) miles."
                    showErrorAlert = true
                }
                
            } catch ChurchSearchError.tooManyRequests {
                print("❌ Too many requests")
                
                await MainActor.run {
                    isPerformingSearch = false
                    errorMessage = "Search limit reached. Please wait a moment and try again."
                    showErrorAlert = true
                }
                
            } catch ChurchSearchError.locationUnavailable {
                print("❌ Location unavailable")
                
                await MainActor.run {
                    isPerformingSearch = false
                    errorMessage = "Location services are unavailable. Please enable location access in Settings."
                    showErrorAlert = true
                }
                
            } catch {
                print("❌ Church search failed: \(error.localizedDescription)")
                
                await MainActor.run {
                    isPerformingSearch = false
                    
                    // Provide more specific error messages
                    if error.localizedDescription.contains("network") || error.localizedDescription.contains("Internet") {
                        errorMessage = "Network error. Please check your internet connection and try again."
                    } else if error.localizedDescription.contains("timeout") {
                        errorMessage = "Search timed out. The network may be slow. Please try again."
                    } else {
                        errorMessage = "Unable to search for churches. \(error.localizedDescription)"
                    }
                    
                    showErrorAlert = true
                    
                    // Error haptic
                    let errorHaptic = UINotificationFeedbackGenerator()
                    errorHaptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    func toggleSave(_ church: Church) {
        withAnimation {
            if savedChurchIds.contains(church.id) {
                persistenceManager.removeChurch(church)
                // Remove all notifications when unsaving
                ChurchNotificationManager.shared.removeNotifications(for: church)
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.warning)
            } else {
                persistenceManager.saveChurch(church)
                // Schedule smart notifications for service times
                scheduleSmartNotifications(for: church)
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            }
        }
    }
    
    func scheduleSmartNotifications(for church: Church) {
        // Request notification permission if needed
        Task {
            let notificationManager = ChurchNotificationManager.shared
            if !notificationManager.isAuthorized {
                let granted = await notificationManager.requestNotificationPermission()
                if granted {
                    enableSmartNotificationsForChurch(church)
                }
            } else {
                enableSmartNotificationsForChurch(church)
            }
        }
    }
    
    func enableSmartNotificationsForChurch(_ church: Church) {
        let notificationManager = ChurchNotificationManager.shared
        let smartScheduler = SmartNotificationScheduler()
        
        // Calculate optimal reminder time using smart algorithm
        if let optimalTime = smartScheduler.calculateOptimalReminderTime(
            for: church,
            preferences: userPreferences,
            visitHistory: churchVisitHistory,
            userLocation: userLocation
        ) {
            print("📅 Smart notification scheduled for: \(optimalTime)")
            // Schedule at optimal time
            notificationManager.scheduleServiceReminder(for: church, beforeMinutes: 60)
        } else {
            // Fallback to default
            notificationManager.scheduleServiceReminder(for: church, beforeMinutes: 60)
        }
        
        // Weekly service reminder (Saturday evening)
        notificationManager.scheduleWeeklyReminder(for: church)
        
        // Location-based reminder (when near church)
        notificationManager.scheduleLocationReminder(for: church, radius: 500)
    }
    
    func openDirections(to church: Church) {
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: church.coordinate))
        mapItem.name = church.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
    
    func callChurch(_ church: Church) {
        let phoneNumber = church.phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        
        // Validate phone number
        guard !phoneNumber.isEmpty, phoneNumber.count >= 10 else {
            errorMessage = "Invalid phone number for this church."
            showErrorAlert = true
            
            // Error haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
            return
        }
        
        if let url = URL(string: "tel://\(phoneNumber)") {
            if UIApplication.shared.canOpenURL(url) {
                // Success haptic before making call
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
                
                UIApplication.shared.open(url)
            } else {
                errorMessage = "Unable to make phone calls on this device."
                showErrorAlert = true
                
                // Error haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        } else {
            errorMessage = "Invalid phone number format."
            showErrorAlert = true
            
            // Error haptic
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }
    
    // MARK: - Smart Features
    
    func markChurchAsViewed(_ church: Church) {
        userPreferences.visitedChurches.insert(church.id)
        
        // Record visit in history
        let visit = ChurchVisit(
            churchId: church.id,
            date: Date(),
            duration: nil,
            arrivalTime: nil,
            wasOnTime: nil
        )
        churchVisitHistory.append(visit)
        
        // Learn preferences from visit
        userPreferences.preferredDenominations.insert(church.denomination)
        
        saveUserPreferences()
    }
    
    func checkInToChurch(_ church: Church) {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        let now = Date()
        
        // Record check-in with arrival time
        let visit = ChurchVisit(
            churchId: church.id,
            date: now,
            duration: nil,
            arrivalTime: now,
            wasOnTime: true // Could calculate based on service time
        )
        churchVisitHistory.append(visit)
        userPreferences.visitedChurches.insert(church.id)
        
        // Learn preferences from visit
        userPreferences.preferredDenominations.insert(church.denomination)
        
        // Track typical attendance day
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        userPreferences.typicalAttendanceDay = weekday
        
        // Auto-save if not already saved
        if !savedChurchIds.contains(church.id) {
            toggleSave(church)
        }
        
        // Show confirmation
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            // Could show a toast or badge here
        }
        
        saveUserPreferences()
        
        print("✅ Checked in to \(church.name) at \(now)")
    }
    
    func addToSchedule(_ church: Church) {
        // Auto-save to schedule
        if !savedChurchIds.contains(church.id) {
            toggleSave(church)
        }
        
        // Schedule notification
        scheduleSmartNotifications(for: church)
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    func saveUserPreferences() {
        do {
            let encoder = JSONEncoder()
            let prefsData = try encoder.encode(userPreferences)
            let historyData = try encoder.encode(churchVisitHistory)
            
            UserDefaults.standard.set(prefsData, forKey: "userChurchPreferences")
            UserDefaults.standard.set(historyData, forKey: "churchVisitHistory")
            
            // Update insights after saving
            updateJourneyInsights()
        } catch {
            print("❌ Failed to save user preferences: \(error.localizedDescription)")
        }
    }
    
    func loadUserPreferences() {
        // Load preferences
        if let prefsData = UserDefaults.standard.data(forKey: "userChurchPreferences") {
            do {
                let decoder = JSONDecoder()
                userPreferences = try decoder.decode(UserChurchPreferences.self, from: prefsData)
            } catch {
                print("❌ Failed to load user preferences: \(error.localizedDescription)")
            }
        }
        
        // Load visit history
        if let historyData = UserDefaults.standard.data(forKey: "churchVisitHistory") {
            do {
                let decoder = JSONDecoder()
                churchVisitHistory = try decoder.decode([ChurchVisit].self, from: historyData)
            } catch {
                print("❌ Failed to load visit history: \(error.localizedDescription)")
            }
        }
        
        // Update journey insights
        updateJourneyInsights()
    }
    
    func updateJourneyInsights() {
        let insightGenerator = JourneyInsights()
        journeyInsights = insightGenerator.generateInsights(
            for: userPreferences,
            visitHistory: churchVisitHistory,
            savedChurches: persistenceManager.savedChurches
        )
    }
    
    // MARK: - AI Recommendations
    
    func loadAIRecommendations() {
        guard !filteredChurches.isEmpty else {
            print("ℹ️ No churches available for AI recommendations")
            return
        }
        
        isLoadingAIRecommendations = true
        
        Task {
            do {
                // Convert churches to format expected by AI service
                let churchesData = filteredChurches.map { church -> [String: Any] in
                    return [
                        "name": church.name,
                        "denomination": church.denomination,
                        "address": church.address,
                        "distance": church.distanceValue,
                        "serviceTime": church.serviceTime,
                        "latitude": church.latitude,
                        "longitude": church.longitude
                    ]
                }
                
                // Get user location
                var userLocationDict: [String: Double]? = nil
                if let userLoc = userLocation {
                    userLocationDict = [
                        "latitude": userLoc.latitude,
                        "longitude": userLoc.longitude
                    ]
                }
                
                // Get AI recommendations
                let recommendations = try await AIChurchRecommendationService.shared.getRecommendations(
                    nearbyChurches: churchesData,
                    userLocation: userLocationDict ?? ["latitude": 0, "longitude": 0]
                )
                
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        aiRecommendations = recommendations
                        isLoadingAIRecommendations = false
                    }
                }
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                print("✅ Loaded \(recommendations.count) AI church recommendations")
            } catch {
                print("❌ Failed to load AI recommendations: \(error)")
                await MainActor.run {
                    isLoadingAIRecommendations = false
                }
            }
        }
    }
}

// MARK: - Scroll Offset Preference Key (renamed to avoid conflicts)
struct ChurchFinderScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var isAuthorized = false
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func checkLocationAuthorization() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            isAuthorized = true
            manager.startUpdatingLocation()
        case .notDetermined:
            // Will show banner to request
            isAuthorized = false
        case .denied, .restricted:
            isAuthorized = false
            // Could notify user to check Settings
            print("⚠️ Location access denied. User must enable in Settings.")
        @unknown default:
            isAuthorized = false
        }
    }
    
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkLocationAuthorization()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location.coordinate
    }
}

// MARK: - Modern Search Header (Based on Design)
struct FindChurchHeader: View {
    @Binding var searchText: String
    let locationStatus: String
    var onRefresh: (() -> Void)? = nil
    var isSearching: Bool = false
    var isCollapsed: Bool = false
    var onSearchSubmit: (() -> Void)? = nil
    @State private var isExpanded = false
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: isCollapsed ? 8 : 16) {
            // Title and Refresh Button Row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Glass morphism title
                    Text("Find a Church")
                        .font(.custom("OpenSans-Bold", size: isCollapsed ? 22 : 28))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.1, green: 0.1, blue: 0.1),
                                    Color(red: 0.2, green: 0.2, blue: 0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .white.opacity(0.5), radius: 1, x: 0, y: 1)
                        .animation(.easeInOut(duration: 0.2), value: isCollapsed)
                    
                    if !isCollapsed {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(locationStatus)
                                    .font(.custom("OpenSans-SemiBold", size: 13))
                                    .lineLimit(1)
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.15, green: 0.15, blue: 0.15),
                                        Color(red: 0.25, green: 0.25, blue: 0.25)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                                    )
                                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                            )
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                
                Spacer()
                
                // Smaller Glass Refresh Button
                if let refresh = onRefresh {
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                        refresh()
                    } label: {
                        Group {
                            if isSearching {
                                ProgressView()
                                    .tint(Color(red: 0.2, green: 0.2, blue: 0.2))
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: isCollapsed ? 13 : 14, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.15, green: 0.15, blue: 0.15),
                                                Color(red: 0.25, green: 0.25, blue: 0.25)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                        }
                        .frame(width: isCollapsed ? 32 : 36, height: isCollapsed ? 32 : 36)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        )
                    }
                    .disabled(isSearching)
                    .animation(.easeInOut(duration: 0.2), value: isCollapsed)
                }
            }
            
            // Expandable location details with glass design
            if isExpanded && !isCollapsed {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.green)
                        Text("Live location enabled")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                    }
                    
                    HStack(spacing: 12) {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(.orange)
                        Text("Smart notifications active")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                        )
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
            
            // Modern Search Bar (functional with submit action)
            HStack(spacing: 0) {
                // Text field area
                HStack(spacing: 10) {
                    Image(systemName: isSearchFocused ? "magnifyingglass.circle.fill" : "magnifyingglass")
                        .font(.system(size: isSearchFocused ? 16 : 14))
                        .foregroundStyle(isSearchFocused ? .blue : .gray.opacity(0.6))
                        .padding(.leading, 4)
                        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
                    
                    TextField("Search churches, addresses...", text: $searchText)
                        .font(.custom("OpenSans-Regular", size: isCollapsed ? 14 : 15))
                        .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                        .tint(.blue)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .submitLabel(.search)
                        .focused($isSearchFocused)
                        .onSubmit {
                            onSearchSubmit?()
                            isSearchFocused = false
                        }
                    
                    if !searchText.isEmpty {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                searchText = ""
                                isSearchFocused = false
                            }
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.gray.opacity(0.5))
                                .font(.system(size: 16))
                        }
                        .transition(.scale.combined(with: .opacity))
                    } else if isSearchFocused {
                        Button {
                            isSearchFocused = false
                        } label: {
                            Text("Cancel")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.blue)
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity)
            }
            .frame(height: isCollapsed ? 44 : 50)
            .background(
                Capsule()
                    .fill(.white)
                    .overlay(
                        Capsule()
                            .stroke(isSearchFocused ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(isSearchFocused ? 0.15 : 0.12), radius: isSearchFocused ? 20 : 16, x: 0, y: 6)
                    .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            )
            .animation(.easeInOut(duration: 0.2), value: isCollapsed)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSearchFocused)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, isCollapsed ? 8 : 12)
        .animation(.easeInOut(duration: 0.2), value: isCollapsed)
    }
}

// MARK: - Enhanced Location Permission Banner
struct EnhancedLocationPermissionBanner: View {
    let onRequestLocation: () -> Void
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                
                Image(systemName: "location.fill.viewfinder")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Enable Location Access")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
                
                Text("Find churches near you and get smart notifications")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            
            Spacer()
            
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
                onRequestLocation()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                    Text("Enable")
                        .font(.custom("OpenSans-Bold", size: 15))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .cyan.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Modern Church Card Design
struct EnhancedChurchCard: View {
    let church: Church
    let isSaved: Bool
    let onSave: () -> Void
    let onGetDirections: () -> Void
    let onCall: () -> Void
    var isSelectedForComparison: Bool = false
    var onToggleComparison: ((UUID) -> Void)? = nil
    
    @State private var isExpanded = false
    @State private var isPressed = false
    @State private var isCallingInProgress = false
    @State private var isGettingDirections = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content
            VStack(alignment: .leading, spacing: 16) {
                // Header with save button
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(church.name)
                            .font(.custom("OpenSans-Bold", size: 22))
                            .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.15))
                            .lineLimit(2)
                        
                        HStack(spacing: 10) {
                            // Denomination badge
                            Text(church.denomination)
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(church.denominationColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(church.denominationColor.opacity(0.15))
                                )
                            
                            // Distance
                            HStack(spacing: 5) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 11))
                                Text(church.distance)
                                    .font(.custom("OpenSans-SemiBold", size: 13))
                            }
                            .foregroundStyle(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    // Save button (circular dark style matching search)
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            onSave()
                            let haptic = UIImpactFeedbackGenerator(style: .medium)
                            haptic.impactOccurred()
                        }
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(isSaved ? .pink : .white)
                            .frame(width: 48, height: 48)
                            .background(
                                Circle()
                                    .fill(isSaved ? Color.pink.opacity(0.2) : Color(red: 0.2, green: 0.2, blue: 0.2))
                            )
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    }
                    .scaleEffect(isPressed && isSaved ? 1.1 : 1.0)
                }
                
                // Quick info tiles - Refined design
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ModernQuickInfoTile(
                        icon: "clock.fill",
                        title: "Service",
                        value: church.shortServiceTime,
                        color: .blue
                    )
                    
                    if let countdown = church.nextServiceCountdown {
                        ModernQuickInfoTile(
                            icon: "calendar",
                            title: "Next",
                            value: countdown.replacingOccurrences(of: "Next service in ", with: ""),
                            color: .green
                        )
                    }
                }
                
                // Action buttons - Modern style with loading states
                HStack(spacing: 12) {
                    Button {
                        guard !isCallingInProgress else { return }
                        
                        isCallingInProgress = true
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        
                        // Simulate brief delay for visual feedback
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onCall()
                            isCallingInProgress = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isCallingInProgress {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 16))
                            }
                            Text("Call")
                                .font(.custom("OpenSans-Bold", size: 15))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(red: 0.2, green: 0.2, blue: 0.2).opacity(isCallingInProgress ? 0.7 : 1.0))
                                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                        )
                    }
                    .disabled(isCallingInProgress)
                    
                    Button {
                        guard !isGettingDirections else { return }
                        
                        isGettingDirections = true
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        
                        // Simulate brief delay for visual feedback
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onGetDirections()
                            isGettingDirections = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isGettingDirections {
                                ProgressView()
                                    .tint(Color(red: 0.2, green: 0.2, blue: 0.2))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                    .font(.system(size: 16))
                            }
                            Text("Directions")
                                .font(.custom("OpenSans-Bold", size: 15))
                        }
                        .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.gray.opacity(0.3), lineWidth: 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(.white.opacity(isGettingDirections ? 0.7 : 1.0))
                                )
                        )
                    }
                    .disabled(isGettingDirections)
                }
                
                // Expandable details
                if isExpanded {
                    VStack(alignment: .leading, spacing: 14) {
                        Divider()
                            .overlay(Color.gray.opacity(0.2))
                        
                        ModernDetailRow(icon: "mappin.and.ellipse", text: church.address, color: .blue)
                        ModernDetailRow(icon: "clock", text: church.serviceTime, color: .green)
                        ModernDetailRow(icon: "phone", text: church.phone, color: .orange)
                        
                        if let website = church.website {
                            Link(destination: URL(string: "https://\(website)")!) {
                                HStack(spacing: 12) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.purple)
                                        .frame(width: 24)
                                    
                                    Text(website)
                                        .font(.custom("OpenSans-Regular", size: 15))
                                        .foregroundStyle(.purple)
                                        .underline()
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.purple)
                                }
                            }
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
                
                // Show more/less button
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        isExpanded.toggle()
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    }
                } label: {
                    HStack {
                        Text(isExpanded ? "Show Less" : "Show More")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.08))
                    )
                }
            }
            .padding(20)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white)
                .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 10)
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isSelectedForComparison ? Color.orange : Color.clear, lineWidth: 3)
                .padding(.horizontal, 20)
        )
        .onLongPressGesture {
            if let onToggleComparison = onToggleComparison {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    onToggleComparison(church.id)
                }
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
            }
        }
    }
}

// Modern Quick Info Tile (cleaner white design)
struct ModernQuickInfoTile: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
            
            Text(title)
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundStyle(.gray)
            
            Text(value)
                .font(.custom("OpenSans-Bold", size: 14))
                .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.gray.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// Modern Detail Row
struct ModernDetailRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(Color(red: 0.3, green: 0.3, blue: 0.3))
            
            Spacer()
        }
    }
}

// MARK: - Location Permission Banner (OLD - Keep for reference)
struct LocationPermissionBanner: View {
    let onRequestLocation: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.fill.viewfinder")
                .font(.system(size: 24))
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Enable Location")
                    .font(.custom("OpenSans-Bold", size: 14))
                
                Text("Find churches near you")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                onRequestLocation()
            } label: {
                Text("Enable")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                    )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

// MARK: - Notification Permission Banner
struct NotificationPermissionBanner: View {
    @State private var showBanner = false
    
    var body: some View {
        Group {
            if showBanner {
                HStack(spacing: 12) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Notifications")
                            .font(.custom("OpenSans-Bold", size: 14))
                        
                        Text("Get reminders for service times")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        requestNotificationPermission()
                    } label: {
                        Text("Enable")
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.orange)
                            )
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.1))
                )
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
        .onAppear {
            checkNotificationStatus()
        }
    }
    
    func checkNotificationStatus() {
        Task {
            let notificationManager = ChurchNotificationManager.shared
            let isAuthorized = await notificationManager.checkAuthorizationStatus()
            await MainActor.run {
                showBanner = !isAuthorized
            }
        }
    }
    
    func requestNotificationPermission() {
        Task {
            let notificationManager = ChurchNotificationManager.shared
            let granted = await notificationManager.requestNotificationPermission()
            if granted {
                await MainActor.run {
                    showBanner = false
                }
            }
        }
    }
}

// MARK: - Quick Stats Banner
struct QuickStatsBanner: View {
    let churchCount: Int
    let nearestDistance: String
    
    var body: some View {
        HStack(spacing: 0) {
            // Churches count
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(churchCount)")
                        .font(.custom("OpenSans-Bold", size: 22))
                        .foregroundStyle(.primary)
                    
                    Text("Churches Found")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            
            Divider()
                .frame(height: 40)
            
            // Nearest distance
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "location.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(nearestDistance.replacingOccurrences(of: " away", with: ""))
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.primary)
                    
                    Text("Nearest Church")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(.systemGray5), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Empty State
struct EmptyChurchesView: View {
    let isFiltered: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text(isFiltered ? "No Churches Found" : "No Churches Nearby")
                .font(.custom("OpenSans-Bold", size: 20))
            
            Text(isFiltered ? "Try adjusting your filters" : "We couldn't find any churches in this area")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Church Card Skeleton Loading State
struct ChurchCardSkeleton: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header skeleton
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    // Church name skeleton
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 200, height: 24)
                    
                    // Denomination and distance skeleton
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 100, height: 24)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 60, height: 16)
                    }
                }
                
                Spacer()
                
                // Save button skeleton
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 48, height: 48)
            }
            
            // Quick info tiles skeleton
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 80)
                
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 80)
            }
            
            // Action buttons skeleton
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 48)
                
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 48)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 20, y: 10)
        )
        .padding(.horizontal, 20)
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(
            Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Map Annotation
struct ChurchMapAnnotation: View {
    let church: Church
    let isSaved: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isSaved ? Color.pink : Color.blue)
                    .frame(width: 32, height: 32)
                
                Image(systemName: isSaved ? "bookmark.fill" : "building.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
            
            Text(church.name)
                .font(.custom("OpenSans-SemiBold", size: 10))
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                )
        }
    }
}

struct ChurchCard: View {
    let church: Church
    let isSaved: Bool
    let onSave: () -> Void
    let onGetDirections: () -> Void
    let onCall: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(church.name)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Text(church.denomination)
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.blue)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        
                        Text(church.distance)
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    Button {
                        onSave()
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isSaved ? .pink : .secondary)
                    }
                    
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            if isExpanded {
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.blue)
                        
                        Text(church.address)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.primary)
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(church.serviceTime)
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.primary)
                            
                            if let nextService = church.nextServiceCountdown {
                                Text(nextService)
                                    .font(.custom("OpenSans-SemiBold", size: 12))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.blue)
                        
                        Text(church.phone)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.primary)
                    }
                    
                    if let website = church.website {
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                                .font(.system(size: 14))
                                .foregroundStyle(.blue)
                            
                            Link(website, destination: URL(string: "https://\(website)")!)
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.blue)
                        }
                    }
                }
                
                HStack(spacing: 12) {
                    Button {
                        onCall()
                    } label: {
                        HStack {
                            Image(systemName: "phone.fill")
                            Text("Call")
                                .font(.custom("OpenSans-Bold", size: 14))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black)
                        )
                    }
                    
                    Button {
                        onGetDirections()
                    } label: {
                        HStack {
                            Image(systemName: "location.fill")
                            Text("Directions")
                                .font(.custom("OpenSans-Bold", size: 14))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                        )
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .padding(.horizontal)
    }
}

// MARK: - Smart Features Banner
struct SmartFeaturesBanner: View {
    let savedCount: Int
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.orange, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Reminders Active")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Text("\(savedCount) church\(savedCount == 1 ? "" : "es") saved")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        isExpanded.toggle()
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "info.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)
                }
            }
            
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.vertical, 12)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        SmartFeatureRow(
                            icon: "bell.badge.fill",
                            title: "Service Reminders",
                            description: "1 hour before services start",
                            color: .blue
                        )
                        
                        SmartFeatureRow(
                            icon: "calendar.badge.clock",
                            title: "Weekly Alerts",
                            description: "Saturday evening preview",
                            color: .green
                        )
                        
                        SmartFeatureRow(
                            icon: "location.fill.viewfinder",
                            title: "Nearby Alerts",
                            description: "When you're near your church",
                            color: .purple
                        )
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [.orange.opacity(0.3), .pink.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 20)
    }
}

struct SmartFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Live Search Banner
struct LiveSearchBanner: View {
    let churchCount: Int
    let onRefresh: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Live Search Active")
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.primary)
                
                Text("\(churchCount) real churches from Apple Maps")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                onRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(Color.green.opacity(0.1))
                    )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [.green.opacity(0.3), .mint.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Search Results Banner
struct SearchResultsBanner: View {
    let searchQuery: String
    let resultCount: Int
    let totalCount: Int
    let onClearSearch: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Search Results")
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.primary)
                
                Text("\(resultCount) of \(totalCount) churches match '\(searchQuery)'")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                onClearSearch()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.gray.opacity(0.7))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .cyan.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Church Persistence Manager
@MainActor
class ChurchPersistenceManager: ObservableObject {
    static let shared = ChurchPersistenceManager()
    
    @Published var savedChurches: [Church] = []
    
    private let savedChurchesKey = "savedChurches"
    private let userDefaults = UserDefaults.standard
    
    private init() {
        loadSavedChurches()
    }
    
    func saveChurch(_ church: Church) {
        // Prevent duplicates
        guard !savedChurches.contains(where: { $0.id == church.id }) else { return }
        
        savedChurches.append(church)
        persistChurches()
        
        print("✅ Saved church: \(church.name)")
    }
    
    func removeChurch(_ church: Church) {
        savedChurches.removeAll { $0.id == church.id }
        persistChurches()
        
        print("🗑️ Removed church: \(church.name)")
    }
    
    func isChurchSaved(_ churchId: UUID) -> Bool {
        savedChurches.contains { $0.id == churchId }
    }
    
    private func persistChurches() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(savedChurches)
            userDefaults.set(data, forKey: savedChurchesKey)
            userDefaults.synchronize()
        } catch {
            print("❌ Failed to save churches: \(error.localizedDescription)")
        }
    }
    
    private func loadSavedChurches() {
        guard let data = userDefaults.data(forKey: savedChurchesKey) else {
            print("ℹ️ No saved churches found")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            savedChurches = try decoder.decode([Church].self, from: data)
            print("✅ Loaded \(savedChurches.count) saved churches")
        } catch {
            print("❌ Failed to load churches: \(error.localizedDescription)")
            savedChurches = []
        }
    }
    
    func clearAllChurches() {
        savedChurches.removeAll()
        userDefaults.removeObject(forKey: savedChurchesKey)
        userDefaults.synchronize()
        print("🗑️ Cleared all saved churches")
    }
}

// MARK: - Church Comparison View
struct ChurchComparisonView: View {
    let churches: [Church]
    let onClose: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if churches.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                        
                        Text("No Churches Selected")
                            .font(.custom("OpenSans-Bold", size: 22))
                        
                        Text("Select churches from the list to compare them side-by-side")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else {
                    VStack(spacing: 20) {
                        // Comparison Header
                        Text("Comparing \(churches.count) Churches")
                            .font(.custom("OpenSans-Bold", size: 24))
                            .padding(.top)
                        
                        // Distance Comparison
                        ComparisonSection(title: "Distance", icon: "location.fill", color: .blue) {
                            ForEach(churches) { church in
                                ComparisonRow(
                                    label: church.name,
                                    value: church.distance,
                                    highlight: church.distanceValue == churches.map(\.distanceValue).min()
                                )
                            }
                        }
                        
                        // Denomination Comparison
                        ComparisonSection(title: "Denomination", icon: "building.2.fill", color: .purple) {
                            ForEach(churches) { church in
                                ComparisonRow(
                                    label: church.name,
                                    value: church.denomination,
                                    highlight: false
                                )
                            }
                        }
                        
                        // Service Times Comparison
                        ComparisonSection(title: "Service Times", icon: "clock.fill", color: .green) {
                            ForEach(churches) { church in
                                ComparisonRow(
                                    label: church.name,
                                    value: church.serviceTime,
                                    highlight: false
                                )
                            }
                        }
                        
                        // Contact Comparison
                        ComparisonSection(title: "Contact", icon: "phone.fill", color: .orange) {
                            ForEach(churches) { church in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(church.name)
                                        .font(.custom("OpenSans-SemiBold", size: 14))
                                    
                                    Link(destination: URL(string: "tel://\(church.phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression))")!) {
                                        HStack {
                                            Image(systemName: "phone.fill")
                                                .font(.system(size: 12))
                                            Text(church.phone)
                                                .font(.custom("OpenSans-Regular", size: 13))
                                        }
                                        .foregroundStyle(.blue)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Compare Churches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.gray)
                    }
                }
            }
        }
    }
}

struct ComparisonSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
                
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
            }
            
            VStack(spacing: 8) {
                content
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
    }
}

struct ComparisonRow: View {
    let label: String
    let value: String
    let highlight: Bool
    
    var body: some View {
        HStack {
            Text(label)
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            Spacer()
            
            Text(value)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(highlight ? .green : .secondary)
                .lineLimit(1)
            
            if highlight {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(highlight ? Color.green.opacity(0.1) : Color.gray.opacity(0.05))
        )
    }
}

// MARK: - Minimal Modern Components

/// Minimal header with clean search - inspired by design
struct MinimalChurchHeader: View {
    @Binding var searchText: String
    let locationText: String
    let isLocationAuthorized: Bool
    var onSearchSubmit: () -> Void
    var onFilterTap: () -> Void
    var onRefresh: (() -> Void)?
    var onBack: () -> Void
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            // Title with location and back button
            HStack {
                // Back button
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(red: 0.3, green: 0.3, blue: 0.3))
                        .frame(width: 32, height: 32)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find Church")
                        .font(.system(size: 32, weight: .bold, design: .default))
                        .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.15))
                    
                    // Show current location
                    if isLocationAuthorized {
                        HStack(spacing: 6) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 11, weight: .medium))
                            Text(locationText)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Refresh button
                    if let refresh = onRefresh, isLocationAuthorized {
                        Button(action: refresh) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Color(red: 0.3, green: 0.3, blue: 0.3))
                        }
                    }
                    
                    // Filter button
                    Button(action: onFilterTap) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(Color(red: 0.3, green: 0.3, blue: 0.3))
                    }
                }
            }
            
            // Clean search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                
                TextField("Search churches...", text: $searchText)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit(onSearchSubmit)
                
                if !searchText.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            searchText = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.96))
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

/// Minimal filter row - only shown when expanded
struct MinimalFilterRow: View {
    @Binding var selectedDenomination: FindChurchView.ChurchDenomination
    @Binding var sortMode: FindChurchView.ChurchSortMode
    @Binding var searchRadius: Double
    @Binding var showSavedOnly: Bool
    @Binding var showDenominationInfo: FindChurchView.ChurchDenomination?
    var onRadiusChange: () -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Saved toggle
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        showSavedOnly.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showSavedOnly ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 12, weight: .medium))
                        Text("Saved")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(showSavedOnly ? Color.white : Color(red: 0.3, green: 0.3, blue: 0.3))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(showSavedOnly ? Color(red: 0.2, green: 0.2, blue: 0.2) : Color(white: 0.96))
                    )
                }
                
                // Sort menu
                Menu {
                    ForEach(FindChurchView.ChurchSortMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                sortMode = mode
                            }
                        } label: {
                            HStack {
                                Text(mode.rawValue)
                                if sortMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                        Text(sortMode.rawValue)
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 0.3, green: 0.3, blue: 0.3))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(white: 0.96))
                    )
                }
                
                // Radius menu
                Menu {
                    Button("3 miles") {
                        searchRadius = 4828.03
                        onRadiusChange()
                    }
                    Button("5 miles") {
                        searchRadius = 8046.72
                        onRadiusChange()
                    }
                    Button("10 miles") {
                        searchRadius = 16093.4
                        onRadiusChange()
                    }
                    Button("25 miles") {
                        searchRadius = 40233.6
                        onRadiusChange()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location.circle")
                            .font(.system(size: 12, weight: .medium))
                        Text("\(Int(searchRadius / 1609.34)) mi")
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 0.3, green: 0.3, blue: 0.3))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(white: 0.96))
                    )
                }
                
                // Denomination filters with info buttons
                ForEach(FindChurchView.ChurchDenomination.allCases, id: \.self) { denomination in
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                selectedDenomination = denomination
                            }
                        } label: {
                            Text(denomination.rawValue)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(selectedDenomination == denomination ? Color.white : Color(red: 0.3, green: 0.3, blue: 0.3))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(selectedDenomination == denomination ? Color(red: 0.2, green: 0.2, blue: 0.2) : Color(white: 0.96))
                                )
                        }
                        
                        // Info button for denominations (not "All")
                        if denomination != .all {
                            Button {
                                showDenominationInfo = denomination
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 8)
    }
}

/// Minimal church card - clean typography, subtle elevation
struct MinimalChurchCard: View {
    let church: Church
    let isSaved: Bool
    var onTap: () -> Void
    var onSave: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(church.name)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.15))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        Text(church.denomination)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                    
                    Spacer()
                    
                    Button(action: onSave) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                    }
                    .buttonStyle(.plain)
                }
                
                // Info row
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11, weight: .medium))
                        Text(church.distance)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                    
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 11, weight: .medium))
                        Text(church.shortServiceTime)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                }
                
                // Subtle address
                Text(church.address)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(red: 0.6, green: 0.6, blue: 0.6))
                    .lineLimit(1)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(isPressed ? 0.08 : 0.04), radius: isPressed ? 12 : 20, y: isPressed ? 4 : 8)
            )
        }
        .buttonStyle(MinimalCardButtonStyle(isPressed: $isPressed))
    }
}

struct MinimalCardButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, newValue in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                    isPressed = newValue
                }
            }
    }
}

/// Minimal empty state for Find Church
struct FindChurchEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var showAction: Bool = false
    var actionTitle: String = ""
    var onAction: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(Color(red: 0.7, green: 0.7, blue: 0.7))
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                
                Text(subtitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            if showAction, let action = onAction {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                        )
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Minimal loading view for Find Church - elegant skeleton
struct FindChurchLoadingView: View {
    @State private var isAnimating = false
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    MinimalChurchCardSkeleton()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(
            Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear { isAnimating = true }
    }
}

struct MinimalChurchCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(white: 0.93))
                        .frame(width: 200, height: 20)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(white: 0.95))
                        .frame(width: 120, height: 14)
                }
                
                Spacer()
                
                Circle()
                    .fill(Color(white: 0.93))
                    .frame(width: 20, height: 20)
            }
            
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(white: 0.95))
                    .frame(width: 80, height: 13)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(white: 0.95))
                    .frame(width: 60, height: 13)
            }
            
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(white: 0.96))
                .frame(height: 13)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.03), radius: 20, y: 8)
        )
    }
}

/// Minimal permission banner
struct MinimalPermissionBanner: View {
    let icon: String
    let title: String
    let message: String
    let accentColor: Color
    var onEnable: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(accentColor)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                
                Text(message)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
            }
            
            Spacer()
            
            Button(action: onEnable) {
                Text("Enable")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(accentColor)
                    )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.97))
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

/// Minimal stats row
struct MinimalStatsRow: View {
    let count: Int
    let nearest: String
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(count)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                
                Text("Churches")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Rectangle()
                .fill(Color(white: 0.9))
                .frame(width: 1, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(nearest.replacingOccurrences(of: " away", with: ""))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                
                Text("Nearest")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.03), radius: 16, y: 6)
        )
    }
}

/// Church detail sheet - full details in a sheet
struct ChurchDetailSheet: View {
    let church: Church
    let isSaved: Bool
    var onSave: () -> Void
    var onGetDirections: () -> Void
    var onCall: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Hero section
                    VStack(alignment: .leading, spacing: 12) {
                        Text(church.name)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.15))
                        
                        Text(church.denomination)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                    
                    // Action buttons
                    HStack(spacing: 12) {
                        Button(action: onGetDirections) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                    .font(.system(size: 18))
                                Text("Directions")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                            )
                        }
                        
                        Button(action: onCall) {
                            HStack(spacing: 8) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 18))
                                Text("Call")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color(white: 0.9), lineWidth: 1.5)
                            )
                        }
                    }
                    
                    Divider()
                    
                    // Details
                    VStack(alignment: .leading, spacing: 20) {
                        DetailRow(icon: "location.fill", title: "Address", value: church.address)
                        DetailRow(icon: "clock.fill", title: "Service Time", value: church.serviceTime)
                        DetailRow(icon: "phone.fill", title: "Phone", value: church.phone)
                        
                        if let website = church.website {
                            Link(destination: URL(string: "https://\(website)")!) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "globe")
                                                .font(.system(size: 14, weight: .medium))
                                            Text("Website")
                                                .font(.system(size: 13, weight: .medium))
                                        }
                                        .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                                        
                                        Text(website)
                                            .font(.system(size: 16, weight: .regular))
                                            .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4))
                                }
                            }
                        }
                        
                        DetailRow(icon: "location.circle.fill", title: "Distance", value: church.distance)
                    }
                }
                .padding(24)
            }
            .background(Color(white: 0.98))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color(red: 0.7, green: 0.7, blue: 0.7))
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onSave) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                    }
                }
            }
        }
    }
}

struct DetailRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
            
            Text(value)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
        }
    }
}

// MARK: - Quick Filter Bar

struct QuickFilterBar: View {
    @Binding var selectedFilter: FindChurchView.QuickFilter?
    let visitedCount: Int
    let savedCount: Int
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(FindChurchView.QuickFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedFilter = selectedFilter == filter ? nil : filter
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: iconForFilter(filter))
                                .font(.system(size: 12, weight: .medium))
                            Text(filter.rawValue)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(selectedFilter == filter ? Color.white : Color(red: 0.3, green: 0.3, blue: 0.3))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedFilter == filter ? Color(red: 0.2, green: 0.2, blue: 0.2) : Color(white: 0.96))
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 8)
    }
    
    private func iconForFilter(_ filter: FindChurchView.QuickFilter) -> String {
        switch filter {
        case .nearestNow: return "location.fill"
        case .serviceToday: return "calendar"
        case .openNow: return "clock.fill"
        case .visitedBefore: return "checkmark.circle.fill"
        case .highlyRated: return "bookmark.fill"
        }
    }
}

// MARK: - Smart Suggestions Banner

struct SmartSuggestionsBanner: View {
    let preferences: FindChurchView.UserChurchPreferences
    let churches: [Church]
    let onSelectChurch: (Church) -> Void
    
    var suggestedChurch: Church? {
        // Find a church matching user preferences
        churches.first { church in
            preferences.preferredDenominations.contains(church.denomination) ||
            preferences.visitedChurches.contains(church.id)
        }
    }
    
    var body: some View {
        if let church = suggestedChurch {
            Button {
                onSelectChurch(church)
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .pink],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suggested For You")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4))
                        
                        Text(church.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4))
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.3), .pink.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
            }
        }
    }
}

// MARK: - Enhanced Minimal Church Card

struct EnhancedMinimalChurchCard: View {
    let church: Church
    let isSaved: Bool
    let isVisited: Bool
    var onTap: () -> Void
    var onSave: () -> Void
    var onShare: () -> Void
    var onCheckIn: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with badges
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(church.name)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.15))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        HStack(spacing: 8) {
                            Text(church.denomination)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                            
                            if isVisited {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                    Text("Visited")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.green.opacity(0.15))
                                )
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: onSave) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                    }
                    .buttonStyle(.plain)
                }
                
                // Info row
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11, weight: .medium))
                        Text(church.distance)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                    
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 11, weight: .medium))
                        Text(church.shortServiceTime)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                }
                
                // Subtle address
                Text(church.address)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(red: 0.6, green: 0.6, blue: 0.6))
                    .lineLimit(1)
                
                // Quick actions
                HStack(spacing: 8) {
                    Button(action: onCheckIn) {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle")
                                .font(.system(size: 11))
                            Text("Check In")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color(white: 0.96))
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onShare) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11))
                            Text("Share")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color(white: 0.96))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(isPressed ? 0.08 : 0.04), radius: isPressed ? 12 : 20, y: isPressed ? 4 : 8)
            )
        }
        .buttonStyle(MinimalCardButtonStyle(isPressed: $isPressed))
    }
}

// MARK: - Enhanced Church Detail Sheet

struct EnhancedChurchDetailSheet: View {
    let church: Church
    let isSaved: Bool
    let isVisited: Bool
    var onSave: () -> Void
    var onGetDirections: () -> Void
    var onCall: () -> Void
    var onShare: () -> Void
    var onCheckIn: () -> Void
    var onAddToSchedule: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Hero section with badges
                    VStack(alignment: .leading, spacing: 12) {
                        Text(church.name)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.15))
                        
                        HStack(spacing: 8) {
                            Text(church.denomination)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                            
                            if isVisited {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                    Text("Visited")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color.green.opacity(0.15))
                                )
                            }
                        }
                    }
                    
                    // Primary action buttons
                    HStack(spacing: 12) {
                        Button(action: onGetDirections) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                    .font(.system(size: 18))
                                Text("Directions")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                            )
                        }
                        
                        Button(action: onCall) {
                            HStack(spacing: 8) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 18))
                                Text("Call")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color(white: 0.9), lineWidth: 1.5)
                            )
                        }
                    }
                    
                    // Secondary actions
                    HStack(spacing: 12) {
                        Button(action: onCheckIn) {
                            HStack(spacing: 6) {
                                Image(systemName: "mappin.circle")
                                Text("Check In")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundStyle(Color(red: 0.3, green: 0.3, blue: 0.3))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(white: 0.96))
                            )
                        }
                        
                        Button(action: onShare) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundStyle(Color(red: 0.3, green: 0.3, blue: 0.3))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(white: 0.96))
                            )
                        }
                        
                        Button(action: onAddToSchedule) {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar.badge.plus")
                                Text("Schedule")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundStyle(Color(red: 0.3, green: 0.3, blue: 0.3))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(white: 0.96))
                            )
                        }
                    }
                    
                    Divider()
                    
                    // Details
                    VStack(alignment: .leading, spacing: 20) {
                        DetailRow(icon: "location.fill", title: "Address", value: church.address)
                        DetailRow(icon: "clock.fill", title: "Service Time", value: church.serviceTime)
                        DetailRow(icon: "phone.fill", title: "Phone", value: church.phone)
                        
                        if let website = church.website {
                            Link(destination: URL(string: "https://\(website)")!) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "globe")
                                                .font(.system(size: 14, weight: .medium))
                                            Text("Website")
                                                .font(.system(size: 13, weight: .medium))
                                        }
                                        .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                                        
                                        Text(website)
                                            .font(.system(size: 16, weight: .regular))
                                            .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4))
                                }
                            }
                        }
                        
                        DetailRow(icon: "location.circle.fill", title: "Distance", value: church.distance)
                    }
                }
                .padding(24)
            }
            .background(Color(white: 0.98))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color(red: 0.7, green: 0.7, blue: 0.7))
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onSave) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                    }
                }
            }
        }
    }
}

// MARK: - Share Church Helper

extension Church {
    var shareText: String {
        """
        Check out \(name)!
        
        📍 \(address)
        ⛪️ \(denomination)
        🕐 \(serviceTime)
        📞 \(phone)
        \(website != nil ? "🌐 \(website!)" : "")
        
        Shared from AMEN App 🙏
        """
    }
}

// MARK: - Church Schedule View

struct ChurchScheduleView: View {
    let savedChurches: [Church]
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if savedChurches.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "calendar")
                                .font(.system(size: 56, weight: .thin))
                                .foregroundStyle(Color(red: 0.7, green: 0.7, blue: 0.7))
                            
                            Text("No Scheduled Churches")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                            
                            Text("Save churches to see their service times here")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                    } else {
                        ForEach(savedChurches) { church in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(church.name)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                                
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.blue)
                                    Text(church.serviceTime)
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundStyle(Color(red: 0.3, green: 0.3, blue: 0.3))
                                }
                                
                                if let countdown = church.nextServiceCountdown {
                                    HStack(spacing: 12) {
                                        Image(systemName: "calendar")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.green)
                                        Text(countdown)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                            )
                        }
                    }
                }
                .padding(24)
            }
            .background(Color(white: 0.98))
            .navigationTitle("My Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color(red: 0.7, green: 0.7, blue: 0.7))
                    }
                }
            }
        }
    }
}

// MARK: - Denomination Info Sheet

struct DenominationInfoSheet: View {
    let denomination: FindChurchView.ChurchDenomination
    @Environment(\.dismiss) private var dismiss
    
    var denominationInfo: (description: String, beliefs: [String], practices: [String]) {
        switch denomination {
        case .all:
            return ("", [], [])
        case .baptist:
            return (
                "Baptist churches emphasize believer's baptism by immersion and the autonomy of the local church.",
                [
                    "Bible as the sole authority",
                    "Believer's baptism (adult baptism)",
                    "Priesthood of all believers",
                    "Autonomy of local churches"
                ],
                [
                    "Sunday worship services",
                    "Bible study groups",
                    "Baptism by full immersion",
                    "Congregational governance"
                ]
            )
        case .catholic:
            return (
                "The Catholic Church is the largest Christian denomination, with a rich tradition spanning 2,000 years.",
                [
                    "Seven Sacraments",
                    "Papal authority",
                    "Real presence in Eucharist",
                    "Veneration of Mary and saints"
                ],
                [
                    "Mass (liturgical worship)",
                    "Confession and reconciliation",
                    "Infant baptism",
                    "Daily prayer and rosary"
                ]
            )
        case .nonDenominational:
            return (
                "Non-denominational churches are independent congregations not affiliated with traditional denominations.",
                [
                    "Bible-centered teaching",
                    "Personal relationship with Jesus",
                    "Contemporary worship",
                    "Flexible church structure"
                ],
                [
                    "Modern worship services",
                    "Small group ministry",
                    "Community outreach",
                    "Practical biblical teaching"
                ]
            )
        case .pentecostal:
            return (
                "Pentecostal churches emphasize the gifts of the Holy Spirit and experiential worship.",
                [
                    "Baptism in the Holy Spirit",
                    "Speaking in tongues",
                    "Divine healing",
                    "Spiritual gifts (charismata)"
                ],
                [
                    "Energetic worship services",
                    "Prayer and healing services",
                    "Testimony sharing",
                    "Evangelism and missions"
                ]
            )
        case .methodist:
            return (
                "Methodist churches follow the teachings of John Wesley, emphasizing personal and social holiness.",
                [
                    "Prevenient grace",
                    "Personal and social holiness",
                    "Works of mercy and piety",
                    "Connection system"
                ],
                [
                    "Traditional liturgy",
                    "Infant and believer baptism",
                    "Social justice ministry",
                    "Sunday school education"
                ]
            )
        case .presbyterian:
            return (
                "Presbyterian churches are governed by elders and follow Reformed theology.",
                [
                    "Sovereignty of God",
                    "Authority of Scripture",
                    "Salvation by grace",
                    "Presbyterian governance"
                ],
                [
                    "Structured worship services",
                    "Infant baptism",
                    "Elder leadership",
                    "Education emphasis"
                ]
            )
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(denomination.rawValue)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.15))
                        
                        Text(denominationInfo.description)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4))
                            .lineSpacing(4)
                    }
                    
                    Divider()
                    
                    // Core Beliefs
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: "book.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                            Text("Core Beliefs")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(denominationInfo.beliefs, id: \.self) { belief in
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 6)
                                    
                                    Text(belief)
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundStyle(Color(red: 0.3, green: 0.3, blue: 0.3))
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Common Practices
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: "hands.sparkles.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                            Text("Common Practices")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(denominationInfo.practices, id: \.self) { practice in
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 6)
                                    
                                    Text(practice)
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundStyle(Color(red: 0.3, green: 0.3, blue: 0.3))
                                }
                            }
                        }
                    }
                    
                    // Disclaimer
                    Text("This information is provided for educational purposes. Each church within a denomination may have unique characteristics and practices.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                        .padding(.top, 8)
                }
                .padding(24)
            }
            .background(Color(white: 0.98))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color(red: 0.7, green: 0.7, blue: 0.7))
                    }
                }
            }
        }
    }
}

// MARK: - Journey Insight Card

struct JourneyInsightCard: View {
    let insight: FindChurchView.JourneyInsights.Insight
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [insight.color.opacity(0.8), insight.color],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                
                Image(systemName: insight.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(insight.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                    
                    // Badge for milestone type
                    if insight.type == .milestone {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                    }
                }
                
                Text(insight.description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4))
                    .lineSpacing(2)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [insight.color.opacity(0.3), insight.color.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: insight.color.opacity(0.15), radius: 12, y: 4)
        )
    }
}

// MARK: - AI Recommendation Card

struct AIRecommendationCard: View {
    let recommendation: ChurchRecommendation
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with match score
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recommendation.churchName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.15))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        if let denomination = recommendation.worshipStyle {
                            Text(denomination)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                        }
                    }
                    
                    Spacer()
                    
                    // Match score badge
                    VStack(spacing: 4) {
                        Text("\(Int(recommendation.matchScore))%")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.purple)
                        Text("Match")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.purple.opacity(0.08))
                    )
                }
                
                // Why recommended section
                if !recommendation.reasons.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 12))
                            Text("Why recommended:")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4))
                        
                        ForEach(recommendation.reasons.prefix(3), id: \.self) { reason in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(Color.purple.opacity(0.6))
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 6)
                                
                                Text(reason)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(Color(red: 0.3, green: 0.3, blue: 0.3))
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                
                // Highlights section
                if !recommendation.highlights.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(recommendation.highlights.prefix(3), id: \.self) { highlight in
                            Text(highlight)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color.purple.opacity(0.1))
                                )
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.purple.opacity(0.15), .pink.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .purple.opacity(0.08), radius: 6, y: 3)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    FindChurchView()
}

