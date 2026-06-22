# Privacy Manifest — Corrections Handoff

**Status:** Patch prepared, NOT applied to the shared tree. Working tree reverted to HEAD.
**Owning lane:** `batch-3-privacy` / `OG-2 Item-12` (the streams that committed `AMENAPP/PrivacyInfo.xcprivacy`).
**Date prepared:** 2026-06-18.

## Why this is a patch and not a commit

`AMENAPP/PrivacyInfo.xcprivacy` is owned by another work-stream and the tree is hot
(6+ agents active). To avoid the two-writers pattern, the corrections live as a patch
(`PrivacyInfo.xcprivacy.patch`) rather than a second commit to that file. Apply them on a
**quiet tree, together with the target-membership wiring** (see Blocker below) — the
corrections are inert until membership is wired, so there is no rush to land them alone.

## BLOCKER (must land with this patch)

`PrivacyInfo.xcprivacy` has **zero references in `AMENAPP.xcodeproj/project.pbxproj`** — it is
not a member of the app target, so it is NOT copied into the shipped bundle. The shipped app
currently has **no privacy manifest**, which Apple rejects. Add the file to the AMENAPP target
(Xcode: select file → Target Membership → AMENAPP). This is an Xcode/pbxproj change — do it in
the IDE on the quiet tree, not via raw pbxproj edits on the hot tree.

## How to apply

```sh
git apply qa/privacy-manifest-handoff/PrivacyInfo.xcprivacy.patch
plutil -lint AMENAPP/PrivacyInfo.xcprivacy   # expect: OK
```

## What the patch changes

### Corrections (non-destructive — fix wrong/missing values)
- `DeviceID` + `ProductInteraction`: `Tracking` true → **false**. The `batch-3-privacy`
  commit set top-level `NSPrivacyTracking=false` but left these two per-type flags true — a
  self-contradiction. Now consistent with the top-level flag and `Docs/APP_STORE_PRIVACY_LABEL_MAPPING.md`.
- `PhoneNumber`, `AudioData`, `CoarseLocation`, `CrashData`: `Linked` false → **true** (all keyed to Firebase UID).
- `UserDefaults` reasons: added **`1C8F.1`** (app uses `UserDefaults.standard`, app-only) alongside
  `CA92.1` (the `group.com.amenapp.shared` App Group suite used by widget/share extension).
- Added **`SensitiveInfo`** (prayer/faith content reveals religious belief; safety/CSAM reports).

### Removals (verified, evidence-backed)
- **`PreciseLocation`** — only `kCLLocationAccuracyReduced` is ever requested; `CoarseLocation` covers it.
- **`Health` + `Fitness`** — HealthKit is read on-device only (`WellnessIntegrationService` /
  `HealthKitAdapter`); the Health module has no `setData`/`httpsCallable`/network writes. On-device
  reads are not "collection." **Re-add if health data is ever transmitted off-device.**
- **`Contacts`** — both contact paths gate on `integration_contacts_enabled`, which is absent from
  the compiled Remote Config defaults (`AMENFeatureFlags.swift`) → Firebase returns false → OFF at launch.
  **CAVEAT:** confirm the *server-side* Remote Config value reads false at launch.
  **Re-add before that flag flips on** — `ContactDiscoveryService.discoverContacts()` sends hashed
  contacts to the `matchHashedContacts` CF when enabled (= collection).
- **`SystemBootTime` (35F9.1)** — no `mach_absolute_time`/`systemUptime` usage anywhere.
- **DiskSpace reason `85F4.1`** dropped (that's "display to user"); kept **`E174.1`** (check capacity
  before writing — matches `CapabilityMonitor.measureStoragePressure()`).

### Verified and KEPT
- **`FileTimestamp` (`C617.1`, `3B52.1`)** — justified: `FileManager.attributesOfItem(...)` (→`stat`)
  in `FileAttachmentHandler`, `ChurchNotesMediaProcessingService`, `VoicePrayerUploadService`.

## Open items for the owning lane / human
1. **Target membership** (the blocker above).
2. **`NSPrivacyTracking`** stays `false`. Confirm against the final ASC "Data Used to Track You"
   answer; flip to true only if ad attribution / on-device conversion is wired before launch.
3. **Contacts server-side flag** confirmation (see caveat).
4. **`PerformanceData`** is still declared (pre-existing). Confirm Firebase Performance SDK is
   actually in use; if not, it is another over-declaration to remove.
5. The manifest must stay consistent with `Docs/APP_STORE_PRIVACY_LABEL_MAPPING.md` and the live
   ASC App Privacy labels.
