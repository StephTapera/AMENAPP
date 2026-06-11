# Total Control Wiring — FLEET CERTIFICATION TEMPLATE
**Required structure for every lane's surface certification (ratified 2026-06-10).**

No interactive control ships dead. Each lane certifies **its own** surfaces in the exact shape below;
ownerless surfaces are claimed + certified by the fix orchestrator. The cert is filed with the lane's
DONE and gates the finish line: *"green, built, safe, committed end-to-end"* means it compiles, it's
committed, AND every control does what it says — or honestly says it doesn't.

## The rule (per control — exactly one disposition)
- **WIRED** — the tap reaches its real service / route / callable, end-to-end (not a toast, not a no-op sheet).
- **fail-closed** — visibly disabled/hidden with a reason the user can perceive (flag off, unrouted deeplink,
  pending provider). Never an enabled control that silently does nothing.
- **INERT-BY-DESIGN** — intentionally non-interactive (e.g. `allowsHitTesting(false)`); declared so it isn't
  mistaken for a dead control.
- **FIXED** — was a dead/inert P1, now WIRED or fail-closed (note what changed).
- **REMOVED** — the promised feature doesn't exist and isn't queued → the control is deleted.

> An enabled, tappable, inert control is a **P1 defect by definition** ("the feature lies to the user").

## Required table shape
| Surface | Control | Destination / action | Disposition | Screenshot (pending green) |
|---|---|---|---|---|
| <View> | <button/gesture/toggle> | → <service / route / callable> | WIRED / fail-closed / INERT-BY-DESIGN / FIXED / REMOVED | <MCP screenshot or test ref, or "OWED @ green"> |

Plus a **fresh sweep on the green build**: grep for empty closures in `Button`/`onTapGesture`/`.onSubmit`,
`NotificationCenter` posts with zero observers, `UIApplication.open` to schemes no router resolves, and handlers
ending in `print`/`TODO` only — each gets a disposition above.

## Scope (currency table)
Feeds, composers, capsules, Pulse cards, Settings rows, Church Notes actions, NoteShare sheet, Resources tiles,
ConnectSpaces, ObjectHub, AIL pills, onboarding CTAs — every surface. Inputs: GAP_BOARD A1 (dead surfaces, empty
actions, unobserved posts) + A2 (void handlers, deep-link dead-ends, orphaned views) rows + the green-build sweep.

---

## Reference implementation — Amen Pulse (the pattern to copy)
Pulse pills = **deeplink-or-disabled, fail-closed, dead-broadcast removed.** Screenshot column OWED @ green.

| Surface | Control | Destination / action | Disposition |
|---|---|---|---|
| AmenPulseSurface | What's New / Customize | → WhatsNewArchiveView / PulsePrefsView | WIRED |
| | Filter chips ×5 / Try Again | → viewModel.chip / viewModel.load() | WIRED |
| | Card tap / backdrop tap | → expand / close() | WIRED |
| | Sabbath card | none | INERT-BY-DESIGN (`allowsHitTesting(false)`) |
| PulseHeroCard | Card tap | → onOpen (expand) | WIRED |
| PulseExpandedCard | Close / brief 30s·3m·10m / What's-New btn | dismiss / filter / open story | WIRED |
| | Primary action pill | → DeepLinkRouter | WIRED + **fail-closed** (hidden unless `canRoute`) |
| WhatsNewStory | Close / swipe / Bookmark | dismiss / page / setBookmark (Firestore) | WIRED |
| | Try It | → DeepLinkRouter | **FIXED** — routes amen://, hidden when unrouted (was raw open on dead schemes) |
| WhatsNewArchive | Close / story tap | dismiss / open story | WIRED |
| PulsePrefs | Done / style / interests / sources / cap | → save() (Firestore) | WIRED |

Card verbs (Pray/RSVP/Send Love/Open Space/Watch) → deeplink → DeepLinkRouter (WIRED); item-level push for
`space`/`event` dispatched to those lanes. Commits: 5227689d, 8dcc9264, ee2e205e.
