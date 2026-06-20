/**
 * insiderThreatAudit.test.ts — unit tests for the insider-threat access-control
 * spine (Trust & Safety Remediation item 21).
 *
 * These tests pin the safety-critical contracts that make the spine shippable:
 *   - Audit logging is ALWAYS on (even when enforcement is off).
 *   - The two-person rule counts DISTINCT approvers and reaches "satisfied" only
 *     at two; legacy auto-id approval docs dedupe by approverUid.
 *   - The gate is fail-closed: when enforcement is on and approval state cannot
 *     be read, access is DENIED; break-glass requires a justification.
 *   - The callables enforce reviewer / oversight roles and App Check.
 *
 * ENFORCEMENT_ENABLED is read once at module load from
 * INSIDER_THREAT_ENFORCEMENT_ENABLED, so we reload the module per scenario via
 * `loadSpine(enforcement)`.
 */

// ─── Controllable firestore / auth handles ──────────────────────────────────────
const mockLogSet = jest.fn();
const mockCaseGet = jest.fn();
const mockApprovalsGet = jest.fn();
const mockApprovalSet = jest.fn();
const mockEvidenceGet = jest.fn();
const mockLogQueryGet = jest.fn();
const mockGetUser = jest.fn();

let logDocCounter = 0;
// The most recent query built against sensitiveAccessLog (for filter assertions).
let lastLogQuery: Record<string, unknown> | null = null;

jest.mock("firebase-admin", () => {
    const makeLogQuery = () => {
        const q: Record<string, unknown> = {};
        q["_where"] = null;
        q["_order"] = null;
        q["_limit"] = null;
        q["where"] = jest.fn((field: string, op: string, val: unknown) => {
            q["_where"] = { field, op, val };
            return q;
        });
        q["orderBy"] = jest.fn((field: string, dir: string) => {
            q["_order"] = { field, dir };
            return q;
        });
        q["limit"] = jest.fn((n: number) => {
            q["_limit"] = n;
            return q;
        });
        q["get"] = mockLogQueryGet;
        return q;
    };

    const firestoreFn = jest.fn(() => ({
        collection: jest.fn((name: string) => {
            if (name === "sensitiveAccessLog") {
                const query = makeLogQuery();
                lastLogQuery = query;
                return {
                    // doc() with no args → a fresh immutable append target.
                    doc: jest.fn((id?: string) => ({
                        id: id ?? `audit-${++logDocCounter}`,
                        set: mockLogSet,
                    })),
                    where: query["where"],
                    orderBy: query["orderBy"],
                    limit: query["limit"],
                    get: mockLogQueryGet,
                };
            }
            if (name === "moderationCases") {
                return {
                    doc: jest.fn((caseId: string) => ({
                        id: caseId,
                        get: mockCaseGet,
                        collection: jest.fn((sub: string) => {
                            if (sub === "approvals") {
                                return {
                                    get: mockApprovalsGet,
                                    doc: jest.fn((uid: string) => ({
                                        id: uid,
                                        set: mockApprovalSet,
                                    })),
                                };
                            }
                            return { get: jest.fn(), doc: jest.fn() };
                        }),
                    })),
                };
            }
            if (name === "evidenceVault") {
                return { doc: jest.fn((id: string) => ({ id, get: mockEvidenceGet })) };
            }
            return { doc: jest.fn(() => ({ get: jest.fn(), set: jest.fn() })) };
        }),
    })) as jest.Mock & { FieldValue: { serverTimestamp: jest.Mock } };

    firestoreFn.FieldValue = { serverTimestamp: jest.fn(() => "serverTimestamp") };

    return {
        firestore: firestoreFn,
        auth: jest.fn(() => ({ getUser: mockGetUser })),
    };
});

// Local https mock returns { options, run } so we can assert App Check options
// AND invoke the handler. (Overrides the global jest.setup mock for this file.)
jest.mock("firebase-functions/v2/https", () => {
    class HttpsError extends Error {
        code: string;
        constructor(code: string, message: string) {
            super(message);
            this.code = code;
        }
    }
    return {
        HttpsError,
        onCall: jest.fn((options: unknown, handler: unknown) => ({ options, run: handler })),
    };
});

// ─── Helpers ────────────────────────────────────────────────────────────────────

type Spine = typeof import("./insiderThreatAudit");

