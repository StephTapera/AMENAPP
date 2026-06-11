# B-17: `moderateUploadedImage` CDN Caching Window
**Group:** BEFORE-LAUNCH
**Decision:** What is the p99 latency of the `moderateUploadedImage` CF under load? If CDN caches the public URL before moderation completes, deletion may be insufficient.

---

## Recommended Answer
Implement pre-moderation URL gating: do not return a public download URL to the client until the `moderateUploadedImage` CF has approved the image. Gate `profilePhotos` public read to authenticated-only during the quarantine window. Measure CF p99 latency under load before the App Store launch.

## Rationale
The current architecture — upload to Storage, return URL immediately, then CF moderates asynchronously — creates a race condition. If a CDN (Firebase Hosting CDN, or any CDN that fetches the public URL) caches the image during the moderation window, then even if the CF deletes the Storage file afterward, the cached copy remains accessible via CDN for up to the TTL. For CSAM this is a critical gap: the image is reported and deleted server-side but continues to be served via CDN. Pre-moderation gating eliminates this race entirely.

## What the code already does (file:line)
- `functions/imageModeration.js` — `moderateUploadedImage` CF exists; triggered on Storage write
- Gap: No pre-moderation URL gating found — public URL appears to be available immediately after upload
- Gap: `profilePhotos/{uid}/{photoId}` Storage rule: `allow read: if true` (unauthenticated read) — CDN can cache immediately
- Gap: p99 latency not measured; no load test results found

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Pre-moderation URL gating (recommended) | Use Storage metadata `quarantine: true` flag; CF sets to `approved` before returning URL; iOS polls or uses Firestore listener | Correct; eliminates CDN race |
| Post-moderation with CDN purge | Add CDN purge API call in moderation CF | CDN purge APIs are not guaranteed to be instant; partial mitigation only |
| Accept current architecture | No change | CDN caching window remains; CSAM may persist in CDN cache after deletion |

## Legal consultation required?
NO — technical infrastructure decision.

---
**Status:** ☐ OPEN
**Owner:** Engineering Lead
