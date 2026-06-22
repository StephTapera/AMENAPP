// capabilities/registry/callables.ts — Capability Registry callable (Wave 1: Lane B)
//
// capabilityRegistry_list: returns active capabilities for a surface.
// App Check is required for every authenticated capability surface.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore } from "firebase-admin/firestore";
import {
  CapabilitySurface,
  CapabilityManifest,
  CapabilityListRequest,
  CapabilityListResponse,
} from "../types";

const VALID_SURFACES: CapabilitySurface[] = ["berean", "messages", "notes"];

export const capabilityRegistry_list = onCall(
  { enforceAppCheck: true },
  async (request): Promise<CapabilityListResponse> => {
    // Auth required
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    const body = request.data as Partial<CapabilityListRequest>;

    // Validate surface
    if (!body.surface || !VALID_SURFACES.includes(body.surface)) {
      throw new HttpsError(
        "invalid-argument",
        `surface must be one of: ${VALID_SURFACES.join(", ")}`
      );
    }
    const surface: CapabilitySurface = body.surface;

    logger.info("[CAP] capabilityRegistry_list", { uid, surface });

    const db = getFirestore();

    // Query capabilities where status == "active" AND surfaces array-contains surface
    const snap = await db
      .collection("capabilities")
      .where("status", "==", "active")
      .where("surfaces", "array-contains", surface)
      .get();

    const capabilities: CapabilityManifest[] = snap.docs.map((doc) => {
      const data = doc.data();
      return {
        id: data.id ?? doc.id,
        displayName: data.displayName ?? "",
        tagline: data.tagline ?? "",
        iconSymbol: data.iconSymbol ?? "",
        surfaces: data.surfaces ?? [],
        requiredContext: data.requiredContext ?? [],
        optionalContext: data.optionalContext ?? [],
        entryFunction: data.entryFunction ?? "",
        minAppVersion: data.minAppVersion ?? "1.0.0",
        status: data.status ?? "active",
        tier: data.tier ?? "free",
      } as CapabilityManifest;
    });

    return { capabilities };
  }
);
