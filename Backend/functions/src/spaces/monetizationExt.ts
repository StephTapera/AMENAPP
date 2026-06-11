// spaces/monetizationExt.ts
//
// Extended monetization callables for AMEN Spaces.
//
// Callables:
//   createStripeConnectLink   — creates a Stripe Connect onboarding link for space hosts
//   createGiftMembership      — purchases a gift membership for another user
//   redeemScholarshipCode     — redeems a scholarship access code
//   submitScholarshipRequest  — requests scholarship access from space host
//   getCreatorEarningsSummary — fetches earnings summary for the space creator
//   updateRevenueSplits       — updates collaborator revenue split configuration
//   generateEarningsReport    — generates a CSV earnings report

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import Stripe from "stripe";

// ── Stripe client (lazy singleton) ───────────────────────────────────────────

function getStripe(): InstanceType<typeof Stripe> {
    const key = process.env.STRIPE_SECRET_KEY;
    if (!key) throw new HttpsError("internal", "Stripe is not configured.");
    return new Stripe(key, { apiVersion: "2026-05-27.dahlia" });
}

// ── Interfaces ────────────────────────────────────────────────────────────────

interface CreateStripeConnectLinkInput {
    entityName: string;
    entityEmail: string;
    hostType: string;
}

interface CreateGiftMembershipInput {
    spaceId: string;
    tierId: string;
    recipientIdentifier: string;
    durationMonths: number;
    message?: string;
}

interface RedeemScholarshipCodeInput {
    spaceId: string;
    code: string;
}

interface SubmitScholarshipRequestInput {
    spaceId: string;
}

interface GetCreatorEarningsSummaryInput {
    spaceId: string;
}

interface RevenueSplit {
    userId: string;
    percentage: number;
    label?: string;
}

interface UpdateRevenueSplitsInput {
    spaceId: string;
    splits: RevenueSplit[];
}

interface GenerateEarningsReportInput {
    spaceId: string;
    startDate?: string;
    endDate?: string;
}

interface EarningsSummary {
    totalRevenue: number;
    membershipRevenue: number;
    eventRevenue: number;
    giftMembershipRevenue: number;
    scholarshipDiscounts: number;
    netRevenue: number;
    pendingPayout: number;
    currency: string;
    periodStart: string | null;
    periodEnd: string | null;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function validateEmail(email: string): boolean {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function validateSpaceId(spaceId: unknown): string {
    if (typeof spaceId !== "string" || !spaceId.trim()) {
        throw new HttpsError("invalid-argument", "spaceId is required.");
    }
    return spaceId.trim();
}

// ── createStripeConnectLink ───────────────────────────────────────────────────

export const createStripeConnectLink = onCall(
    { region: "us-central1" },
    async (request): Promise<{ url: string }> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const data = (request.data ?? {}) as Partial<CreateStripeConnectLinkInput>;

        const entityName = data.entityName?.trim() ?? "";
        const entityEmail = data.entityEmail?.trim() ?? "";

        if (!entityName) {
            throw new HttpsError("invalid-argument", "entityName is required.");
        }
        if (!entityEmail || !validateEmail(entityEmail)) {
            throw new HttpsError("invalid-argument", "A valid entityEmail is required.");
        }

        const stripe = getStripe();
        const db = getFirestore();
        const hostRef = db.doc(`users/${uid}/stripeConnect/account`);
        const hostSnap = await hostRef.get();

        let stripeAccountId: string;

        if (hostSnap.exists && hostSnap.data()?.stripeAccountId) {
            stripeAccountId = hostSnap.data()!.stripeAccountId as string;
        } else {
            // Create a new Express account
            const account = await stripe.accounts.create({
                type: "express",
                email: entityEmail,
                business_profile: { name: entityName },
                capabilities: {
                    card_payments: { requested: true },
                    transfers: { requested: true },
                },
                metadata: { uid, hostType: data.hostType ?? "" },
            });
            stripeAccountId = account.id;
            await hostRef.set({
                stripeAccountId,
                createdAt: Timestamp.now(),
                entityName,
                entityEmail,
                hostType: data.hostType ?? "",
            });
        }

        // Use the app's universal link as return/refresh URL
        const baseUrl = "https://amenapp.page.link/stripe-connect";
        const accountLink = await stripe.accountLinks.create({
            account: stripeAccountId,
            refresh_url: `${baseUrl}?status=refresh`,
            return_url: `${baseUrl}?status=return`,
            type: "account_onboarding",
        });

        return { url: accountLink.url };
    }
);

// ── createSpaceGiftMembership ─────────────────────────────────────────────────

export const createSpaceGiftMembership = onCall(
    { region: "us-central1" },
    async (request): Promise<{ giftId: string }> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const data = (request.data ?? {}) as Partial<CreateGiftMembershipInput>;
        const spaceId = validateSpaceId(data.spaceId);

        if (typeof data.tierId !== "string" || !data.tierId.trim()) {
            throw new HttpsError("invalid-argument", "tierId is required.");
        }
        if (
            typeof data.recipientIdentifier !== "string" ||
            !data.recipientIdentifier.trim()
        ) {
            throw new HttpsError("invalid-argument", "recipientIdentifier is required.");
        }
        if (
            typeof data.durationMonths !== "number" ||
            data.durationMonths < 1 ||
            data.durationMonths > 24
        ) {
            throw new HttpsError(
                "invalid-argument",
                "durationMonths must be between 1 and 24."
            );
        }

        const db = getFirestore();
        const giftRef = db.collection(`spaces/${spaceId}/giftMemberships`).doc();

        await giftRef.set({
            tierId: data.tierId.trim(),
            recipientIdentifier: data.recipientIdentifier.trim(),
            durationMonths: data.durationMonths,
            message: data.message?.trim() ?? null,
            purchasedBy: uid,
            purchasedAt: Timestamp.now(),
            status: "pending",
        });

        return { giftId: giftRef.id };
    }
);

