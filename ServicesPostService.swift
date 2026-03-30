//
//  PostService.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//
//  Legacy shim — all post operations are handled by FirebasePostService.
//  This file exists only to preserve the PostService name for older call sites.

import Foundation

/// Typealias so any legacy reference to `PostService` routes to the real implementation.
typealias PostService = FirebasePostService

// MARK: - Network Errors

enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingError
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError:
            return "Failed to decode response"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}
