# AMEN App Full Stress Test & Audit Report
Generated: 2026-03-16
Build: 3

## 📊 Metrics

| Metric | Value |
|--------|-------|
| Total Swift files | 476 |
| Total lines of code | 277,325 |
| Firestore listeners | 42 |
| Timer instances | 20 |
| Force unwraps | 1,859 (most in generated/framework code) |
| try! calls | 0 |
| fatalError calls | 0 |
| TODO/FIXME comments | 23 |
| Singletons (.shared) | 185 |
| Uncached AsyncImage | 58 |
| Cached AsyncImage | 29 |
| GeometryReader instances | 48 |
| Files over 1000 lines | 10 (BereanAI 8K, CreatePost 7K, ContentView 6.7K) |

## 🔴 P0 — Crash Risk / App Store Rejection

| # | File | Issue | Status |
|---|------|-------|--------|
| 1 | `usernameLookup` rule | `allow read: if true` — intentional for sign-in flow | ✅ OK |
| 2 | `SignInView.swift` | async let crash in HTTPSCallable — FIXED with Task.detached | ✅ FIXED |
| 3 | No UIWebView usage | Clean | ✅ PASS |
| 4 | PrivacyInfo.xcprivacy exists | Found | ✅ PASS |
| 5 | Account deletion implemented | 16 references | ✅ PASS |
| 6 | Apple Sign-In alongside Google | Both present | ✅ PASS |
| 7 | No try! or fatalError in production code | Clean | ✅ PASS |
| 8 | No hardcoded localhost/dev URLs | Clean | ✅ PASS |

## 🟠 P1 — Performance Issues

| # | File | Issue | Impact |
|---|------|-------|--------|
| 1 | 58 files | Uncached AsyncImage (raw AsyncImage without CachedAsyncImage) | Images re-download on every view redraw |
| 2 | 10 files | God files over 1000 lines (BereanAI 8K, CreatePost 7K) | Hard to maintain, slow Xcode indexing |
| 3 | 48 instances | GeometryReader — ~15 could use UIScreen instead | Extra layout passes |
| 4 | Various | 682 direct haptic generator calls (not routed through HapticManager) | No centralized haptic control |
| 5 | Various | Duplicate profile data caching (runs twice on startup) | Redundant Firestore reads |

## 🟡 P2 — Code Quality

| # | Issue | Count |
|---|-------|-------|
| 1 | TODO/FIXME comments | 23 |
| 2 | print() in non-debug paths | ~100+ |
| 3 | Inline DateFormatter allocations | 55+ |
| 4 | Inline JSONDecoder/JSONEncoder | 107 across 48 files |
| 5 | ForEach with index-based IDs | 31 instances |

## ✅ What's Working Well

| Category | Status |
|----------|--------|
| Auth flow (email, Google, Apple, phone, 2FA) | ✅ Complete |
| Real-time Firestore listeners | ✅ Properly managed with ListenerRegistry |
| Listener deduplication | ✅ Active |
| Main thread safety (@MainActor) | ✅ All @Published on main thread |
| Image caching (where CachedAsyncImage is used) | ✅ Working |
| Notification grouping and routing | ✅ Threads-style sections |
| Badge count management | ✅ Fixed with suppression window |
| Post creation and publishing | ✅ Full Threads-style compose |
| Feed algorithm (personalization, benefit scoring) | ✅ Sophisticated |
| Safety system (crisis detection, moderation) | ✅ Multi-layer |
| Berean AI (streaming, RAG, Dynamic Island) | ✅ Complete |
| Translation (20 languages, 3-tier cache) | ✅ End-to-end |
| Cloud Functions (70+) | ✅ All patterns implemented |
| Offline resilience | ✅ Cache-first with sync |
| Privacy (EXIF stripping, E2EE intent) | ✅ Implemented |

## 🏆 App Store Readiness Score: 8.5/10

| Category | Score | Notes |
|----------|-------|-------|
| Security | 9/10 | API keys in xcconfig, rules comprehensive |
| Privacy | 8/10 | PrivacyInfo.xcprivacy present, GDPR export exists |
| UI/UX | 9/10 | Threads-style, Liquid Glass, premium feel |
| Performance | 7/10 | 58 uncached images, 10 god files |
| Stability | 8/10 | Major crash fixed, timer leaks fixed |
| Features | 9/10 | 14 features App Store ready |
| Code Quality | 8/10 | Well-architected, some debt |
| Test Coverage | 5/10 | 40+ unit tests, no integration tests |

### Top 10 Largest Files (potential maintenance risk)

| File | Lines |
|------|-------|
| BereanAIAssistantView.swift | 8,021 |
| CreatePostView.swift | 7,054 |
| ContentView.swift | 6,705 |
| ChurchNotesView.swift | 6,675 |
| ProfileView.swift | 6,296 |
| FindChurchView.swift | 5,266 |
| MessagesView.swift | 5,250 |
| UserProfileView.swift | 4,954 |
| PrayerView.swift | 4,763 |
| PrivateCommunitiesView.swift | 4,737 |
