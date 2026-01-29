# Christian Dating - Quick Backend Hookup Reference

## 🚀 30-Second Setup

```swift
// 1. Set your backend URL
// In DatingAPIClient.swift, line 14:
private let baseURL = "https://your-backend.com/api/dating"

// 2. Set auth token after user logs in
DatingAPIClient.shared.setAuthToken(userAuthToken)

// 3. That's it! The app now uses your backend.
```

## 📋 Replace These TODO Comments

### In ChristianDatingService.swift

| Method | Line | What to Replace |
|--------|------|-----------------|
| `createDatingProfile` | ~45 | Mock profile creation → `DatingAPIClient.shared.post("/profiles", body: request)` |
| `fetchDiscoveryProfiles` | ~157 | Sample data → `DatingAPIClient.shared.get("/discover", queryParams: params)` |
| `likeProfile` | ~202 | Mock match → `DatingAPIClient.shared.post("/swipes", body: swipe)` |
| `sendMessage` | ~291 | Local message → `DatingAPIClient.shared.post("/matches/{id}/messages", body: message)` |
| `uploadPhoto` | ~380 | Placeholder → `DatingAPIClient.shared.uploadImage("/photos", imageData: data)` |

### In DatingNotificationService.swift

| Method | Line | What to Replace |
|--------|------|-----------------|
| `connect` | ~23 | Mock URL → `URL(string: "wss://your-backend.com/dating/notifications")` |

## 🔗 API Endpoint Quick Reference

```
Profiles:    POST   /api/dating/profiles
Discovery:   GET    /api/dating/discover?lat={lat}&lon={lon}
Swipe:       POST   /api/dating/swipes
Matches:     GET    /api/dating/matches
Messages:    POST   /api/dating/matches/{matchId}/messages
Photos:      POST   /api/dating/photos (multipart/form-data)
Verify:      POST   /api/dating/verify/phone
Report:      POST   /api/dating/reports
Block:       POST   /api/dating/blocks
```

## 📊 Database Tables You Need

```sql
dating_profiles      -- User profiles
dating_photos        -- Profile pictures
dating_swipes        -- Like/pass history
dating_matches       -- Matched pairs
dating_messages      -- Chat messages
dating_reports       -- Safety reports
dating_blocks        -- Blocked users
```

Full schema: See `CHRISTIAN_DATING_BACKEND_GUIDE.md`

## 🎯 Example: Converting Mock to Real API

### Before (Mock):
```swift
func likeProfile(_ profileId: String) async throws -> Bool {
    // TODO: Replace with actual API call
    try await Task.sleep(nanoseconds: 500_000_000)
    let isMatch = Int.random(in: 1...5) == 1
    return isMatch
}
```

### After (Real):
```swift
func likeProfile(_ profileId: String) async throws -> Bool {
    struct SwipeRequest: Encodable {
        let profileId: String
        let action: String
    }
    
    struct SwipeResponse: Decodable {
        let isMatch: Bool
        let match: DatingMatch?
    }
    
    let response: SwipeResponse = try await DatingAPIClient.shared.post(
        "/swipes",
        body: SwipeRequest(profileId: profileId, action: "like")
    )
    
    if response.isMatch, let match = response.match {
        matches.append(match)
    }
    
    return response.isMatch
}
```

## ⚡ Backend Matching Logic

Your backend should implement:

```javascript
// When user A likes user B
if (action === 'like') {
    // Check if B already liked A
    const reverseSwipe = await checkSwipe(profileId, swiperId);
    
    if (reverseSwipe && reverseSwipe.action === 'like') {
        // IT'S A MATCH! 💕
        const match = await createMatch(swiperId, profileId);
        await sendNotification(swiperId, 'new_match', match);
        await sendNotification(profileId, 'new_match', match);
        return { isMatch: true, match };
    }
}
return { isMatch: false };
```

## 🔐 Security Checklist

