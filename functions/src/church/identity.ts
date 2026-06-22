// identity.ts — SERVER-SIDE resolution of uid, isMinor, and church preferences.
//
// The client NEVER supplies uid, isMinor, or preferences. We resolve them from
// context.auth and Firestore. isMinor fails CLOSED: a missing/unknown age tier
// is treated as a minor (the protective default), consistent with ageTier.js.

import { getFirestore } from "firebase-admin/firestore";
import type { ChurchPreferences } from "../contracts/church";

// Single source of truth for which age tiers denote a minor (COPPA). Shared with
// firestore.rules and auth helpers via ../../ageTier — do not fork this list.
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { MINOR_TIERS } = require("../../ageTier") as { MINOR_TIERS: string[] };

const db = getFirestore();

export interface ResolvedIdentity {
  uid: string;
  isMinor: boolean;
  preferences: ChurchPreferences | null;
}

/** Resolve identity from an authenticated callable request. */
export async function resolveIdentity(uid: string): Promise<ResolvedIdentity> {
  const [userSnap, prefsSnap] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection("users").doc(uid).collection("churchPreferences").doc("preferences").get(),
  ]);

  const ageTier = userSnap.exists ? (userSnap.data()?.ageTier as string | undefined) : undefined;
  // Fail closed: no/unknown tier → treat as minor.
  const isMinor = ageTier == null || MINOR_TIERS.includes(ageTier);

  const preferences = prefsSnap.exists
    ? (prefsSnap.data() as ChurchPreferences)
    : null;

  return { uid, isMinor, preferences };
}
