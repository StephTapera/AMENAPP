# Firestore Rules Test Ports

Rules suites read emulator endpoints from environment variables instead of
hard-coding Firebase defaults:

```bash
export FIRESTORE_EMULATOR_HOST=127.0.0.1:18080
export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:19099
export FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:19000
export FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:19199
npm test -- messaging-private-actions.rules.test.ts
```

When using `firebase emulators:exec`, the Firebase config still decides which
ports the emulators bind to. The repo includes `firebase.rules-tests.isolated.json`
for alternate-port runs:

```bash
FIRESTORE_EMULATOR_HOST=127.0.0.1:18080 \
FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:19000 \
FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:19199 \
firebase emulators:exec --config ../../firebase.rules-tests.isolated.json \
  --only firestore,database,storage "npm test -- --runInBand messaging-private-actions.rules.test.ts"
```
