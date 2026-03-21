// mentorshipFunctions.js
// Mentorship subscription management via Stripe + Firestore

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

// Stripe — lazy-initialized so deploy-time analysis doesn't require the key
let _stripeClient = null;
function getStripe() {
  if (!_stripeClient) {
    const key = process.env.STRIPE_SECRET_KEY;
    if (!key) throw new Error("STRIPE_SECRET_KEY environment variable is not set");
    _stripeClient = require("stripe")(key);
  }
  return _stripeClient;
}

// P1 FIX: v1 callables must declare secrets via runWith({secrets:[...]}) so that
// process.env.STRIPE_SECRET_KEY is injected at runtime. Without this, the env var
// is undefined in production even when the secret exists in Secret Manager.
exports.createMentorshipSubscription = functions.runWith({ secrets: ["STRIPE_SECRET_KEY"] }).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required");
  }

  const { mentorId, stripePriceId } = data;
  const uid = context.auth.uid;

  if (!mentorId || !stripePriceId) {
    throw new functions.https.HttpsError("invalid-argument", "mentorId and stripePriceId required");
  }

  const db = admin.firestore();

  // Get or create Stripe customer
  const userDoc = await db.collection("users").doc(uid).get();
  const userData = userDoc.data() || {};
  let customerId = userData.stripeCustomerId;

  if (!customerId) {
    const customer = await getStripe().customers.create({
      email: userData.email || "",
      metadata: { firebaseUID: uid },
    });
    customerId = customer.id;
    await db.collection("users").doc(uid).update({ stripeCustomerId: customerId });
  }

  // Create subscription
  const subscription = await getStripe().subscriptions.create({
    customer: customerId,
    items: [{ price: stripePriceId }],
    payment_behavior: "default_incomplete",
    expand: ["latest_invoice.payment_intent"],
    metadata: { mentorId, menteeId: uid },
  });

  const paymentIntent = subscription.latest_invoice.payment_intent;

  return {
    subscriptionId: subscription.id,
    clientSecret: paymentIntent ? paymentIntent.client_secret : "",
  };
});

exports.cancelMentorshipSubscription = functions.runWith({ secrets: ["STRIPE_SECRET_KEY"] }).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required");
  }

  const { subscriptionId, relationshipId } = data;
  const uid = context.auth.uid;

  // Verify this user owns the relationship
  const relDoc = await admin.firestore().doc(`mentorshipRelationships/${relationshipId}`).get();
  if (!relDoc.exists || relDoc.data().menteeId !== uid) {
    throw new functions.https.HttpsError("permission-denied", "Not authorized");
  }

  await getStripe().subscriptions.cancel(subscriptionId);
  await admin.firestore().doc(`mentorshipRelationships/${relationshipId}`).update({
    status: "ended",
    endedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { success: true };
});

exports.sendWeeklyCheckIns = functions.pubsub
  .schedule("every monday 09:00")
  .timeZone("America/New_York")
  .onRun(async () => {
    const db = admin.firestore();

    // Fetch all active relationships
    const relsSnap = await db.collection("mentorshipRelationships")
      .where("status", "==", "active")
      .get();

    const dueDate = new Date();
    dueDate.setDate(dueDate.getDate() + 7); // Due next Monday

    const prompts = [
      "What scripture has spoken to you most this week?",
      "Where did you feel closest to God this week?",
      "What challenge are you facing in your faith right now?",
      "How has your prayer life been this week?",
      "What are you most grateful for today?",
    ];

    const batch = db.batch();
    for (const doc of relsSnap.docs) {
      const rel = doc.data();
      // Only create check-in if plan includes them
      const checkInId = db.collection("mentorshipCheckIns").doc().id;
      batch.set(db.collection("mentorshipCheckIns").doc(checkInId), {
        id: checkInId,
        relationshipId: doc.id,
        mentorId: rel.mentorId,
        menteeId: rel.menteeId,
        mentorName: rel.mentorName || "",
        mentorPhotoURL: rel.mentorPhotoURL || null,
        prompt: prompts[Math.floor(Math.random() * prompts.length)],
        dueDate: admin.firestore.Timestamp.fromDate(dueDate),
        completedAt: null,
        response: null,
        mentorReply: null,
        status: "pending",
      });
    }
    await batch.commit();
    console.log(`Created ${relsSnap.docs.length} weekly check-ins`);
  });
