# Sanctuary Deploy Plan

Status: `BLOCKED-QUOTA — sequenced behind Release Train R2.`

Do not deploy these functions until the `us-central1` Cloud Run service inventory cleanup or quota grant creates headroom for eight new services.

## Commands

```bash
firebase deploy --only functions:default:sanctuaryTranscribe
firebase deploy --only functions:default:sanctuaryAnchorScripture
firebase deploy --only functions:default:sanctuaryAskMoment
firebase deploy --only functions:default:sanctuaryReact
firebase deploy --only functions:default:sanctuaryReactionField
firebase deploy --only functions:default:sanctuaryRoomSync
firebase deploy --only functions:default:sanctuarySearch
firebase deploy --only functions:default:sanctuaryWeeklyDigest
```

## Gate Proof

Emulator gate command:

```bash
XDG_CONFIG_HOME=/private/tmp/firebase-config FIREBASE_CLI_DISABLE_UPDATE_CHECK=1 firebase --config firebase.sanctuary-emulator.json emulators:exec --only firestore,auth,functions "npm --prefix functions test -- --runTestsByPath src/sanctuary/sanctuary.test.ts"
```

Latest result: pass, 12 tests across B1-B4, all eight Sanctuary functions covered.
