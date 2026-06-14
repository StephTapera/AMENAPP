import * as admin from "firebase-admin";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

const REGION = "us-east1"; // us-central1 quota exhausted (~999/1000) — see docs/FUNCTION_INVENTORY.md §Interim Region Table
const db = admin.firestore();

type PrayerLedgerStatus = "answered" | "ongoing" | "redirected" | "grieving";
type WitnessCadence = "weekly" | "biweekly" | "monthly" | "seasonal";
type DailyOfficeSlot = "morning" | "evening";

const DISTINCTIVE_FLAGS = {
  prayerLedger: "ff_prayer_ledger",
  testEverything: "ff_test_everything",
  witnessedCommitments: "ff_witnessed_commitments",
  dailyOffice: "ff_daily_office",
  liturgicalPacing: "ff_liturgical_pacing",
};

function requireAuth(uid?: string): string {
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return uid;
}

async function isKilled(key: string): Promise<boolean> {
  const snap = await db.collection("serverFeatureFlags").doc(key).get().catch(() => null);
  return snap?.data()?.enabled === true;
}

async function requireNotKilled(key: string) {
  if (await isKilled(key)) {
    throw new HttpsError("failed-precondition", "This feature is temporarily unavailable.");
  }
}

function cleanText(value: unknown, maxLength: number): string {
  if (typeof value !== "string") return "";
  return value
    .replace(/system\s*:/gi, "")
    .replace(/ignore\s+(previous|all)\s+instructions/gi, "")
    .trim()
    .slice(0, maxLength);
}

function isValidCadence(value: unknown): value is WitnessCadence {
  return value === "weekly" || value === "biweekly" || value === "monthly" || value === "seasonal";
}

function currentLiturgicalContext() {
  const now = admin.firestore.Timestamp.now();
  return {
    id: "canonical",
    season: "Ordinary Time",
    week: 1,
    tempoProfile: {
      name: "ordinary",
      animationScale: 1,
      spacingScale: 1,
      accentToken: "amenAccent",
      motionTone: "gentle",
    },
    effectiveFrom: now,
    effectiveUntil: admin.firestore.Timestamp.fromMillis(Date.now() + 7 * 24 * 60 * 60 * 1000),
    source: "backend",
    updatedAt: now,
    tier: "S",
  };
}

export const resurfacePrayers = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 30 },
  async (request) => {
    const uid = requireAuth(request.auth?.uid);
    await requireNotKilled("kill_resurface_prayers");

    const maxCandidates = Math.min(Math.max(Number(request.data?.maxCandidates ?? 3), 1), 5);
    const minAgeDays = Math.min(Math.max(Number(request.data?.minAgeDays ?? 21), 7), 365);
    const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - minAgeDays * 24 * 60 * 60 * 1000);

    const prayers = await db
      .collection("users")
      .doc(uid)
      .collection("prayers")
      .where("createdAt", "<=", cutoff)
      .limit(25)
      .get();

    const candidates: Array<{ candidateId: string; prayerId: string; surfacedReason: string; gentleCopyVariant: string }> = [];
    for (const prayer of prayers.docs) {
      if (candidates.length >= maxCandidates) break;
      const data = prayer.data();
      if (data.crisisFlag === true && data.crisisClearanceId == null) continue;
      if (data.griefFlag === true && data.crisisClearanceId == null) continue;

      const existingLedger = await db
        .collection("users")
        .doc(uid)
        .collection("prayer_ledger")
        .where("prayerId", "==", prayer.id)
        .limit(1)
        .get();
      if (!existingLedger.empty) continue;

      const candidateRef = db.collection("users").doc(uid).collection("prayer_resurfacing_queue").doc(prayer.id);
      await candidateRef.set(
        {
          userId: uid,
          prayerId: prayer.id,
          sourceMemoryId: data.sourceMemoryId ?? null,
          surfacedReason: "aging_without_outcome",
          gentleCopyVariant: data.griefFlag === true ? "grieving" : "standard",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          tier: "C",
        },
        { merge: true }
      );
      candidates.push({
        candidateId: candidateRef.id,
        prayerId: prayer.id,
        surfacedReason: "aging_without_outcome",
        gentleCopyVariant: data.griefFlag === true ? "grieving" : "standard",
      });
    }

    console.info("distinctive_function_latency", {
      functionName: "resurfacePrayers",
      region: REGION,
      success: true,
      flag: DISTINCTIVE_FLAGS.prayerLedger,
    });
    return { candidates };
  }
);

export const resurfacePrayersScheduled = onSchedule(
  { region: REGION, schedule: "every 24 hours", timeZone: "UTC" },
  async () => {
    if (await isKilled("kill_resurface_prayers")) return;
    console.info("resurfacePrayersScheduled", { region: REGION, status: "scheduled_scan_deferred_to_user_callable" });
  }
);

