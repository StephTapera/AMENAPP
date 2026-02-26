//
//  SafetyPolicyFramework.swift
//  AMENAPP
//
//  World-Class Safety & Moderation Policy Framework
//  Clear, enforceable, context-aware rules for content moderation
//

import Foundation

// MARK: - Policy Types (File-level for cross-file usage)

enum PolicyViolation: String, Codable, CaseIterable {
        // TIER 1: Severe Violations (Immediate Block)
        case threatOfViolence = "threat_of_violence"
        case sexualExploitation = "sexual_exploitation"
        case childSafety = "child_safety"
        case credibleThreat = "credible_threat"
        case suicideEncouragement = "suicide_encouragement"
        
        // TIER 2: Serious Violations (Block + Review)
        case harassment = "harassment"
        case hateSpeech = "hate_speech"
        case targetedBullying = "targeted_bullying"
        case sexualContent = "sexual_content"
        case doxxing = "doxxing"
        case impersonation = "impersonation"
        
        // TIER 3: Moderate Violations (Warn + Revise)
        case hostileLanguage = "hostile_language"
        case personalAttacks = "personal_attacks"
        case spam = "spam"
        case scam = "scam"
        case misleadingContent = "misleading_content"
        case excessiveProfanity = "excessive_profanity"
        
        // TIER 4: Light Violations (Nudge Only)
        case aiGeneratedSpam = "ai_generated_spam"
        case lowQualityContent = "low_quality_content"
        case offTopic = "off_topic"
        
        var severity: ViolationSeverity {
            switch self {
            case .threatOfViolence, .sexualExploitation, .childSafety, .credibleThreat, .suicideEncouragement:
                return .critical
            case .harassment, .hateSpeech, .targetedBullying, .sexualContent, .doxxing, .impersonation:
                return .severe
            case .hostileLanguage, .personalAttacks, .spam, .scam, .misleadingContent, .excessiveProfanity:
                return .moderate
            case .aiGeneratedSpam, .lowQualityContent, .offTopic:
                return .light
            }
        }
        
        var description: String {
            switch self {
            case .threatOfViolence: return "Threats of violence or harm"
            case .sexualExploitation: return "Sexual exploitation or predatory behavior"
            case .childSafety: return "Content endangering minors"
            case .credibleThreat: return "Credible threat of harm"
            case .suicideEncouragement: return "Encouraging self-harm or suicide"
            case .harassment: return "Harassment or targeted abuse"
            case .hateSpeech: return "Hate speech or slurs"
            case .targetedBullying: return "Targeted bullying behavior"
            case .sexualContent: return "Explicit sexual content"
            case .doxxing: return "Sharing private information"
            case .impersonation: return "Impersonation or identity fraud"
            case .hostileLanguage: return "Hostile or aggressive language"
            case .personalAttacks: return "Personal attacks or insults"
            case .spam: return "Spam or unwanted content"
            case .scam: return "Scam or phishing attempt"
            case .misleadingContent: return "Misleading or deceptive content"
            case .excessiveProfanity: return "Excessive profanity"
            case .aiGeneratedSpam: return "AI-generated spam"
            case .lowQualityContent: return "Low-quality content"
            case .offTopic: return "Off-topic content"
            }
        }
        
        /// User-facing message when content is blocked
        var userFacingMessage: String {
            switch self {
            case .threatOfViolence:
                return "This content contains threats of violence, which violates our community guidelines."
            case .sexualExploitation:
                return "This content violates our policies on sexual exploitation and predatory behavior."
            case .childSafety:
                return "This content violates our child safety policies."
            case .credibleThreat:
                return "This content contains a credible threat, which is not allowed."
            case .suicideEncouragement:
                return "We take self-harm very seriously. If you're struggling, please reach out for help."
            case .harassment:
                return "This content appears to target or harass another person. Please be respectful."
            case .hateSpeech:
                return "This content contains hate speech or slurs, which violates our guidelines."
            case .targetedBullying:
                return "This content appears to be targeted bullying. Let's keep our community kind."
            case .sexualContent:
                return "This content contains explicit sexual material, which isn't appropriate here."
            case .doxxing:
                return "Sharing someone's private information without consent isn't allowed."
            case .impersonation:
                return "Impersonating others violates our authenticity policies."
            case .hostileLanguage:
                return "This language comes across as hostile. Want to rephrase more constructively?"
            case .personalAttacks:
                return "This seems like a personal attack. Can you share your thoughts more respectfully?"
            case .spam:
                return "This looks like spam. Please share meaningful content with the community."
            case .scam:
                return "This appears to be a scam or phishing attempt, which isn't allowed."
            case .misleadingContent:
                return "This content appears misleading. Please share accurate information."
            case .excessiveProfanity:
                return "Consider reducing profanity to keep conversations respectful."
            case .aiGeneratedSpam:
                return "This appears to be AI-generated spam. Share your own authentic thoughts!"
            case .lowQualityContent:
                return "This content could use more substance. Want to add more detail?"
            case .offTopic:
                return "This seems off-topic. Want to share it in a more relevant space?"
            }
        }
    }

