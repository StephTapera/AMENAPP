"use strict";
// identity.ts — SERVER-SIDE resolution of uid, isMinor, and church preferences.
//
// The client NEVER supplies uid, isMinor, or preferences. We resolve them from
// context.auth and Firestore. isMinor fails CLOSED: a missing/unknown age tier
// is treated as a minor (the protective default), consistent with ageTier.js.
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveIdentity = resolveIdentity;
const firestore_1 = require("firebase-admin/firestore");
// Single source of truth for which age tiers denote a minor (COPPA). Shared with
// firestore.rules and auth helpers via ../../ageTier — do not fork this list.
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { MINOR_TIERS } = require("../../ageTier");
const db = (0, firestore_1.getFirestore)();
/** Resolve identity from an authenticated callable request. */
async function resolveIdentity(uid) {
    const [userSnap, prefsSnap] = await Promise.all([
        db.collection("users").doc(uid).get(),
        db.collection("users").doc(uid).collection("churchPreferences").doc("preferences").get(),
    ]);
    const ageTier = userSnap.exists ? userSnap.data()?.ageTier : undefined;
    // Fail closed: no/unknown tier → treat as minor.
    const isMinor = ageTier == null || MINOR_TIERS.includes(ageTier);
    const preferences = prefsSnap.exists
        ? prefsSnap.data()
        : null;
    return { uid, isMinor, preferences };
}
