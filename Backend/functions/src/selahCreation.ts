// selahCreation.ts
// AMEN Backend — Selah Creation callables
//
// Exports:
//   generateC2PAManifest  — creates a provenance manifest record for a testimony
//   createRemixLineage    — transactional lineage write for remixed content
//
// Both callables require authentication and App Check.
// Region: us-central1

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";

const db = admin.firestore();

// MARK: - Auth / App Check helpers

function requireAuth(auth: { uid: string } | undefined): string {
  if (!auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return auth.uid;
}

function requireAppCheck(app: { appId?: string } | undefined) {
  if (!app) {
    throw new HttpsError("failed-precondition", "App Check required.");
  }
}

// MARK: - generateC2PAManifest
//
// Generates a provenance manifest record for a testimony.
// This is a stub — real C2PA signing would use a PKI system.
//
// Stores at:  c2paManifests/{testimonyId}
// Returns:    { manifestRef: "c2paManifests/{testimonyId}", verified: true }
//
// The manifest record includes:
//   - authorUid        — the authenticated creator
//   - timestamp        — server-side creation time
//   - contentHash      — SHA-256 of testimonyId + authorUid + timestamp (stub)
//   - signatureStub    — placeholder for future PKI signature
//
// Invariant: once written, the manifest record is immutable.
// The iOS publish layer hard-fails if manifestRef is absent.

export const generateC2PAManifest = onCall(
  {
    region: "us-central1",
    enforceAppCheck: true,
  },
  async (request) => {
    requireAppCheck(request.app);
    const uid = requireAuth(request.auth);

    const { testimonyId, authorUid } = request.data as {
      testimonyId?: string;
      authorUid?: string;
    };

    if (!testimonyId || typeof testimonyId !== "string" || testimonyId.trim() === "") {
      throw new HttpsError("invalid-argument", "testimonyId is required.");
    }

    // Confirm the requesting user matches the declared authorUid (anti-spoofing)
    if (authorUid && authorUid !== uid) {
      throw new HttpsError(
        "permission-denied",
        "authorUid must match the authenticated user."
      );
    }

    const manifestRef = `c2paManifests/${testimonyId}`;
    const docRef = db.doc(manifestRef);

    // Idempotent: if the manifest already exists, return the existing ref.
    const existing = await docRef.get();
    if (existing.exists) {
      return { manifestRef, verified: true };
    }

    const now = admin.firestore.Timestamp.now();

    // Stub content hash: in production replace with real SHA-256 via PKI
    const contentHashInput = `${testimonyId}:${uid}:${now.toMillis()}`;
    const contentHash = Buffer.from(contentHashInput).toString("base64");

    const manifestData = {
      testimonyId,
      authorUid: uid,
      timestamp: now,
      contentHash,
      signatureStub: `stub:${contentHash.slice(0, 16)}`,
      verified: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // Fail closed: if the write fails, the iOS layer will not be able to publish.
    await docRef.set(manifestData);

    return { manifestRef, verified: true };
  }
);

// MARK: - createRemixLineage
//
// Transactionally writes a RemixLineage document to remixLineage/{id}.
//
// Transaction logic:
//   1. Look up the parent artifact's existing lineage entry (where childArtifactId == parentArtifactId).
//   2. If found, inherit its rootArtifactId — preserving the full chain to the original root.
//   3. If not found, the parent IS the root: rootArtifactId = parentArtifactId.
//   4. Write the new lineage document atomically.
//
// Returns the full RemixLineage record.
//
// No counters are stored or returned — attribution chain only.

export const createRemixLineage = onCall(
  {
    region: "us-central1",
    enforceAppCheck: true,
  },
  async (request) => {
    requireAppCheck(request.app);
    const uid = requireAuth(request.auth);

    const { parentArtifactId, childArtifactId, creatorUid } = request.data as {
      parentArtifactId?: string;
      childArtifactId?: string;
      creatorUid?: string;
    };

    if (!parentArtifactId || !childArtifactId) {
      throw new HttpsError(
        "invalid-argument",
        "parentArtifactId and childArtifactId are required."
      );
    }

    // Confirm the requesting user matches the declared creatorUid
    if (creatorUid && creatorUid !== uid) {
      throw new HttpsError(
        "permission-denied",
        "creatorUid must match the authenticated user."
      );
    }

    const lineageId = db.collection("remixLineage").doc().id;
    const lineageRef = db.collection("remixLineage").doc(lineageId);

    let rootArtifactId: string;

    await db.runTransaction(async (tx) => {
      // Find the parent's own lineage entry (if any) to resolve rootArtifactId
      const parentLineageQuery = await db
        .collection("remixLineage")
        .where("childArtifactId", "==", parentArtifactId)
        .limit(1)
        .get();

      if (!parentLineageQuery.empty) {
        // Parent has a lineage — inherit its root
        const parentLineageDoc = parentLineageQuery.docs[0];
        rootArtifactId = parentLineageDoc.data().rootArtifactId as string;
      } else {
        // Parent is the root
        rootArtifactId = parentArtifactId;
      }

      const now = admin.firestore.Timestamp.now();

      tx.set(lineageRef, {
        id: lineageId,
        rootArtifactId,
        parentArtifactId,
        childArtifactId,
        creatorUid: uid,
        createdAt: now,
      });
    });

    const snap = await lineageRef.get();
    const data = snap.data()!;
    const createdAtMs = (data.createdAt as admin.firestore.Timestamp).toMillis();

    return {
      id: lineageId,
      rootArtifactId: data.rootArtifactId,
      parentArtifactId: data.parentArtifactId,
      childArtifactId: data.childArtifactId,
      creatorUid: data.creatorUid,
      createdAt: createdAtMs,
    };
  }
);
