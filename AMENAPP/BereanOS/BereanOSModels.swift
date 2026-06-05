// BereanOSModels.swift
// AMENAPP — Berean OS
//
// All shared data models for the Berean Wisdom Operating System.
// This file is the single source of truth for Berean OS types.

import Foundation
import FirebaseFirestore

// MARK: - Firestore Path Registry

enum BereanOSFirestore {
    // User-scoped project paths
    static func project(uid: String, projectId: String) -> String {
        "users/\(uid)/bereanProjects/\(projectId)"
    }
    static func projects(uid: String) -> String {
        "users/\(uid)/bereanProjects"
    }
    static func memoryEntries(uid: String, projectId: String) -> String {
        "users/\(uid)/bereanProjects/\(projectId)/memoryEntries"
    }
    static func memoryEntry(uid: String, projectId: String, entryId: String) -> String {
        "users/\(uid)/bereanProjects/\(projectId)/memoryEntries/\(entryId)"
    }
    static func researchReports(uid: String, projectId: String) -> String {
        "users/\(uid)/bereanProjects/\(projectId)/researchReports"
    }
    static func researchReport(uid: String, projectId: String, reportId: String) -> String {
        "users/\(uid)/bereanProjects/\(projectId)/researchReports/\(reportId)"
    }
    static func knowledgeGraph(uid: String) -> String {
        "users/\(uid)/bereanKnowledgeGraph"
    }

    // Social / public paths
    static let socialProjects = "bereanSocialProjects"
    static func socialProject(projectId: String) -> String {
        "bereanSocialProjects/\(projectId)"
    }
    static func socialProjectContributors(projectId: String) -> String {
        "bereanSocialProjects/\(projectId)/contributors"
    }
    static func socialProjectCommunityActions(projectId: String) -> String {
        "bereanSocialProjects/\(projectId)/communityActions"
    }

    // Mentorships
    static let mentorships = "bereanMentorships"
    static func mentorship(relationshipId: String) -> String {
        "bereanMentorships/\(relationshipId)"
    }

    // Advisory boards — uid-scoped (private to each user)
    static func advisoryBoards(uid: String) -> String {
        "users/\(uid)/bereanAdvisoryBoards"
    }
    static func advisoryBoard(uid: String, boardId: String) -> String {
        "users/\(uid)/bereanAdvisoryBoards/\(boardId)"
    }

    // Action plans — uid + project scoped
    static func actionPlans(uid: String, projectId: String) -> String {
        "users/\(uid)/bereanProjects/\(projectId)/actionPlans"
    }
    static func actionPlan(uid: String, projectId: String, planId: String) -> String {
        "users/\(uid)/bereanProjects/\(projectId)/actionPlans/\(planId)"
    }

    // Documents — uid + project scoped
    static func documents(uid: String, projectId: String) -> String {
        "users/\(uid)/bereanProjects/\(projectId)/documents"
    }
    static func document(uid: String, projectId: String, documentId: String) -> String {
        "users/\(uid)/bereanProjects/\(projectId)/documents/\(documentId)"
    }
    static func document(uid: String, projectId: String, docId: String) -> String {
        "users/\(uid)/bereanProjects/\(projectId)/documents/\(docId)"
    }

    // Wisdom analyses — uid scoped
    static func wisdomAnalyses(uid: String) -> String {
        "users/\(uid)/wisdomAnalyses"
    }
}

// MARK: - BereanProject

enum BereanProjectStatus: String, CaseIterable, Codable {
    case active, paused, completed, archived
}

enum BereanProjectVisibility: String, CaseIterable, Codable {
    case `private`, community, `public`
}

struct BereanProject: Identifiable, Codable {
    let id: String
    var title: String
    var description: String
    var status: BereanProjectStatus
    var visibility: BereanProjectVisibility
    var ownerUid: String
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - BereanResearchReport

enum BereanResearchMode: String, CaseIterable, Identifiable, Codable {
    case quick, deep, balanced, scriptural, academic, biblical, market, community, multiAgent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .quick:       return "Quick"
        case .deep:        return "Deep"
        case .balanced:    return "Balanced"
        case .scriptural:  return "Scriptural"
        case .academic:    return "Academic"
        case .biblical:    return "Biblical"
        case .market:      return "Market"
        case .community:   return "Community"
        case .multiAgent:  return "Multi-Agent"
        }
    }

    var systemIcon: String {
        switch self {
        case .quick:       return "bolt.fill"
        case .deep:        return "magnifyingglass.circle.fill"
        case .balanced:    return "scale.3d"
        case .scriptural:  return "book.fill"
        case .academic:    return "graduationcap.fill"
        case .biblical:    return "cross.fill"
        case .market:      return "chart.bar.fill"
        case .community:   return "person.3.fill"
        case .multiAgent:  return "cpu.fill"
        }
    }
}