/** Reload the spine with enforcement on/off (env is read at module load). */
function loadSpine(enforcement: boolean): Spine {
    jest.resetModules();
    if (enforcement) {
        process.env.INSIDER_THREAT_ENFORCEMENT_ENABLED = "true";
    } else {
        delete process.env.INSIDER_THREAT_ENFORCEMENT_ENABLED;
    }
    let mod: Spine | undefined;
    jest.isolateModules(() => {
        // eslint-disable-next-line @typescript-eslint/no-var-requires
        mod = require("./insiderThreatAudit");
    });
    return mod as Spine;
}

/** Build an approvals subcollection snapshot from approver descriptors. */
function approvalsSnap(
    approvers: Array<string | { id: string; approverUid?: string }>
): { size: number; forEach: (cb: (d: unknown) => void) => void } {
    const docs = approvers.map((a) =>
        typeof a === "string"
            ? { id: a, data: () => ({ approverUid: a }) }
            : { id: a.id, data: () => ({ approverUid: a.approverUid }) }
    );
    return { size: docs.length, forEach: (cb) => docs.forEach(cb) };
}

type CallRequest = Record<string, unknown>;
type Callable = { options: { enforceAppCheck?: boolean }; run: (r: CallRequest) => Promise<unknown> };

beforeEach(() => {
    jest.clearAllMocks();
    logDocCounter = 0;
    lastLogQuery = null;
    mockLogSet.mockResolvedValue(undefined);
    mockApprovalSet.mockResolvedValue(undefined);
    mockCaseGet.mockResolvedValue({ exists: false, data: () => ({}) });
    mockApprovalsGet.mockResolvedValue(approvalsSnap([]));
    mockEvidenceGet.mockResolvedValue({ exists: false, data: () => ({}) });
    mockLogQueryGet.mockResolvedValue({ docs: [], size: 0 });
    mockGetUser.mockResolvedValue({ customClaims: {} });
});

// ─── recordSensitiveAccess (always-on audit log) ────────────────────────────────

describe("recordSensitiveAccess", () => {
    it("writes an immutable audit row with all fields and returns its id", async () => {
        const spine = loadSpine(false);
        const id = await spine.recordSensitiveAccess({
            actorUid: "mod-1",
            resourceType: "dm",
            resourceId: "conv-9",
            action: "view",
            subjectUid: "victim-7",
            justification: "report triage",
            breakGlass: true,
            metadata: { tier: 1 },
        });

        expect(id).toMatch(/^audit-/);
        expect(mockLogSet).toHaveBeenCalledTimes(1);
        const row = mockLogSet.mock.calls[0][0];
        expect(row).toMatchObject({
            auditId: id,
            actorUid: "mod-1",
            resourceType: "dm",
            resourceId: "conv-9",
            action: "view",
            subjectUid: "victim-7",
            justification: "report triage",
            breakGlass: true,
            metadata: { tier: 1 },
            enforcementEnabled: false,
            createdAt: "serverTimestamp",
        });
    });

    it("records enforcementEnabled=true when enforcement is on, and defaults optionals", async () => {
        const spine = loadSpine(true);
        await spine.recordSensitiveAccess({
            actorUid: "mod-2",
            resourceType: "minor_data",
            resourceId: "user-3",
            action: "export",
        });
        const row = mockLogSet.mock.calls[0][0];
        expect(row.enforcementEnabled).toBe(true);
        expect(row.subjectUid).toBeNull();
        expect(row.justification).toBeNull();
        expect(row.breakGlass).toBe(false);
        expect(row.metadata).toEqual({});
    });
});

// ─── evaluateDualApproval (two-person rule) ─────────────────────────────────────

