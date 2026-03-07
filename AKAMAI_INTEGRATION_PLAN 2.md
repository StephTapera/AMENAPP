# Akamai Integration Plan — AMEN App

## Overview

AMEN currently serves all media (profile photos, post images, video thumbnails) directly from
Firebase Storage via `firebasestorage.googleapis.com` download URLs. Images are resized
client-side using `UIImage.preparingThumbnail`. Cloud Run services are exposed with GCP IAM
authentication only.

Akamai adds:
1. **Global CDN edge caching** — media served from the nearest PoP, not just `us-central1`
2. **Image Manager** — server-side resize, WebP/AVIF conversion, format negotiation
3. **Bot Manager / Kona Site Defender** — WAF protecting Cloud Run endpoints

---

## Phase 1 — CDN for Firebase Storage Media

### How Firebase Storage URLs Work

Every `getDownloadURL()` call returns a signed URL like:
```
https://firebasestorage.googleapis.com/v0/b/PROJECT.appspot.com/o/users%2FUID%2Fprofile.jpg?alt=media&token=...
```

These URLs are long-lived (token doesn't expire for most profile/post images).

### Option A — Akamai as a Reverse Proxy (Recommended)

Set up an Akamai Property for a custom subdomain, e.g. `media.amenapp.com`, that:
- **Origin** → `firebasestorage.googleapis.com`
- **Cache key** strips the `token=` query param so identical images share one cache entry
- **Edge TTL** → 7 days for profile images, 30 days for post images
- **Image Manager behavior** attached (see Phase 2)

App changes:
1. After uploading to Firebase Storage, store the **Akamai URL** in Firestore instead of the
   raw Firebase download URL:
   ```swift
   // BEFORE (current)
   let downloadURL = try await storageRef.downloadURL()
   // downloadURL = "https://firebasestorage.googleapis.com/v0/b/..."

   // AFTER
   let downloadURL = try await storageRef.downloadURL()
   let akamaiURL = AkamaiMediaService.shared.cdnURL(for: downloadURL)
   // akamaiURL = "https://media.amenapp.com/v0/b/PROJECT.appspot.com/o/..."
   ```

2. Add `AkamaiMediaService` (see `AkamaiMediaService.swift` stub below).

3. `CachedAsyncImage` and `ImageCache` already use `URLSession`/`URLCache` — they will
   automatically benefit once URLs point to Akamai edge nodes.

### Option B — Firebase Hosting as CDN Proxy (Simpler, no Akamai contract needed)

Firebase Hosting can serve Storage files via `/__/storage/` rewrites. This gives you
Firebase's built-in CDN (Fastly) for free. Cheaper starting point before Akamai.

---

## Phase 2 — Akamai Image Manager

Image Manager intercepts requests and applies transforms server-side based on query params or
`Accept` headers. No client library needed.

### URL Transform Scheme

```
https://media.amenapp.com/v0/b/PROJECT.appspot.com/o/ENCODED_PATH?
  alt=media&         ← required by Firebase Storage
  im=               ← Image Manager directive
  resize,width=88,   ← size matching the render target
  format=webp        ← WebP for iOS 14+ (all our users)
```

### Integration in `ImageCache.swift`

Replace the client-side `UIImage.preparingThumbnail` resize path with a URL-param resize:

```swift
// In ImageCache.loadImage(url:size:)
// Instead of downloading full-res then resizing on device:
let akamaiURL = AkamaiMediaService.shared.imageManagerURL(
    base: url,
    width: Int(size.width),
    height: Int(size.height)
)
// Download the already-resized image from Akamai edge
let (data, _) = try await URLSession.shared.data(from: akamaiURL)
```

Benefits:
- Network payload drops ~60–80% (88px profile = ~3KB WebP vs ~40KB JPEG full-res)
- Device CPU/memory freed from resize work
- Retina handled by passing `width: Int(size.width)` (already 2x from callers)

### Convenience Sizes to Pre-Configure in Image Manager Policy

| Use case           | Width | Height | Quality |
|--------------------|-------|--------|---------|
| Profile avatar     | 88    | 88     | 85      |
| Comment avatar     | 60    | 60     | 85      |
| Post feed image    | 750   | auto   | 80      |
| Post detail image  | 1242  | auto   | 85      |
| Thumbnail preview  | 200   | 150    | 70      |

---

## Phase 3 — WAF for Cloud Run Endpoints

Cloud Run services (`FEED_RANKING_URL`, `SEARCH_SERVICE_URL`) currently use GCP IAP/service
accounts for auth. For any endpoints exposed to client-generated tokens (e.g. Firebase ID
tokens), add Akamai Kona Site Defender as an additional layer:

1. Create an Akamai Property for `api.amenapp.com`
2. Origin → Cloud Run service URL
3. Forward `Authorization: Bearer <firebase-id-token>` header to origin
4. Add WAF rules:
   - Rate limit: 60 req/min per IP on `/search`
   - Block SQL/injection patterns on request body
   - Geographic restrictions if needed

App changes:
- Set `FEED_RANKING_URL = https://api.amenapp.com/feed/rank` in `Config.xcconfig`
- Set `SEARCH_SERVICE_URL = https://api.amenapp.com/search` in `Config.xcconfig`

---

## Files to Create/Modify

### New: `AMENAPP/AkamaiMediaService.swift`

```swift
// AkamaiMediaService.swift
// Converts Firebase Storage download URLs to Akamai CDN URLs with
// optional Image Manager resize directives.

import Foundation

struct AkamaiMediaService {
    static let shared = AkamaiMediaService()

    // Set this after Akamai property is configured
    // Also add AKAMAI_MEDIA_HOST to Config.xcconfig + Info.plist
    private let cdnHost: String? = Bundle.main.object(
        forInfoDictionaryKey: "AKAMAI_MEDIA_HOST"
    ) as? String

    private init() {}

    /// Rewrite a Firebase Storage URL to go through Akamai CDN.
    /// Returns the original URL unchanged if no CDN host is configured.
    func cdnURL(for firebaseURL: URL) -> URL {
        guard let host = cdnHost, !host.isEmpty,
              var components = URLComponents(url: firebaseURL, resolvingAgainstBaseURL: false)
        else { return firebaseURL }
        components.host = host
        return components.url ?? firebaseURL
    }

    func cdnURL(for string: String) -> String {
        guard let url = URL(string: string) else { return string }
        return cdnURL(for: url).absoluteString
    }

    /// Build an Image Manager URL that resizes and converts to WebP at the edge.
    func imageManagerURL(base: String, width: Int, height: Int? = nil) -> URL? {
        guard let host = cdnHost, !host.isEmpty,
              var components = URLComponents(string: base)
        else { return URL(string: base) }
        components.host = host
        // Image Manager directive via query param
        var im = "resize,width=\(width),format=webp"
        if let height = height { im += ",height=\(height)" }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "im", value: im))
        components.queryItems = items
        return components.url
    }
}
```

### Modified: `Config.xcconfig`

```
# Akamai CDN hostname (set after property is configured)
AKAMAI_MEDIA_HOST =
```

### Modified: `Info.plist`

Add:
```xml
<key>AKAMAI_MEDIA_HOST</key>
<string>$(AKAMAI_MEDIA_HOST)</string>
```

---

## Rollout Strategy

1. **Week 1** — Configure Akamai property in staging, point to Firebase Storage origin,
   validate cache behavior with existing URLs. No app changes.
2. **Week 2** — Merge `AkamaiMediaService.swift`, add `AKAMAI_MEDIA_HOST` to xcconfig/plist.
   Deploy TestFlight build. Monitor image load times (P50/P95) and cache-hit rate in Akamai
   Control Center.
3. **Week 3** — Enable Image Manager policy. Validate WebP delivery on device. Measure network
   payload reduction.
4. **Week 4** — Switch Cloud Run endpoints to `api.amenapp.com` (Akamai WAF). Enable rate
   limits. Monitor for false positives before enforcing block mode.

---

## Success Metrics

| Metric                  | Before    | Target     |
|-------------------------|-----------|------------|
| Profile image load (P95)| ~800ms    | <150ms     |
| Post image payload/cell | ~40KB avg | <8KB avg   |
| Feed image cache-hit %  | N/A       | >85%       |
| Cloud Run request errors| baseline  | -40%       |
