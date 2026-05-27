/**
 * InteractionModeService.test.ts
 *
 * Tests for mode transitions, capability gates, post constraints,
 * and new user initialization.
 *
 * Mocks: firebase-admin, firebase-functions/v2/https, firebase-functions/v2/firestore
 */

import admin from "firebase-admin";

const mockDoc = (admin as any).__mockDoc as {
  get: jest.Mock;
  set: jest.Mock;
  update: jest.Mock;
  collection: jest.Mock;
  ref: { update: jest.Mock };
  __data: Record<string, unknown> | undefined;
};
const mockCollection = (admin as any).__mockCollection as {
  doc: jest.Mock;
  add: jest.Mock;
  where: jest.Mock;
  get: jest.Mock;
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

function makeCallableRequest(data: Record<string, unknown>, uid = "uid-user-1") {
  return { auth: { uid, token: {} }, data } as any;
}

function resetMocks() {
  jest.clearAllMocks();
  mockDoc.__data = undefined;
  mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: !!mockDoc.__data });
  mockDoc.set.mockResolvedValue(undefined);
  mockDoc.update.mockResolvedValue(undefined);
  mockCollection.add.mockResolvedValue({ id: "mock-id" });
}

// ─── Import service under test ────────────────────────────────────────────────

import {
  MODE_CAPABILITIES,
  setInteractionMode as _setInteractionMode,
  getInteractionMode as _getInteractionMode,
  checkModeCapability,
  enforcePostModeConstraints as _enforcePostModeConstraints,
  initializeModeForNewUser as _initializeModeForNewUser,
} from "../InteractionModeService";

// onCall / onDocumentCreated exports are handler functions at runtime but typed
// as HttpsFunction / CloudFunction at compile time. Unwrap to any for tests.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const setInteractionMode = _setInteractionMode as unknown as (req: any) => Promise<any>;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const getInteractionMode = _getInteractionMode as unknown as (req: any) => Promise<any>;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const enforcePostModeConstraints = _enforcePostModeConstraints as unknown as (event: any) => Promise<void>;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const initializeModeForNewUser = _initializeModeForNewUser as unknown as (event: any) => Promise<void>;

// ─── Tests ────────────────────────────────────────────────────────────────────

