# GAP_BOARD.md

| Gap | Evidence | Severity | Owner | Fix Size |
|---|---|---|---|
| Mock data use in production services | DiscoverFeedService.swift:103-357 | P1 | Content Team | L |
| Missing reachability path for Berean OS | BereanOS/BereanHubView.swift | P1 | Berean Team | M |
| Unresolved package dependencies (blocker) | SourcePackages/checkouts/ | P0 | Build Engineering | M |
| Untracked junk files ("* 2.swift") | Multiple locations | P2 | Platform | S |
| XCTest in app target | AMENAPP/ContextStore/ContextStoreAdversarialTests.swift | P1 | Platform | S |
| Missing AIL/caption support in Media views | AmenMediaDetailView.swift | P2 | Media Team | M |
| Client-side privacy level validation gap | firestore.rules | P0 | Security | L |
| Missing automated tests for Action Intelligence | AMENAPPTests/ActionIntelligenceDetectorTests.swift (stubs) | P1 | Intelligence Team | M |
| Hard-coded placeholders in UI | MusicContentLayer/MusicAttachmentPickerView.swift | P2 | Design/UI | S |
| Potential raw PII in opportunity fields | firestore.rules (I-5 reference) | P0 | Security | S |

## P0 LIST (Action Required)
1. Unresolved package dependencies causing build failures (SourcePackages saga).
2. XCTest usage in app target causing compilation errors.
3. Client-side privacy level validation gap in firestore.rules.
4. Potential raw PII in volunteerOpportunity fields.