enum ViolationSeverity: Int, Codable, Comparable {
    case light = 1      // Nudge only
    case moderate = 2   // Warn + revise
    case severe = 3     // Block + review
    case critical = 4   // Immediate block + escalate

    static func < (lhs: ViolationSeverity, rhs: ViolationSeverity) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

enum EnforcementAction: String, Codable {
    case allow = "allow"
    case nudgeOnly = "nudge_only"                    // Gentle suggestion, content still posts
    case warnAndAllow = "warn_and_allow"             // Warning message, content still posts
    case requireRevision = "require_revision"        // Must revise before posting
    case temporaryDelay = "temporary_delay"          // 5-minute cooldown before retry
    case blockAndReview = "block_and_review"         // Block content, human review queue
    case blockAndEscalate = "block_and_escalate"     // Block content, escalate to safety team
    case restrictComments = "restrict_comments"      // Limit commenting for period
    case restrictPosting = "restrict_posting"        // Limit posting for period
    case shadowRestrict = "shadow_restrict"          // Content only visible to author
    case cooldown = "cooldown"                       // Rate limit cooldown

    var isBlocking: Bool {
        switch self {
        case .allow, .nudgeOnly, .warnAndAllow:
            return false
        default:
            return true
        }
    }

    var rawValue: String {
        switch self {
        case .allow: return "allow"
        case .nudgeOnly: return "nudge_only"
        case .warnAndAllow: return "warn_and_allow"
        case .requireRevision: return "require_revision"
        case .temporaryDelay: return "temporary_delay"
        case .blockAndReview: return "block_and_review"
        case .blockAndEscalate: return "block_and_escalate"
        case .restrictComments: return "restrict_comments"
        case .restrictPosting: return "restrict_posting"
        case .shadowRestrict: return "shadow_restrict"
        case .cooldown: return "cooldown"
        }
    }

    var requiresHumanReview: Bool {
        switch self {
        case .blockAndReview, .blockAndEscalate:
            return true
        default:
            return false
        }
    }
}

// MARK: - Safety Policy Framework

/// Comprehensive safety policy framework defining what is/isn't allowed
/// with clear enforcement actions and context-aware handling
class SafetyPolicyFramework {
    static let shared = SafetyPolicyFramework()

    // MARK: - Policy Definitions
    
    /// Detailed policy rules with examples and gray areas
    struct PolicyDefinition {
        let violation: PolicyViolation
        let allowed: [String]
        let notAllowed: [String]
        let grayAreas: [String]
        let escalationTriggers: [String]
        let examples: PolicyExamples
    }
    
    struct PolicyExamples {
        let clearViolations: [String]
        let borderline: [String]
        let acceptable: [String]
    }
    
    // MARK: - Harassment Policy
    
    static let harassmentPolicy = PolicyDefinition(
        violation: .harassment,
        allowed: [
            "Respectful disagreement on ideas or beliefs",
            "Constructive criticism of public figures or actions",
            "Expressing concern for someone's wellbeing",
            "Asking clarifying questions"
        ],
        notAllowed: [
            "Repeated unwanted contact after being asked to stop",
            "Targeted insults or name-calling",
            "Mocking or ridiculing someone's appearance, identity, or faith",
            "Dogpiling (many users attacking one person)",
            "Threatening or intimidating language",
            "Humiliating or degrading someone publicly"
        ],
        grayAreas: [
            "Single critical comment (context matters: tone, target, history)",
            "Sarcasm or humor that could be misinterpreted",
            "Strong disagreement that feels personal (check: is it about ideas or person?)"
        ],
        escalationTriggers: [
            "User has harassed same person 3+ times",
            "Multiple users attacking one person simultaneously",
            "Harassment continues after warning",
            "Target reports feeling unsafe or harassed"
        ],
        examples: PolicyExamples(
            clearViolations: [
                "\"You're so stupid, no wonder nobody likes you\"",
                "\"Why don't you just leave the church, fake Christian\"",
                "\"Ugly inside and out. Stop posting.\""
            ],
            borderline: [
                "\"That's a really bad take\" (acceptable if one-time, crosses line if repeated/piled on)",
                "\"I can't believe you actually think that\" (tone matters)"
            ],
            acceptable: [
                "\"I respectfully disagree with your interpretation of this verse\"",
                "\"I see it differently - here's my perspective...\""
            ]
        )
    )
    
