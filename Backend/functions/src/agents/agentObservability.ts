import * as admin from "firebase-admin";

const db = admin.firestore();

export async function logAgentEvent(event: string, payload: Record<string, unknown>) {
    await db.collection("aiAudit").doc("events").collection("entries").add({event, payload, createdAt: admin.firestore.FieldValue.serverTimestamp()});
}

export async function startAgentRun(meta: Record<string, unknown>): Promise<string> {
    const runId = `run_${Date.now()}_${Math.random().toString(36).slice(2)}`;
    await db.collection("aiAudit").doc("runs").collection("entries").doc(runId).set(
        { runId, status: "started", startedAt: admin.firestore.FieldValue.serverTimestamp(), ...meta },
        { merge: true }
    );
    return runId;
}

export async function finishAgentRun(runId: string, result: Record<string, unknown>): Promise<void> {
    await db.collection("aiAudit").doc("runs").collection("entries").doc(runId).set(
        { runId, status: "finished", finishedAt: admin.firestore.FieldValue.serverTimestamp(), ...result },
        { merge: true }
    );
}

export async function logAgentSpan(runId: string, data: Record<string, unknown>): Promise<void> {
    await db.collection("aiAudit").doc("spans").collection("entries").add({
        runId, data, createdAt: admin.firestore.FieldValue.serverTimestamp()
    });
}
