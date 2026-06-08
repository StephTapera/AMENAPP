# AMEN iOS App — Frozen Contract Definitions

**Purpose:** Canonical type definitions for cross-platform consistency  
**Locked:** YES (C5 phase 4 production)  
**Last Updated:** 2026-06-07  

---

## CapabilityTier Enum

**File:** `BereanFaithOSContracts.swift:11`

```swift
enum BereanCapabilityTier: String, Codable, CaseIterable, Comparable {
    case free = "FREE"
    case plus = "PLUS"
    case pro  = "PRO"
    
    var displayName: String {
        switch self { 
        case .free: return "Free"
        case .plus: return "Amen+"
        case .pro: return "Amen Pro"
        }
    }
}
```

**Ordering:** FREE < PLUS < PRO (via Comparable)  
**Used In:** 
- Berean OSagent access (minimumTier per Kind)
- Formation card access
- Spaces features (founding member = highest tier)

---

## Domain Enum (MISSING)

**Status:** ❌ NOT FOUND in Swift source during audit

**Expected Definition (from contracts spec):**
```swift
enum Domain: String, Codable, CaseIterable {
    case personal
    case professional
    case spiritual
    case community
    case health
    case relationships
    case growth
    case creativity
    case service
    case faith
    case family
    case learning
    case wellness
    case purpose
}
```

**Expected Count:** 14 values  
**Location:** Should be in TrustOS or Berean contracts file (VERIFY)

---

## Provenance Struct (Version: ONEProvenanceLabel)

**File:** `ONEProvenanceModels.swift:9`

```swift
struct ONEProvenanceLabel: Codable, Sendable {
    let classification: ONEProvenanceClass
    let confidence: Float          // 0.0–1.0; < 0.70 → .unknown
    let c2paPayload: Data?         // C2PA attestation (optional)
    let attestedAt: Date?
    let processorNote: String?     // e.g., "Adobe Firefly"
    
    var displayClassification: ONEProvenanceClass {
        confidence >= 0.70 ? classification : .unknown
    }
}

enum ONEProvenanceClass: String, Codable, Sendable {
    case captured    // Direct camera capture, no edits
    case edited      // Filters, crop, color grading
    case aiAssisted  // Generative inpainting, upscale, enhancement
    case synthetic   // Fully AI-generated
    case unknown     // Insufficient signal (safe default)
}
```

**TruthLevel Field:** Via confidence (0.0–1.0)  
**Safe Default:** .unknown (when confidence < 0.70)  
**C2PA Integration:** Optional (degrade gracefully)

---

## TrustProfile Struct (Version: UserTrustProfile)

**File:** `ModerationConstitutionModels.swift:line TBD`

```swift
struct UserTrustProfile: Identifiable, Codable {
    let id: String  // uid
    let uid: String
    
    // Trust metrics (0.0–1.0 scale)
    var contentTrustScore: Float    // Credibility of user's posts
    var communityTrustScore: Float  // Respect in community
    var safetyTrustScore: Float     // Compliance with safety rules
    var overallTrustScore: Float    // Weighted average
    
    // Signals
    var trustSignals: [String]      // List of positive trust indicators
    var riskSignals: [String]       // List of risk indicators
    var strikes: Int                // Enforcement strikes (3 = ban)
    var isAccountActive: Bool       // Not suspended/deactivated
    var isBanned: Bool              // Permanent ban
    
    // Audit trail
    let createdAt: Date
    var lastUpdatedAt: Date
    var lastReviewedBy: String?     // Moderator uid if human review
}
```