    // MARK: - Hate Speech Policy
    
    static let hateSpeechPolicy = PolicyDefinition(
        violation: .hateSpeech,
        allowed: [
            "Discussing social issues respectfully",
            "Sharing personal experiences with discrimination",
            "Quoting scripture on love, inclusion, justice",
            "Advocating for marginalized groups"
        ],
        notAllowed: [
            "Slurs or derogatory terms targeting identity (race, religion, gender, orientation, disability, etc.)",
            "Dehumanizing language (\"animals\", \"vermin\", \"infestation\")",
            "Claims of inherent inferiority/superiority",
            "Calls for exclusion, segregation, or violence",
            "Denying humanity or dignity of a group"
        ],
        grayAreas: [
            "Reclaimed slurs within in-group (context: who is saying it, intent)",
            "Theological disagreement that touches identity (must be respectful, not dehumanizing)",
            "Criticism of ideologies vs people (\"I disagree with X belief\" vs \"X people are...\")"
        ],
        escalationTriggers: [
            "Use of known hate symbols or codes",
            "Repeated slurs despite warnings",
            "Coordinated hate campaign",
            "Incitement to harm a group"
        ],
        examples: PolicyExamples(
            clearViolations: [
                "[Any racial, religious, gender, or orientation-based slurs]",
                "\"They're not even human\"",
                "\"This country needs to be cleansed of [group]\""
            ],
            borderline: [
                "\"I believe marriage is between man and woman\" (theological view, allowed if stated respectfully)",
                "\"I struggle to understand [group]'s perspective\" (curiosity, not hate)"
            ],
            acceptable: [
                "\"As Christians, we're called to love everyone\"",
                "\"My faith teaches me to welcome the stranger\""
            ]
        )
    )
    
    // MARK: - Comment Pile-On Policy
    
    static let pileOnPolicy = PolicyDefinition(
        violation: .targetedBullying,
        allowed: [
            "Multiple people agreeing with a viewpoint",
            "Shared concern about a behavior (respectfully expressed)",
            "Community discussion of ideas"
        ],
        notAllowed: [
            "Many users attacking one person in rapid succession",
            "Coordinated campaign to silence or drive someone off platform",
            "Mocking, ridiculing, or humiliating someone en masse",
            "Comments designed to overwhelm or exhaust target"
        ],
        grayAreas: [
            "Popular post attracting many critical comments (check: tone, coordination, repetition)",
            "Community expressing shared disagreement (respectful critiques vs attacks)"
        ],
        escalationTriggers: [
            "10+ negative comments on one user's content within 1 hour",
            "5+ users with hostile language targeting same person",
            "Comments contain similar wording (coordinated)",
            "Target reports feeling overwhelmed or unsafe"
        ],
        examples: PolicyExamples(
            clearViolations: [
                "[Multiple users] \"You're wrong\", \"You're stupid\", \"Leave\", \"Nobody wants you here\"",
                "Coordinated flood of negative emoji reactions + hostile comments"
            ],
            borderline: [
                "Many people disagreeing but using respectful language",
                "Shared concern expressed constructively by multiple people"
            ],
            acceptable: [
                "Multiple people sharing alternative perspectives respectfully",
                "Community rallying to support someone (positive pile-on)"
            ]
        )
    )
    
    // MARK: - Threat Policy
    
