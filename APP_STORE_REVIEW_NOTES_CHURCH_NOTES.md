# Church Notes App Store Review Notes

## Notification Usage

Church Notes can schedule a local midweek reflection reminder when the user explicitly taps the contextual reminder action. The reminder is created through `UNUserNotificationCenter` after the standard iOS notification permission flow. The app does not schedule Church Notes reminders silently.

Suggested review note:

> Church Notes uses local notifications only for user-requested note follow-up reminders, such as a midweek prompt tied to a saved sermon note. Users initiate these reminders from the Church Notes editor and can manage notification permission through iOS Settings.

## Scripture Provider Staging

API.Bible is the approved scripture provider. Provider-backed scripture text must remain behind feature flags until provider credentials, entitlement to requested translations, and production cache policy are approved.

Implementation policy:

- BSB, WEB, and KJV are the core tier. They are eligible for offline cache and Berean AI context where licensing permits.
- Licensed translations are display-only unless the license explicitly grants persistent cache and AI-context use.
- Display-only translations must not be persisted as scripture text and must not be embedded into Berean AI context.

## Music Metadata Staging

MusicKit is the primary metadata source. Spotify link unfurling is secondary. Church Notes may store song title, artist, artwork URL, provider, and source links. Lyrics are not reproduced, cached, transformed, summarized, or sent through AI workflows.

## Privacy Manifest Staging

No new provider network data declarations are added in this pass because API.Bible and MusicKit provider calls remain feature-gated. Update `AMENAPP/AMENAPP/PrivacyInfo.xcprivacy` when provider traffic ships in production.
