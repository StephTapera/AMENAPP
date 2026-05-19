const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
} = require("firebase/firestore");
const {
  ref,
  uploadBytes,
} = require("firebase/storage");

const projectId = `amen-media-rules-${Date.now()}`;
const repoRoot = path.resolve(__dirname, "..", "..");

async function createTestEnv() {
  return initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync(path.join(repoRoot, "AMENAPP/firestore.deploy.rules"), "utf8"),
    },
    storage: {
      rules: fs.readFileSync(path.join(repoRoot, "AMENAPP/storage.rules"), "utf8"),
    },
  });
}

test("media Firestore rules enforce owner progress and server-only fields", async () => {
  const env = await createTestEnv();
  try {
    const alice = env.authenticatedContext("alice");
    const bob = env.authenticatedContext("bob");
    const aliceDb = alice.firestore();
    const bobDb = bob.firestore();

    const progressRef = doc(aliceDb, "users/alice/mediaProgress/media-1");
    await assertSucceeds(setDoc(progressRef, {
      ownerUid: "alice",
      mediaId: "media-1",
      postId: "post-1",
      progressSeconds: 42,
      durationSeconds: 180,
      percentComplete: 23,
      sourceSurface: "feed",
    }));

    await assertFails(setDoc(doc(bobDb, "users/alice/mediaProgress/media-2"), {
      ownerUid: "alice",
      mediaId: "media-2",
      progressSeconds: 1,
      durationSeconds: 10,
      percentComplete: 10,
    }));

    await assertFails(setDoc(doc(aliceDb, "users/alice/mediaProgress/media-3"), {
      ownerUid: "alice",
      mediaId: "media-3",
      progressSeconds: 5,
      durationSeconds: 10,
      percentComplete: 50,
      moderationStatus: "approved",
    }));

    await assertFails(setDoc(doc(aliceDb, "mediaRankingSignals/media-1"), {
      safetyScore: 100,
    }));

    await assertFails(setDoc(doc(aliceDb, "mediaModerationQueue/media-1"), {
      status: "approved",
    }));
  } finally {
    await env.cleanup();
  }
});

test("media metadata rules hide drafts and block client approval writes", async () => {
  const env = await createTestEnv();
  try {
    await env.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      await setDoc(doc(adminDb, "posts/post-1"), {
        authorId: "creator",
        visibility: "everyone",
        isRemoved: false,
        deletedAt: null,
      });
      await setDoc(doc(adminDb, "users/creator"), {
        isPrivate: false,
        isPrivateAccount: false,
      });
      await setDoc(doc(adminDb, "posts/post-1/mediaMeta/media-1/captionTracks/draft"), {
        source: "generated",
        status: "draft",
        approvedByUser: false,
        language: "en",
      });
      await setDoc(doc(adminDb, "posts/post-1/mediaMeta/media-1/captionTracks/approved"), {
        source: "generated",
        status: "approved",
        approvedByUser: true,
        visibleToPublic: true,
        language: "en",
      });
      await setDoc(doc(adminDb, "posts/post-1/media/media-1"), {
        postId: "post-1",
        mediaId: "media-1",
        ownerUid: "creator",
        status: "published",
        visibility: "everyone",
        safety: {status: "approved"},
      });
      await setDoc(doc(adminDb, "posts/post-1/media/media-1/keyMoments/draft"), {
        source: "generated",
        status: "pending_review",
        approvedByUser: false,
        visibleToPublic: false,
      });
      await setDoc(doc(adminDb, "posts/post-1/media/media-1/keyMoments/approved"), {
        source: "generated",
        status: "approved",
        approvedByUser: true,
        visibleToPublic: true,
      });
      await setDoc(doc(adminDb, "posts/post-1/mediaMeta/media-1/draftMetadata/draft-1"), {
        source: "generated",
        status: "draft",
      });
    });

    const publicDb = env.authenticatedContext("viewer").firestore();
    const creatorDb = env.authenticatedContext("creator").firestore();

    await assertFails(getDoc(doc(publicDb, "posts/post-1/mediaMeta/media-1/captionTracks/draft")));
    await assertSucceeds(getDoc(doc(publicDb, "posts/post-1/mediaMeta/media-1/captionTracks/approved")));
    await assertFails(getDoc(doc(publicDb, "posts/post-1/mediaMeta/media-1/draftMetadata/draft-1")));
    await assertSucceeds(getDoc(doc(publicDb, "posts/post-1/media/media-1/keyMoments/approved")));
    await assertFails(getDoc(doc(publicDb, "posts/post-1/media/media-1/keyMoments/draft")));

    await assertFails(updateDoc(doc(creatorDb, "posts/post-1/mediaMeta/media-1/captionTracks/draft"), {
      status: "approved",
      approvedByUser: true,
    }));
    await assertFails(updateDoc(doc(creatorDb, "posts/post-1/media/media-1/keyMoments/draft"), {
      status: "approved",
      approvedByUser: true,
      visibleToPublic: true,
      creatorApprovedAt: new Date(),
    }));
  } finally {
    await env.cleanup();
  }
});

