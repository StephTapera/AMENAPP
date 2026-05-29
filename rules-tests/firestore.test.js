/**
 * AMEN App — Firestore Security Rules Test Suite (Agent 2 hardening pass)
 *
 * Covers:
 *   ALLOW tests: owner-scoped reads that must succeed
 *   DENY tests:  cross-user and unauthenticated reads/writes that must be blocked
 *
 * Run with (from rules-tests/ directory):
 *   npm test
 *   npm run test:watch
 *
 * Or from functions/ directory:
 *   npm run test:rules
 *
 * Prerequisites:
 *   - Firebase Emulator Suite must be running:
 *       firebase emulators:start --only firestore
 *   - FIREBASE_EMULATOR_HOST env var is set by @firebase/rules-unit-testing
 *     automatically when the emulator is on default port (8080).
 *
 * Pattern: initializeTestEnvironment (v9 / rules-unit-testing v2 API)
 * Reference: https://firebase.google.com/docs/rules/unit-tests
 */

const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const { resolve } = require('path');

// ── Test environment setup ─────────────────────────────────────────────────

const PROJECT_ID = 'amen-rules-test';

// When run from rules-tests/, rules are at ../firestore.rules
// When run from functions/ via test:rules script, same relative path applies
const RULES_PATH = resolve(__dirname, '../firestore.rules');

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(RULES_PATH, 'utf8'),
      // Connects to the local Firestore emulator. If not running, tests will fail
      // with ECONNREFUSED — start with: firebase emulators:start --only firestore
      host: 'localhost',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

// ── Helpers ────────────────────────────────────────────────────────────────

/** Returns a Firestore instance authenticated as the given uid. */
function authedDb(uid, additionalClaims = {}) {
  return testEnv.authenticatedContext(uid, additionalClaims).firestore();
}

/** Returns a Firestore instance for an admin user. */
function adminDb() {
  return testEnv.authenticatedContext('admin-user', { admin: true }).firestore();
}

/** Returns a Firestore instance for a moderator user. */
function moderatorDb() {
  return testEnv.authenticatedContext('mod-user', { moderator: true }).firestore();
}

/** Returns an unauthenticated Firestore instance. */
function unauthDb() {
  return testEnv.unauthenticatedContext().firestore();
}

/**
 * Seeds a document via the Admin SDK (bypasses Security Rules).
 * Use this to set up test data that normal users cannot write directly.
 */
async function seedDoc(collectionPath, docId, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection(collectionPath).doc(docId).set(data);
  });
}

// ── Test fixture user IDs ──────────────────────────────────────────────────
const UID_A = 'user-alice';
const UID_B = 'user-bob';
const UID_C = 'user-charlie';
const CONVO_AB = 'conversation-ab';
const CONVO_AC = 'conversation-ac';
const NOTE_ID  = 'note-xyz';
const PRAYER_ID = 'prayer-001';
const CONV_ID  = 'berean-conv-001';

// ════════════════════════════════════════════════════════════════════════════
// ALLOW TESTS — these must succeed
// ════════════════════════════════════════════════════════════════════════════

describe('ALLOW: User A can read their own /users/{uid} doc', () => {
  it('owner reads their own user document', async () => {
    await seedDoc('users', UID_A, {
      displayName: 'Alice',
      bio: 'Test user A',
    });

    const db = authedDb(UID_A);
    await assertSucceeds(db.collection('users').doc(UID_A).get());
  });
});

describe('ALLOW: User A can read their own /users/{uid}/bereanConversations/{convId}', () => {
  it('owner reads their own berean conversation subcollection doc', async () => {
    await seedDoc(`users/${UID_A}/bereanConversations`, CONV_ID, {
      userId: UID_A,
      title: 'Faith journey',
      createdAt: new Date(),
    });

    const db = authedDb(UID_A);
    await assertSucceeds(
      db.collection(`users/${UID_A}/bereanConversations`).doc(CONV_ID).get()
    );
  });
});

