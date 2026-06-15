# DISCOVERY_TELEMETRY.md
# AMEN Connect Discovery Engine — Formation-Aligned Event Taxonomy

Wave 0 FROZEN: 2026-06-14

## Philosophy

Telemetry is for understanding **formation** (spiritual growth, community health), 
not for optimizing engagement. **Engagement-maximizing metrics are explicitly forbidden.**

---

## Instrumented Events

| Event Name                  | Trigger                                                        | Properties |
|-----------------------------|----------------------------------------------------------------|------------|
| `discovery_feed_shown`      | Discovery tab opens, feed renders from CF                      | `shelfCount`, `heroPresent`, `feedToken`, `calmCapMaxShelves` |
| `card_opened`               | User taps a DiscoveryCard                                      | `cardType`, `shelfKind`, `reasonKind`, `safetyStampClearedBy`, `position` |
| `pill_selected`             | Category pill tapped (re-queries server)                       | `categoryId`, `previousCategory` |
| `search_intent`             | User types in search field (fires once per session, not per keystroke) | `hasQuery: Bool`, `resultCount` |
| `calmcap_reached`           | Feed bottom reached, soft-limit nudge shown                    | `sessionDurationSeconds`, `shelvesSeen`, `cardsOpened` |
| `why_shown_viewed`          | User long-presses card and views WhyShown explanation          | `cardType`, `reasonKind` |
| `preview_opened`            | Long-press preview sheet appears                               | `cardType`, `shelfKind` |
| `hero_collapsed`            | Hero compresses to floating pill (scroll threshold crossed)    | `heroCardType` |
| `hero_expanded`             | User taps floating pill to re-expand hero                      | — |
| `search_result_opened`      | User selects a search match                                    | `cardType`, `matchPosition`, `queryLength` |

---

## Explicitly NOT Instrumented (anti-doomscroll guard)

The following metrics MUST NOT be added without a product owner override and documented justification:

- Dwell time per card (time-on-content)
- Scroll depth as an optimization signal
- Click-through rate as a ranking input
- Engagement velocity (likes/shares/comments per session)
- Return rate or DAU/WAU for feed optimization
- Any metric fed back into `FORMATION_WEIGHTS` without explicit product review

---

## Privacy Staging

All events go through `AmenAnalyticsService` privacy staging before transmission:
- No PII in event properties
- No user IDs in event properties (Firebase Analytics adds user context separately)
- Content IDs (cardId, shelfId) are hashed before transmission to analytics
- Events honor ATT/privacy consent state; if consent is absent, events are dropped

---

## Implementation Reference

```swift
// Log via AmenAnalyticsService (privacy-staged, not direct Analytics calls)
AmenAnalyticsService.shared.log(.discoveryFeedShown(shelfCount: feed.shelves.count))
AmenAnalyticsService.shared.log(.cardOpened(card: card, shelfKind: shelf.kind))
AmenAnalyticsService.shared.log(.calmCapReached(sessionDuration: elapsed, shelvesSeen: count))
```
