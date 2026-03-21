// MentorshipViewModel.swift
// AMENAPP
import SwiftUI
import FirebaseAuth
import Combine

@MainActor
final class MentorshipViewModel: ObservableObject {

    // MARK: - State
    @Published var mentors: [Mentor] = []
    @Published var filteredMentors: [Mentor] = []
    @Published var relationships: [MentorshipRelationship] = []
    @Published var checkIns: [MentorshipCheckIn] = []
    @Published var selectedTab: MentorshipTab = .findMentor
    @Published var selectedSpecialty: String = "All"
    @Published var isLoading: Bool = false
    @Published var loadError: String? = nil
    @Published var selectedMentor: Mentor? = nil
    @Published var showPlanSheet: Bool = false
    @Published var showChatFor: String? = nil  // chatId
    @Published var showCheckInFor: MentorshipCheckIn? = nil

    // Stats (animate-up on appear)
    @Published var displayedMentorCount: Int = 0
    @Published var displayedRelationshipCount: Int = 0
    @Published var displayedSessionCount: Int = 0

    // Specialties from fetched mentors
    var allSpecialties: [String] {
        var specs = ["All"]
        specs += Array(Set(mentors.flatMap { $0.specialties })).sorted()
        return specs
    }

    // Check-ins grouped
    var todayCheckIns: [MentorshipCheckIn] { checkIns.filter { $0.dueSectionLabel == "Due Today" } }
    var thisWeekCheckIns: [MentorshipCheckIn] { checkIns.filter { $0.dueSectionLabel == "This Week" } }
    var upcomingCheckIns: [MentorshipCheckIn] { checkIns.filter { $0.dueSectionLabel == "Upcoming" } }

    private let service = MentorshipService.shared

    enum MentorshipTab: String, CaseIterable {
        case findMentor = "Find Mentor"
        case myCircles  = "My Circles"
        case checkIns   = "Check-ins"
        var icon: String {
            switch self {
            case .findMentor: return "person.2.fill"
            case .myCircles:  return "circle.grid.3x3.fill"
            case .checkIns:   return "checklist"
            }
        }
    }

    // MARK: - Load
    func loadAll() async {
        isLoading = true
        loadError = nil
        async let mentorsFetch = service.fetchMentors()
        async let relsFetch = service.fetchMyRelationships()
        async let checkInsFetch = service.fetchMyCheckIns()
        do {
            let (m, r, c) = try await (mentorsFetch, relsFetch, checkInsFetch)
            mentors = m
            filteredMentors = m
            relationships = r
            checkIns = c
            animateStats()
        } catch {
            loadError = error.localizedDescription
            dlog("⚠️ MentorshipViewModel.loadAll error: \(error)")
        }
        isLoading = false
    }

    func filterMentors(by specialty: String) {
        selectedSpecialty = specialty
        if specialty == "All" {
            filteredMentors = mentors
        } else {
            filteredMentors = mentors.filter { $0.specialties.contains(specialty) }
        }
    }

    private func animateStats() {
        let totalMentors = mentors.count
        let totalRels = relationships.count
        let totalSessions = relationships.reduce(0) { $0 + $1.sessionsCompleted }

        let duration = 1.2
        let steps = 30
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let eased = 1 - pow(1 - t, 3)  // ease-out cubic
            DispatchQueue.main.asyncAfter(deadline: .now() + (duration / Double(steps)) * Double(i)) {
                self.displayedMentorCount = Int(Double(totalMentors) * eased)
                self.displayedRelationshipCount = Int(Double(totalRels) * eased)
                self.displayedSessionCount = Int(Double(totalSessions) * eased)
            }
        }
    }

    func hasRelationshipWith(_ mentorId: String) -> Bool {
        service.hasRelationship(mentorId: mentorId, relationships: relationships)
    }
}
