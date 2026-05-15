// Starts the Firestore emulator process check.
// Actual emulator must be running before tests: firebase emulators:start --only firestore
export default async function globalSetup() {
  process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
}