describe('ALLOW: User A can read their own /bereanConversations/{uid}/{convId} (top-level path)', () => {
  it('owner reads their own berean conversation top-level doc', async () => {
    await seedDoc(`bereanConversations/${UID_A}`, CONV_ID, {
      userId: UID_A,
      title: 'Scripture study session',
    });

    const db = authedDb(UID_A);
    await assertSucceeds(
      db.collection(`bereanConversations/${UID_A}`).doc(CONV_ID).get()
    );
  });
});

describe('ALLOW: User A can read their own /users/{uid}/prayers/{prayerId}', () => {
  it('owner reads their own prayer subcollection doc', async () => {
    await seedDoc(`users/${UID_A}/prayerReflections`, 'reflection-1', {
      userId: UID_A,
      content: 'Daily reflection',
    });

    const db = authedDb(UID_A);
    await assertSucceeds(
      db.collection(`users/${UID_A}/prayerReflections`).doc('reflection-1').get()
    );
  });
});

describe('ALLOW: User A can read their own /prayers/{prayerId} (top-level)', () => {
  it('owner reads their own prayer from the top-level prayers collection', async () => {
    await seedDoc('prayers', PRAYER_ID, {
      userId: UID_A,
      title: 'Prayer for guidance',
      text: 'Lord, show me the way.',
    });

    const db = authedDb(UID_A);
    await assertSucceeds(db.collection('prayers').doc(PRAYER_ID).get());
  });
});

describe('ALLOW: Participant A can read /conversations/{convId}/messages/{msgId}', () => {
  it('participant reads a message in a conversation they belong to', async () => {
    await seedDoc('conversations', CONVO_AB, {
      participantIds: [UID_A, UID_B],
      lastMessageAt: new Date(),
    });
    await seedDoc(`conversations/${CONVO_AB}/messages`, 'msg-1', {
      senderId: UID_B,
      text: 'Hello Alice',
      timestamp: new Date(),
    });

    const db = authedDb(UID_A);
    await assertSucceeds(
      db.collection(`conversations/${CONVO_AB}/messages`).doc('msg-1').get()
    );
  });
});

describe('ALLOW: Participant A can read the conversation doc itself', () => {
  it('participant A reads their conversation', async () => {
    await seedDoc('conversations', CONVO_AB, {
      participantIds: [UID_A, UID_B],
      lastMessageAt: new Date(),
    });

    const db = authedDb(UID_A);
    await assertSucceeds(db.collection('conversations').doc(CONVO_AB).get());
  });
});

describe('ALLOW: Admin user can read /safetyReviews/{reviewId}', () => {
  it('moderator (isModerator claim) reads a safety review', async () => {
    await seedDoc('safetyReviews', 'review-1', {
      targetId: 'post-abc',
      reason: 'Potential abuse',
      createdAt: new Date(),
    });

    const db = moderatorDb();
    await assertSucceeds(db.collection('safetyReviews').doc('review-1').get());
  });
});

describe('ALLOW: Public prayerWall readable by authenticated users', () => {
  it('authenticated user B reads the community prayer wall', async () => {
    await seedDoc('prayerWall', 'prayer-wall-1', {
      authorId: UID_A,
      body: 'Pray for healing',
      createdAt: new Date(),
    });

    const db = authedDb(UID_B);
    await assertSucceeds(db.collection('prayerWall').doc('prayer-wall-1').get());
  });
});

describe('ALLOW: Owner can create a post without PII or server fields', () => {
  it('verified user creates a valid post without server-owned fields', async () => {
    const db = testEnv.authenticatedContext(UID_A, {
      email_verified: true,
    }).firestore();

    const ref = db.collection('posts').doc();
    await assertSucceeds(ref.set({
      authorId: UID_A,
      caption: 'A new post about faith',
      status: 'publishing',
      publishState: 'draft',
      createdAt: new Date(),
    }));
  });
});

describe('ALLOW: Owner updates their own user doc non-PII fields', () => {
  it('owner updates bio field without triggering PII guard', async () => {
    await seedDoc('users', UID_A, { displayName: 'Alice', bio: 'Original bio' });

    const db = authedDb(UID_A);
    await assertSucceeds(db.collection('users').doc(UID_A).update({
      bio: 'Updated spiritual journey bio',
    }));
  });
});

