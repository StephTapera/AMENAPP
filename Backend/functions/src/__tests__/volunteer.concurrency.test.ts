// volunteer.concurrency.test.ts
// AMEN — Smart Volunteer Board · Wave 0 invariant tests.
//
//   I1 — No overfill: simultaneous signups at the last slot never exceed countNeeded.
//   I2 — Derived board: computeBoard counts active assignments; it is never a stored counter.
//   I3 — Blackout respected: a blacked-out volunteer cannot sign up.
//
// I1 is proven against an in-memory Firestore that models the *observable guarantee* of a
// Firestore transaction: snapshot-isolated reads + optimistic concurrency (abort-and-retry on a
// read/write conflict). A `readBarrier` forces all N transactions to finish their READ phase
// before any COMMIT — the exact last-slot race. If signUpForSlot read counts OUTSIDE the
// transaction, this test would show overfill; because it reads inside, it cannot.

import { computeBoard, evaluateSignup } from "../volunteer/volunteerBoardLogic";
import { resolveSignupVolunteerId, runSignUpTransaction } from "../volunteer/volunteerCallables";
import { Assignment, StaffingNeed } from "../contracts/volunteer";

// ────────────────────────────────────────────────────────────────────
// Minimal OCC Firestore simulator (transaction semantics under test)
// ────────────────────────────────────────────────────────────────────

interface Filter { field: string; value: unknown; }

class FakeOCCFirestore {
  private store = new Map<string, Record<string, unknown>>();
  private docVersion = new Map<string, number>();
  private collVersion = new Map<string, number>();
  private idCounter = 0;
  private commitLock: Promise<void> = Promise.resolve();
  /** Optional barrier invoked once per transaction (attempt 0) after its reads complete. */
  readBarrier?: () => Promise<void>;

  seed(path: string, data: Record<string, unknown>): void {
    this.store.set(path, data);
    this.bump(path);
  }

  private bump(path: string): void {
    this.docVersion.set(path, (this.docVersion.get(path) ?? 0) + 1);
    const coll = path.slice(0, path.lastIndexOf("/"));
    this.collVersion.set(coll, (this.collVersion.get(coll) ?? 0) + 1);
  }

  collection(name: string): FakeCollection {
    return new FakeCollection(this, name);
  }

  // --- internals used by refs/queries ---
  _get(path: string) { return this.store.get(path); }
  _docVer(path: string) { return this.docVersion.get(path) ?? 0; }
  _collVer(coll: string) { return this.collVersion.get(coll) ?? 0; }
  _nextId() { this.idCounter += 1; return `gen-${this.idCounter}`; }
  _queryDocs(coll: string, filters: Filter[]) {
    const out: Array<{ path: string; data: Record<string, unknown> }> = [];
    for (const [path, data] of this.store.entries()) {
      if (path.slice(0, path.lastIndexOf("/")) !== coll) continue;
      if (filters.every((f) => data[f.field] === f.value)) out.push({ path, data });
    }
    return out;
  }

  async runTransaction<T>(cb: (tx: FakeTransaction) => Promise<T>): Promise<T> {
    for (let attempt = 0; attempt < 50; attempt += 1) {
      const tx = new FakeTransaction(this);
      const result = await cb(tx);

      // Force the simultaneous last-slot race on the first attempt only.
      if (attempt === 0 && this.readBarrier) await this.readBarrier();

      // Serialize commits; validate the optimistic read-set, then apply atomically.
      const conflicted = await this.commitSection(() => {
        for (const [path, ver] of tx.readDocVersions) {
          if (this._docVer(path) !== ver) return true;
        }
        for (const [coll, ver] of tx.readCollVersions) {
          if (this._collVer(coll) !== ver) return true;
        }
        for (const w of tx.writes) {
          this.store.set(w.path, w.data);
          this.bump(w.path);
        }
        return false;
      });

      if (!conflicted) return result;
      // else: retry with a fresh snapshot
    }
    throw new Error("transaction exceeded retry budget");
  }

  private async commitSection(critical: () => boolean): Promise<boolean> {
    let release!: () => void;
    const next = new Promise<void>((r) => (release = r));
    const prev = this.commitLock;
    this.commitLock = next;
    await prev;
    try {
      return critical();
    } finally {
      release();
    }
  }
}