enum BereanResearchStatus: String, Codable {
    case pending, inProgress = "in_progress", complete, failed
}

struct BereanResearchCitation: Identifiable, Codable {
    let id: String
    let title: String
    let url: String?
    let sourceType: String
    let relevanceScore: Double
}

struct BereanResearchReport: Identifiable, Codable {
    let id: String
    let projectId: String?
    let ownerUid: String
    let query: String
    let researchMode: BereanResearchMode
    let status: BereanResearchStatus
    let executiveSummary: String
    let keyFindings: [BereanResearchFinding]
    let supportingEvidence: [String]
    let counterarguments: [String]
    let openQuestions: [String]
    let confidenceScore: Double
    let sources: [BereanResearchCitation]
    let actionableRecommendations: [String]
    let createdAt: Date
    let completedAt: Date?
}

// MARK: - BereanWisdomMode

enum BereanWisdomMode: String, CaseIterable, Identifiable, Codable {
    case secular, christian, churchLeadership, family, business, educational, mentorship

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .secular:          return "General"
        case .christian:        return "Christian"
        case .churchLeadership: return "Church Leadership"
        case .family:           return "Family"
        case .business:         return "Business"
        case .educational:      return "Educational"
        case .mentorship:       return "Mentorship"
        }
    }
}

// MARK: - BereanPerspective

struct BereanPerspective: Identifiable, Codable {
    let id: String
    var perspectiveType: String
    var summary: String
    var agreements: [String]
    var disagreements: [String]
    var tradeoffs: [String]
    var unknowns: [String]
}

// MARK: - BereanWisdomAnalysis

struct BereanWisdomAnalysis: Identifiable, Codable {
    let id: String
    var projectId: String?
    var question: String
    var truthScore: Double
    var wisdomScore: Double
    var impactSummary: String
    var riskSummary: String
    var stewardshipNotes: String
    var characterImplications: String
    var longTermConsequences: String
    var perspectives: [BereanPerspective]
    var faithPerspective: String?
    var mode: BereanWisdomMode
    let createdAt: Date
}

// MARK: - BereanDebate

struct BereanDebateArgument: Identifiable, Codable {
    let id: String
    let position: String
    let argument: String
    let scriptureRefs: [String]
    let strengthScore: Double
}

struct BereanDebate: Identifiable, Codable {
    let id: String
    let projectId: String?
    let topic: String
    let proArguments: [BereanDebateArgument]
    let conArguments: [BereanDebateArgument]
    let synthesisNote: String
    let createdAt: Date
}

// MARK: - BereanAdvisoryBoard

struct BereanAIAdvisor: Identifiable, Codable {
    let id: String
    var role: String
    var specialization: String
    var systemPrompt: String
    var lastResponseAt: Date?
}

struct BereanAdvisoryBoard: Identifiable, Codable {
    let id: String
    var ownerUid: String
    var name: String
    var boardType: String
    var advisors: [BereanAIAdvisor]
    var projectId: String?
    var createdAt: Date
}

// Legacy alias kept for backward compatibility
typealias BereanAdvisor = BereanAIAdvisor

// MARK: - BereanOSSearchResults

struct BereanOSSearchResults {
    let projects: [BereanProject]
    let memoryEntries: [BereanProjectMemoryEntry]
    let researchReports: [BereanResearchReport]
    let documents: [BereanDocument]
    let knowledgeNodes: [BereanKnowledgeNode]

    var isEmpty: Bool {
        projects.isEmpty &&
        memoryEntries.isEmpty &&
        researchReports.isEmpty &&
        documents.isEmpty &&
        knowledgeNodes.isEmpty
    }
}

// MARK: - BereanDocument

