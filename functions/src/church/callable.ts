// callable.ts — Find a Church v2 callables (v2 onCall, us-east1).
//
// Every callable resolves uid / isMinor / preferences SERVER-SIDE from auth and
// clamps/validates client geo. The minor branch (§5.2) and visit-plan mirror
// conditions (§5.3) are enforced IN-FUNCTION here. Nothing trusts client claims.

import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import type {
  ChurchDiscoveryRequest, ChurchDiscoveryResponse, ChurchMatch, ChurchProfile,
  ChurchFilter, PlanVisitRequest, PlanVisitResponse, ReportReason,
  Church, VisitPlan,
} from "../contracts/church";
import { resolveIdentity, type ResolvedIdentity } from "./identity";
import { isValidCenter, clampRadius } from "./geo";
import type { RankingContext } from "./ranking";
import {
  assembleChurchDiscovery as assembleDiscovery,
  searchChurches as searchEngine,
  getChurchProfile as getProfileEngine,
} from "./engine";

const db = getFirestore();
const OPTS = { enforceAppCheck: true, region: "us-east1" as const };

function requireAuth(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");
  return uid;
}

function buildContext(center: { lat: number; lng: number }, radiusMeters: number,
                      identity: ResolvedIdentity): RankingContext {
  return {
    center,
    radiusMeters: clampRadius(radiusMeters),
    nowMs: Date.now(),
    preferences: identity.preferences,
    isMinor: identity.isMinor,
  };
}

// ── assembleChurchDiscovery ────────────────────────────────────────────────

export const assembleChurchDiscovery = onCall(OPTS, async (request): Promise<ChurchDiscoveryResponse> => {
  const uid = requireAuth(request);
  const data = (request.data ?? {}) as Partial<ChurchDiscoveryRequest>;
  if (!isValidCenter(data.center)) {
    throw new HttpsError("invalid-argument", "center {lat,lng} required.");
  }
  const radiusMeters = clampRadius(Number(data.radiusMeters ?? 0));
  const filters: ChurchFilter[] = Array.isArray(data.filters) ? data.filters : [];

  const identity = await resolveIdentity(uid);
  const ctx = buildContext(data.center, radiusMeters, identity);
  const req: ChurchDiscoveryRequest = {
    center: data.center, radiusMeters, filters,
    nowIso: typeof data.nowIso === "string" ? data.nowIso : new Date(ctx.nowMs).toISOString(),
    sessionId: typeof data.sessionId === "string" ? data.sessionId : "",
  };
  return assembleDiscovery(req, ctx);
});

// ── searchChurches ─────────────────────────────────────────────────────────

export const searchChurches = onCall(OPTS, async (request): Promise<{ items: ChurchMatch[]; nextPage: number | null }> => {
  const uid = requireAuth(request);
  const data = (request.data ?? {}) as {
    q?: string; center?: unknown; radiusMeters?: number; filters?: ChurchFilter[]; page?: number;
  };
  if (!isValidCenter(data.center)) {
    throw new HttpsError("invalid-argument", "center {lat,lng} required.");
  }
  const q = String(data.q ?? "").slice(0, 200);
  const radiusMeters = clampRadius(Number(data.radiusMeters ?? 0));
  const filters = Array.isArray(data.filters) ? data.filters : [];
  const page = Number.isFinite(data.page) ? Math.max(0, Number(data.page)) : 0;

  const identity = await resolveIdentity(uid);
  const ctx = buildContext(data.center, radiusMeters, identity);
  return searchEngine(q, data.center, radiusMeters, filters, page, ctx);
});

// ── getChurchProfile ───────────────────────────────────────────────────────

export const getChurchProfile = onCall(OPTS, async (request): Promise<ChurchProfile> => {
  requireAuth(request);
  const churchId = String((request.data ?? {}).churchId ?? "").trim();
  if (!churchId) throw new HttpsError("invalid-argument", "churchId required.");
  try {
    return await getProfileEngine(churchId);
  } catch (e) {
    if (e instanceof Error && e.message === "not-found") {
      throw new HttpsError("not-found", "Church not found.");
    }
    throw e;
  }
});