class FakeCollection {
  constructor(private db: FakeOCCFirestore, public name: string) {}
  doc(id?: string): FakeDocRef {
    return new FakeDocRef(this.db, `${this.name}/${id ?? this.db._nextId()}`);
  }
  where(field: string, _op: string, value: unknown): FakeQuery {
    return new FakeQuery(this.db, this.name, [{ field, value }]);
  }
}

class FakeDocRef {
  constructor(private db: FakeOCCFirestore, public path: string) {}
  get id() { return this.path.slice(this.path.lastIndexOf("/") + 1); }
  collection(name: string): FakeCollection {
    return new FakeCollection(this.db, `${this.path}/${name}`);
  }
  // Non-transactional read (used by requireEventLeader / resolveSignupVolunteerId).
  async get(): Promise<any> {
    const data = this.db._get(this.path);
    return { exists: data !== undefined, data: () => data };
  }
}

class FakeQuery {
  constructor(private db: FakeOCCFirestore, public coll: string, private filters: Filter[]) {}
  where(field: string, _op: string, value: unknown): FakeQuery {
    return new FakeQuery(this.db, this.coll, [...this.filters, { field, value }]);
  }
  _read() { return this.db._queryDocs(this.coll, this.filters); }
}

class FakeTransaction {
  readDocVersions = new Map<string, number>();
  readCollVersions = new Map<string, number>();
  writes: Array<{ path: string; data: Record<string, unknown> }> = [];
  constructor(private db: FakeOCCFirestore) {}

  async get(target: FakeDocRef | FakeQuery): Promise<any> {
    if (target instanceof FakeDocRef) {
      this.readDocVersions.set(target.path, this.db._docVer(target.path));
      const data = this.db._get(target.path);
      return { exists: data !== undefined, data: () => data };
    }
    this.readCollVersions.set(target.coll, this.db._collVer(target.coll));
    const docs = target._read().map((d) => ({ data: () => d.data }));
    return { docs };
  }
  set(ref: FakeDocRef, data: Record<string, unknown>): void {
    this.writes.push({ path: ref.path, data });
  }
}

function makeBarrier(n: number): () => Promise<void> {
  let count = 0;
  let release!: () => void;
  const gate = new Promise<void>((r) => (release = r));
  return async () => {
    count += 1;
    if (count >= n) release();
    await gate;
  };
}

function activeCount(db: FakeOCCFirestore, eventId: string, role: string): number {
  return (db as any)._queryDocs("volunteerAssignments", [
    { field: "eventId", value: eventId },
    { field: "role", value: role },
  ]).filter((d: any) => {
    const s = d.data.status;
    return s === "signedUp" || s === "confirmed";
  }).length;
}

// ────────────────────────────────────────────────────────────────────
// I1 — No overfill under simultaneous last-slot signups
// ────────────────────────────────────────────────────────────────────

describe("I1 — atomic slot-fill never overfills", () => {
  it("countNeeded=1, 5 simultaneous signups → exactly 1 filled, 4 waitlisted", async () => {
    const db = new FakeOCCFirestore();
    db.seed("volunteerEvents/evt1/needs/Greeter", {
      eventId: "evt1", role: "Greeter", countNeeded: 1, status: "open",
    });

    const N = 5;
    db.readBarrier = makeBarrier(N);

    const results = await Promise.all(
      Array.from({ length: N }, (_unused, i) =>
        runSignUpTransaction(db as any, {
          eventId: "evt1", role: "Greeter", volunteerId: `vol-${i}`, eventDate: "2026-06-21",
        }),
      ),
    );

    const fills = results.filter((r) => r.decision === "fill");
    const waits = results.filter((r) => r.decision === "waitlist");
    expect(fills).toHaveLength(1);
    expect(waits).toHaveLength(4);
    expect(activeCount(db, "evt1", "Greeter")).toBe(1); // never exceeds countNeeded
  });

  it("countNeeded=3, 10 simultaneous signups → exactly 3 filled", async () => {
    const db = new FakeOCCFirestore();
    db.seed("volunteerEvents/evt2/needs/Media", {
      eventId: "evt2", role: "Media", countNeeded: 3, status: "open",
    });

    const N = 10;
    db.readBarrier = makeBarrier(N);

    const results = await Promise.all(
      Array.from({ length: N }, (_unused, i) =>
        runSignUpTransaction(db as any, {
          eventId: "evt2", role: "Media", volunteerId: `vol-${i}`, eventDate: "2026-06-21",
        }),
      ),
    );

    expect(results.filter((r) => r.decision === "fill")).toHaveLength(3);
    expect(results.filter((r) => r.decision === "waitlist")).toHaveLength(7);
    expect(activeCount(db, "evt2", "Media")).toBe(3);
  });
});