struct BereanDocument: Identifiable, Codable {
    let id: String
    var title: String
    var content: String
    var projectId: String?
    var ownerUid: String
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - BereanActionPlan

struct BereanActionStep: Identifiable, Codable {
    let id: String
    var title: String
    var detail: String
    var isCompleted: Bool
    var dueDate: Date?
}

enum BereanActionPlanType: String, CaseIterable, Codable {
    case business, personal, ministry, academic, project, spiritual

    var displayName: String {
        switch self {
        case .business:  return "Business"
        case .personal:  return "Personal"
        case .ministry:  return "Ministry"
        case .academic:  return "Academic"
        case .project:   return "Project"
        case .spiritual: return "Spiritual"
        }
    }
}

struct BereanOSTask: Identifiable, Codable {
    let id: String
    var title: String
    var assignedTo: String?
    var dueDate: Date?
    var status: BereanTaskStatus
    var priority: BereanTaskPriority
}

struct BereanMilestone: Identifiable, Codable {
    let id: String
    var title: String
    var dueDate: Date?
    var status: BereanTaskStatus
    var dependsOnIds: [String]
    var tasks: [BereanOSTask]
}

struct BereanActionPlan: Identifiable, Codable {
    let id: String
    var projectId: String
    var title: String
    var planType: BereanActionPlanType
    var milestones: [BereanMilestone]
    var risks: [String]
    var successMetrics: [String]
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - BereanProjectMemoryEntry

enum BereanProjectMemoryEntryType: String, CaseIterable, Codable {
    case insight, fact, question, decision, reference, note
}

struct BereanProjectMemoryEntry: Identifiable, Codable {
    let id: String
    var entryType: BereanProjectMemoryEntryType
    var content: String
    var projectId: String
    var ownerUid: String
    var sourceLabel: String?
    var isResolved: Bool
    var createdAt: Date
}

// MARK: - BereanKnowledgeNode

enum BereanKnowledgeNodeType: String, CaseIterable, Codable {
    case concept, scripture, person, event, place, theme, question
}

struct BereanKnowledgeNode: Identifiable, Codable {
    let id: String
    var title: String
    var nodeType: BereanKnowledgeNodeType
    var ownerUid: String
    var linkedNodeIds: [String]
    var projectIds: [String]
    var metadata: [String: String]
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - BereanMentorRelationship

enum BereanMentorshipStatus: String, CaseIterable, Codable {
    case pending, active, paused, completed, declined
}

enum BereanTaskStatus: String, CaseIterable, Codable {
    case notStarted, inProgress, completed, cancelled
}

enum BereanTaskPriority: String, CaseIterable, Codable {
    case low, medium, high, critical
}

struct BereanMentorNote: Identifiable, Codable {
    let id: String
    var content: String
    var targetEntryId: String?
    var authorUid: String
    var isPinned: Bool
    var isActedUpon: Bool
    var createdAt: Date
}

struct BereanMentorRelationship: Identifiable, Codable {
    let id: String
    var mentorUid: String?
    var menteeUid: String
    var projectId: String?
    var status: BereanMentorshipStatus
    var mentorNotes: [BereanMentorNote]
    var milestoneIds: [String]
    var createdAt: Date
}

// MARK: - Social Project Models

enum BereanContributorRole: String, CaseIterable, Codable {
    case owner, collaborator, reader
}

struct BereanProjectContributor: Identifiable, Codable {
    let id: String
    var userId: String
    var role: BereanContributorRole
    var joinedAt: Date
    var contributionCount: Int
}

enum BereanCommunityActionType: String, CaseIterable, Identifiable, Codable {
    case question, insight, correction, reference, encouragement
    case addSource, addContext, factCheck, challenge, askQuestion, flagIssue, expand, summarize

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .question:      return "Question"
        case .insight:       return "Insight"
        case .correction:    return "Correction"
        case .reference:     return "Reference"
        case .encouragement: return "Encouragement"
        case .addSource:     return "Add Source"
        case .addContext:    return "Add Context"
        case .factCheck:     return "Fact Check"
        case .challenge:     return "Challenge"
        case .askQuestion:   return "Ask Question"
        case .flagIssue:     return "Flag Issue"
        case .expand:        return "Expand"
        case .summarize:     return "Summarize"
        }
    }

