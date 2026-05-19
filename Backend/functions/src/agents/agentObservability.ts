import * as admin from "firebase-admin";

const db = admin.firestore();

export async function logAgentEvent(event: string, payload: Record<string, unknown>) {
    await db.collection("aiAudit").doc("events").collection("entries").add({event, payload, createdAt: admin.firestore.FieldValue.serverTimestamp()});
}
