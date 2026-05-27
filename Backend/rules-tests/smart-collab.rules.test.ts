/**
 * smart-collab.rules.test.ts
 *
 * Firestore Security Rules tests for the Smart Collaboration Layer (Phase 1).
 *
 * Paths exercised:
 *   conversations/{id}/smartContext/main
 *   conversations/{id}/summary/main
 *   conversations/{id}/smartActions/{actionId}
 *   conversations/{id}/prayerSignals/{signalId}
 *   conversations/{id}/presence/{userId}
 *   spaces/{spaceId}/channels/{channelId}/smartContext/main
 *   spaces/{spaceId}/channels/{channelId}/summary/main
 *   spaces/{spaceId}/channels/{channelId}/smartActions/{actionId}
 *   spaces/{spaceId}/channels/{channelId}/prayerSignals/{signalId}
 *   spaces/{spaceId}/channels/{channelId}/presence/{userId}
 *   spaces/{spaceId}/channels/{channelId}/pulse/main
 *   users/{uid}/rateLimits/smartCollab
 *   mediaJobs/{jobId}
 *
 * Non-negotiable rule mapping tested:
 *   Rule 1 — Clients NEVER write AI-generated docs → create denied on all AI paths
 *   Rule 2 — Members-only read for smart context → non-member denied
 *   Rule 3 — Users write ONLY their own presence doc → cross-user write denied
 *   Rule 4 — Action status-only update → generatedBy update denied
 *   Rule 5 — Prayer signal privacy (isAnonymous=true non-requestor denied)
 *   Rule 6 — Space members read pulse
 *   Rule 7 — Rate limit doc: own only
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
} from "firebase/firestore";
import fs from "fs";
import path from "path";
import { Timestamp } from "firebase/firestore";

// ─────────────────────────────────────────────────────────────────────────────
// Test constants
// ─────────────────────────────────────────────────────────────────────────────

const PARTICIPANT_A = "participantA";
const PARTICIPANT_B = "participantB";
const NON_MEMBER = "outsider";
const SPACE_MEMBER = "spaceMember1";
const CONV_ID = "conv1";
const SPACE_ID = "space1";
const CHANNEL_ID = "channel1";

// A future timestamp safely within the 31-minute window (28 minutes from now).
function expiresAtSoon(): Timestamp {
  return Timestamp.fromMillis(Date.now() + 28 * 60 * 1000);
}

// A future timestamp that violates the 31-minute cap (35 minutes from now).
function expiresAtTooFar(): Timestamp {
  return Timestamp.fromMillis(Date.now() + 35 * 60 * 1000);
}

// ─────────────────────────────────────────────────────────────────────────────
// Test environment setup / teardown
// ─────────────────────────────────────────────────────────────────────────────

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "amen-smart-collab-rules",
    firestore: {
      rules: fs.readFileSync(
        path.join(__dirname, "../../firestore.rules"),
        "utf8"
      ),
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    // ── Conversation seed data ──────────────────────────────────────────────

    // Parent conversation doc with participantIds (matches existing rules field name)
    await setDoc(doc(db, `conversations/${CONV_ID}`), {
      participantIds: [PARTICIPANT_A, PARTICIPANT_B],
      isGroup: false,
    });

    // AI-generated smartContext — written server-side in tests, never by client
    await setDoc(doc(db, `conversations/${CONV_ID}/smartContext/main`), {
      threadId: CONV_ID,
      generatedBy: "service-account@amen-app.iam.gserviceaccount.com",
      generatedAt: Timestamp.now(),
      modelVersion: "gemini-1.5-pro",
      summaryText: "Test context summary",
      keyThemes: ["faith", "community"],
      participantCount: 2,
      messageCount: 10,
      lastSourceMessageId: "msg99",
      isStale: false,
    });

    // AI-generated summary
    await setDoc(doc(db, `conversations/${CONV_ID}/summary/main`), {
      threadId: CONV_ID,
      summaryText: "Thread summary",
      bulletPoints: ["Point A", "Point B"],
      generatedBy: "service-account@amen-app.iam.gserviceaccount.com",
      generatedAt: Timestamp.now(),
      modelVersion: "gemini-1.5-pro",
      isStale: false,
    });

    // AI-generated smart action — status starts as "suggested"
    await setDoc(doc(db, `conversations/${CONV_ID}/smartActions/action1`), {
      id: "action1",
      threadId: CONV_ID,
      actionType: "followUp",
      suggestedText: "Possible: follow up with James",
      sourceMessageId: "msg42",
      confidence: 0.75,
      status: "suggested",
      generatedBy: "service-account@amen-app.iam.gserviceaccount.com",
      generatedAt: Timestamp.now(),
      modelVersion: "gemini-1.5-pro",
    });

    // Prayer signal — non-anonymous, approved (readable by members)
    await setDoc(doc(db, `conversations/${CONV_ID}/prayerSignals/signal1`), {
      id: "signal1",
      threadId: CONV_ID,
      requestorId: PARTICIPANT_A,
      prayerTheme: "health",
      isAnonymous: false,
      sourceMessageId: "msg7",
      moderationStatus: "approved",
      generatedBy: "service-account@amen-app.iam.gserviceaccount.com",
      generatedAt: Timestamp.now(),
      modelVersion: "gemini-1.5-pro",
    });

    // Prayer signal — anonymous (non-requestor must be denied full doc read)
    await setDoc(
      doc(db, `conversations/${CONV_ID}/prayerSignals/signalAnon`),
      {
        id: "signalAnon",
        threadId: CONV_ID,
        requestorId: PARTICIPANT_A,
        prayerTheme: "family",
        isAnonymous: true,
        sourceMessageId: "msg8",
        moderationStatus: "approved",
        generatedBy: "service-account@amen-app.iam.gserviceaccount.com",
        generatedAt: Timestamp.now(),
        modelVersion: "gemini-1.5-pro",
      }
    );

    // ── Space / channel seed data ───────────────────────────────────────────

    await setDoc(doc(db, `spaces/${SPACE_ID}`), {
      memberIds: [SPACE_MEMBER],
    });
    await setDoc(doc(db, `spaces/${SPACE_ID}/members/${SPACE_MEMBER}`), {
      status: "active",
      roles: ["member"],
    });
    await setDoc(doc(db, `spaces/${SPACE_ID}/channels/${CHANNEL_ID}`), {
      name: "General",
    });

    // Channel AI docs
    await setDoc(
      doc(
        db,
        `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/smartContext/main`
      ),
      {
        threadId: CHANNEL_ID,
        generatedBy: "service-account@amen-app.iam.gserviceaccount.com",
        generatedAt: Timestamp.now(),
        modelVersion: "gemini-1.5-pro",
        summaryText: "Channel context",
        keyThemes: ["worship"],
        participantCount: 5,
        messageCount: 50,
        lastSourceMessageId: "msgC9",
        isStale: false,
      }
    );

    await setDoc(
      doc(db, `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/summary/main`),
      {
        threadId: CHANNEL_ID,
        summaryText: "Channel summary",
        bulletPoints: ["A", "B"],
        generatedBy: "service-account@amen-app.iam.gserviceaccount.com",
        generatedAt: Timestamp.now(),
        modelVersion: "gemini-1.5-pro",
        isStale: false,
      }
    );

    await setDoc(
      doc(
        db,
        `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/smartActions/cAction1`
      ),
      {
        id: "cAction1",
        threadId: CHANNEL_ID,
        actionType: "decision",
        suggestedText: "Possible: decide on venue",
        sourceMessageId: "msgC3",
        confidence: 0.8,
        status: "suggested",
        generatedBy: "service-account@amen-app.iam.gserviceaccount.com",
        generatedAt: Timestamp.now(),
        modelVersion: "gemini-1.5-pro",
      }
    );

    await setDoc(
      doc(
        db,
        `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/prayerSignals/cSignal1`
      ),
      {
        id: "cSignal1",
        threadId: CHANNEL_ID,
        requestorId: SPACE_MEMBER,
        prayerTheme: "community",
        isAnonymous: false,
        sourceMessageId: "msgC5",
        moderationStatus: "approved",
        generatedBy: "service-account@amen-app.iam.gserviceaccount.com",
        generatedAt: Timestamp.now(),
        modelVersion: "gemini-1.5-pro",
      }
    );

    await setDoc(
      doc(
        db,
        `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/prayerSignals/cSignalAnon`
      ),
      {
        id: "cSignalAnon",
        threadId: CHANNEL_ID,
        requestorId: SPACE_MEMBER,
        prayerTheme: "personal",
        isAnonymous: true,
        sourceMessageId: "msgC6",
        moderationStatus: "approved",
        generatedBy: "service-account@amen-app.iam.gserviceaccount.com",
        generatedAt: Timestamp.now(),
        modelVersion: "gemini-1.5-pro",
      }
    );

    await setDoc(
      doc(db, `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/pulse/main`),
      {
        id: "pulse1",
        channelId: CHANNEL_ID,
        urgency: "normal",
        activeParticipantCount: 3,
        topicMomentum: 0.5,
        alignmentEvidenceMessageIds: [],
        generatedBy: "service-account@amen-app.iam.gserviceaccount.com",
        generatedAt: Timestamp.now(),
        modelVersion: "gemini-1.5-pro",
        isStale: false,
      }
    );

    // ── Rate limit & media job seed data ───────────────────────────────────

    await setDoc(
      doc(db, `users/${PARTICIPANT_A}/rateLimits/smartCollab`),
      {
        callCount: 5,
        windowStartMs: Date.now(),
        updatedAt: Timestamp.now(),
      }
    );

    await setDoc(doc(db, `mediaJobs/job1`), {
      requestedBy: PARTICIPANT_A,
      status: "processing",
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// ALLOW CASES
// ─────────────────────────────────────────────────────────────────────────────

describe("Smart Collaboration Rules — ALLOW cases", () => {
  // 1. Conversation participant reads smartContext/main
  it("allows conversation participant to read smartContext/main", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertSucceeds(
      getDoc(doc(db, `conversations/${CONV_ID}/smartContext/main`))
    );
  });

  // 2. Conversation participant reads summary/main
  it("allows conversation participant to read summary/main", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_B).firestore();
    await assertSucceeds(
      getDoc(doc(db, `conversations/${CONV_ID}/summary/main`))
    );
  });

  // 3. Conversation participant reads smartActions
  it("allows conversation participant to read smartActions", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertSucceeds(
      getDoc(doc(db, `conversations/${CONV_ID}/smartActions/action1`))
    );
  });

  // 4. Conversation participant updates action status to "accepted"
  it("allows participant to update action status to accepted", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertSucceeds(
      updateDoc(doc(db, `conversations/${CONV_ID}/smartActions/action1`), {
        status: "accepted",
      })
    );
  });

  // 4b. Participant updates status to "dismissed"
  it("allows participant to update action status to dismissed", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_B).firestore();
    await assertSucceeds(
      updateDoc(doc(db, `conversations/${CONV_ID}/smartActions/action1`), {
        status: "dismissed",
      })
    );
  });

  // 5. User writes their own presence doc (within 31-minute window)
  it("allows user to write their own conversation presence doc", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, `conversations/${CONV_ID}/presence/${PARTICIPANT_A}`),
        {
          userId: PARTICIPANT_A,
          state: "activeNow",
          updatedAt: Timestamp.now(),
          expiresAt: expiresAtSoon(),
        }
      )
    );
  });

  // 6. Prayer signal requestor reads their own signal
  it("allows prayer signal requestor to read their own signal (including requestorId)", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertSucceeds(
      getDoc(doc(db, `conversations/${CONV_ID}/prayerSignals/signal1`))
    );
  });

  // 6b. Prayer signal requestor reads their own anonymous signal
  it("allows prayer signal requestor to read their own anonymous signal", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertSucceeds(
      getDoc(doc(db, `conversations/${CONV_ID}/prayerSignals/signalAnon`))
    );
  });

  // 6c. Other member can read approved non-anonymous signal
  it("allows other conversation member to read approved non-anonymous signal", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_B).firestore();
    await assertSucceeds(
      getDoc(doc(db, `conversations/${CONV_ID}/prayerSignals/signal1`))
    );
  });

  // 7. Space member reads channel smartContext
  it("allows space member to read channel smartContext/main", async () => {
    const db = testEnv.authenticatedContext(SPACE_MEMBER).firestore();
    await assertSucceeds(
      getDoc(
        doc(
          db,
          `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/smartContext/main`
        )
      )
    );
  });

  // 7b. Space member reads channel summary
  it("allows space member to read channel summary/main", async () => {
    const db = testEnv.authenticatedContext(SPACE_MEMBER).firestore();
    await assertSucceeds(
      getDoc(
        doc(db, `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/summary/main`)
      )
    );
  });

  // 8. Space member reads channel pulse
  it("allows space member to read channel pulse/main", async () => {
    const db = testEnv.authenticatedContext(SPACE_MEMBER).firestore();
    await assertSucceeds(
      getDoc(
        doc(db, `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/pulse/main`)
      )
    );
  });

  // 8b. Space member reads channel smartActions
  it("allows space member to read channel smartActions", async () => {
    const db = testEnv.authenticatedContext(SPACE_MEMBER).firestore();
    await assertSucceeds(
      getDoc(
        doc(
          db,
          `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/smartActions/cAction1`
        )
      )
    );
  });

  // 8c. Space member updates channel action status
  it("allows space member to update channel action status to completed", async () => {
    const db = testEnv.authenticatedContext(SPACE_MEMBER).firestore();
    await assertSucceeds(
      updateDoc(
        doc(
          db,
          `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/smartActions/cAction1`
        ),
        { status: "completed" }
      )
    );
  });

  // 8d. Space member writes their own channel presence doc
  it("allows space member to write their own channel presence doc", async () => {
    const db = testEnv.authenticatedContext(SPACE_MEMBER).firestore();
    await assertSucceeds(
      setDoc(
        doc(
          db,
          `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/presence/${SPACE_MEMBER}`
        ),
        {
          userId: SPACE_MEMBER,
          state: "activeNow",
          updatedAt: Timestamp.now(),
          expiresAt: expiresAtSoon(),
        }
      )
    );
  });

  // 9. User reads their own rateLimits/smartCollab
  it("allows user to read their own rateLimits/smartCollab", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertSucceeds(
      getDoc(doc(db, `users/${PARTICIPANT_A}/rateLimits/smartCollab`))
    );
  });

  // 9b. User writes their own rateLimits/smartCollab
  it("allows user to write their own rateLimits/smartCollab", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertSucceeds(
      setDoc(doc(db, `users/${PARTICIPANT_A}/rateLimits/smartCollab`), {
        callCount: 6,
        windowStartMs: Date.now(),
        updatedAt: Timestamp.now(),
      })
    );
  });

  // 10. Requesting user reads their own mediaJob
  it("allows requesting user to read their own mediaJob", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertSucceeds(getDoc(doc(db, `mediaJobs/job1`)));
  });

  // 11. Space member reads channel non-anonymous prayer signal
  it("allows space member to read approved non-anonymous channel prayer signal", async () => {
    const db = testEnv.authenticatedContext(SPACE_MEMBER).firestore();
    await assertSucceeds(
      getDoc(
        doc(
          db,
          `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/prayerSignals/cSignal1`
        )
      )
    );
  });

  // 12. Prayer signal requestor can delete their own signal
  it("allows prayer signal requestor to delete their own signal", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertSucceeds(
      deleteDoc(
        doc(db, `conversations/${CONV_ID}/prayerSignals/signal1`)
      )
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// DENY CASES
// ─────────────────────────────────────────────────────────────────────────────

describe("Smart Collaboration Rules — DENY cases", () => {
  // 1. Non-member reads conversation smartContext
  it("denies non-member reading conversation smartContext/main", async () => {
    const db = testEnv.authenticatedContext(NON_MEMBER).firestore();
    await assertFails(
      getDoc(doc(db, `conversations/${CONV_ID}/smartContext/main`))
    );
  });

  // 2. Non-member reads channel smartContext
  it("denies non-member reading channel smartContext/main", async () => {
    const db = testEnv.authenticatedContext(NON_MEMBER).firestore();
    await assertFails(
      getDoc(
        doc(
          db,
          `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/smartContext/main`
        )
      )
    );
  });

  // 3. Client creates smartContext (only server can)
  it("denies client creating conversation smartContext/main (Rule 1)", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertFails(
      setDoc(doc(db, `conversations/${CONV_ID}/smartContext/main`), {
        threadId: CONV_ID,
        generatedBy: PARTICIPANT_A,
        summaryText: "Client injected",
      })
    );
  });

  // 4. Client creates summary (only server can)
  it("denies client creating conversation summary/main (Rule 1)", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertFails(
      setDoc(doc(db, `conversations/${CONV_ID}/summary/main`), {
        threadId: CONV_ID,
        summaryText: "Client summary",
        generatedBy: PARTICIPANT_A,
      })
    );
  });

  // 5. Client creates prayerSignal (only server can)
  it("denies client creating a conversation prayerSignal (Rule 1)", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertFails(
      setDoc(doc(db, `conversations/${CONV_ID}/prayerSignals/fakeSignal`), {
        requestorId: PARTICIPANT_A,
        prayerTheme: "injected",
        isAnonymous: false,
        moderationStatus: "approved",
        generatedBy: PARTICIPANT_A,
      })
    );
  });

  // 6. Client writes channel pulse (only server can)
  it("denies client writing channel pulse/main (Rule 1)", async () => {
    const db = testEnv.authenticatedContext(SPACE_MEMBER).firestore();
    await assertFails(
      setDoc(
        doc(db, `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/pulse/main`),
        {
          channelId: CHANNEL_ID,
          urgency: "urgent",
          activeParticipantCount: 10,
          topicMomentum: 0.9,
          generatedBy: SPACE_MEMBER,
        }
      )
    );
  });

  // 7. User writes ANOTHER user's conversation presence doc (Rule 3)
  it("denies user writing another user's conversation presence doc (Rule 3)", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_B).firestore();
    await assertFails(
      setDoc(
        doc(
          db,
          `conversations/${CONV_ID}/presence/${PARTICIPANT_A}`
        ),
        {
          userId: PARTICIPANT_A,
          state: "activeNow",
          updatedAt: Timestamp.now(),
          expiresAt: expiresAtSoon(),
        }
      )
    );
  });

  // 7b. User writes another user's channel presence doc (Rule 3)
  it("denies user writing another user's channel presence doc (Rule 3)", async () => {
    // Use a second space member for cross-user write attempt
    const otherMember = "spaceMember2";
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(
          ctx.firestore(),
          `spaces/${SPACE_ID}/members/${otherMember}`
        ),
        { status: "active", roles: ["member"] }
      );
    });
    const db = testEnv.authenticatedContext(otherMember).firestore();
    await assertFails(
      setDoc(
        doc(
          db,
          `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/presence/${SPACE_MEMBER}`
        ),
        {
          userId: SPACE_MEMBER,
          state: "activeNow",
          updatedAt: Timestamp.now(),
          expiresAt: expiresAtSoon(),
        }
      )
    );
  });

  // 8. Client updates smartAction generatedBy field (Rule 4)
  it("denies client updating smartAction generatedBy field (Rule 4)", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertFails(
      updateDoc(
        doc(db, `conversations/${CONV_ID}/smartActions/action1`),
        {
          generatedBy: PARTICIPANT_A,
        }
      )
    );
  });

  // 8b. Client updates smartAction modelVersion (Rule 4)
  it("denies client updating smartAction modelVersion (Rule 4)", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertFails(
      updateDoc(
        doc(db, `conversations/${CONV_ID}/smartActions/action1`),
        {
          modelVersion: "client-injected",
        }
      )
    );
  });

  // 8c. Client updates smartAction status + generatedBy together (Rule 4)
  it("denies client updating status + generatedBy in same update (Rule 4)", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertFails(
      updateDoc(
        doc(db, `conversations/${CONV_ID}/smartActions/action1`),
        {
          status: "accepted",
          generatedBy: "evil@hack.com",
        }
      )
    );
  });

  // 8d. Client attempts to set an invalid status value
  it("denies client setting an invalid action status value", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertFails(
      updateDoc(
        doc(db, `conversations/${CONV_ID}/smartActions/action1`),
        {
          status: "hacked",
        }
      )
    );
  });

  // 9. Client deletes a smartAction (Rule 4)
  it("denies client deleting a conversation smartAction (Rule 4)", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertFails(
      deleteDoc(
        doc(db, `conversations/${CONV_ID}/smartActions/action1`)
      )
    );
  });

  // 10. Unauthenticated request reads conversation smartContext
  it("denies unauthenticated read of conversation smartContext/main", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      getDoc(doc(db, `conversations/${CONV_ID}/smartContext/main`))
    );
  });

  // 10b. Unauthenticated request reads channel smartContext
  it("denies unauthenticated read of channel smartContext/main", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      getDoc(
        doc(
          db,
          `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/smartContext/main`
        )
      )
    );
  });

  // 10c. Unauthenticated read of pulse
  it("denies unauthenticated read of channel pulse/main", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      getDoc(
        doc(db, `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/pulse/main`)
      )
    );
  });

  // 11. Anonymous prayer signal cannot be read by non-requestor (Rule 5)
  it("denies non-requestor reading anonymous conversation prayer signal (Rule 5)", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_B).firestore();
    await assertFails(
      getDoc(
        doc(db, `conversations/${CONV_ID}/prayerSignals/signalAnon`)
      )
    );
  });

  // 11b. Anonymous channel prayer signal — non-requestor denied
  it("denies non-requestor reading anonymous channel prayer signal (Rule 5)", async () => {
    // Use NON_MEMBER who is not in the space at all — for extra hardening
    const db = testEnv.authenticatedContext(NON_MEMBER).firestore();
    await assertFails(
      getDoc(
        doc(
          db,
          `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/prayerSignals/cSignalAnon`
        )
      )
    );
  });

  // 12. User reads another user's rateLimits/smartCollab (Rule 7)
  it("denies user reading another user's rateLimits/smartCollab (Rule 7)", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_B).firestore();
    await assertFails(
      getDoc(doc(db, `users/${PARTICIPANT_A}/rateLimits/smartCollab`))
    );
  });

  // 13. Non-member reads channel pulse (Rule 2)
  it("denies non-member reading channel pulse/main (Rule 2)", async () => {
    const db = testEnv.authenticatedContext(NON_MEMBER).firestore();
    await assertFails(
      getDoc(
        doc(db, `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/pulse/main`)
      )
    );
  });

  // 14. Non-owner reading another user's mediaJob
  it("denies non-owner reading another user's mediaJob", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_B).firestore();
    await assertFails(getDoc(doc(db, `mediaJobs/job1`)));
  });

  // 15. Presence write with expiresAt too far in the future
  it("denies conversation presence write with expiresAt > 31 minutes from now", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertFails(
      setDoc(
        doc(
          db,
          `conversations/${CONV_ID}/presence/${PARTICIPANT_A}`
        ),
        {
          userId: PARTICIPANT_A,
          state: "activeNow",
          updatedAt: Timestamp.now(),
          expiresAt: expiresAtTooFar(),
        }
      )
    );
  });

  // 16. Client creates channel smartContext (only server can)
  it("denies client creating channel smartContext/main (Rule 1)", async () => {
    const db = testEnv.authenticatedContext(SPACE_MEMBER).firestore();
    await assertFails(
      setDoc(
        doc(
          db,
          `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/smartContext/main`
        ),
        {
          threadId: CHANNEL_ID,
          generatedBy: SPACE_MEMBER,
          summaryText: "Client injected channel context",
        }
      )
    );
  });

  // 17. Client creates channel summary (only server can)
  it("denies client creating channel summary/main (Rule 1)", async () => {
    const db = testEnv.authenticatedContext(SPACE_MEMBER).firestore();
    await assertFails(
      setDoc(
        doc(
          db,
          `spaces/${SPACE_ID}/channels/${CHANNEL_ID}/summary/main`
        ),
        {
          threadId: CHANNEL_ID,
          summaryText: "Client channel summary",
          generatedBy: SPACE_MEMBER,
        }
      )
    );
  });

  // 18. Client writes mediaJob (only server can)
  it("denies client writing a mediaJob (Rule 1)", async () => {
    const db = testEnv.authenticatedContext(PARTICIPANT_A).firestore();
    await assertFails(
      setDoc(doc(db, `mediaJobs/fakeJob`), {
        requestedBy: PARTICIPANT_A,
        status: "processing",
      })
    );
  });
});
