// ContentBlock.swift
// AMENAPP
// Rich content block model for universal content nodes.

import Foundation

enum ContentBlockType: String, Codable, CaseIterable {
    case text
    case heading
    case quote
    case list
    case media
    case embed
    case divider
}

struct ContentBlock: Identifiable, Codable, Equatable {
    var id: String
    var type: ContentBlockType
    var text: String?
    var mediaRefId: String?
    var order: Int
    var metadata: [String: String]?

    init(
        id: String = UUID().uuidString,
        type: ContentBlockType,
        text: String? = nil,
        mediaRefId: String? = nil,
        order: Int = 0,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.mediaRefId = mediaRefId
        self.order = order
        self.metadata = metadata
    }
}
