# _perf/LOG.md — Performance Pass Execution Log
## Branch: overnight/perf-pass-20260531
## Started: 2026-05-31

---

## BUILD COMMAND
```
xcodebuild \
  -project AMENAPP.xcodeproj \
  -scheme AMENAPP \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  | tail -20
```
Fast typecheck only (no full build — use XcodeRefreshCodeIssuesInFile for single files):
```
xcodebuild ... build-for-testing CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

---

## EXISTING PERF INFRASTRUCTURE (catalogued at SETUP)

| Asset | File | Notes |
|---|---|---|
| `PerformanceLog` (os_signpost) | `AMENAPP/PerformanceHUD.swift` | `OSLog` subsystem `com.amen.app`, category `"Performance"`. `.begin`/`.end`/`.event`. Used via `PerfBegin`/`PerfEnd` tokens in AMENAPPApp. Visible in Instruments → Points of Interest track. **EXTEND THIS — do not duplicate.** |
| `PerformanceHUD` | `AMENAPP/PerformanceHUD.swift` | Dev-only overlay; live memory, FPS, listener counts. Already attached. |
| `AMENLogger` | `AMENAPP/AMENLogger.swift` | Leveled logger with PII redaction. Use for observability, not perf. |
| `ImageCache` | `AMENAPP/ImageCache.swift` | NSCache (150 images / 75MB), URLCache-backed URLSession, dedup in-flight tasks, background resize queue. **Primary image cache — reuse.** |
| `ProfileImageCache` | `AMENAPP/ProfileImageCache.swift` | Separate NSCache for profile pics. Possibly redundant with ImageCache. |
| `NotificationImageCache` | `AMENAPP/NotificationImageCache.swift` | Third cache. |
| `CachedAsyncImage` | `AMENAPP/CachedAsyncImage.swift` | SwiftUI wrapper using ImageCache. |
| `CacheManager` | `AMENAPP/CacheManager.swift` | General-purpose cache manager. |
| `APIResponseCache` | `AMENAPP/APIResponseCache.swift` | Response-level cache. |
| `TranslationCacheManager` | `AMENAPP/TranslationCacheManager.swift` | Translation output cache. |
| `FeedPrefetchService` | `AMENAPP/FeedPrefetchService.swift` | Pre-fetches next 10 posts when within 5 of end. |

## SCALE MARKERS
- **316 files** with Firestore listeners / Combine sinks
- **802 files** with `onAppear`/`.task`
- **1354 files** with VStack (vs **331** with LazyVStack — large lazy-ification opportunity)

---

## TIMELINE

| Time | Action | Result |
|---|---|---|
| 06:45 | SETUP: stash dirty state, create branch overnight/perf-pass-20260531 | OK |
| 06:46 | Discovered build command (xcodebuild -scheme AMENAPP) | OK |
| 06:46 | Catalogued perf infrastructure | OK |
| 06:47 | Wrote _perf/ scaffold files | OK |
| 06:47 | Launched Phase 0 + Phase 1 parallel agents | RUNNING |