**Owner Field:** uid (user's own profile is owner-only readable)  
**Computed Field:** overallTrustScore (weighted from 3 component scores)  
**Strike System:** 3 strikes = account ban (after appeals period)

---

## Formation Card Kind Enum

**File:** `BereanFaithOSContracts.swift:189`

```swift
enum FormationCardKind: String, Codable, CaseIterable {
    case scripture  = "SCRIPTURE"
    case reflection = "REFLECTION"
    case prayer     = "PRAYER"
    case habit      = "HABIT"
    case challenge  = "CHALLENGE"
    case testimony  = "TESTIMONY"
    case crisis     = "CRISIS"
    
    var allowsAIReflection: Bool { self != .crisis }
}
```

**Critical Invariant:** .crisis cards NEVER trigger AI reflection  
**Enforced In:** formationGovernor.js, BereanFormationCardViews.swift

---

## Memory Node Kind Enum

**File:** `BereanFaithOSContracts.swift:40`

```swift
enum BereanMemoryNode.Kind: String, Codable, CaseIterable {
    case prayer     = "PRAYER"
    case study      = "STUDY"
    case attendance = "ATTENDANCE"
    case note       = "NOTE"
    case teacher    = "TEACHER"
    case topic      = "TOPIC"
    case goal       = "GOAL"
    case milestone  = "MILESTONE"
    case person     = "PERSON"
    case formation  = "FORMATION"
    case mentorship = "MENTORSHIP"
}

enum Sensitivity: String, Codable {
    case normal    = "NORMAL"
    case sensitive = "SENSITIVE"
}
```

**Storage:** users/{uid}/memoryGraph/{nodeId}  
**Immutability:** Nodes are append-only (update = false in rules)

---

## Workspace Kind Enum

**File:** `BereanFaithOSContracts.swift:85`

```swift
enum BereanWorkspaceModel.Kind: String, Codable, CaseIterable {
    case study      = "STUDY"
    case theology   = "THEOLOGY"
    case leadership = "LEADERSHIP"
    case marriage   = "MARRIAGE"
    case custom     = "CUSTOM"
    case formation  = "FORMATION"
    case mentorship = "MENTORSHIP"
    
    var displayName: String { ... }
    var systemImage: String { ... }
}
```

---

## Agent Kind Enum

**File:** `BereanFaithOSContracts.swift:123`

```swift
enum BereanAgentModel.Kind: String, Codable, CaseIterable {
    case prayer    = "PRAYER"
    case study     = "STUDY"
    case church    = "CHURCH"
    case mentor    = "MENTOR"
    case formation = "FORMATION"
    
    var minimumTier: BereanCapabilityTier {
        switch self {
        case .prayer, .study, .formation: return .free
        case .church, .mentor: return .plus
        }
    }
}
```

**Tier Gating:** Restricts agent access by subscription level

---

## Artifact Kind Enum

**File:** `BereanFaithOSContracts.swift:149`

```swift
enum BereanArtifactModel.Kind: String, Codable, CaseIterable {
    case studyGuide       = "STUDY_GUIDE"
    case prayerPlan       = "PRAYER_PLAN"
    case eventPlan        = "EVENT_PLAN"
    case leadershipNotes  = "LEADERSHIP_NOTES"
    case discipleshipPlan = "DISCIPLESHIP_PLAN"
    case formationPlan    = "FORMATION_PLAN"
    case mentorshipPlan   = "MENTORSHIP_PLAN"
}
```

---

## ONE Provenance Class Enum

**File:** `ONEProvenanceModels.swift:31`

```swift
enum ONEProvenanceClass: String, Codable, Sendable {
    case captured    // Direct camera, no edits
    case edited      // Filters, crop, color grading
    case aiAssisted  // Generative inpainting, upscale
    case synthetic   // Fully AI-generated
    case unknown     // Insufficient signal
}
```

**Display Labels:** Human-readable text for UI  
**Icons:** SF Symbol name for each class  
**Accessibility Labels:** Full description for VoiceOver

---

## ONE Feed Mode Enum

**File:** `ONEProvenanceModels.swift:95`

```swift
enum ONEFeedModeKind: String, Codable, Sendable, CaseIterable {
    case close   // Close friends + witnesses only
    case create  // Creator drops + collaborative content
    case learn   // Long-form, articles, scripture study
    case local   // Geo-adjacent community
    case quiet   // Curated slow feed; no video; low-motion
    
    var defaultSessionBudget: Int {
        switch self {
        case .close:  return 20
        case .create: return 15
        case .learn:  return 10
        case .local:  return 25
        case .quiet:  return 8
        }
    }
    
    var allowsVideo: Bool { self != .quiet }
    var allowsAutoplay: Bool { false }  // Always off by default
}
```

**Session Budget:** Items user can scroll per session  
**Quiet Mode:** Accessibility-focused (low motion, no autoplay)

---

## ProvenanceStatus Enum (True Source)

**File:** `TrueSourceModels.swift`

```swift
enum ProvenanceStatus: String, Codable, CaseIterable {
    case original       = "original"
    case repost         = "repost"
    case edited         = "edited"
    case aiGenerated    = "ai_generated"
    case unknown        = "unknown"
}
```

**Tracked On:** Posts/prayers (original author vs repost metadata)

---

## Moderation Enforcement Actions

**File:** `ModerationConstitutionModels.swift:70`

```swift
enum EnforcementActionType: String, Codable, CaseIterable {
    case allow                          // Level 0 — clean
    case nudge                          // Level 1 — soft prompt
    case requireEdit                    // Level 2 — block submit until edited
    case holdReview                     // Level 3 — pending human review
    case shadowRestrict                 // Level 4 — visible to author only
    case removePermanent                // Level 5 — removed
    case strikeIssued
    case accountCooldown                // Temp posting ban
    case accountFreeze                  // Temp suspension
    case accountBan                     // Permanent ban
}
```

**Enforcement Ladder:** 0–5 scale (0=allow, 5=remove)  
**Account Penalties:** Escalate to suspension/ban at higher strikes

---

## Age Tier Enum

**Derived From:** Firestore rules token.ageTier  
**File:** `MinorSafetyService.swift` (inferred from rules)

```swift
enum AgeTier: String, Codable {
    case adult = "adult"
    case teen = "teen"              // 13-17 (US COPPA)
    case under_minimum = "under_minimum"  // < 13, completely blocked
}
```

**Gating Logic:**
- under_minimum: Cannot create content, cannot DM, cannot join spaces
- teen: Private by default, public requires confirmation, no jobs, mutual-follow DM gate
- adult: Full access

---

## Comparison & Validation

**Stability:** All enums use String rawValue for Codable serialization (JSON-safe)  
**Ordering:** Comparable implemented where needed (CapabilityTier, TrustScore float ranges)  
**Extension:** CaseIterable used for listing all values (UI dropdowns, migration)  
**Sendable:** ONEProvenanceLabel and models marked Sendable for async/await

---

## Summary

| Contract | Type | Count | File | Status |
|----------|------|-------|------|--------|
| CapabilityTier | Enum | 3 values | BereanFaithOSContracts.swift | ✅ Frozen |
| Domain | Enum | 14 values | ❌ NOT FOUND | ⚠️ Verify |
| ONEProvenanceClass | Enum | 5 values | ONEProvenanceModels.swift | ✅ Frozen |
| TrustProfile | Struct | - | ModerationConstitutionModels.swift | ✅ Frozen |
| FormationCardKind | Enum | 7 values | BereanFaithOSContracts.swift | ✅ Frozen (crisis invariant) |
| MemoryNode.Kind | Enum | 11 values | BereanFaithOSContracts.swift | ✅ Frozen |
| EnforcementAction | Enum | 10 values | ModerationConstitutionModels.swift | ✅ Frozen |
| AgeTier | Enum | 3 values | (rules-derived) | ✅ Frozen |

**UNRESOLVED:** Domain enum (14 values) — must be located in production code

