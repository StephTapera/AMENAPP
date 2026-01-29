//
//  DatingAPIClient.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import Foundation

/// API Client for Christian Dating backend
/// Replace the baseURL with your actual backend URL
class DatingAPIClient {
    static let shared = DatingAPIClient()
    
    // TODO: Replace with your actual backend URL
    private let baseURL = "https://your-backend.com/api/dating"
    
    private let session: URLSession
    private var authToken: String?
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Authentication
    
    func setAuthToken(_ token: String) {
        self.authToken = token
    }
    
    // MARK: - Generic Request Methods
    
    func get<T: Decodable>(
        _ endpoint: String,
        queryParams: [String: String]? = nil
    ) async throws -> T {
        var urlComponents = URLComponents(string: baseURL + endpoint)
        
        if let queryParams = queryParams {
            urlComponents?.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        guard let url = urlComponents?.url else {
            throw DatingAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(to: &request)
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    func post<T: Encodable, R: Decodable>(
        _ endpoint: String,
        body: T
    ) async throws -> R {
        guard let url = URL(string: baseURL + endpoint) else {
            throw DatingAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(to: &request)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        return try JSONDecoder().decode(R.self, from: data)
    }
    
    func post<T: Encodable>(
        _ endpoint: String,
        body: T
    ) async throws {
        guard let url = URL(string: baseURL + endpoint) else {
            throw DatingAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(to: &request)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }
    
    func put<T: Encodable, R: Decodable>(
        _ endpoint: String,
        body: T
    ) async throws -> R {
        guard let url = URL(string: baseURL + endpoint) else {
            throw DatingAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        addHeaders(to: &request)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        return try JSONDecoder().decode(R.self, from: data)
    }
    
    func put<T: Encodable>(
        _ endpoint: String,
        body: T
    ) async throws {
        guard let url = URL(string: baseURL + endpoint) else {
            throw DatingAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        addHeaders(to: &request)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }
    
    func delete(_ endpoint: String) async throws {
        guard let url = URL(string: baseURL + endpoint) else {
            throw DatingAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addHeaders(to: &request)
        
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }
    
    // MARK: - Image Upload
    
    func uploadImage(_ endpoint: String, imageData: Data) async throws -> DatingImageUploadResponse {
        guard let url = URL(string: baseURL + endpoint) else {
            throw DatingAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        var body = Data()
        
        // Add image data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        return try JSONDecoder().decode(DatingImageUploadResponse.self, from: data)
    }
    
    // MARK: - Helper Methods
    
    private func addHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DatingAPIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw DatingAPIError.unauthorized
        case 403:
            throw DatingAPIError.forbidden
        case 404:
            throw DatingAPIError.notFound
        case 429:
            throw DatingAPIError.rateLimited
        case 500...599:
            throw DatingAPIError.serverError
        default:
            throw DatingAPIError.unknown(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - Dating API Error

enum DatingAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case serverError
    case decodingError
    case encodingError
    case unknown(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Unauthorized. Please sign in again."
        case .forbidden:
            return "Access forbidden"
        case .notFound:
            return "Resource not found"
        case .rateLimited:
            return "Too many requests. Please try again later."
        case .serverError:
            return "Server error. Please try again."
        case .decodingError:
            return "Failed to decode response"
        case .encodingError:
            return "Failed to encode request"
        case .unknown(let statusCode):
            return "Unknown error (Status: \(statusCode))"
        }
    }
}

// MARK: - API Response Models

struct DatingImageUploadResponse: Codable {
    let url: String
    let thumbnailUrl: String?
}

struct PaginatedResponse<T: Codable>: Codable {
    let data: [T]
    let page: Int
    let pageSize: Int
    let totalCount: Int
    let hasMore: Bool
}

struct APISuccessResponse: Codable {
    let success: Bool
    let message: String?
}

// MARK: - Example Usage

/*
 
 // In ChristianDatingService, replace mock implementations with:
 
 // Create Profile
 func createDatingProfile(...) async throws -> DatingProfile {
     struct CreateProfileRequest: Encodable {
         let name: String
         let age: Int
         let gender: String
         // ... other fields
     }
     
     let request = CreateProfileRequest(
         name: name,
         age: age,
         gender: gender
         // ...
     )
     
     let profile: DatingProfile = try await DatingAPIClient.shared.post(
         "/profiles",
         body: request
     )
     
     return profile
 }
 
 // Fetch Discovery Profiles
 func fetchDiscoveryProfiles(location: CLLocationCoordinate2D, filters: ProfileFilters?) async throws -> [DatingProfile] {
     var queryParams: [String: String] = [
         "lat": String(location.latitude),
         "lon": String(location.longitude)
     ]
     
     if let ageRange = filters?.ageRange {
         queryParams["ageMin"] = String(ageRange.lowerBound)
         queryParams["ageMax"] = String(ageRange.upperBound)
     }
     
     let response: PaginatedResponse<DatingProfile> = try await DatingAPIClient.shared.get(
         "/discover",
         queryParams: queryParams
     )
     
     return response.data
 }
 
 // Like Profile
 func likeProfile(_ profileId: String) async throws -> Bool {
     struct SwipeRequest: Encodable {
         let profileId: String
         let action: String
     }
     
     struct SwipeResponse: Decodable {
         let isMatch: Bool
         let match: DatingMatch?
     }
     
     let response: SwipeResponse = try await DatingAPIClient.shared.post(
         "/swipes",
         body: SwipeRequest(profileId: profileId, action: "like")
     )
     
     if response.isMatch, let match = response.match {
         matches.append(match)
     }
     
     return response.isMatch
 }
 
 // Send Message
 func sendMessage(matchId: String, receiverId: String, content: String) async throws -> DatingMessage {
     struct SendMessageRequest: Encodable {
         let content: String
         let messageType: String
     }
     
     let message: DatingMessage = try await DatingAPIClient.shared.post(
         "/matches/\(matchId)/messages",
         body: SendMessageRequest(content: content, messageType: "text")
     )
     
     return message
 }
 
 // Upload Photo
 func uploadPhoto(_ imageData: Data) async throws -> String {
     let response = try await DatingAPIClient.shared.uploadImage(
         "/photos",
         imageData: imageData
     )
     
     return response.url
 }
 
 */
