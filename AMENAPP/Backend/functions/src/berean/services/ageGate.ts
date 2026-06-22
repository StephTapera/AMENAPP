import * as admin from "firebase-admin";

export interface AgeGateResult {
  allowed: boolean;
  reason?: string;
}

// Module-level kill switch cache
let killSwitchCachedValue: boolean = false;
let killSwitchLastFetchedAt: number = 0;
const KILL_SWITCH_TTL_MS = 30_000;

export async function enforceAgeGate(
  uid: string,
  db: admin.firestore.Firestore
): Promise<AgeGateResult> {
  try {
    const userDoc = await db.collection("users").doc(uid).get();

    if (!userDoc.exists) {
      // No user document — fail closed
      return { allowed: false, reason: "dob_required" };
    }

    const userData = userDoc.data() as Record<string, unknown>;

    // Explicit minor flag takes precedence
    if (userData.minorStatus === true) {
      return { allowed: false, reason: "minor_restricted" };
    }

    // Attempt to determine age from known field names
    const now = new Date();
    let birthYear: number | null = null;

    if (typeof userData.birthYear === "number") {
      birthYear = userData.birthYear;
    } else if (typeof userData.dob === "string" && userData.dob.length > 0) {
      const parsed = new Date(userData.dob);
      if (!isNaN(parsed.getTime())) {
        birthYear = parsed.getFullYear();
      }
    } else if (
      typeof userData.birthDate === "string" &&
      userData.birthDate.length > 0
    ) {
      const parsed = new Date(userData.birthDate);
      if (!isNaN(parsed.getTime())) {
        birthYear = parsed.getFullYear();
      }
    }

    if (birthYear === null) {
      // No date of birth info — fail closed per COPPA requirements
      return { allowed: false, reason: "dob_required" };
    }

    const age = now.getFullYear() - birthYear;
    if (age < 13) {
      return { allowed: false, reason: "coppa_age_gate" };
    }

    return { allowed: true };
  } catch (err) {
    console.error("[ageGate] enforceAgeGate error for uid", uid, err);
    return { allowed: false, reason: "unknown" };
  }
}

export async function checkBereanKillSwitch(
  db: admin.firestore.Firestore
): Promise<boolean> {
  const now = Date.now();

  if (now - killSwitchLastFetchedAt < KILL_SWITCH_TTL_MS) {
    return killSwitchCachedValue;
  }

  try {
    const flagsDoc = await db.collection("system").doc("featureFlags").get();
    const data = flagsDoc.data() as Record<string, unknown> | undefined;
    const killSwitch =
      data && typeof data.bereanChatKillSwitch === "boolean"
        ? data.bereanChatKillSwitch
        : false;

    killSwitchCachedValue = killSwitch;
    killSwitchLastFetchedAt = Date.now();

    return killSwitch;
  } catch (err) {
    console.error("[ageGate] checkBereanKillSwitch error", err);
    // Fail open — do not block users if kill switch cannot be read
    return false;
  }
}