// ── toggleSavedChurch ──────────────────────────────────────────────────────

export const toggleSavedChurch = onCall(OPTS, async (request): Promise<{ saved: boolean }> => {
  const uid = requireAuth(request);
  const data = (request.data ?? {}) as { churchId?: string; saved?: boolean };
  const churchId = String(data.churchId ?? "").trim();
  if (!churchId) throw new HttpsError("invalid-argument", "churchId required.");
  const saved = data.saved === true;

  const ref = db.collection("users").doc(uid).collection("savedChurches").doc(churchId);
  if (saved) {
    await ref.set({ churchId, savedAt: Date.now() });
  } else {
    await ref.delete();
  }
  return { saved };
});

// ── recordChurchSearch ─────────────────────────────────────────────────────

export const recordChurchSearch = onCall(OPTS, async (request): Promise<void> => {
  const uid = requireAuth(request);
  const data = (request.data ?? {}) as { term?: string; resultChurchId?: string };
  const term = String(data.term ?? "").trim().slice(0, 200);
  if (!term) return;

  const identity = await resolveIdentity(uid);
  // Private-search toggle suppresses writes entirely (§5.1).
  if (identity.preferences?.privateSearch === true) return;

  const ref = db.collection("users").doc(uid).collection("churchSearchHistory").doc();
  await ref.set({
    id: ref.id, term,
    resultChurchId: data.resultChurchId ? String(data.resultChurchId) : null,
    searchedAt: Date.now(),
  });
});

// ── planVisit ──────────────────────────────────────────────────────────────

export const planVisit = onCall(OPTS, async (request): Promise<PlanVisitResponse> => {
  const uid = requireAuth(request);
  const data = (request.data ?? {}) as Partial<PlanVisitRequest>;
  const churchId = String(data.churchId ?? "").trim();
  if (!churchId) throw new HttpsError("invalid-argument", "churchId required.");
  const plannedForIso = String(data.plannedForIso ?? "").trim();
  if (!plannedForIso) throw new HttpsError("invalid-argument", "plannedForIso required.");

  const identity = await resolveIdentity(uid);

  // Determine mirror eligibility (§5.3): verified church AND opt-in AND non-minor.
  const churchSnap = await db.collection("churches").doc(churchId).get();
  if (!churchSnap.exists) throw new HttpsError("not-found", "Church not found.");
  const church = churchSnap.data() as Church;
  const isVerified = church.verification?.status === "verified";

  // HARD minor branch (§5.2): sharedWithChurch is ALWAYS false for minors.
  const sharedWithChurch = !identity.isMinor && isVerified && data.shareWithChurch === true;

  const planRef = db.collection("users").doc(uid).collection("visitPlans").doc();
  const now = Date.now();
  const plan: VisitPlan = {
    id: planRef.id,
    churchId,
    serviceTimeId: data.serviceTimeId ? String(data.serviceTimeId) : null,
    plannedForIso,
    partySize: typeof data.partySize === "number" ? data.partySize : null,
    notes: data.notes ? String(data.notes).slice(0, 500) : null,
    sharedWithChurch,
    createdAt: now,
    updatedAt: now,
  };
  await planRef.set(plan);

  // Mirror to the church ONLY when all conditions hold — and never any minor PII.
  if (sharedWithChurch) {
    const intentRef = db.collection("churches").doc(churchId).collection("visitorIntents").doc();
    await intentRef.set({
      id: intentRef.id,
      visitPlanId: planRef.id,
      plannedForIso,
      partySize: plan.partySize,
      createdAt: now,
    });
  }

  return { visitPlanId: planRef.id, sharedWithChurch };
});

// ── reportChurch ───────────────────────────────────────────────────────────

const VALID_REASONS: ReportReason[] = [
  "misleading_profile", "impersonation", "child_safety_concern",
  "inappropriate_media", "spam", "other",
];