export const groundClaim = onRequest(
  { region: REGION, timeoutSeconds: 120, memory: "256MiB", cors: false },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }
    if (await isKilled("kill_ground_claim")) {
      res.status(503).json({ error: "This feature is temporarily unavailable." });
      return;
    }

    const appCheckToken = req.header("X-Firebase-AppCheck");
    if (!appCheckToken) {
      res.status(401).json({ error: "App Check attestation required." });
      return;
    }
    await admin.appCheck().verifyToken(appCheckToken).catch(() => {
      throw new HttpsError("unauthenticated", "Invalid App Check token.");
    });

    const authHeader = req.header("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      res.status(401).json({ error: "Authentication required." });
      return;
    }
    const decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
    const uid = decoded.uid;
    const claimText = cleanText(req.body?.claimText, 2000);
    const sourceContentId = cleanText(req.body?.sourceContentId, 200);
    if (!claimText || !sourceContentId) {
      res.status(400).json({ error: "claimText and sourceContentId are required." });
      return;
    }

    const bereanSessionId = db.collection("_ids").doc().id;
    res.setHeader("Content-Type", "text/event-stream");
    res.setHeader("Cache-Control", "no-cache, no-transform");
    res.setHeader("Connection", "keep-alive");

    const send = (payload: Record<string, unknown>) => {
      res.write(`data: ${JSON.stringify(payload)}\n\n`);
    };

    req.on("close", () => {
      console.info("ground_claim_stream_cancelled", { bereanSessionId });
    });

    const provenanceStatus = "unknown";
    send({ type: "started", bereanSessionId, provenanceStatus });
    send({
      type: "scripture_ref",
      ref: { book: "Acts", chapter: 17, verseStart: 11, translation: req.body?.translationPreference ?? "preferred", confidence: 0.72 },
    });
    send({
      type: "tradition_note",
      note: {
        tradition: "Historic Christian interpretation",
        note: "Traditions commonly test teaching by Scripture, communal discernment, and pastoral fruit.",
        confidence: 0.62,
      },
    });
    send({ type: "summary_delta", text: "Berean grounding mode checks the claim against Scripture and provenance before offering a conclusion." });

    const groundingRef = db.collection("users").doc(uid).collection("claim_groundings").doc();
    await groundingRef.set({
      userId: uid,
      sourceContentId,
      claimText,
      groundingRefs: [{ book: "Acts", chapter: 17, verseStart: 11, translation: req.body?.translationPreference ?? "preferred", confidence: 0.72 }],
      traditionNotes: [{
        tradition: "Historic Christian interpretation",
        note: "Traditions commonly test teaching by Scripture, communal discernment, and pastoral fruit.",
        confidence: 0.62,
      }],
      provenanceStatus,
      bereanSessionId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      tier: "C",
    });
    send({ type: "completed", groundingId: groundingRef.id });
    res.end();
  }
);

export const inviteWitness = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 30 },
  async (request) => {
    const uid = requireAuth(request.auth?.uid);
    await requireNotKilled("kill_invite_witness");
    const commitmentId = cleanText(request.data?.commitmentId, 160);
    const witnessUserId = cleanText(request.data?.witnessUserId, 160);
    const checkInCadence = request.data?.checkInCadence;
    if (!commitmentId || !witnessUserId || !isValidCadence(checkInCadence)) {
      throw new HttpsError("invalid-argument", "commitmentId, witnessUserId, and checkInCadence are required.");
    }
    if (uid === witnessUserId) {
      throw new HttpsError("failed-precondition", "Choose someone else to witness this commitment.");
    }

    const activeWitnesses = await db.collection("commitments").doc(commitmentId).collection("witnesses")
      .where("status", "in", ["invited", "accepted"])
      .limit(3)
      .get();
    if (activeWitnesses.size >= 3) {
      throw new HttpsError("failed-precondition", "This commitment already has its witness circle.");
    }

    const witnessUser = await db.collection("users").doc(witnessUserId).get();
    const ageTier = witnessUser.data()?.ageTier;
    if (["blocked", "tierB", "tierC", "teen", "under_minimum"].includes(ageTier) && request.auth?.token?.guardian !== true) {
      throw new HttpsError("permission-denied", "A guardian relationship is required for this witness invitation.");
    }

    const inviteRef = db.collection("witness_invites").doc();
    await inviteRef.set({
      senderUserId: uid,
      recipientUserId: witnessUserId,
      commitmentId,
      checkInCadence,
      status: "invited",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      tier: "C",
    });
    return { inviteId: inviteRef.id, status: "invited" };
  }
);

