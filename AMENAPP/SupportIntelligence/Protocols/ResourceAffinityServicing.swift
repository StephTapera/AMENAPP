//
//  ResourceAffinityServicing.swift
//  AMENAPP
//

import Foundation

protocol ResourceAffinityServicing: AnyObject, Sendable {
    func fetchAffinities(userId: String) async throws -> [ResourceAffinity]
    func recordOpen(resourceType: String, userId: String) async throws
    func recordCompletion(resourceType: String, userId: String) async throws
    func rankedResourceTypes(userId: String, limit: Int) async throws -> [String]
}