describe('ALLOW: User B can read a published public testimony', () => {
  it('authenticated user reads a public testimony', async () => {
    await seedDoc('testimonies', 'test-1', {
      authorId: UID_A,
      title: 'How God changed my life',
      isPublic: true,
    });

    const db = authedDb(UID_B);
    await assertSucceeds(db.collection('testimonies').doc('test-1').get());
  });
});

// ════════════════════════════════════════════════════════════════════════════
// DENY TESTS — these MUST fail (the critical privacy/security tests)
// ════════════════════════════════════════════════════════════════════════════

// ── Cross-user Berean conversation access ──────────────────────────────────

describe('DENY: User B CANNOT read User A /users/{userAId}/bereanConversations/{convId}', () => {
  it('User B is denied access to User A bereanConversations subcollection', async () => {
    await seedDoc(`users/${UID_A}/bereanConversations`, CONV_ID, {
      userId: UID_A,
      title: 'Private spiritual dialogue',
    });

    const db = authedDb(UID_B);
    await assertFails(
      db.collection(`users/${UID_A}/bereanConversations`).doc(CONV_ID).get()
    );
  });

  it('User B is denied access to top-level bereanConversations for User A', async () => {
    await seedDoc(`bereanConversations/${UID_A}`, CONV_ID, {
      userId: UID_A,
      title: 'Private spiritual dialogue',
    });

    const db = authedDb(UID_B);
    await assertFails(
      db.collection(`bereanConversations/${UID_A}`).doc(CONV_ID).get()
    );
  });
});

// ── Cross-user private prayer access ──────────────────────────────────────

describe('DENY: User B CANNOT read User A private prayers', () => {
  it('User B cannot read a prayer with userId == UID_A', async () => {
    await seedDoc('prayers', PRAYER_ID, {
      userId: UID_A,
      title: 'Private prayer',
      text: 'Personal supplication',
      isPublic: false,
    });

    const db = authedDb(UID_B);
    await assertFails(db.collection('prayers').doc(PRAYER_ID).get());
  });
});

// ── Conversation isolation ─────────────────────────────────────────────────

describe('DENY: User B CANNOT read a conversation they are not part of', () => {
  it('User B denied access to conversation between A and C', async () => {
    await seedDoc('conversations', CONVO_AC, {
      participantIds: [UID_A, UID_C],
      lastMessageAt: new Date(),
    });

    const db = authedDb(UID_B);
    await assertFails(db.collection('conversations').doc(CONVO_AC).get());
  });

  it('User B CANNOT read messages in a conversation they do not belong to', async () => {
    await seedDoc('conversations', CONVO_AC, {
      participantIds: [UID_A, UID_C],
      lastMessageAt: new Date(),
    });
    await seedDoc(`conversations/${CONVO_AC}/messages`, 'msg-private', {
      senderId: UID_A,
      text: 'Private message to Charlie',
      timestamp: new Date(),
    });

    const db = authedDb(UID_B);
    await assertFails(
      db.collection(`conversations/${CONVO_AC}/messages`).doc('msg-private').get()
    );
  });
});

// ── Unauthenticated access ─────────────────────────────────────────────────

describe('DENY: Unauthenticated user CANNOT read ANY /users/{uid} data', () => {
  it('unauthenticated user denied access to root user doc', async () => {
    await seedDoc('users', UID_A, { displayName: 'Alice', bio: 'A test user' });

    const db = unauthDb();
    await assertFails(db.collection('users').doc(UID_A).get());
  });

  it('unauthenticated user denied access to user bereanConversations subcollection', async () => {
    await seedDoc(`users/${UID_A}/bereanConversations`, CONV_ID, {
      userId: UID_A,
      title: 'Private',
    });

    const db = unauthDb();
    await assertFails(
      db.collection(`users/${UID_A}/bereanConversations`).doc(CONV_ID).get()
    );
  });
});