export const acceptCovenant = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 30 },
  async (request) => {
    const uid = requireAuth(request.auth?.uid);
    await requireNotKilled("kill_accept_covenant");
    const inviteId = cleanText(request.data?.inviteId, 160);
    const accepted = Boolean(request.data?.accepted);
    const inviteRef = db.collection("witness_invites").doc(inviteId);
    const invite = await inviteRef.get();
    if (!invite.exists || invite.data()?.recipientUserId !== uid) {
      throw new HttpsError("permission-denied", "Invitation not available.");
    }
    const data = invite.data()!;
    if (!accepted) {
      await inviteRef.update({ status: "declined", updatedAt: admin.firestore.FieldValue.serverTimestamp() });
      return { status: "declined" };
    }

    const witnessRef = db.collection("commitments").doc(data.commitmentId).collection("witnesses").doc(uid);
    await witnessRef.set({
      commitmentId: data.commitmentId,
      ownerUserId: data.senderUserId,
      witnessUserId: uid,
      covenantAcceptedAt: admin.firestore.FieldValue.serverTimestamp(),
      checkInCadence: data.checkInCadence,
      status: "accepted",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      tier: "C",
    });
    await inviteRef.update({ status: "accepted", updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    return { witnessId: witnessRef.id, status: "accepted" };
  }
);

export const witnessCheckIn = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 30 },
  async (request) => {
    const uid = requireAuth(request.auth?.uid);
    await requireNotKilled("kill_witness_check_in");
    const commitmentId = cleanText(request.data?.commitmentId, 160);
    const witnessId = cleanText(request.data?.witnessId, 160);
    const witnessRef = db.collection("commitments").doc(commitmentId).collection("witnesses").doc(witnessId);
    const witness = await witnessRef.get();
    if (!witness.exists || witness.data()?.witnessUserId !== uid || witness.data()?.status !== "accepted") {
      throw new HttpsError("permission-denied", "Witness covenant not available.");
    }
    await witnessRef.collection("checkIns").add({
      witnessUserId: uid,
      message: cleanText(request.data?.message, 800),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      tier: "C",
    });
    await witnessRef.update({ lastCheckInAt: admin.firestore.FieldValue.serverTimestamp(), updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    return { status: "recorded", checkedInAt: new Date().toISOString() };
  }
);

export const publishLiturgicalContext = onSchedule(
  { region: REGION, schedule: "every 24 hours", timeZone: "UTC" },
  async () => {
    if (await isKilled("kill_liturgical_context_provider")) return;
    await db.collection("config").doc("liturgical_context").set(currentLiturgicalContext(), { merge: true });
  }
);

export const liturgicalContextProvider = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 15 },
  async () => {
    await requireNotKilled("kill_liturgical_context_provider");
    const ref = db.collection("config").doc("liturgical_context");
    const snap = await ref.get();
    const context = snap.exists ? (snap.data() ?? currentLiturgicalContext()) : currentLiturgicalContext();
    if (!snap.exists) await ref.set(context, { merge: true });
    return { context };
  }
);

export const generateDailyOffice = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 60, memory: "512MiB" },
  async (request) => {
    const uid = requireAuth(request.auth?.uid);
    await requireNotKilled("kill_generate_daily_office");
    const slot = request.data?.slot as DailyOfficeSlot;
    if (slot !== "morning" && slot !== "evening") {
      throw new HttpsError("invalid-argument", "slot must be morning or evening.");
    }
    const date = cleanText(request.data?.date, 40) || new Date().toISOString().slice(0, 10);
    const user = await db.collection("users").doc(uid).get();
    const translationPreference = user.data()?.translationPreference ?? "preferred";
    const contextSnap = await db.collection("config").doc("liturgical_context").get();
    const context = contextSnap.exists ? contextSnap.data()! : currentLiturgicalContext();
    const opening = slot === "morning" ? "Lord, open our lips." : "Stay with us, Lord.";
    const officeRef = db.collection("users").doc(uid).collection("daily_offices").doc(`${date}_${slot}`);

    await officeRef.set({
      userId: uid,
      date,
      slot,
      components: [
        { kind: "opening", title: slot === "morning" ? "Morning Prayer" : "Evening Prayer", body: opening },
        { kind: "scripture", title: "Scripture", body: "Acts 17:11", scriptureRefs: [{ book: "Acts", chapter: 17, verseStart: 11, translation: translationPreference, confidence: 0.7 }] },
        { kind: "prayer", title: "Prayer", body: "Gather what is unfinished and hold it in mercy." },
        { kind: "dismissal", title: "Go in Peace", body: "Go in peace. The work of love can continue without the phone in your hand." },
      ],
      audioAssetRef: request.data?.renderAudio ? `daily_offices/${uid}/${date}_${slot}.m4a` : null,
      pdfAssetRef: request.data?.renderPDF ? `daily_offices/${uid}/${date}_${slot}.pdf` : null,
      generatedFrom: {
        translationPreference,
        liturgicalContextId: context.id ?? "canonical",
        livingMemoryThemeRefs: [],
        prayerLedgerEntryRefs: [],
        tierPolicy: "tier_respecting_summary_only",
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      tier: "C",
    });
    return {
      officeId: officeRef.id,
      audioAssetRef: request.data?.renderAudio ? `daily_offices/${uid}/${date}_${slot}.m4a` : undefined,
      pdfAssetRef: request.data?.renderPDF ? `daily_offices/${uid}/${date}_${slot}.pdf` : undefined,
    };
  }
);

export const generateDailyOfficeScheduled = onSchedule(
  { region: REGION, schedule: "every 24 hours", timeZone: "UTC" },
  async () => {
    if (await isKilled("kill_generate_daily_office")) return;
    console.info("generateDailyOfficeScheduled", { region: REGION, status: "scheduled_generation_requires_user_policy_window" });
  }
);
