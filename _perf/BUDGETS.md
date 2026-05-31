# _perf/BUDGETS.md — Performance Budgets

These are the yardsticks. Any finding that risks breaching a budget is flagged HIGH.

| Metric | Budget | Notes |
|---|---|---|
| Cold launch → first frame | ≤ 1.0s | App.init + FirebaseConfigure + first SwiftUI render |
| Cold launch → interactive | ≤ 2.0s | Auth resolve + initial data load |
| Tap → screen visible | ≤ 300ms | Content can stream after |
| Sheet / compose open | ≤ 250ms | No data fetch on present |
| Scroll frame time | ≤ 16ms (60fps) / ≤ 8ms (120fps ProMotion) | No burst drops |
| Berean AI first token | ≤ 1.5s | SSE first token from CF |
| Berean AI cancel | Instant | Task must be cancellable |
| Create-post flow (optimistic) | Feels instant | No blocking main-thread spinner |
| Main-thread block per frame | ≤ 16ms | Any sync work > this = jank |
| Firestore unbounded read | Flag any | Must have `.limit()` |
| Image decode on main thread | Zero | All decode off-main |
| Duplicate network/listener calls on re-appear | Zero | Guard with isLoaded / task tracking |
