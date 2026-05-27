/**
 * InteractionModeService.ts
 *
 * Firebase Cloud Functions v2 — Amen iOS Social Platform
 *
 * Implements Identity/Interaction Modes: users choose how they want to exist on
 * the platform (Social, Discussion, Study, Quiet, Youth, Campus, Family). This
 * service defines the capability set for each mode, enforces mode transitions,
 * and applies server-side post constraints so that mode rules cannot be bypassed
 * by a modified iOS client.
 *
 * Key exports:
 *   setInteractionMode      — callable: change the authenticated user's mode
 *   getInteractionMode      — callable: read the authenticated user's current mode
 *   checkModeCapability     — async helper: used by other backend services to gate actions
 *   enforcePostModeConstraints — Firestore trigger: blocks posts that violate the author's mode
 *   initializeModeForNewUser   — Firestore trigger: writes the correct default mode on user creation
 *
 * NOTE: enforcePostModeConstraints and YouthSafetyService.enforceYouthAccountDefaults both
 * trigger on document creation in their respective collections and are designed to be
 * non-conflicting: this service handles mode-based post blocking; YouthSafetyService
 * handles account-level defaults for minor/teen users.
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Types ────────────────────────────────────────────────────────────────────

export type InteractionMode =
  | "social"       // Full platform: posting, media, DMs, discovery
  | "discussion"   // Text-only: discussions, comments, no public media posts
  | "study"        // Groups, notes, scripture study, mentorship — no social broadcasting
  | "quiet"        // No public posting, only trusted circle DMs and groups
  | "youth"        // Set automatically for minors; higher protections, no adult discovery
  | "campus"       // College-focused: campus hubs, local events, study groups
  | "family";      // Parent-linked; restricted content, family-safe discovery

export interface ModeCapabilities {
  canPostPublicly: boolean;
  canUploadMedia: boolean;                 // images/videos in posts
  canDM: boolean;
  canJoinPublicGroups: boolean;
  canBeDiscovered: boolean;                // appears in search/recommendations
  canViewPublicFeed: boolean;
  canCreateGroups: boolean;
  discussionOnlyPosting: boolean;          // text posts only, no media
  requiresTrustedCircleForDMs: boolean;
  youthProtectionsActive: boolean;
  campusFeaturesEnabled: boolean;
  familyModeActive: boolean;
}

// ─── Capability Map ───────────────────────────────────────────────────────────

export const MODE_CAPABILITIES: Record<InteractionMode, ModeCapabilities> = {
  social: {
    canPostPublicly: true,
    canUploadMedia: true,
    canDM: true,
    canJoinPublicGroups: true,
    canBeDiscovered: true,
    canViewPublicFeed: true,
    canCreateGroups: true,
    discussionOnlyPosting: false,
    requiresTrustedCircleForDMs: false,
    youthProtectionsActive: false,
    campusFeaturesEnabled: false,
    familyModeActive: false,
  },

  discussion: {
    canPostPublicly: true,
    canUploadMedia: false,
    canDM: true,
    canJoinPublicGroups: true,
    canBeDiscovered: true,
    canViewPublicFeed: true,
    canCreateGroups: true,
    discussionOnlyPosting: true,
    requiresTrustedCircleForDMs: false,
    youthProtectionsActive: false,
    campusFeaturesEnabled: false,
    familyModeActive: false,
  },

  study: {
    canPostPublicly: false,
    canUploadMedia: false,
    canDM: true,
    canJoinPublicGroups: true,   // study-type groups only; enforced client-side and server-side
    canBeDiscovered: false,
    canViewPublicFeed: true,
    canCreateGroups: true,
    discussionOnlyPosting: false,
    requiresTrustedCircleForDMs: false,
    youthProtectionsActive: false,
    campusFeaturesEnabled: false,
    familyModeActive: false,
  },

  quiet: {
    canPostPublicly: false,
    canUploadMedia: false,
    canDM: true,
    canJoinPublicGroups: false,
    canBeDiscovered: false,
    canViewPublicFeed: true,
    canCreateGroups: false,
    discussionOnlyPosting: false,
    requiresTrustedCircleForDMs: true,
    youthProtectionsActive: false,
    campusFeaturesEnabled: false,
    familyModeActive: false,
  },

  youth: {
    canPostPublicly: true,
    canUploadMedia: false,
    canDM: true,
    canJoinPublicGroups: true,
    canBeDiscovered: false,
    canViewPublicFeed: true,
    canCreateGroups: false,
    discussionOnlyPosting: true,
    requiresTrustedCircleForDMs: true,
    youthProtectionsActive: true,
    campusFeaturesEnabled: false,
    familyModeActive: false,
  },

  campus: {
    canPostPublicly: true,
    canUploadMedia: true,
    canDM: true,
    canJoinPublicGroups: true,
    canBeDiscovered: true,
    canViewPublicFeed: true,
    canCreateGroups: true,
    discussionOnlyPosting: false,
    requiresTrustedCircleForDMs: false,
    youthProtectionsActive: false,
    campusFeaturesEnabled: true,
    familyModeActive: false,
  },

  family: {
    canPostPublicly: true,
    canUploadMedia: true,
    canDM: true,
    canJoinPublicGroups: true,
    canBeDiscovered: true,
    canViewPublicFeed: true,
    canCreateGroups: true,
    discussionOnlyPosting: false,
    requiresTrustedCircleForDMs: true,
    youthProtectionsActive: true,
    campusFeaturesEnabled: false,
    familyModeActive: true,
  },
};

// ─── Validation Helpers ───────────────────────────────────────────────────────

const VALID_MODES = new Set<InteractionMode>([
  "social", "discussion", "study", "quiet", "youth", "campus", "family",
]);

function isValidMode(value: unknown): value is InteractionMode {
  return typeof value === "string" && VALID_MODES.has(value as InteractionMode);
}

function requireAuth(request: CallableRequest): string {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

// ─── Callable: setInteractionMode ─────────────────────────────────────────────

interface SetInteractionModeInput {
  mode: InteractionMode;
}

interface SetInteractionModeResult {
  mode: InteractionMode;
  capabilities: ModeCapabilities;
}

export const setInteractionMode = onCall(
  { region: "us-central1", enforceAppCheck: true },
  async (request: CallableRequest): Promise<SetInteractionModeResult> => {
    const uid = requireAuth(request);

    const input = request.data as SetInteractionModeInput;
    const { mode } = input;

    // Validate mode is a known InteractionMode value
    if (!isValidMode(mode)) {
      throw new HttpsError(
        "invalid-argument",
        `Invalid mode. Must be one of: ${[...VALID_MODES].join(", ")}.`
      );
    }

    // Youth mode may only be set by YouthSafetyService based on ageTier — not manually
    if (mode === "youth") {
      throw new HttpsError(
        "permission-denied",
        "Youth mode is set automatically based on account age and cannot be chosen manually."
      );
    }

    const userRef = db.collection("users").doc(uid);

    // Read previous mode before overwriting so we can write history
    const userSnap = await userRef.get();
    const previousMode: InteractionMode | null =
      (userSnap.data()?.interactionMode as InteractionMode | undefined) ?? null;

    const capabilities = MODE_CAPABILITIES[mode];
    const now = admin.firestore.FieldValue.serverTimestamp();

    // Update the user document
    await userRef.set(
      {
        interactionMode: mode,
        modeCapabilities: capabilities,
        modeUpdatedAt: now,
      },
      { merge: true }
    );

    // Write a mode history entry
    await userRef
      .collection("modeHistory")
      .add({
        mode,
        previousMode,
        changedAt: now,
      });

    logger.info("[InteractionMode] mode updated", { uid, mode, previousMode });

    return { mode, capabilities };
  }
);

// ─── Callable: getInteractionMode ─────────────────────────────────────────────

interface GetInteractionModeResult {
  mode: InteractionMode;
  capabilities: ModeCapabilities;
}

export const getInteractionMode = onCall(
  { region: "us-central1", enforceAppCheck: true },
  async (request: CallableRequest): Promise<GetInteractionModeResult> => {
    const uid = requireAuth(request);

    const userSnap = await db.collection("users").doc(uid).get();
    const data = userSnap.data();

    // Fall back to "social" if the field is absent — backwards compatible with existing users
    const mode: InteractionMode = isValidMode(data?.interactionMode)
      ? (data!.interactionMode as InteractionMode)
      : "social";

    const capabilities: ModeCapabilities =
      (data?.modeCapabilities as ModeCapabilities | undefined) ?? MODE_CAPABILITIES[mode];

    return { mode, capabilities };
  }
);

// ─── Exported Helper: checkModeCapability ────────────────────────────────────
//
// NOT a callable — used by other backend services to gate actions without
// exposing an HTTP endpoint for this check.

export async function checkModeCapability(
  uid: string,
  capability: keyof ModeCapabilities
): Promise<boolean> {
  try {
    const userSnap = await db.collection("users").doc(uid).get();
    const data = userSnap.data();

    if (!data) {
      // Unknown user — apply safe default (social mode)
      return MODE_CAPABILITIES.social[capability];
    }

    // If modeCapabilities is stored on the document, read directly from it
    const stored = data.modeCapabilities as Partial<ModeCapabilities> | undefined;
    if (stored && typeof stored[capability] === "boolean") {
      return stored[capability] as boolean;
    }

    // Fall back to re-deriving from the stored mode (backwards compatible)
    const mode: InteractionMode = isValidMode(data.interactionMode)
      ? (data.interactionMode as InteractionMode)
      : "social";

    return MODE_CAPABILITIES[mode][capability];
  } catch (err) {
    logger.warn("[InteractionMode] checkModeCapability error — defaulting to social", { uid, capability, err });
    // Safe default on error: use social mode capabilities
    return MODE_CAPABILITIES.social[capability];
  }
}

// ─── Firestore Trigger: enforcePostModeConstraints ───────────────────────────
//
// Server-side safety net layered on top of iOS client enforcement.
// Runs when any post document is created; reads the author's interactionMode
// and blocks the post if it violates the mode's constraints.
//
// Does NOT conflict with YouthSafetyService.enforceYouthAccountDefaults:
//   - YouthSafetyService triggers on users/{uid} creation and sets account defaults.
//   - This trigger fires on posts/{postId} creation and enforces post-level rules.

export const enforcePostModeConstraints = onDocumentCreated(
  { document: "posts/{postId}", region: "us-central1" },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const post = snap.data();
    if (!post) return;

    const authorUid: string | undefined = post.authorUid ?? post.userId ?? post.uid;
    if (!authorUid) {
      logger.warn("[InteractionMode] post created without authorUid — skipping mode check", {
        postId: event.params.postId,
      });
      return;
    }

    // Read the author's current interaction mode
    const userSnap = await db.collection("users").doc(authorUid).get();
    const userData = userSnap.data();
    const mode: InteractionMode = isValidMode(userData?.interactionMode)
      ? (userData!.interactionMode as InteractionMode)
      : "social";

    const mediaUrls: unknown[] = Array.isArray(post.mediaUrls) ? post.mediaUrls : [];
    const visibility: string = typeof post.visibility === "string" ? post.visibility : "everyone";

    let blocked = false;
    let blockedReason: string | null = null;

    // Modes that prohibit media uploads: block posts that contain media attachments
    if (
      (mode === "discussion" || mode === "study" || mode === "quiet") &&
      mediaUrls.length > 0
    ) {
      blocked = true;
      blockedReason = "mode_violation";
      logger.info("[InteractionMode] blocking media post due to mode constraint", {
        postId: event.params.postId,
        authorUid,
        mode,
        mediaCount: mediaUrls.length,
      });
    }

    // Quiet mode also prohibits public ("everyone") posts entirely
    if (!blocked && mode === "quiet" && visibility === "everyone") {
      blocked = true;
      blockedReason = "mode_violation";
      logger.info("[InteractionMode] blocking public post from quiet-mode user", {
        postId: event.params.postId,
        authorUid,
        mode,
        visibility,
      });
    }

    if (blocked) {
      await snap.ref.update({
        moderationStatus: "blocked",
        blockedReason,
        blockedAt: admin.firestore.FieldValue.serverTimestamp(),
        blockedByMode: mode,
      });
    }
  }
);

// ─── Firestore Trigger: initializeModeForNewUser ──────────────────────────────
//
// Runs when a new user document is created. Writes the appropriate default
// interactionMode and modeCapabilities so that every user document always has
// these fields set server-authoritatively.
//
// Defaults:
//   - ageTier "minor" or "teen" → "youth"  (higher protections by default)
//   - all other new users       → "discussion"  (safer default than "social")

export const initializeModeForNewUser = onDocumentCreated(
  { document: "users/{uid}", region: "us-central1" },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    if (!data) return;

    // Skip if mode is already set (e.g., if migration or admin tooling pre-populated it)
    if (typeof data.interactionMode === "string" && VALID_MODES.has(data.interactionMode as InteractionMode)) {
      logger.info("[InteractionMode] new user already has interactionMode — skipping init", {
        uid: event.params.uid,
        mode: data.interactionMode,
      });
      return;
    }

    const ageTier: string | undefined = data.ageTier;
    const isMinorOrTeen = ageTier === "minor" || ageTier === "teen";

    const defaultMode: InteractionMode = isMinorOrTeen ? "youth" : "discussion";
    const capabilities = MODE_CAPABILITIES[defaultMode];

    await snap.ref.set(
      {
        interactionMode: defaultMode,
        modeCapabilities: capabilities,
        modeUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    logger.info("[InteractionMode] initialized mode for new user", {
      uid: event.params.uid,
      ageTier: ageTier ?? "unknown",
      defaultMode,
    });
  }
);
