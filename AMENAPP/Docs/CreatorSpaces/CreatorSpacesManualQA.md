# Creator Spaces Manual QA Checklist

## Resources navigation

- Open Resources.
- Verify `Open Creator Spaces` appears only when `creator_spaces_enabled` is true.
- Tap `Open Creator Spaces` and verify the Creator Spaces home loads.

## Provenance label

- Confirm the Shot Real badge appears only for captured-on-device, unedited, no-AI labels.
- Confirm Phase 2 fields display as `Not measured`, not fabricated scores.

## Daily Portion

- Open Daily Portion.
- Confirm the first load calls `getDailyPortion`.
- Confirm empty or exhausted responses show `You're caught up` instead of a spinner.
- Confirm the feed does not auto-refill.

## Upload contract

- Upload with no frames: expect `invalid-argument`.
- Upload without App Check: expect `failed-precondition`.
- Upload without auth: expect `unauthenticated`.
- Upload without `creator_spaces.hmac_secret`: expect fail-closed.
- Upload with valid frame paths: expect `mediaAssets`, `provenanceLabels`, `memoryNodes`, and `guardianMediaQueue` writes.

## Edit provenance

- Record edit as non-owner: expect `permission-denied`.
- Record AI edit as owner: expect provenance label `editedWithAI == true` and no Shot Real badge.

## Unsupported devices

- Presence capture workstream must guard `AVCaptureMultiCamSession.isMultiCamSupported` before shipping capture UI.
