//
//  AmenConnectModels.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import SwiftUI
import PhotosUI

// MARK: - User Profile Model

struct AmenConnectProfile: Identifiable, Codable {
    let id: UUID
    var name: String
    var age: Int
    var birthYear: Int
    var bio: String
    var profilePhoto: Data? // Store image as Data for persistence
    
    // Faith Information
    var yearsSaved: Int // How long they've been saved
    var isBaptized: Bool
    var churchName: String
    var churchCity: String
    var churchState: String
    
    // Additional Info
    var interests: [String]
    var denomination: String?
    var lookingFor: String // e.g., "Friendship", "Dating", "Fellowship"
    
    // Computed Properties
    var location: String {
        "\(churchCity), \(churchState)"
    }
    
    var savedDescription: String {
        if yearsSaved == 0 {
            return "Recently saved"
        } else if yearsSaved == 1 {
            return "Saved for 1 year"
        } else {
            return "Saved for \(yearsSaved) years"
        }
    }
    
    var baptismStatus: String {
        isBaptized ? "Baptized" : "Not yet baptized"
    }
    
    init(
        id: UUID = UUID(),
        name: String = "",
        age: Int = 18,
        birthYear: Int = 2006,
        bio: String = "",
        profilePhoto: Data? = nil,
        yearsSaved: Int = 0,
        isBaptized: Bool = false,
        churchName: String = "",
        churchCity: String = "",
        churchState: String = "",
        interests: [String] = [],
        denomination: String? = nil,
        lookingFor: String = "Fellowship"
    ) {
        self.id = id
        self.name = name
        self.age = age
        self.birthYear = birthYear
        self.bio = bio
        self.profilePhoto = profilePhoto
        self.yearsSaved = yearsSaved
        self.isBaptized = isBaptized
        self.churchName = churchName
        self.churchCity = churchCity
        self.churchState = churchState
        self.interests = interests
        self.denomination = denomination
        self.lookingFor = lookingFor
    }
}

// MARK: - Sample Data for Preview

extension AmenConnectProfile {
    static let sampleProfiles: [AmenConnectProfile] = [
        AmenConnectProfile(
            name: "Sarah Johnson",
            age: 28,
            birthYear: 1998,
            bio: "Hey there! I'm a designer who loves exploring new places, trying out new diving spots, and spending time outdoors. Looking to connect with fellow believers who share a passion for adventure and faith.",
            yearsSaved: 5,
            isBaptized: true,
            churchName: "Grace Community Church",
            churchCity: "Austin",
            churchState: "TX",
            interests: ["Outdoor", "Design", "Diving", "Photography"],
            denomination: "Non-denominational",
            lookingFor: "Dating"
        ),
        AmenConnectProfile(
            name: "Michael Chen",
            age: 32,
            birthYear: 1994,
            bio: "Software engineer by day, worship leader by night. I love serving in my church community and connecting with others through music and faith. Always up for good conversations about theology and life.",
            yearsSaved: 10,
            isBaptized: true,
            churchName: "New Life Baptist Church",
            churchCity: "San Jose",
            churchState: "CA",
            interests: ["Music", "Technology", "Literature", "Worship"],
            denomination: "Baptist",
            lookingFor: "Dating"
        ),
        AmenConnectProfile(
            name: "Emily Rodriguez",
            age: 25,
            birthYear: 2001,
            bio: "Teacher and youth group leader. I'm passionate about mentoring the next generation and growing in my faith journey. Love coffee, books, and deep conversations about life and purpose.",
            yearsSaved: 3,
            isBaptized: true,
            churchName: "First Presbyterian Church",
            churchCity: "Denver",
            churchState: "CO",
            interests: ["Literature", "Education", "Coffee", "Mentoring"],
            denomination: "Presbyterian",
            lookingFor: "Fellowship"
        )
    ]
}

// MARK: - Search Filters

struct AmenConnectFilters {
    var ageRange: ClosedRange<Int> = 18...100
    var maxDistance: Double = 50 // miles
    var baptizedOnly: Bool = false
    var denomination: String?
    var lookingFor: String?
    var minYearsSaved: Int = 0
}