describe("setInteractionMode callable", () => {
  beforeEach(() => resetMocks());

  test("throws unauthenticated when no auth", async () => {
    await expect(
      setInteractionMode({ auth: null, data: { mode: "social" } } as any)
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("throws permission-denied when mode is 'youth'", async () => {
    await expect(
      setInteractionMode(makeCallableRequest({ mode: "youth" }))
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  test("throws invalid-argument for unknown mode string", async () => {
    await expect(
      setInteractionMode(makeCallableRequest({ mode: "ultramode" }))
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("writes correct capabilities for 'social' mode", async () => {
    mockDoc.__data = { interactionMode: "discussion" };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });

    const result = await setInteractionMode(makeCallableRequest({ mode: "social" }));

    expect(result.mode).toBe("social");
    expect(result.capabilities).toEqual(MODE_CAPABILITIES.social);
    expect(mockDoc.set).toHaveBeenCalledWith(
      expect.objectContaining({
        interactionMode: "social",
        modeCapabilities: MODE_CAPABILITIES.social,
      }),
      expect.objectContaining({ merge: true })
    );
  });

  test("writes correct capabilities for 'quiet' mode", async () => {
    mockDoc.__data = { interactionMode: "social" };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });

    const result = await setInteractionMode(makeCallableRequest({ mode: "quiet" }));

    expect(result.mode).toBe("quiet");
    expect(result.capabilities.canPostPublicly).toBe(false);
    expect(result.capabilities.requiresTrustedCircleForDMs).toBe(true);
  });

  test("writes mode history entry on change", async () => {
    mockDoc.__data = { interactionMode: "social" };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });

    await setInteractionMode(makeCallableRequest({ mode: "study" }));

    // modeHistory.add() should have been called with previousMode
    expect(mockCollection.add).toHaveBeenCalledWith(
      expect.objectContaining({ mode: "study", previousMode: "social" })
    );
  });

  test.each(["social", "discussion", "study", "quiet", "campus", "family"] as const)(
    "accepts valid mode '%s'",
    async (mode) => {
      mockDoc.__data = undefined;
      mockDoc.get.mockResolvedValue({ data: () => undefined, exists: false });

      const result = await setInteractionMode(makeCallableRequest({ mode }));
      expect(result.mode).toBe(mode);
    }
  );
});

describe("getInteractionMode callable", () => {
  beforeEach(() => resetMocks());

  test("throws unauthenticated when no auth", async () => {
    await expect(
      getInteractionMode({ auth: null, data: {} } as any)
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("falls back to 'social' when interactionMode field is absent", async () => {
    mockDoc.__data = {}; // no interactionMode field
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });

    const result = await getInteractionMode(makeCallableRequest({}));

    expect(result.mode).toBe("social");
    expect(result.capabilities).toEqual(MODE_CAPABILITIES.social);
  });

  test("returns the stored mode when present", async () => {
    mockDoc.__data = { interactionMode: "study", modeCapabilities: MODE_CAPABILITIES.study };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });

    const result = await getInteractionMode(makeCallableRequest({}));

    expect(result.mode).toBe("study");
    expect(result.capabilities).toEqual(MODE_CAPABILITIES.study);
  });
});

describe("checkModeCapability helper", () => {
  beforeEach(() => resetMocks());

  test("returns social-mode default when user document is missing", async () => {
    mockDoc.get.mockResolvedValue({ data: () => undefined, exists: false });
    // social mode: canPostPublicly = true
    const result = await checkModeCapability("uid-1", "canPostPublicly");
    expect(result).toBe(MODE_CAPABILITIES.social.canPostPublicly);
  });

  test("returns stored capability value when modeCapabilities is present", async () => {
    mockDoc.__data = { modeCapabilities: MODE_CAPABILITIES.quiet };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });

    const result = await checkModeCapability("uid-1", "canPostPublicly");
    expect(result).toBe(false); // quiet mode blocks public posts
  });

  test("falls back to deriving from stored mode when modeCapabilities absent", async () => {
    mockDoc.__data = { interactionMode: "discussion" };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });

    const result = await checkModeCapability("uid-1", "canUploadMedia");
    expect(result).toBe(false); // discussion mode: no media upload
  });

  test("returns social-mode default on Firestore error", async () => {
    mockDoc.get.mockRejectedValue(new Error("Firestore error"));
    const result = await checkModeCapability("uid-1", "canDM");
    expect(result).toBe(MODE_CAPABILITIES.social.canDM); // true
  });
});

describe("enforcePostModeConstraints Firestore trigger", () => {
  beforeEach(() => resetMocks());

  /** Build a mock Firestore trigger event for a post document. */
  function makePostEvent(postData: Record<string, unknown>, postId = "post-1") {
    const ref = { update: jest.fn().mockResolvedValue(undefined) };
    return {
      params: { postId },
      data: {
        data: () => postData,
        ref,
      },
    } as any;
  }

  test("blocks media post from a user in 'discussion' mode", async () => {
    mockDoc.__data = { interactionMode: "discussion" };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });

    const event = makePostEvent({
      authorUid: "uid-1",
      mediaUrls: ["https://example.com/image.jpg"],
      visibility: "everyone",
    });

    await enforcePostModeConstraints(event);

    expect(event.data.ref.update).toHaveBeenCalledWith(
      expect.objectContaining({ moderationStatus: "blocked", blockedByMode: "discussion" })
    );
  });

  test("blocks public post from a user in 'quiet' mode", async () => {
    mockDoc.__data = { interactionMode: "quiet" };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });

    const event = makePostEvent({
      authorUid: "uid-1",
      mediaUrls: [],
      visibility: "everyone",
    });

    await enforcePostModeConstraints(event);

    expect(event.data.ref.update).toHaveBeenCalledWith(
      expect.objectContaining({ moderationStatus: "blocked", blockedByMode: "quiet" })
    );
  });

  test("does NOT block a text-only post from a 'discussion' mode user", async () => {
    mockDoc.__data = { interactionMode: "discussion" };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });

    const event = makePostEvent({
      authorUid: "uid-1",
      mediaUrls: [], // no media
      visibility: "everyone",
    });

    await enforcePostModeConstraints(event);

    expect(event.data.ref.update).not.toHaveBeenCalled();
  });

  test("does NOT block public post from 'social' mode user", async () => {
    mockDoc.__data = { interactionMode: "social" };
    mockDoc.get.mockResolvedValue({ data: () => mockDoc.__data, exists: true });

    const event = makePostEvent({
      authorUid: "uid-1",
      mediaUrls: ["https://example.com/img.jpg"],
      visibility: "everyone",
    });

    await enforcePostModeConstraints(event);

    expect(event.data.ref.update).not.toHaveBeenCalled();
  });

  test("skips check when post has no authorUid", async () => {
    const event = makePostEvent({ visibility: "everyone", mediaUrls: [] });
    // Should not throw or call get
    await enforcePostModeConstraints(event);
    expect(mockDoc.get).not.toHaveBeenCalled();
  });
});