export const reportChurch = onCall(OPTS, async (request): Promise<{ reportId: string }> => {
  const uid = requireAuth(request);
  const data = (request.data ?? {}) as { churchId?: string; reason?: ReportReason; details?: string };
  const churchId = String(data.churchId ?? "").trim();
  if (!churchId) throw new HttpsError("invalid-argument", "churchId required.");
  const reason = data.reason as ReportReason;
  if (!VALID_REASONS.includes(reason)) {
    throw new HttpsError("invalid-argument", "Invalid reason.");
  }
  const details = data.details ? String(data.details).slice(0, 1000) : null;
  const isChildSafety = reason === "child_safety_concern";

  const reportRef = db.collection("churchReports").doc();
  await reportRef.set({
    id: reportRef.id,
    churchId,
    reporterUid: uid,                       // SERVER-stamped, never client-supplied
    reason,
    details,
    state: isChildSafety ? "escalated" : "open",
    createdAt: Date.now(),
  });

  // Routing: child_safety_concern uses the ABSOLUTE-STOP critical path (§5.5) —
  // the canonical moderationQueue critical category, NOT the normal report queue.
  await db.collection("moderationQueue").add({
    type: "church_report",
    churchId,
    reporterUid: uid,
    category: isChildSafety ? "child_safety" : reason,
    priority: isChildSafety ? "critical" : "normal",
    state: isChildSafety ? "pending_crisis" : "pending",
    escalateImmediately: isChildSafety,
    childSafetyEscalated: isChildSafety,
    reportRef: reportRef.path,
    createdAt: FieldValue.serverTimestamp(),
  });

  if (isChildSafety) {
    logger.warn(`[reportChurch] child_safety_concern escalated for church=${churchId}`);
  }
  return { reportId: reportRef.id };
});

// ── requestChurchVerification (org side) ───────────────────────────────────

export const requestChurchVerification = onCall(OPTS, async (request): Promise<{ requestId: string }> => {
  const uid = requireAuth(request);
  const data = (request.data ?? {}) as { churchId?: string; method?: string; evidenceUrl?: string };
  const churchId = String(data.churchId ?? "").trim();
  if (!churchId) throw new HttpsError("invalid-argument", "churchId required.");
  const method = data.method;
  if (method !== "domain" && method !== "doc" && method !== "manual") {
    throw new HttpsError("invalid-argument", "Invalid method.");
  }

  const ref = db.collection("churchVerificationRequests").doc();
  await ref.set({
    id: ref.id,
    churchId,
    requesterUid: uid,                      // SERVER-stamped
    method,
    evidenceUrl: data.evidenceUrl ? String(data.evidenceUrl).slice(0, 500) : null,
    status: "pending",                      // server-managed; client cannot self-verify
    createdAt: Date.now(),
  });
  return { requestId: ref.id };
});

// ── submitChurchClaim (org onboarding) ─────────────────────────────────────

export const submitChurchClaim = onCall(OPTS, async (request): Promise<{ claimId: string }> => {
  const uid = requireAuth(request);
  const data = (request.data ?? {}) as {
    churchId?: string; proposedName?: string; role?: string; contactEmail?: string; evidenceUrl?: string;
  };
  const contactEmail = String(data.contactEmail ?? "").trim();
  if (!contactEmail) throw new HttpsError("invalid-argument", "contactEmail required.");
  const role = data.role;
  if (role !== "owner" && role !== "pastor" && role !== "executive_admin" && role !== "editor") {
    throw new HttpsError("invalid-argument", "Invalid role.");
  }

  const ref = db.collection("churchClaims").doc();
  await ref.set({
    id: ref.id,
    claimantUid: uid,                       // SERVER-stamped
    churchId: data.churchId ? String(data.churchId) : null,
    proposedName: data.proposedName ? String(data.proposedName).slice(0, 200) : null,
    role,
    contactEmail: contactEmail.slice(0, 320),
    evidenceUrl: data.evidenceUrl ? String(data.evidenceUrl).slice(0, 500) : null,
    status: "pending",                      // server-managed
    createdAt: Date.now(),
  });
  return { claimId: ref.id };
});
