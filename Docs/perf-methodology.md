# AMEN — Performance Measurement Methodology (G-1 / PRE-8)

Created 2026-06-19 as remediation for the Performance Architecture Audit finding that every
performance target was a single unfalsifiable number (no percentile, device floor, or network
condition). **No performance target may be marked GREEN unless measured per this doc.**

## 1. Percentiles, not points
Report **P50, P95, and P99** for every runtime target. A target is met only if **P95** clears
it (use **P99** for launch and input/first-token latency). Single-sample numbers are not evidence.

## 2. Device floor
The oldest supported device is the measurement floor — **not** a flagship. Flagship-only numbers
are AMBER, never GREEN. Floor device: define and pin here when hardware is confirmed
(candidate: iPhone SE 3 / iPhone 11-class). The `CapabilityMonitor.deviceTier` table must be kept
current to this floor.

## 3. Network matrix
Every network-dependent target is measured across: **WiFi · LTE · slow-3G · offline · "lie-fi"
(high latency + loss)** via Network Link Conditioner. WiFi-only passes are AMBER.

## 4. Thermal & power states
Re-measure under `.serious` thermal state and Low Power Mode. Targets that collapse under
throttling are RED. (Prefetch now fails closed under both — see `FeedPrefetchService.shouldPrefetch`.)

## 5. Tooling
| Target | Tool |
|--------|------|
| Cold/warm launch (A-1/A-2) | MetricKit `MXAppLaunchMetric` + signpost |
| Scroll FPS / hitches (H-1/E-3) | Instruments Animation Hitches + `os_signpost` intervals |
| AI first token (I-1) | `os_signpost` interval request→first rendered token |
| Energy (G-5) | MetricKit energy payload + Energy Log |
| Hangs/ANR (G-9) | MetricKit `MXHangMetric` |
| Disk writes | MetricKit `MXDiskWriteExceptionDiagnostic` |
| Cache-hit rate (D-1) | per-layer counters surfaced to telemetry |

## 6. Per-target table (fill as measured)
| ID | Target | P50 | P95 | P99 | Floor device | Network | Thermal/Power | Verdict |
|----|--------|-----|-----|-----|--------------|---------|---------------|---------|
| A-1 cold launch | <1s | | | | | | | |
| A-2 warm content | <100ms | | | | | | | |
| H-1 scroll | 120fps | | | | | | | |
| I-1 AI first token | <300ms | | | | | | | |
| J-1 search suggest | <50ms | | | | | | | |
| G-5 energy | (ceiling TBD) | | | | | | | |

## 7. CI gate (G-8 — not yet wired)
Add `XCTApplicationLaunchMetric` + scroll/memory `measure(metrics:)` tests with committed
baselines; a CI job fails the PR on regression. Tracked as a follow-up (needs target membership
on the build lock).
