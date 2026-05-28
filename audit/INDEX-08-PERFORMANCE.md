# Performance, Reliability & Crashes Audit — Quick Index

**Run Date:** 2026-05-27  
**Auditor:** Performance & Reliability Specialist  
**Scope:** AI-touching code (Berean Chat, Prayer Room, Moderation, Memory Services)

---

## Quick Navigation

| Document | Purpose | Read Time |
|----------|---------|-----------|
| **08-performance-crashes.md** | Full audit report with detailed findings, code citations, and recommendations | 30 min |
| **FINDINGS_SUMMARY.txt** | Executive summary with prioritized backlog | 5 min |
| **AUDIT_CHECKLIST.txt** | Completion checklist and statistics | 5 min |

---

## Key Findings at a Glance

### Critical Issues
1. **F-perf-001** — Message array grows unbounded (HIGH, CONFIRMED)
   - File: BereanChatView.swift:115-116, 328, 463
   - Impact: Memory leak for 50+ message conversations
   - Fix: Implement message windowing

2. **F-perf-002** — BiblicalAlignment blocking UI (MEDIUM, CONFIRMED)
   - File: BereanChatView.swift:477-495
   - Impact: 300-800ms stall after response
   - Fix: Move to background Task

3. **F-perf-004** — Preflight latency hidden (MEDIUM, CONFIRMED)
   - File: ClaudeService.swift:502-572
   - Impact: First-token latency misreported (real: 600-1200ms, reported: 200-400ms)
   - Fix: Add separate instrumentation

### Medium Issues
4. **F-perf-003** — ChatMemoryService listener leak (MEDIUM, SUSPECTED)
5. **F-perf-005** — String concat O(n²) (LOW, CONFIRMED)
6. **F-perf-006** — Cross-session history requery (MEDIUM, CONFIRMED)
7. **F-perf-007** — WebSocket backpressure (MEDIUM, CONFIRMED)
8. **F-perf-008** — Model router not cached (LOW, CONFIRMED)

---

## Latency Summary

| Operation | Target | Observed | Status |
|-----------|--------|----------|--------|
| First-token (real) | <800ms | 600-1200ms | ⚠️ Misreported |
| Complete response | <5s | 3-6s | ✓ Met |
| Preflight | <1.5s | 500-1500ms | ⚠️ Marginal |

---

## Priority Action Items

**Next Sprint (P0 - Immediate):**
- [ ] Implement message windowing + auto-trim (F-perf-001)
- [ ] Add preflight latency instrumentation (F-perf-004)
- [ ] Move BiblicalAlignment to background Task (F-perf-002)
- [ ] Add stopObserving() to chat view lifecycle (F-perf-003)

**Next 2 Sprints (P1-P2 - Short-term):**
- [ ] Cache cross-session history (F-perf-006)
- [ ] Batch SSE chunks before UI update (F-perf-005)
- [ ] Add offline mode to ClaudeService (F-perf-006)

**Next 4+ Sprints (P3-P4 - Long-term):**
- [ ] Add backpressure flow control (F-perf-007)
- [ ] Memory profiling test suite
- [ ] Message pagination UI

---

## Compliance Status

| Area | Status | Notes |
|------|--------|-------|
| @MainActor | ✓ Good | All AI ViewModels properly isolated |
| Capture cycles | ✓ Good | [weak self] used correctly |
| Force unwraps | ✓ Good | None in critical hot paths |
| Memory safety | ⚠️ Issues | Unbounded message array (F-perf-001) |
| Offline support | ⚠️ Gaps | No offline mode in ClaudeService |
| Instrumentation | ⚠️ Gaps | Preflight latency hidden |

---

## Memory Profile

**100-message conversation:** 150-200 MB worst case  
**Image cache:** 150 images × 75 MB limit (good)  
**Streaming peaks:** 2-5 MB per response  

→ Approaching SwiftUI list memory budget (250-300 MB before jank)

---

## Report Structure

### Main Report (08-performance-crashes.md)

1. **Executive Summary** — Overview and critical findings
2. **Inventory** — Services, ViewModels, and Cloud Functions scanned
3. **Findings (F-perf-001 through F-perf-008)** — Detailed analysis with code citations
4. **@MainActor Compliance Table** — Coverage across all AI-touching code
5. **Crash Hypotheses** — Validation of common crash patterns
6. **Latency Targets Table** — Measured vs. target performance
7. **Streaming Throughput** — Token/sec and UI batching strategy
8. **Network Reachability** — Offline behavior and gaps
9. **Memory Lifecycle** — Long conversation analysis
10. **Cold-Start Impact** — Initialization chain analysis
11. **Open Questions** — Items needing product input
12. **Optimization Backlog** — Prioritized action items

---

## Code Files Audited

**Core Chat:**
- BereanChatView.swift (message accumulation, streaming)
- ClaudeService.swift (SSE client, latency logging)
- BereanAPIClient.swift (preflight, moderation)

**Memory & Realtime:**
- BereanMemoryService.swift (cross-session context)
- BereanRealtimeWebSocketTransport.swift (WebSocket)
- BereanRealtimeSessionManager.swift (realtime coordination)

**Infrastructure:**
- ImageCache.swift (image caching with deduplication)
- FirebaseOfflineHelper.swift (offline fallback + queuing)
- AmenAIModelRouter.swift (routing decisions)

---

## Questions for Product/Engineering

1. What is typical conversation length for power users? (Impacts F-perf-001)
2. Is BiblicalAlignment blocking UI intentional? (Impacts F-perf-002)
3. What is first-token latency target? (600-1200ms vs 800ms goal)
4. Do users expect offline chat? (Offline caching feature)
5. How often does app hit memory warning? (F-perf-001 severity)

---

## How to Use This Audit

**For Engineering Leads:**
1. Read FINDINGS_SUMMARY.txt (5 min)
2. Prioritize P0 items in next sprint planning
3. Reference 08-performance-crashes.md for implementation details

**For Performance Optimization Team:**
1. Review Optimization Backlog section in main report
2. Use code citations to understand root causes
3. Implement P0 fixes first (message windowing, latency instrumentation)

**For QA/Testing:**
1. Create test case for 200+ message conversation
2. Monitor memory pressure and Firestore listener count
3. Verify preflight + streaming latency end-to-end

---

## Revision History

| Date | Version | Changes |
|------|---------|---------|
| 2026-05-27 | 1.0 | Initial comprehensive audit |

---

Generated: 2026-05-27  
Files: 08-performance-crashes.md, FINDINGS_SUMMARY.txt, AUDIT_CHECKLIST.txt