describe("evaluateDualApproval", () => {
    it("is satisfied when the case does not require dual approval", async () => {
        const spine = loadSpine(false);
        mockCaseGet.mockResolvedValue({ exists: true, data: () => ({ dualApprovalRequired: false }) });
        mockApprovalsGet.mockResolvedValue(approvalsSnap([]));

        const state = await spine.evaluateDualApproval("case-a");
        expect(state).toEqual({
            required: false,
            approverCount: 0,
            satisfied: true,
            breakGlassRequired: false,
        });
    });

    it("is NOT satisfied with zero approvers when required", async () => {
        const spine = loadSpine(false);
        mockCaseGet.mockResolvedValue({ exists: true, data: () => ({ dualApprovalRequired: true }) });
        mockApprovalsGet.mockResolvedValue(approvalsSnap([]));

        const state = await spine.evaluateDualApproval("case-b");
        expect(state.required).toBe(true);
        expect(state.approverCount).toBe(0);
        expect(state.satisfied).toBe(false);
    });

    it("is NOT satisfied with a single approver", async () => {
        const spine = loadSpine(false);
        mockCaseGet.mockResolvedValue({ exists: true, data: () => ({ dualApprovalRequired: true }) });
        mockApprovalsGet.mockResolvedValue(approvalsSnap(["mod-a"]));

        const state = await spine.evaluateDualApproval("case-c");
        expect(state.approverCount).toBe(1);
        expect(state.satisfied).toBe(false);
    });

    it("is satisfied with two DISTINCT approvers", async () => {
        const spine = loadSpine(false);
        mockCaseGet.mockResolvedValue({ exists: true, data: () => ({ dualApprovalRequired: true }) });
        mockApprovalsGet.mockResolvedValue(approvalsSnap(["mod-a", "mod-b"]));

        const state = await spine.evaluateDualApproval("case-d");
        expect(state.approverCount).toBe(2);
        expect(state.satisfied).toBe(true);
    });

    it("dedupes legacy auto-id approval docs by approverUid (same reviewer counts once)", async () => {
        const spine = loadSpine(false);
        mockCaseGet.mockResolvedValue({ exists: true, data: () => ({ dualApprovalRequired: true }) });
        // Two docs with auto-generated ids but the SAME approverUid.
        mockApprovalsGet.mockResolvedValue(
            approvalsSnap([
                { id: "auto-1", approverUid: "mod-a" },
                { id: "auto-2", approverUid: "mod-a" },
            ])
        );

        const state = await spine.evaluateDualApproval("case-e");
        expect(state.approverCount).toBe(1);
        expect(state.satisfied).toBe(false);
    });

    it("surfaces the break-glass-required flag from the case", async () => {
        const spine = loadSpine(false);
        mockCaseGet.mockResolvedValue({
            exists: true,
            data: () => ({ dualApprovalRequired: true, breakGlassRequiredForPrivateContent: true }),
        });
        const state = await spine.evaluateDualApproval("case-f");
        expect(state.breakGlassRequired).toBe(true);
    });
});

// ─── recordApproval (idempotent per approver) ───────────────────────────────────

describe("recordApproval", () => {
    it("writes the approval keyed by approver UID and returns updated state", async () => {
        const spine = loadSpine(false);
        mockCaseGet.mockResolvedValue({ exists: true, data: () => ({ dualApprovalRequired: true }) });
        mockApprovalsGet.mockResolvedValue(approvalsSnap(["mod-a"]));

        const state = await spine.recordApproval("case-g", "mod-a");
        expect(mockApprovalSet).toHaveBeenCalledWith(
            expect.objectContaining({ approverUid: "mod-a", approvedAt: "serverTimestamp" }),
            { merge: true }
        );
        expect(state.approverCount).toBe(1);
        expect(state.satisfied).toBe(false);
    });
});

// ─── authorizeSensitiveAccess (the gate) ────────────────────────────────────────

describe("authorizeSensitiveAccess — enforcement OFF", () => {
    it("always authorizes (logged_only) and always logs, even with an unsatisfied case", async () => {
        const spine = loadSpine(false);
        mockCaseGet.mockResolvedValue({ exists: true, data: () => ({ dualApprovalRequired: true }) });
        mockApprovalsGet.mockResolvedValue(approvalsSnap([])); // not satisfied

        const decision = await spine.authorizeSensitiveAccess({
            actorUid: "mod-1",
            resourceType: "evidence_vault",
            resourceId: "case-h",
            action: "view",
            caseId: "case-h",
        });

        expect(decision.authorized).toBe(true);
        expect(decision.reason).toBe("logged_only");
        expect(mockLogSet).toHaveBeenCalledTimes(1);
    });

    it("authorizes even when break-glass is set without a justification (logging only)", async () => {
        const spine = loadSpine(false);
        const decision = await spine.authorizeSensitiveAccess({
            actorUid: "mod-1",
            resourceType: "dm",
            resourceId: "conv-1",
            action: "view",
            breakGlass: true,
        });
        expect(decision.authorized).toBe(true);
        expect(decision.reason).toBe("logged_only");
    });
});