    static let threatPolicy = PolicyDefinition(
        violation: .threatOfViolence,
        allowed: [
            "Expressing strong disagreement",
            "Saying you'll pray for someone",
            "Expressing hope for positive change"
        ],
        notAllowed: [
            "Direct threats of violence (\"I will hurt you\")",
            "Indirect threats (\"You better watch out\")",
            "Wishing harm on someone",
            "Threatening to reveal private information",
            "Stalking or tracking behavior threats"
        ],
        grayAreas: [
            "Hyperbolic language that isn't meant literally (\"I'm gonna lose it\")",
            "Expressing strong emotion without threat intent"
        ],
        escalationTriggers: [
            "Specific details about intended harm",
            "Mention of weapons or methods",
            "Knowledge of target's location or schedule",
            "History of escalating behavior",
            "Target reports feeling unsafe"
        ],
        examples: PolicyExamples(
            clearViolations: [
                "\"I know where you live and I'm coming for you\"",
                "\"You deserve to be hurt\"",
                "\"Watch your back\""
            ],
            borderline: [
                "\"I'm so mad I could explode\" (hyperbolic, not directed at person)",
                "\"You're going to regret this\" (depends on context)"
            ],
            acceptable: [
                "\"I strongly disagree and I'm upset about this\"",
                "\"I hope you reconsider this position\""
            ]
        )
    )
    
    // MARK: - Spam Policy
    
    static let spamPolicy = PolicyDefinition(
        violation: .spam,
        allowed: [
            "Sharing relevant resources or links (occasionally)",
            "Recommending content related to discussion",
            "Personal blog or ministry links (if relevant)"
        ],
        notAllowed: [
            "Posting same content repeatedly",
            "Copy-paste generic messages",
            "Irrelevant promotional content",
            "Mass commenting with same message",
            "Engagement bait (\"Comment AMEN if...\")",
            "Deceptive links or clickbait"
        ],
        grayAreas: [
            "Sharing your own content occasionally (fine if relevant)",
            "Repeated sharing of same message in different contexts (check: is it truly relevant?)"
        ],
        escalationTriggers: [
            "Same content posted 3+ times in short period",
            "Copy-paste detected across multiple posts",
            "Links flagged as suspicious by multiple users",
            "Rapid-fire commenting (10+ comments in 5 minutes)"
        ],
        examples: PolicyExamples(
            clearViolations: [
                "\"Click here for FREE BIBLES NOW!!! [link]\" (posted 10x)",
                "\"I prayed this prayer and got rich! Comment AMEN\" (engagement bait)",
                "Copy-pasted verse + link on 20 unrelated posts"
            ],
            borderline: [
                "Sharing your ministry link on relevant discussion (once is fine)",
                "Recommending same resource to different people (check: is it truly helpful?)"
            ],
            acceptable: [
                "\"This article really helped me understand this topic\" [relevant link]",
                "\"I wrote about this on my blog if anyone's interested\" (context-appropriate)"
            ]
        )
    )
    
    // MARK: - Sexual Content Policy
    
    static let sexualContentPolicy = PolicyDefinition(
        violation: .sexualContent,
        allowed: [
            "Mature, respectful discussion of relationships/marriage",
            "Biblical teaching on sexuality (appropriately framed)",
            "Sharing testimony about purity, healing from abuse, etc.",
            "Age-appropriate questions about relationships"
        ],
        notAllowed: [
            "Explicit sexual descriptions or imagery",
            "Solicitation of sexual content or encounters",
            "Sexualization of minors (zero tolerance)",
            "Pornographic content or links",
            "Sexual harassment or unwanted advances",
            "Graphic sexual language"
        ],
        grayAreas: [
            "Biblical passages with sexual content (Song of Songs, etc.) - context matters",
            "Discussion of sexuality in educational/theological context (must be appropriate)",
            "Innuendo or suggestive language (check: intent and audience)"
        ],
        escalationTriggers: [
            "Any content involving minors (immediate escalation)",
            "Repeated sexual comments after warning",
            "Targeting specific user with sexual content",
            "Links to pornographic sites"
        ],
        examples: PolicyExamples(
            clearViolations: [
                "[Explicit sexual descriptions or solicitations]",
                "[Sexualization of anyone, especially minors]",
                "Unwanted sexual comments or advances"
            ],
            borderline: [
                "\"What does the Bible say about intimacy in marriage?\" (acceptable if framed maturely)",
                "Innuendo that could be innocent or inappropriate (context matters)"
            ],
            acceptable: [
                "\"Struggling with purity, looking for accountability\"",
                "\"Biblical perspective on marriage and intimacy\""
            ]
        )
    )
    