test("canonical media rules block client writes to system-controlled media fields", async () => {
  const env = await createTestEnv();
  try {
    await env.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      await setDoc(doc(adminDb, "posts/post-2"), {
        authorId: "creator",
        visibility: "everyone",
        isRemoved: false,
        deletedAt: null,
      });
      await setDoc(doc(adminDb, "users/creator"), {
        isPrivate: false,
        isPrivateAccount: false,
      });
    });

    const creatorDb = env.authenticatedContext("creator").firestore();
    await assertFails(setDoc(doc(creatorDb, "posts/post-2/media/media-2"), {
      ownerUid: "creator",
      status: "published",
      rankingScore: 100,
      trustScore: 100,
      moderationStatus: "approved",
      syntheticRiskScore: 0,
      provenanceConfidence: 1,
    }));
    await assertFails(setDoc(doc(creatorDb, "posts/post-2/media/media-2/draftMetadata/draft-1"), {
      status: "approved",
      approvedByUser: true,
      visibleToPublic: true,
      creatorApprovedBy: "creator",
    }));
  } finally {
    await env.cleanup();
  }
});

test("media Storage rules restrict uploads to the owning user path", async () => {
  const env = await createTestEnv();
  try {
    const aliceStorage = env.authenticatedContext("alice").storage();
    const bobStorage = env.authenticatedContext("bob").storage();
    const unauthStorage = env.unauthenticatedContext().storage();
    const data = new Uint8Array([1, 2, 3]);
    const metadata = {contentType: "image/jpeg"};

    await assertSucceeds(uploadBytes(
        ref(aliceStorage, "mediaUploads/alice/media-1/raw/photo.jpg"),
        data,
        metadata,
    ));

    await assertFails(uploadBytes(
        ref(bobStorage, "mediaUploads/alice/media-2/raw/photo.jpg"),
        data,
        metadata,
    ));

    await assertFails(uploadBytes(
        ref(unauthStorage, "mediaUploads/alice/media-3/raw/photo.jpg"),
        data,
        metadata,
    ));

    await assertFails(uploadBytes(
        ref(aliceStorage, "mediaProcessed/media-1/video/file.mp4"),
        data,
        {contentType: "video/mp4"},
    ));

    await assertSucceeds(uploadBytes(
        ref(aliceStorage, "users/alice/profile/profileImage.jpg"),
        data,
        metadata,
    ));

    await assertFails(uploadBytes(
        ref(bobStorage, "users/alice/profile/profileImage.jpg"),
        data,
        metadata,
    ));

    await assertFails(uploadBytes(
        ref(aliceStorage, "users/alice/profile/profileImage.txt"),
        data,
        {contentType: "text/plain"},
    ));
  } finally {
    await env.cleanup();
  }
});
