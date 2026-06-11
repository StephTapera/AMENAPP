import * as admin from "firebase-admin";

const db = admin.firestore();

export async function logAgentEvent(event: string, payload: Record<string, unknown>) {
    await db.collection("aiAudit").doc("events").collection("entries").add({event, payload, createdAt: admin.firestore.FieldValue.serverTimestamp()});
}

export async function startAgentRun(payload: Record<string, unknown>): Promise<string> {
    const ref = db.collection("aiAudit").doc("agentRuns").collection("entries").doc();
    await ref.set({
        ...payload,
        status: "running",
        startedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return ref.id;
}

export async function logAgentSpan(runId: string, payload: Record<string, unknown>): Promise<void> {
    await db.collection("aiAudit").doc("agentRuns").collection("entries").doc(runId)
        .collection("spans")
        .add({
            ...payload,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
}

export async function finishAgentRun(runId: string, payload: Record<string, unknown>): Promise<void> {
    await db.collection("aiAudit").doc("agentRuns").collection("entries").doc(runId).set({
        ...payload,
        finishedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}