// ── redeemScholarshipCode ─────────────────────────────────────────────────────

export const redeemScholarshipCode = onCall(
    { region: "us-central1" },
    async (
        request
    ): Promise<{ tier: Record<string, unknown>; expiresAt: string | null; grantedBy: string }> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const data = (request.data ?? {}) as Partial<RedeemScholarshipCodeInput>;
        const spaceId = validateSpaceId(data.spaceId);

        if (typeof data.code !== "string" || !data.code.trim()) {
            throw new HttpsError("invalid-argument", "code is required.");
        }

        const db = getFirestore();
        const codeRef = db.doc(`spaces/${spaceId}/scholarshipCodes/${data.code.trim()}`);
        const codeSnap = await codeRef.get();

        if (!codeSnap.exists) {
            throw new HttpsError("not-found", "Scholarship code is invalid.");
        }

        const codeData = codeSnap.data()!;

        if (codeData.usedAt !== null && codeData.usedAt !== undefined) {
            throw new HttpsError("already-exists", "This scholarship code has already been used.");
        }

        const expiresAt = codeData.expiresAt as Timestamp | null | undefined;
        if (expiresAt && expiresAt.toMillis() < Date.now()) {
            throw new HttpsError("failed-precondition", "This scholarship code has expired.");
        }

        const now = Timestamp.now();
        const batch = db.batch();

        // Mark code as used
        batch.update(codeRef, { usedAt: now, usedBy: uid });

        // Grant membership
        const memberRef = db.doc(`spaces/${spaceId}/members/${uid}`);
        batch.set(
            memberRef,
            {
                userId: uid,
                tierId: (codeData.tierId as string) ?? "scholarship",
                joinedAt: now,
                status: "active",
                scholarshipCodeId: codeSnap.id,
            },
            { merge: true }
        );

        await batch.commit();

        return {
            tier: (codeData.tier as Record<string, unknown>) ?? { id: codeData.tierId ?? "scholarship" },
            expiresAt: expiresAt ? expiresAt.toDate().toISOString() : null,
            grantedBy: (codeData.grantedBy as string) ?? "space_host",
        };
    }
);

// ── submitScholarshipRequest ──────────────────────────────────────────────────

export const submitScholarshipRequest = onCall(
    { region: "us-central1" },
    async (request): Promise<{ success: true }> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const data = (request.data ?? {}) as Partial<SubmitScholarshipRequestInput>;
        const spaceId = validateSpaceId(data.spaceId);

        const db = getFirestore();

        // Check for existing pending request to prevent duplicate submissions
        const existingSnap = await db
            .collection(`spaces/${spaceId}/scholarshipRequests`)
            .where("requestedBy", "==", uid)
            .where("status", "==", "pending")
            .limit(1)
            .get();

        if (!existingSnap.empty) {
            throw new HttpsError(
                "already-exists",
                "You already have a pending scholarship request for this space."
            );
        }

        await db.collection(`spaces/${spaceId}/scholarshipRequests`).add({
            requestedBy: uid,
            requestedAt: Timestamp.now(),
            status: "pending",
        });

        return { success: true };
    }
);

// ── getCreatorEarningsSummary ─────────────────────────────────────────────────

