import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {enforceAmenGuards, requireAuthAndAppCheck} from "../../amenAI/common";

const db = admin.firestore();

const scripturePattern = /\b(?:[1-3]\s*)?(?:Genesis|Exodus|Leviticus|Numbers|Deuteronomy|Joshua|Judges|Ruth|Samuel|Kings|Chronicles|Ezra|Nehemiah|Esther|Job|Psalms?|Proverbs|Ecclesiastes|Song of Songs|Isaiah|Jeremiah|Lamentations|Ezekiel|Daniel|Hosea|Joel|Amos|Obadiah|Jonah|Micah|Nahum|Habakkuk|Zephaniah|Haggai|Zechariah|Malachi|Matthew|Mark|Luke|John|Acts|Romans|Corinthians|Galatians|Ephesians|Philippians|Colossians|Thessalonians|Timothy|Titus|Philemon|Hebrews|James|Peter|Jude|Revelation)\s+\d{1,3}:\d{1,3}(?:-\d{1,3})?\b/gi;

function normalizeReference(reference: string): string {
    return reference.replace(/\s+/g, " ").trim();
}

export const resolveScriptureReferences = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);
    await enforceAmenGuards({
        uid,
        taskType: "berean_scripture_resolution",
        featureFlag: "bereanSmartNotesEnabled",
        killSwitch: "bereanRealtimeKillSwitch",
    });

    const text = String(request.data?.text ?? "").trim();
    const sessionId = String(request.data?.sessionId ?? "").trim();
    if (!text) throw new HttpsError("invalid-argument", "Text is required.");
    if (text.length > 20000) throw new HttpsError("invalid-argument", "Text is too large.");

    const matches = Array.from(text.matchAll(scripturePattern))
        .map((match) => normalizeReference(match[0]))
        .filter((value, index, all) => all.indexOf(value) === index)
        .slice(0, 24);

    const references = matches.map((reference) => ({
        reference,
        normalizedReference: reference,
        confidence: 0.9,
        source: "explicit_text_match",
    }));

    if (sessionId) {
        const batch = db.batch();
        references.forEach((reference) => {
            const ref = db.collection("realtimeSessions").doc(sessionId).collection("scriptureReferences").doc();
            batch.set(ref, {
                ...reference,
                ownerId: uid,
                moderationStatus: "approved",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        });
        await batch.commit();
    }

    await db.collection("aiAudit").doc("scriptureResolution").collection("events").add({
        uid,
        sessionId: sessionId || null,
        count: references.length,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {references};
});