describe("initializeModeForNewUser Firestore trigger", () => {
  beforeEach(() => resetMocks());

  function makeUserCreatedEvent(userData: Record<string, unknown>, uid = "uid-new") {
    const ref = { set: jest.fn().mockResolvedValue(undefined) };
    return {
      params: { uid },
      data: {
        data: () => userData,
        ref,
      },
    } as any;
  }

  test("initializes non-minor users to 'discussion' mode", async () => {
    const event = makeUserCreatedEvent({ displayName: "Alice" }); // no ageTier

    await initializeModeForNewUser(event);

    expect(event.data.ref.set).toHaveBeenCalledWith(
      expect.objectContaining({ interactionMode: "discussion" }),
      expect.objectContaining({ merge: true })
    );
  });

  test("initializes minor accounts to 'youth' mode", async () => {
    const event = makeUserCreatedEvent({ ageTier: "minor" });

    await initializeModeForNewUser(event);

    expect(event.data.ref.set).toHaveBeenCalledWith(
      expect.objectContaining({ interactionMode: "youth" }),
      expect.objectContaining({ merge: true })
    );
  });

  test("initializes teen accounts to 'youth' mode", async () => {
    const event = makeUserCreatedEvent({ ageTier: "teen" });

    await initializeModeForNewUser(event);

    expect(event.data.ref.set).toHaveBeenCalledWith(
      expect.objectContaining({ interactionMode: "youth" }),
      expect.objectContaining({ merge: true })
    );
  });

  test("skips initialization when mode is already set", async () => {
    const event = makeUserCreatedEvent({ interactionMode: "campus" });

    await initializeModeForNewUser(event);

    expect(event.data.ref.set).not.toHaveBeenCalled();
  });

  test("sets correct modeCapabilities for 'youth' init", async () => {
    const event = makeUserCreatedEvent({ ageTier: "minor" });

    await initializeModeForNewUser(event);

    expect(event.data.ref.set).toHaveBeenCalledWith(
      expect.objectContaining({ modeCapabilities: MODE_CAPABILITIES.youth }),
      expect.anything()
    );
  });
});

describe("MODE_CAPABILITIES constants", () => {
  test("discussion mode: canUploadMedia is false, discussionOnlyPosting is true", () => {
    expect(MODE_CAPABILITIES.discussion.canUploadMedia).toBe(false);
    expect(MODE_CAPABILITIES.discussion.discussionOnlyPosting).toBe(true);
  });

  test("quiet mode: canPostPublicly is false, requiresTrustedCircleForDMs is true", () => {
    expect(MODE_CAPABILITIES.quiet.canPostPublicly).toBe(false);
    expect(MODE_CAPABILITIES.quiet.requiresTrustedCircleForDMs).toBe(true);
  });

  test("youth mode: youthProtectionsActive is true, canBeDiscovered is false", () => {
    expect(MODE_CAPABILITIES.youth.youthProtectionsActive).toBe(true);
    expect(MODE_CAPABILITIES.youth.canBeDiscovered).toBe(false);
  });

  test("social mode: all positive capabilities are true", () => {
    const caps = MODE_CAPABILITIES.social;
    expect(caps.canPostPublicly).toBe(true);
    expect(caps.canDM).toBe(true);
    expect(caps.canUploadMedia).toBe(true);
    expect(caps.canCreateGroups).toBe(true);
    expect(caps.canBeDiscovered).toBe(true);
  });
});
