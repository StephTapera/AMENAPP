import * as admin from 'firebase-admin'

admin.initializeApp()
const db = admin.firestore()

async function seed() {
  const ref = db.doc('featureFlags/trustArchitecture')
  const snap = await ref.get()

  if (snap.exists) {
    console.log('featureFlags/trustArchitecture already exists:')
    console.log(JSON.stringify(snap.data(), null, 2))
    console.log('Skipping seed — document not overwritten (idempotent).')
  } else {
    const flags = {
      modelRouter: false,
      evidenceRetrieval: false,
      constitutionalPipeline: false,
      memoryLayer: false,
      feedbackCapture: false
    }
    await ref.set(flags)
    const verify = await ref.get()
    console.log('Seeded featureFlags/trustArchitecture:')
    console.log(JSON.stringify(verify.data(), null, 2))
  }
  process.exit(0)
}

seed().catch(err => { console.error(err); process.exit(1) })