    // MARK: - Self-Harm Policy
    
    static let selfHarmPolicy = PolicyDefinition(
        violation: .suicideEncouragement,
        allowed: [
            "Sharing struggles with mental health (for support)",
            "Offering hope, resources, crisis helplines",
            "Testimony of recovery from dark times",
            "Asking community for prayer during difficult season"
        ],
        notAllowed: [
            "Encouraging or glorifying self-harm or suicide",
            "Sharing methods or plans",
            "Suicide pacts or agreements",
            "Mocking or dismissing someone's suicidal ideation",
            "\"You should just do it\" type comments"
        ],
        grayAreas: [
            "Expressing suicidal ideation (needs compassionate response + resources, not removal)",
            "Dark humor about depression (context: coping mechanism vs encouragement)",
            "Discussion of past self-harm in recovery context (acceptable if focused on healing)"
        ],
        escalationTriggers: [
            "Specific plan or method mentioned",
            "Imminent risk language (\"tonight\", \"right now\")",
            "User has history of crisis posts",
            "Multiple concerning posts in short period"
        ],
        examples: PolicyExamples(
            clearViolations: [
                "\"Just end it already\"",
                "\"Here's how to do it...\"",
                "\"Suicide is the answer\""
            ],
            borderline: [
                "\"Sometimes I wish I could just disappear\" (concerning, needs support not removal)",
                "Dark depression memes (check: glorifying or coping?)"
            ],
            acceptable: [
                "\"I'm really struggling today. Please pray for me\"",
                "\"If you're having dark thoughts, here's the crisis line: [number]\""
            ]
        )
    )
    
    // MARK: - Policy Lookup
    
    static func getPolicy(for violation: PolicyViolation) -> PolicyDefinition? {
        switch violation {
        case .harassment, .targetedBullying:
            return harassmentPolicy
        case .hateSpeech:
            return hateSpeechPolicy
        case .threatOfViolence, .credibleThreat:
            return threatPolicy
        case .spam, .aiGeneratedSpam:
            return spamPolicy
        case .sexualContent, .sexualExploitation:
            return sexualContentPolicy
        case .suicideEncouragement:
            return selfHarmPolicy
        default:
            return nil
        }
    }
}

// MARK: - Context-Aware Policy Evaluation

/// Evaluates policy violations with context (user history, target, timing, etc.)
struct PolicyContext {
    let userId: String
    let targetUserId: String?
    let contentType: ContentCategory
    let previousViolations: [PolicyViolation]
    let recentActivityCount: Int  // How many posts/comments in last hour
    let isRepeatTarget: Bool       // Has user targeted this person before?
    let targetReportedUser: Bool   // Has target reported this user?
    let communityReports: Int      // How many users reported this content
    let createdAt: Date
    
    /// Should this violation be escalated based on context?
    func shouldEscalate(for violation: PolicyViolation) -> Bool {
        // Escalate if repeat offender
        if previousViolations.filter({ $0.severity >= .severe }).count >= 2 {
            return true
        }
        
        // Escalate if targeting same person repeatedly
        if isRepeatTarget && violation.severity >= .moderate {
            return true
        }
        
        // Escalate if target has reported this user
        if targetReportedUser && violation.severity >= .moderate {
            return true
        }
        
        // Escalate if multiple community reports
        if communityReports >= 3 {
            return true
        }
        
        // Escalate if high-frequency posting (potential spam campaign)
        if recentActivityCount > 20 {
            return true
        }
        
        return false
    }
    
    /// Get recommended enforcement action considering context
    func recommendedAction(for violation: PolicyViolation, confidence: Double) -> EnforcementAction {
        let baseSeverity = violation.severity
        let shouldEscalate = self.shouldEscalate(for: violation)
        
        // Critical violations always block
        if baseSeverity == .critical {
            return .blockAndEscalate
        }
        
        // Severe violations block or review
        if baseSeverity == .severe {
            return shouldEscalate ? .blockAndEscalate : .blockAndReview
        }
        
        // Moderate violations warn or block based on context
        if baseSeverity == .moderate {
            if shouldEscalate {
                return .blockAndReview
            } else if confidence > 0.85 {
                return .requireRevision
            } else {
                return .warnAndAllow
            }
        }
        
        // Light violations just nudge
        return .nudgeOnly
    }
}
