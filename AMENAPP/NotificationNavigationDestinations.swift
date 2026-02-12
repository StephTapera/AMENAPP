//
//  NotificationNavigationDestinations.swift
//  AMENAPP
//
//  Created by Steph on 1/31/26.
//
//  Navigation destination enum for notification taps
//

import SwiftUI

// MARK: - Navigation Destinations Namespace

struct NotificationNavigationDestinations {
    // MARK: - Navigation Destination Enum
    
    enum NotificationDestination: Hashable {
        case post(postId: String)
        case profile(userId: String)
        
        var id: String {
            switch self {
            case .post(let postId):
                return "post_\(postId)"
            case .profile(let userId):
                return "profile_\(userId)"
            }
        }
    }
}

