//
//  SupportGraphServicing.swift
//  AMENAPP
//

import Foundation

protocol SupportGraphServicing: AnyObject, Sendable {
    func fetchTrustedContacts(userId: String, limit: Int) async throws -> [SupportGraphEdge]
    func recordSupportInteraction(fromUserId: String, toUserId: String, type: SupportGraphEdgeType) async throws
}