// ────────────────────────────────────────────────────────────────────
// I3 — Blackout respected
// ────────────────────────────────────────────────────────────────────

describe("I3 — blackout blocks signup", () => {
  it("a blacked-out volunteer is rejected and no assignment is written", async () => {
    const db = new FakeOCCFirestore();
    db.seed("volunteerEvents/evt3/needs/Worship", {
      eventId: "evt3", role: "Worship", countNeeded: 2, status: "open",
    });
    db.seed("volunteerBlackouts/vol-x_2026-06-21", { volunteerId: "vol-x", date: "2026-06-21" });

    const res = await runSignUpTransaction(db as any, {
      eventId: "evt3", role: "Worship", volunteerId: "vol-x", eventDate: "2026-06-21",
    });

    expect(res.decision).toBe("reject_blackout");
    expect(res.assignmentId).toBeNull();
    expect(activeCount(db, "evt3", "Worship")).toBe(0);
  });
});

// ────────────────────────────────────────────────────────────────────
// Duplicate guard — a volunteer cannot inflate filled past their one slot
// ────────────────────────────────────────────────────────────────────

describe("duplicate signup is rejected", () => {
  it("same volunteer signing twice → second is reject_duplicate", async () => {
    const db = new FakeOCCFirestore();
    db.seed("volunteerEvents/evt4/needs/Usher", {
      eventId: "evt4", role: "Usher", countNeeded: 5, status: "open",
    });

    const first = await runSignUpTransaction(db as any, {
      eventId: "evt4", role: "Usher", volunteerId: "vol-d", eventDate: "2026-06-21",
    });
    const second = await runSignUpTransaction(db as any, {
      eventId: "evt4", role: "Usher", volunteerId: "vol-d", eventDate: "2026-06-21",
    });

    expect(first.decision).toBe("fill");
    expect(second.decision).toBe("reject_duplicate");
    expect(activeCount(db, "evt4", "Usher")).toBe(1);
  });
});

// ────────────────────────────────────────────────────────────────────
// I2 — Derived board (computed, never a stored counter)
// ────────────────────────────────────────────────────────────────────

describe("I2 — board is derived from assignments", () => {
  const needs: StaffingNeed[] = [
    { eventId: "e", role: "Greeter", countNeeded: 4, status: "open" },
    { eventId: "e", role: "Worship", countNeeded: 2, status: "open" },
    { eventId: "e", role: "Media", countNeeded: 1, status: "needsBackup" },
    { eventId: "e", role: "Parking", countNeeded: 2, status: "closed" },
  ];
  const assignments: Assignment[] = [
    { id: "a1", eventId: "e", role: "Greeter", volunteerId: "v1", status: "signedUp" },
    { id: "a2", eventId: "e", role: "Greeter", volunteerId: "v2", status: "confirmed" },
    { id: "a3", eventId: "e", role: "Greeter", volunteerId: "v3", status: "waitlisted" }, // not counted
    { id: "a4", eventId: "e", role: "Worship", volunteerId: "v4", status: "signedUp" },
    { id: "a5", eventId: "e", role: "Worship", volunteerId: "v5", status: "confirmed" },
    { id: "a6", eventId: "e", role: "Media", volunteerId: "v6", status: "confirmed" },
    { id: "a7", eventId: "e", role: "Media", volunteerId: "v7", status: "declined" }, // not counted
  ];

  it("filled is counted from active assignments; statuses derive correctly", () => {
    const board = computeBoard("e", needs, assignments);
    const byRole = Object.fromEntries(board.roles.map((r) => [r.role, r]));

    expect(byRole.Greeter).toMatchObject({ filled: 2, needed: 4, status: "open" });   // 2/4 open
    expect(byRole.Worship).toMatchObject({ filled: 2, needed: 2, status: "full" });    // full
    expect(byRole.Media).toMatchObject({ filled: 1, needed: 1, status: "needsBackup" }); // needs backup
    expect(byRole.Parking).toMatchObject({ filled: 0, needed: 2, status: "closed" });  // closed
  });

  it("waitlisted/declined assignments never inflate filled (no drift)", () => {
    const board = computeBoard("e", needs, assignments);
    const greeter = board.roles.find((r) => r.role === "Greeter")!;
    // 3 Greeter assignment docs exist, but only 2 are active → filled is derived, not a count of docs.
    expect(greeter.filled).toBe(2);
  });
});