describe("authorizeSensitiveAccess — enforcement ON", () => {
    it("denies break-glass without a justification", async () => {
        const spine = loadSpine(true);
        const decision = await spine.authorizeSensitiveAccess({
            actorUid: "mod-1",
            resourceType: "dm",
            resourceId: "conv-1",
            action: "view",
            breakGlass: true,
            justification: "   ", // whitespace only → not a justification
        });
        expect(decision.authorized).toBe(false);
        expect(decision.reason).toBe("denied_break_glass_requires_justification");
        expect(mockLogSet).toHaveBeenCalledTimes(1); // still logged
    });

    it("authorizes with no case context (log + break-glass rule are the controls)", async () => {
        const spine = loadSpine(true);
        const decision = await spine.authorizeSensitiveAccess({
            actorUid: "mod-1",
            resourceType: "user_pii",
            resourceId: "user-1",
            action: "view",
        });
        expect(decision.authorized).toBe(true);
        expect(decision.reason).toBe("approved_no_case_context");
    });

    it("authorizes when dual approval is satisfied", async () => {
        const spine = loadSpine(true);
        mockCaseGet.mockResolvedValue({ exists: true, data: () => ({ dualApprovalRequired: true }) });
        mockApprovalsGet.mockResolvedValue(approvalsSnap(["mod-a", "mod-b"]));

        const decision = await spine.authorizeSensitiveAccess({
            actorUid: "mod-c",
            resourceType: "evidence_vault",
            resourceId: "case-i",
            action: "view",
            caseId: "case-i",
        });
        expect(decision.authorized).toBe(true);
        expect(decision.reason).toBe("approved");
        expect(decision.dualApproval?.satisfied).toBe(true);
    });

    it("denies a case pending dual approval when no break-glass override is given", async () => {
        const spine = loadSpine(true);
        mockCaseGet.mockResolvedValue({ exists: true, data: () => ({ dualApprovalRequired: true }) });
        mockApprovalsGet.mockResolvedValue(approvalsSnap(["mod-a"])); // only one

        const decision = await spine.authorizeSensitiveAccess({
            actorUid: "mod-c",
            resourceType: "evidence_vault",
            resourceId: "case-j",
            action: "view",
            caseId: "case-j",
        });
        expect(decision.authorized).toBe(false);
        expect(decision.reason).toBe("denied_pending_dual_approval");
        expect(decision.dualApproval?.approverCount).toBe(1);
    });

    it("allows a break-glass override on an unsatisfied case and logs it loudly", async () => {
        const spine = loadSpine(true);
        const { logger } = require("firebase-functions/v2");
        mockCaseGet.mockResolvedValue({ exists: true, data: () => ({ dualApprovalRequired: true }) });
        mockApprovalsGet.mockResolvedValue(approvalsSnap(["mod-a"]));

        const decision = await spine.authorizeSensitiveAccess({
            actorUid: "mod-c",
            resourceType: "evidence_vault",
            resourceId: "case-k",
            action: "view",
            caseId: "case-k",
            breakGlass: true,
            justification: "imminent harm — escalating to NCMEC",
        });
        expect(decision.authorized).toBe(true);
        expect(decision.reason).toBe("approved_break_glass_override");
        expect(logger.warn).toHaveBeenCalled();
    });

    it("fails CLOSED when approval state cannot be evaluated", async () => {
        const spine = loadSpine(true);
        mockCaseGet.mockRejectedValue(new Error("firestore unavailable"));

        const decision = await spine.authorizeSensitiveAccess({
            actorUid: "mod-c",
            resourceType: "evidence_vault",
            resourceId: "case-l",
            action: "view",
            caseId: "case-l",
        });
        expect(decision.authorized).toBe(false);
        expect(decision.reason).toBe("denied_evaluation_error");
        expect(mockLogSet).toHaveBeenCalledTimes(1); // access still logged
    });
});

// ─── Callables ──────────────────────────────────────────────────────────────────

