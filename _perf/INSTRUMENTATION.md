# _perf/INSTRUMENTATION.md — Signpost Instrumentation Guide

## How to read in Instruments
1. Product → Profile → Instruments → Time Profiler or "Blank" template
2. Add **Points of Interest** instrument
3. Filter by subsystem: `com.amen.app`, category: `Performance`
4. Each `PerformanceLog.begin/end` pair shows as a named interval in the track
5. Look for long intervals → drill down in Time Profiler call tree

## Existing signposts (pre-perf-pass)
- `app_init` — AMENAPPApp.init() total duration
- See PerformanceHUD.swift for full list

## New signposts added this pass
(populated by Phase 1.5 agent)

## How to use Console.app
- Filter: subsystem = `com.amen.app`
- Look for `[Performance]` category lines
- Timestamps give wall-clock durations between begin/end pairs