- [ ] Verify auth token on every request
- [ ] Rate limit swipes (e.g., 100/day)
- [ ] Validate profile data (age >= 18, etc.)
- [ ] Scan uploaded photos for inappropriate content
- [ ] Auto-ban after 3+ reports (pending review)
- [ ] Encrypt sensitive data (phone numbers, emergency contacts)
- [ ] Use HTTPS only
- [ ] Implement CORS properly

## 📱 Push Notifications

When sending APNs from backend:

```json
{
  "aps": {
    "alert": {
      "title": "New Match! 💕",
      "body": "You matched with Sarah"
    },
    "badge": 1,
    "sound": "default"
  },
  "type": "new_match",
  "matchId": "uuid-here"
}
```

## 🧪 Testing Flow

1. ✅ Run app with mock data (works now!)
2. ✅ Set up backend database
3. ✅ Implement one endpoint (e.g., create profile)
4. ✅ Replace TODO in service
5. ✅ Test with real data
6. ✅ Repeat for other endpoints
7. ✅ Add WebSocket
8. ✅ Enable push notifications
9. ✅ Deploy!

## 🎨 Already Integrated

These work automatically:
- ✅ Local caching (UserDefaults)
- ✅ Location services
- ✅ Distance calculations
- ✅ Profile filtering
- ✅ Swipe tracking
- ✅ Error handling
- ✅ Loading states

## 📞 Common Issues

**"CORS error"**
→ Enable CORS on your backend for your app's domain

**"401 Unauthorized"**
→ Check `DatingAPIClient.shared.setAuthToken()` was called

**"Can't upload photo"**
→ Verify backend accepts `multipart/form-data`

**"WebSocket disconnects"**
→ Implement reconnection logic (already in code, just uncomment)

## 🏆 Recommended Stack

**Fastest:** Firebase
- Firestore for database
- Storage for photos
- Cloud Functions for matching
- FCM for notifications

**Most Control:** Node.js + PostgreSQL
- Express.js backend
- PostgreSQL + PostGIS
- S3/Cloudinary for photos
- Socket.io for real-time

**Python Option:** Django + PostgreSQL
- Django REST Framework
- PostgreSQL database
- S3 for storage
- Django Channels for WebSocket

## 📚 Files to Reference

- `DatingModels.swift` - Data structures
- `ChristianDatingService.swift` - Business logic (replace TODOs here)
- `DatingAPIClient.swift` - HTTP client (set baseURL here)
- `DatingNotificationService.swift` - Real-time features
- `DatingLocationManager.swift` - Location services
- `CHRISTIAN_DATING_BACKEND_GUIDE.md` - Full documentation
- `IMPLEMENTATION_SUMMARY.md` - Overview

## ⚡ Code Snippets

### Get current user's profile
```swift
if let profile = ChristianDatingService.shared.currentUserProfile {
    // Use profile
}
```

### Fetch discovery profiles
```swift
let profiles = try await ChristianDatingService.shared.fetchDiscoveryProfiles(
    location: locationManager.currentLocation,
    filters: ProfileFilters(ageRange: 25...35, maxDistance: 30)
)
```

### Like a profile
```swift
let isMatch = try await ChristianDatingService.shared.likeProfile(profileId)
if isMatch {
    // Show match celebration!
}
```

### Send a message
```swift
let message = try await ChristianDatingService.shared.sendMessage(
    matchId: match.id.uuidString,
    receiverId: otherUserId,
    content: "Hey! How's your day?"
)
```

### Upload a photo
```swift
let url = try await ChristianDatingService.shared.uploadPhoto(imageData)
```

## 🎯 One More Time: What You Need to Do

1. Choose backend platform (Firebase or custom)
2. Set up database (schema provided)
3. Update `baseURL` in `DatingAPIClient.swift`
4. Implement API endpoints on backend
5. Replace TODOs in `ChristianDatingService.swift`
6. Test!

**That's it! Everything else is done.** 🎉

---

Questions? Check `CHRISTIAN_DATING_BACKEND_GUIDE.md` for detailed docs!
