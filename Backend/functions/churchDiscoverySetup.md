# Find Your Community Setup

Enable these Google Cloud APIs for the Firebase project:

- Places API (New)
- Places SDK for iOS
- Maps SDK for iOS, only if native map rendering is enabled
- Geocoding API, only if server-side geocoding is added
- Routes API or Directions API, only if server-side travel time is added

Firebase Functions secrets:

```bash
firebase functions:secrets:set OPENAI_API_KEY
firebase functions:secrets:set ANTHROPIC_API_KEY
firebase functions:secrets:set GOOGLE_MAPS_API_KEY
firebase functions:secrets:set GOOGLE_PLACES_API_KEY
firebase functions:config:set amen.ai_provider_mode=openai
firebase functions:config:set amen.church_discovery_enabled=true
```

Use separate Google Maps keys where possible:

- iOS key: restrict by iOS bundle ID and enable only client SDKs needed by the app.
- Server key: restrict to backend/service usage where available and enable only Places API (New) and any server APIs actually used.
- Never place OpenAI, Anthropic, or unrestricted Google keys in the app bundle.

iOS Info.plist keys are needed only when client SDK rendering/autocomplete is added. The current implementation calls Google Places from Firebase Functions, so SwiftUI does not need OpenAI, Anthropic, or server Google keys.