describe('DENY: Unauthenticated user CANNOT write to /posts/{postId}', () => {
  it('unauthenticated user denied post creation', async () => {
    const db = unauthDb();
    const ref = db.collection('posts').doc('new-post');
    await assertFails(ref.set({
      authorId: 'some-uid',
      caption: 'Unauthorized post attempt',
      status: 'publishing',
    }));
  });
});

// ── Cross-user writes ──────────────────────────────────────────────────────

describe('DENY: User A CANNOT write to /users/{userBId}', () => {
  it('User A cannot create a document in User B user path', async () => {
    const db = authedDb(UID_A);
    await assertFails(db.collection('users').doc(UID_B).set({
      displayName: 'Hacked by Alice',
      bio: 'Cross-user write attempt',
    }));
  });

  it('User A cannot update User B user doc', async () => {
    await seedDoc('users', UID_B, { displayName: 'Bob', bio: 'User B' });

    const db = authedDb(UID_A);
    await assertFails(db.collection('users').doc(UID_B).update({
      bio: 'Tampered by Alice',
    }));
  });
});

// ── Admin role escalation ──────────────────────────────────────────────────

describe("DENY: User A CANNOT set role: 'admin' on their own user doc", () => {
  it('user cannot write admin role flag to own user doc', async () => {
    await seedDoc('users', UID_A, { displayName: 'Alice', bio: 'A user' });

    const db = authedDb(UID_A);
    await assertFails(db.collection('users').doc(UID_A).update({
      role: 'admin',
    }));
  });

  it('user cannot set premiumTier on own user doc', async () => {
    await seedDoc('users', UID_A, { displayName: 'Alice', bio: 'A user' });

    const db = authedDb(UID_A);
    await assertFails(db.collection('users').doc(UID_A).update({
      premiumTier: 'pro',
    }));
  });

  it('user cannot set hasPlusAccess on own user doc', async () => {
    await seedDoc('users', UID_A, { displayName: 'Alice', bio: 'A user' });

    const db = authedDb(UID_A);
    await assertFails(db.collection('users').doc(UID_A).update({
      hasPlusAccess: true,
    }));
  });
});

// ── Post createdAt immutability ────────────────────────────────────────────

describe('DENY: User A CANNOT modify createdAt on an existing post', () => {
  it('author cannot modify createdAt field on their own post', async () => {
    const originalDate = new Date('2024-01-01T00:00:00Z');
    await seedDoc('posts', 'post-1', {
      authorId: UID_A,
      caption: 'Original post',
      status: 'publishing',
      publishState: 'draft',
      createdAt: originalDate,
    });

    const db = authedDb(UID_A);
    // Attempting to update createdAt should be denied by the update rule
    await assertFails(db.collection('posts').doc('post-1').update({
      createdAt: new Date('2020-01-01T00:00:00Z'),
    }));
  });
});

// ── PII field protection ───────────────────────────────────────────────────

describe('DENY: User CANNOT write email or phoneNumber to root /users/{uid} doc', () => {
  it('user A cannot include email field on create of own user doc', async () => {
    const db = authedDb(UID_A);
    await assertFails(db.collection('users').doc(UID_A).set({
      displayName: 'Alice',
      bio: 'No PII allowed here',
      email: 'alice@example.com',
    }));
  });

  it('user A cannot include phoneNumber field on create of own user doc', async () => {
    const db = authedDb(UID_A);
    await assertFails(db.collection('users').doc(UID_A).set({
      displayName: 'Alice',
      bio: 'No PII allowed here',
      phoneNumber: '+15555550100',
    }));
  });

  it('user A cannot update email on existing root user doc', async () => {
    await seedDoc('users', UID_A, { displayName: 'Alice', bio: 'Original bio' });

    const db = authedDb(UID_A);
    await assertFails(db.collection('users').doc(UID_A).update({
      email: 'alice@example.com',
    }));
  });

  it('user A cannot update phoneNumber on existing root user doc', async () => {
    await seedDoc('users', UID_A, { displayName: 'Alice', bio: 'Original bio' });

    const db = authedDb(UID_A);
    await assertFails(db.collection('users').doc(UID_A).update({
      phoneNumber: '+15555550100',
    }));
  });
});

