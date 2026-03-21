//
//  StudioDraft.swift
//  AMENAPP
//
//  SwiftData model for Studio auto-save drafts.
//  Stores up to 5 versions per session; oldest is pruned on each save.
//

import SwiftData
import Foundation

@Model
final class StudioDraft {
    var id: UUID
    var tool: String          // StudioTool.rawValue
    var userInput: String
    var scriptureRef: String
    var tone: String
    var generatedText: String
    var savedAt: Date
    var version: Int

    init(tool: String,
         userInput: String,
         scriptureRef: String,
         tone: String,
         generatedText: String,
         version: Int = 1) {
        self.id = UUID()
        self.tool = tool
        self.userInput = userInput
        self.scriptureRef = scriptureRef
        self.tone = tone
        self.generatedText = generatedText
        self.savedAt = Date()
        self.version = version
    }
}
