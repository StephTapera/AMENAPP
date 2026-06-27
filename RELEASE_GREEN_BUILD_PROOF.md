# Release Green Build Proof

**Generated:** 2026-06-27  
**Branch:** `release-green/restore-paywall-blockers`  
**Status:** BLOCKED / NO-GO

## Command

```bash
xcodebuild -scheme AMENAPP -destination 'generic/platform=iOS' build -clonedSourcePackagesDirPath ./SourcePackages.nosync -derivedDataPath ./DerivedData.nosync
```

## Log

```text
deploy-logs/xcodebuild-release-green-build-20260627-100748.log
```

## Result

FAILED before compile during SwiftPM package resolution.

Primary error:

```text
cannot open file '/Users/stephtapera/Library/Caches/org.swift.swiftpm/manifests/ManifestLoading/generative-ai-swift.dia' for diagnostics emission (Operation not permitted)
```

Additional environment issue:

```text
CoreSimulatorService connection became invalid. Simulator services will no longer be available.
```

## Release Impact

This is not a green build. Archive and App Store validation were not attempted because package resolution failed first.