// ────────────────────────────────────────────────────────────────────
// IDOR guard — signUpForSlot binds the assignment to the caller, not to a
// client-supplied volunteerId (unless the caller is a verified event leader).
// ────────────────────────────────────────────────────────────────────

describe("resolveSignupVolunteerId — identity binding (IDOR guard)", () => {
  function seedEvent(leaderIds: string[] = []): FakeOCCFirestore {
    const db = new FakeOCCFirestore();
    db.seed("volunteerEvents/evt", {
      eventId: "evt", title: "Sunday", startUTC: "2026-06-21T15:00:00Z", leaderIds,
    });
    return db;
  }

  it("binds to the caller when volunteerId matches the caller", async () => {
    const db = seedEvent();
    const id = await resolveSignupVolunteerId(db as any, "me", "me", "evt");
    expect(id).toBe("me");
  });

  it("binds to the caller when volunteerId is missing/empty (no spoofable default)", async () => {
    const db = seedEvent();
    await expect(resolveSignupVolunteerId(db as any, "me", undefined, "evt")).resolves.toBe("me");
    await expect(resolveSignupVolunteerId(db as any, "me", "   ", "evt")).resolves.toBe("me");
  });

  it("a non-leader signing up SOMEONE ELSE is rejected (permission-denied)", async () => {
    const db = seedEvent([]); // caller is not a leader
    await expect(
      resolveSignupVolunteerId(db as any, "attacker", "victim", "evt"),
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  it("a non-leader still cannot spoof even when they ARE a different real user", async () => {
    const db = seedEvent(["someLeader"]);
    await expect(
      resolveSignupVolunteerId(db as any, "attacker", "victim", "evt"),
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  it("a verified event leader MAY sign another volunteer up", async () => {
    const db = seedEvent(["leader1"]);
    const id = await resolveSignupVolunteerId(db as any, "leader1", "volunteerB", "evt");
    expect(id).toBe("volunteerB");
  });
});

// ────────────────────────────────────────────────────────────────────
// evaluateSignup — pure branch coverage
// ────────────────────────────────────────────────────────────────────

describe("evaluateSignup pure decision", () => {
  it("blackout takes precedence", () => {
    expect(evaluateSignup({ countNeeded: 5, activeFilled: 0, isBlackedOut: true, volunteerAlreadyActive: false }).decision)
      .toBe("reject_blackout");
  });
  it("duplicate rejected", () => {
    expect(evaluateSignup({ countNeeded: 5, activeFilled: 1, isBlackedOut: false, volunteerAlreadyActive: true }).decision)
      .toBe("reject_duplicate");
  });
  it("waitlists when full", () => {
    expect(evaluateSignup({ countNeeded: 2, activeFilled: 2, isBlackedOut: false, volunteerAlreadyActive: false }))
      .toEqual({ decision: "waitlist", resultingStatus: "waitlisted" });
  });
  it("fills when open", () => {
    expect(evaluateSignup({ countNeeded: 2, activeFilled: 1, isBlackedOut: false, volunteerAlreadyActive: false }))
      .toEqual({ decision: "fill", resultingStatus: "signedUp" });
  });
});