describe("approveSensitiveCase", () => {
    it("enforces App Check", () => {
        const spine = loadSpine(false);
        const callable = spine.approveSensitiveCase as unknown as Callable;
        expect(callable.options.enforceAppCheck).toBe(true);
    });

    it("rejects non-reviewer callers", async () => {
        const spine = loadSpine(false);
        mockGetUser.mockResolvedValue({ customClaims: { role: "member" } });
        const callable = spine.approveSensitiveCase as unknown as Callable;
        await expect(
            callable.run({ auth: { uid: "u1" }, data: { caseId: "case-m" } })
        ).rejects.toMatchObject({ code: "permission-denied" });
    });

    it("rejects an unauthenticated caller", async () => {
        const spine = loadSpine(false);
        const callable = spine.approveSensitiveCase as unknown as Callable;
        await expect(callable.run({ data: { caseId: "case-m" } })).rejects.toMatchObject({
            code: "unauthenticated",
        });
    });

    it("requires a caseId", async () => {
        const spine = loadSpine(false);
        mockGetUser.mockResolvedValue({ customClaims: { role: "moderator" } });
        const callable = spine.approveSensitiveCase as unknown as Callable;
        await expect(
            callable.run({ auth: { uid: "mod-1" }, data: {} })
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    it("records an approval for a reviewer and reports progress", async () => {
        const spine = loadSpine(false);
        mockGetUser.mockResolvedValue({ customClaims: { role: "moderator" } });
        mockCaseGet.mockResolvedValue({ exists: true, data: () => ({ dualApprovalRequired: true }) });
        mockApprovalsGet.mockResolvedValue(approvalsSnap(["mod-1"]));
        const callable = spine.approveSensitiveCase as unknown as Callable;

        const result = (await callable.run({
            auth: { uid: "mod-1" },
            data: { caseId: "case-n" },
        })) as Record<string, unknown>;

        expect(mockApprovalSet).toHaveBeenCalled();
        expect(result).toMatchObject({
            caseId: "case-n",
            requiredApprovers: 2,
            satisfied: false,
        });
    });
});

describe("accessSensitiveCase", () => {
    it("denies a pending case under enforcement and never returns evidence", async () => {
        const spine = loadSpine(true);
        mockGetUser.mockResolvedValue({ customClaims: { admin: true } });
        mockCaseGet.mockResolvedValue({ exists: true, data: () => ({ dualApprovalRequired: true }) });
        mockApprovalsGet.mockResolvedValue(approvalsSnap(["mod-a"])); // one approver
        const callable = spine.accessSensitiveCase as unknown as Callable;

        await expect(
            callable.run({ auth: { uid: "mod-x" }, data: { caseId: "case-o" } })
        ).rejects.toMatchObject({ code: "permission-denied" });
        // Evidence vault must not have been read on the deny path.
        expect(mockEvidenceGet).not.toHaveBeenCalled();
    });

    it("returns case + evidence when authorized", async () => {
        const spine = loadSpine(true);
        mockGetUser.mockResolvedValue({ customClaims: { admin: true } });
        mockCaseGet.mockResolvedValue({
            exists: true,
            data: () => ({ dualApprovalRequired: true, tier: 1 }),
        });
        mockApprovalsGet.mockResolvedValue(approvalsSnap(["mod-a", "mod-b"]));
        mockEvidenceGet.mockResolvedValue({ exists: true, data: () => ({ preserved: true }) });
        const callable = spine.accessSensitiveCase as unknown as Callable;

        const result = (await callable.run({
            auth: { uid: "mod-x" },
            data: { caseId: "case-p" },
        })) as Record<string, unknown>;

        expect(result.authorized).toBe(true);
        expect(result.case).toMatchObject({ tier: 1 });
        expect(result.evidence).toMatchObject({ preserved: true });
    });
});

describe("getSensitiveAccessLog", () => {
    it("rejects reviewers without an oversight role", async () => {
        const spine = loadSpine(false);
        mockGetUser.mockResolvedValue({ customClaims: { role: "moderator" } });
        const callable = spine.getSensitiveAccessLog as unknown as Callable;
        await expect(
            callable.run({ auth: { uid: "mod-1" }, data: {} })
        ).rejects.toMatchObject({ code: "permission-denied" });
    });

    it("returns entries for an owner and audits its own oversight read", async () => {
        const spine = loadSpine(false);
        mockGetUser.mockResolvedValue({ customClaims: { role: "owner" } });
        mockLogQueryGet.mockResolvedValue({
            docs: [{ data: () => ({ auditId: "a1" }) }, { data: () => ({ auditId: "a2" }) }],
            size: 2,
        });
        const callable = spine.getSensitiveAccessLog as unknown as Callable;

        const result = (await callable.run({
            auth: { uid: "owner-1" },
            data: { limit: 50 },
        })) as Record<string, unknown>;

        expect((result.entries as unknown[]).length).toBe(2);
        expect(result.count).toBe(2);
        // The oversight read is itself recorded in the audit log.
        expect(mockLogSet).toHaveBeenCalledTimes(1);
    });
});