// ── followerCount / isMinor spoofing ──────────────────────────────────────

describe('DENY: User cannot self-write server-owned counters', () => {
  it('user cannot increment their own followersCount', async () => {
    await seedDoc('users', UID_A, {
      displayName: 'Alice',
      followersCount: 10,
    });

    const db = authedDb(UID_A);
    await assertFails(db.collection('users').doc(UID_A).update({
      followersCount: 999,
    }));
  });

  it('user cannot set isMinor on own user doc', async () => {
    await seedDoc('users', UID_A, {
      displayName: 'Alice',
      isMinor: false,
    });

    const db = authedDb(UID_A);
    await assertFails(db.collection('users').doc(UID_A).update({
      isMinor: true,
    }));
  });
});

// ── Post engagement counter spoofing ──────────────────────────────────────

describe('DENY: Author cannot modify server-owned engagement counters on their post', () => {
  it('author cannot update amenCount on own post', async () => {
    await seedDoc('posts', 'post-counters', {
      authorId: UID_A,
      caption: 'Test post',
      status: 'publishing',
      publishState: 'draft',
      amenCount: 0,
    });

    const db = authedDb(UID_A);
    await assertFails(db.collection('posts').doc('post-counters').update({
      amenCount: 9999,
    }));
  });

  it('author cannot update commentCount on own post', async () => {
    await seedDoc('posts', 'post-counters-2', {
      authorId: UID_A,
      caption: 'Test post 2',
      status: 'publishing',
      publishState: 'draft',
      commentCount: 0,
    });

    const db = authedDb(UID_A);
    await assertFails(db.collection('posts').doc('post-counters-2').update({
      commentCount: 9999,
    }));
  });
});

// ── Server-only collection write protection ────────────────────────────────

describe('DENY: Client CANNOT write to server-only enforcement collections', () => {
  it('authenticated user cannot write to /rateLimits', async () => {
    const db = authedDb(UID_A);
    await assertFails(db.collection('rateLimits').doc(UID_A).set({ count: 0 }));
  });

  it('authenticated user cannot write to /userRestrictions', async () => {
    const db = authedDb(UID_A);
    await assertFails(db.collection('userRestrictions').doc(UID_A).set({
      restricted: false,
    }));
  });

  it('authenticated user cannot read from /userRestrictions', async () => {
    await seedDoc('userRestrictions', UID_A, { restricted: true });
    const db = authedDb(UID_A);
    await assertFails(db.collection('userRestrictions').doc(UID_A).get());
  });

  it('authenticated user cannot read from /enforcementHistory', async () => {
    await seedDoc('enforcementHistory', 'record-1', {
      userId: UID_A,
      action: 'warn',
    });
    const db = authedDb(UID_A);
    await assertFails(db.collection('enforcementHistory').doc('record-1').get());
  });

  it('authenticated user cannot write to /moderationQueue directly', async () => {
    const db = authedDb(UID_A);
    await assertFails(db.collection('moderationQueue').doc('fake-queue').set({
      targetId: 'post-xyz',
      action: 'remove',
    }));
  });

  it('authenticated user cannot write to /shadowBans', async () => {
    const db = authedDb(UID_A);
    await assertFails(db.collection('shadowBans').doc(UID_B).set({
      shadowBanned: true,
      reason: 'Malicious test',
    }));
  });
});

// ── Private PII subcollection ──────────────────────────────────────────────

describe('DENY: Client CANNOT read /users/{uid}/private/{docId} (PII migration target)', () => {
  it('owner cannot read their own /users/{uid}/private/pii doc', async () => {
    await seedDoc(`users/${UID_A}/private`, 'pii', {
      email: 'alice@example.com',
      phoneNumber: '+15555550100',
    });

    // Even the owner is blocked — server (Admin SDK) only
    const db = authedDb(UID_A);
    await assertFails(db.collection(`users/${UID_A}/private`).doc('pii').get());
  });
});

