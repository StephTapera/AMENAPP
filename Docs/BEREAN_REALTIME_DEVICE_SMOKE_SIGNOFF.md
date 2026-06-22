# Berean Realtime Device Smoke Signoff

This file is the production acknowledgement artifact consumed by
`scripts/verify_berean_realtime_10_go.sh` when `REQUIRE_DEVICE_SMOKE_ACK=1`.

Complete these markers only after testing on a real iOS device against the
intended Firebase project and OpenAI realtime backend.

REAL_AUDIO_SESSION_STARTED=false
OPENAI_REALTIME_CONNECTED=false
CAPTIONS_RENDERED=false
TRANSCRIPT_CHUNKS_PERSISTED=false
MODERATION_EVENTS_VERIFIED=false
RECONNECT_RECOVERY_VERIFIED=false

Test metadata:

FIREBASE_PROJECT_ID=
IOS_DEVICE_MODEL=
IOS_VERSION=
APP_BUILD_NUMBER=
TESTER=
TESTED_AT_UTC=
NOTES=
