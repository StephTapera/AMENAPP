# Sanctuary Wave 0 Preflight Blocker

Date: 2026-06-12  
Lane: W0 Architect / Amendment A pre-flight

## Blocker

The required shell gate `xcodebuild -scheme AMENAPP build` cannot complete in the current Codex shell sandbox before source compilation.

## Verification Completed

- `sanctuary-w0-frozen` resolves to `34c6e92b`.
- `AMENAPP/Shared/Contracts/SanctuaryModels.swift` is present at the tagged commit and contains the required frozen models: `LivingVideo`, `ScriptureAnchor`, `VideoLayer`, `SacredReaction`, `WatchRoom`, `SelahCard`, and `JourneyNode`.
- `AMENAPP/Docs/Contracts/Sanctuary/sanctuary.types.ts` is present at the tagged commit and matches the stored Swift fields. Swift-only computed `id` properties on `ScriptureAnchor` and `SacredReaction` are not stored fields.
- `AMENAPP/Docs/Contracts/Sanctuary/firestore-schema.md` is present at the tagged commit and includes the required collections and a security rules sketch.

## Attempts

1. `xcodebuild -scheme AMENAPP build`
   - Failed before compilation.
   - Errors included inability to write `workspace-state.json` under DerivedData `SourcePackages`, inability to write SwiftPM `.dia` diagnostics under `~/Library/Caches/org.swift.swiftpm`, and CoreSimulator service connection failures.

2. `xcodebuild -scheme AMENAPP -derivedDataPath /private/tmp/amen-derived -clonedSourcePackagesDirPath /private/tmp/amen-sourcepackages build` with `SWIFTPM_MODULECACHE_PATH=/private/tmp/amen-swiftpm-cache`
   - Package checkouts moved to writable `/private/tmp` successfully.
   - Still failed before compilation because SwiftPM diagnostics attempted writes under `~/Library/Caches/org.swift.swiftpm`.

3. Same as attempt 2 with `HOME=/private/tmp/amen-home` and `CFFIXED_USER_HOME=/private/tmp/amen-home`
   - Failed before compilation with `sandbox-exec: sandbox_apply: Operation not permitted` during SwiftPM package manifest evaluation.

4. Xcode MCP `BuildProject`
   - App build service reported success once, but build log retrieval later reported a package dependency graph failure and unrelated test-target diagnostics. This does not satisfy Amendment A's explicit shell `xcodebuild -scheme AMENAPP build` gate.

## Hypothesis

The shell runner is already sandboxed, and SwiftPM package manifest evaluation tries to invoke Apple's `sandbox-exec`. Nested sandbox application is denied in this environment. A normal terminal/Xcode run outside this Codex shell sandbox should be able to complete the exact command, assuming CoreSimulator services are healthy.

## BIL Status

No BIL compiler errors were reached or observed. All failures occurred during package graph resolution/toolchain setup before source compilation.

## Next Action

Run `xcodebuild -scheme AMENAPP build` from an unsandboxed local terminal or resolve the CoreSimulator/SwiftPM sandbox environment, then rerun Amendment A before starting Wave 2.