    var systemIcon: String {
        switch self {
        case .question:      return "questionmark.circle.fill"
        case .insight:       return "lightbulb.fill"
        case .correction:    return "exclamationmark.triangle.fill"
        case .reference:     return "book.fill"
        case .encouragement: return "heart.fill"
        case .addSource:     return "link.badge.plus"
        case .addContext:    return "text.badge.plus"
        case .factCheck:     return "checkmark.seal.fill"
        case .challenge:     return "bolt.fill"
        case .askQuestion:   return "bubble.left.and.bubble.right.fill"
        case .flagIssue:     return "flag.fill"
        case .expand:        return "arrow.up.left.and.arrow.down.right"
        case .summarize:     return "doc.text.magnifyingglass"
        }
    }
}

struct BereanCommunityAction: Identifiable, Codable {
    let id: String
    var actionType: BereanCommunityActionType
    var userId: String
    var content: String
    var targetEntryId: String
    var timestamp: Date
}

// MARK: - BereanConfidenceLevel

enum BereanConfidenceLevel: String, CaseIterable, Codable, Identifiable {
    case certain, probable, uncertain, speculative, unsupported

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .certain:     return "Certain"
        case .probable:    return "Probable"
        case .uncertain:   return "Uncertain"
        case .speculative: return "Speculative"
        case .unsupported: return "Unsupported"
        }
    }

    var explanation: String {
        switch self {
        case .certain:     return "Strongly supported by multiple reliable sources."
        case .probable:    return "Likely true based on available evidence."
        case .uncertain:   return "Evidence is mixed or limited."
        case .speculative: return "Based on inference; limited direct support."
        case .unsupported: return "Insufficient evidence to assess this claim."
        }
    }
}

// MARK: - BereanSourceType

enum BereanSourceType: String, Codable, CaseIterable {
    case scripture, peerReviewed, expertCommentary, communityNote, news, video, blog, unknown

    var displayName: String {
        switch self {
        case .scripture:        return "Scripture"
        case .peerReviewed:     return "Peer Reviewed"
        case .expertCommentary: return "Expert Commentary"
        case .communityNote:    return "Community Note"
        case .news:             return "News"
        case .video:            return "Video"
        case .blog:             return "Blog"
        case .unknown:          return "Unknown"
        }
    }

    var systemIcon: String {
        switch self {
        case .scripture:        return "book.closed.fill"
        case .peerReviewed:     return "graduationcap.fill"
        case .expertCommentary: return "person.text.rectangle.fill"
        case .communityNote:    return "person.3.fill"
        case .news:             return "newspaper.fill"
        case .video:            return "play.rectangle.fill"
        case .blog:             return "doc.richtext.fill"
        case .unknown:          return "questionmark.circle.fill"
        }
    }
}

// MARK: - BereanSourceEntry

struct BereanSourceEntry: Identifiable, Codable {
    let id: String
    let url: String?
    let title: String
    let author: String?
    let publishedAt: Date?
    let sourceType: BereanSourceType
    let qualityScore: Double
    let excerpt: String?
    let conflictsWithSourceIds: [String]
    let verifiedAt: Date?
}

// MARK: - BereanResearchFinding (used by BereanResearchReportCard)

struct BereanResearchFinding: Identifiable, Codable {
    let id: String
    var content: String
    var confidence: BereanConfidenceLevel
    var sourceIds: [String]
}

// MARK: - BereanDocumentType

enum BereanDocumentType: String, CaseIterable, Codable {
    case essay, outline, sermon, studyGuide, devotional, report, note, other

    var displayName: String {
        switch self {
        case .essay:      return "Essay"
        case .outline:    return "Outline"
        case .sermon:     return "Sermon"
        case .studyGuide: return "Study Guide"
        case .devotional: return "Devotional"
        case .report:     return "Report"
        case .note:       return "Note"
        case .other:      return "Document"
        }
    }
}

// MARK: - BereanDocumentVersion

struct BereanDocumentVersion: Identifiable, Codable {
    let id: String
    let versionNumber: Int
    let body: String
    let changedBy: String
    let changedAt: Date
    let changeNotes: String
}

// MARK: - BereanLivingDocument

struct BereanLivingDocument: Identifiable, Codable {
    let id: String
    let projectId: String
    let ownerUid: String
    var title: String
    var documentType: BereanDocumentType
    var body: String
    var version: Int
    var versionHistory: [BereanDocumentVersion]
    var sources: [String]
    var isPublished: Bool
    let createdAt: Date
    var updatedAt: Date
}

// MARK: - JSONDecoder Convenience

extension JSONDecoder {
    static let berean: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