export const getCreatorEarningsSummary = onCall(
    { region: "us-central1" },
    async (request): Promise<EarningsSummary> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const data =
            (request.data ?? {}) as Partial<GetCreatorEarningsSummaryInput>;
        const spaceId = validateSpaceId(data.spaceId);

        const db = getFirestore();

        // Verify the caller is the space creator
        const spaceSnap = await db.doc(`spaces/${spaceId}`).get();
        if (!spaceSnap.exists) {
            throw new HttpsError("not-found", "Space not found.");
        }
        if ((spaceSnap.data()?.createdBy as string) !== uid) {
            throw new HttpsError(
                "permission-denied",
                "Only the space creator can view earnings."
            );
        }

        const summarySnap = await db.doc(`spaces/${spaceId}/earnings/summary`).get();

        if (!summarySnap.exists) {
            return {
                totalRevenue: 0,
                membershipRevenue: 0,
                eventRevenue: 0,
                giftMembershipRevenue: 0,
                scholarshipDiscounts: 0,
                netRevenue: 0,
                pendingPayout: 0,
                currency: "USD",
                periodStart: null,
                periodEnd: null,
            };
        }

        const d = summarySnap.data()!;
        const toDate = (ts: unknown): string | null =>
            ts instanceof Timestamp ? ts.toDate().toISOString() : null;

        return {
            totalRevenue: (d.totalRevenue as number) ?? 0,
            membershipRevenue: (d.membershipRevenue as number) ?? 0,
            eventRevenue: (d.eventRevenue as number) ?? 0,
            giftMembershipRevenue: (d.giftMembershipRevenue as number) ?? 0,
            scholarshipDiscounts: (d.scholarshipDiscounts as number) ?? 0,
            netRevenue: (d.netRevenue as number) ?? 0,
            pendingPayout: (d.pendingPayout as number) ?? 0,
            currency: (d.currency as string) ?? "USD",
            periodStart: toDate(d.periodStart),
            periodEnd: toDate(d.periodEnd),
        };
    }
);

// ── updateRevenueSplits ───────────────────────────────────────────────────────

export const updateRevenueSplits = onCall(
    { region: "us-central1" },
    async (request): Promise<{ success: true }> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const data = (request.data ?? {}) as Partial<UpdateRevenueSplitsInput>;
        const spaceId = validateSpaceId(data.spaceId);

        if (!Array.isArray(data.splits)) {
            throw new HttpsError("invalid-argument", "splits must be an array.");
        }

        // Validate individual split entries
        for (const split of data.splits) {
            if (typeof split.userId !== "string" || !split.userId.trim()) {
                throw new HttpsError("invalid-argument", "Each split must have a valid userId.");
            }
            if (
                typeof split.percentage !== "number" ||
                split.percentage < 0 ||
                split.percentage > 100
            ) {
                throw new HttpsError(
                    "invalid-argument",
                    "Each split percentage must be between 0 and 100."
                );
            }
        }

        const totalPercentage = data.splits.reduce(
            (sum, s) => sum + (s.percentage ?? 0),
            0
        );
        if (totalPercentage > 100) {
            throw new HttpsError(
                "invalid-argument",
                `Total split percentage (${totalPercentage}) cannot exceed 100.`
            );
        }

        const db = getFirestore();

        // Verify the caller is the space creator
        const spaceSnap = await db.doc(`spaces/${spaceId}`).get();
        if (!spaceSnap.exists) {
            throw new HttpsError("not-found", "Space not found.");
        }
        if ((spaceSnap.data()?.createdBy as string) !== uid) {
            throw new HttpsError("permission-denied", "Only the space creator can update revenue splits.");
        }

        await db.doc(`spaces/${spaceId}/revenueSplits`).set({
            splits: data.splits,
            updatedAt: Timestamp.now(),
            updatedBy: uid,
        });

        return { success: true };
    }
);

// ── generateEarningsReport ────────────────────────────────────────────────────

export const generateEarningsReport = onCall(
    { region: "us-central1" },
    async (request): Promise<{ csvData: string; filename: string }> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const data = (request.data ?? {}) as Partial<GenerateEarningsReportInput>;
        const spaceId = validateSpaceId(data.spaceId);

        const db = getFirestore();

        // Verify the caller is the space creator
        const spaceSnap = await db.doc(`spaces/${spaceId}`).get();
        if (!spaceSnap.exists) {
            throw new HttpsError("not-found", "Space not found.");
        }
        if ((spaceSnap.data()?.createdBy as string) !== uid) {
            throw new HttpsError("permission-denied", "Only the space creator can generate reports.");
        }

        // Read earnings line items
        let earningsQuery = db
            .collection(`spaces/${spaceId}/earnings/transactions/items`)
            .orderBy("createdAt", "desc")
            .limit(1000);

        if (data.startDate) {
            earningsQuery = earningsQuery.startAfter(new Date(data.startDate));
        }

        const earningsSnap = await earningsQuery.get();

        const csvHeader = "Date,Type,Amount,Currency,MemberId,Description\n";
        const csvRows = earningsSnap.docs
            .map((doc) => {
                const d = doc.data();
                const dateStr =
                    d.createdAt instanceof Timestamp
                        ? d.createdAt.toDate().toISOString().split("T")[0]
                        : "";
                const type = (d.type as string) ?? "";
                const amount = (d.amount as number) ?? 0;
                const currency = (d.currency as string) ?? "USD";
                const memberId = (d.memberId as string) ?? "";
                const description = ((d.description as string) ?? "").replace(/,/g, ";");
                return `${dateStr},${type},${amount.toFixed(2)},${currency},${memberId},${description}`;
            })
            .join("\n");

        const csvData = csvHeader + csvRows;
        const dateTag = new Date().toISOString().split("T")[0];
        const filename = `earnings_${spaceId}_${dateTag}.csv`;

        return { csvData, filename };
    }
);