// ── User B cannot read User A safety/usage subcollections ─────────────────

describe('DENY: User B CANNOT read User A safety subcollection data', () => {
  it('User B denied access to User A safety subcollection doc', async () => {
    await seedDoc(`users/${UID_A}/safety`, 'main', {
      crisisFlags: [],
      lastChecked: new Date(),
    });

    const db = authedDb(UID_B);
    await assertFails(
      db.collection(`users/${UID_A}/safety`).doc('main').get()
    );
  });

  it('User B denied access to User A usage subcollection doc', async () => {
    await seedDoc(`users/${UID_A}/usage`, 'daily', {
      aiCallsToday: 5,
    });

    const db = authedDb(UID_B);
    await assertFails(db.collection(`users/${UID_A}/usage`).doc('daily').get());
  });
});

// ── Covenant subscription protection ──────────────────────────────────────

describe('DENY: User B CANNOT read User A covenantSubscriptions', () => {
  it('User B cannot read User A covenant subscription status', async () => {
    await seedDoc('covenantSubscriptions', UID_A, {
      tier: 'pro',
      activeUntil: new Date(),
    });

    const db = authedDb(UID_B);
    await assertFails(db.collection('covenantSubscriptions').doc(UID_A).get());
  });
});

// ── Post create with server-owned fields blocked ───────────────────────────

describe('DENY: Author CANNOT set server-owned fields on post create', () => {
  it('author cannot set moderationStatus on new post', async () => {
    const db = testEnv.authenticatedContext(UID_A, {
      email_verified: true,
    }).firestore();

    await assertFails(db.collection('posts').doc().set({
      authorId: UID_A,
      caption: 'Test post',
      status: 'publishing',
      publishState: 'draft',
      createdAt: new Date(),
      moderationStatus: 'approved', // server field — must be blocked
    }));
  });

  it('author cannot set publishedAt on new post', async () => {
    const db = testEnv.authenticatedContext(UID_A, {
      email_verified: true,
    }).firestore();

    await assertFails(db.collection('posts').doc().set({
      authorId: UID_A,
      caption: 'Test post',
      status: 'publishing',
      publishState: 'draft',
      createdAt: new Date(),
      publishedAt: new Date(), // server field — must be blocked
    }));
  });
});

// ── Prayer create with wrong userId ───────────────────────────────────────

describe('DENY: User A CANNOT create a prayer attributed to User B', () => {
  it('User A denied creating prayer with userId = UID_B', async () => {
    const db = authedDb(UID_A);
    await assertFails(db.collection('prayers').doc('spoof-prayer').set({
      userId: UID_B,
      title: 'Spoofed prayer',
      text: 'Attribution fraud attempt',
    }));
  });
});

// ── Prayer wall and prayerRequests public vs private ──────────────────────

describe('DENY: Unauthenticated user CANNOT read the prayer wall', () => {
  it('unauthenticated access to prayerWall is denied', async () => {
    await seedDoc('prayerWall', 'wall-1', {
      authorId: UID_A,
      body: 'Prayer for the community',
    });

    const db = unauthDb();
    await assertFails(db.collection('prayerWall').doc('wall-1').get());
  });
});

describe('DENY: User B CANNOT read User A private prayerRequest', () => {
  it('User B cannot read private prayerRequest from User A', async () => {
    await seedDoc('prayerRequests', 'req-1', {
      userId: UID_A,
      body: 'Private prayer request',
      isPublic: false,
    });

    const db = authedDb(UID_B);
    await assertFails(db.collection('prayerRequests').doc('req-1').get());
  });
});

// ── bereanPreferences enumeration guard ───────────────────────────────────

describe('DENY: User A CANNOT create bereanPreferences attributed to User B', () => {
  it('User A cannot create a bereanPreferences doc for User B', async () => {
    const db = authedDb(UID_A);
    await assertFails(db.collection('bereanPreferences').doc('prefs-b').set({
      uid: UID_B,   // trying to attribute to User B
      theme: 'dark',
    }));
  });
});
