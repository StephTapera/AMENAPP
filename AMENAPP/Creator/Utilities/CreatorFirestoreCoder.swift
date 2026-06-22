import Foundation
import FirebaseFirestore

enum CreatorFirestoreCoder {
    static func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        return object as? [String: Any] ?? [:]
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: [String: Any]) throws -> T {
        let normalized = normalizeFirestoreValue(data)
        let json = try JSONSerialization.data(withJSONObject: normalized, options: [])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: json)
    }

    private static func normalizeFirestoreValue(_ value: Any) -> Any {
        if let timestamp = value as? Timestamp {
            return ISO8601DateFormatter().string(from: timestamp.dateValue())
        }
        if let date = value as? Date {
            return ISO8601DateFormatter().string(from: date)
        }
        if let dict = value as? [String: Any] {
            var mapped: [String: Any] = [:]
            for (key, value) in dict {
                mapped[key] = normalizeFirestoreValue(value)
            }
            return mapped
        }
        if let array = value as? [Any] {
            return array.map { normalizeFirestoreValue($0) }
        }
        return value
    }
}
