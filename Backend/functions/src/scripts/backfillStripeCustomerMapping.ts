/**
 * backfillStripeCustomerMapping.ts
 *
 * P1-1 backfill: writes stripeCustomers/{customerId} → { uid } mappings for
 * Stripe customers that existed BEFORE createCovenantCheckoutSession started
 * creating them. The covenant webhook now rejects any subscription event
 * whose customer has no mapping, so legacy paying users will be locked out
 * on their next subscription event until this script has been run.
 *
 * Usage:
 *   STRIPE_SECRET_KEY=sk_live_... \
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/admin-sa.json \
 *   FIREBASE_PROJECT_ID=amen-5e359 \
 *   node ./lib/scripts/backfillStripeCustomerMapping.js --dry-run
 *
 *   STRIPE_SECRET_KEY=sk_live_... \
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/admin-sa.json \
 *   FIREBASE_PROJECT_ID=amen-5e359 \
 *   node ./lib/scripts/backfillStripeCustomerMapping.js
 *
 * Required env:
 *   STRIPE_SECRET_KEY         — Stripe restricted key with customer.read
 *   GOOGLE_APPLICATION_CREDENTIALS — Firebase admin SA JSON path
 *   FIREBASE_PROJECT_ID       — Project id (also accepts GCLOUD_PROJECT)
 *
 * Flags:
 *   --dry-run    Do not write to Firestore; print what *would* happen.
 *   --limit=N    Optional hard cap on customers scanned (default: unlimited).
 *
 * Idempotency:
 *   - Existing mapping with matching uid: SKIP (idempotent re-run).
 *   - Existing mapping with conflicting uid: SKIP (never overwrite — flag for ops).
 *   - Customer without metadata.uid: SKIP (cannot verify identity).
 *   - Customer with metadata.uid but no Firebase user: still SKIP and log.
 *
 * Rollback: This script only writes new docs and only when the mapping is
 * absent — there is nothing to roll back. To remove a mapping written in
 * error, delete the doc by hand from Firestore admin console.
 *
 * THIS SCRIPT IS NOT A CALLABLE. It runs as a node CLI with admin
 * credentials. It must never be exposed via Cloud Functions.
 */

import * as admin from "firebase-admin";
import Stripe from "stripe";

export type BackfillAction =
    | "create"
    | "skip-existing-match"
    | "skip-existing-conflict"
    | "skip-no-uid";

export interface ExistingMapping {
    uid: string;
    provider?: string;
}

/**
 * Pure helper: decide what to do for a single Stripe customer given the
 * mapping doc (if any) currently in Firestore. Exported for unit testing.
 */
export function classifyCustomer(
    customer: { id: string; metadata?: Record<string, string> | null },
    existingMapping: ExistingMapping | null
): BackfillAction {
    const metadataUid = String(customer.metadata?.uid ?? "").trim();
    if (!metadataUid) {
        return "skip-no-uid";
    }
    if (existingMapping == null) {
        return "create";
    }
    if (existingMapping.uid === metadataUid) {
        return "skip-existing-match";
    }
    return "skip-existing-conflict";
}

export interface BackfillSummary {
    scanned: number;
    created: number;
    skippedExistingMatch: number;
    skippedExistingConflict: number;
    skippedNoUid: number;
    errors: number;
    dryRun: boolean;
}

export function emptySummary(dryRun: boolean): BackfillSummary {
    return {
        scanned: 0,
        created: 0,
        skippedExistingMatch: 0,
        skippedExistingConflict: 0,
        skippedNoUid: 0,
        errors: 0,
        dryRun,
    };
}

/**
 * Core backfill loop, isolated for unit testing. The caller provides a
 * customer iterator, a mapping reader, and a writer — none of which the
 * test needs to be a real Stripe or Firestore client.
 */
export async function runBackfill(args: {
    customers: AsyncIterable<{ id: string; metadata?: Record<string, string> | null }>;
    readMapping: (customerId: string) => Promise<ExistingMapping | null>;
    writeMapping: (customerId: string, uid: string) => Promise<void>;
    dryRun: boolean;
    log?: (message: string, extra?: Record<string, unknown>) => void;
    limit?: number;
}): Promise<BackfillSummary> {
    const summary = emptySummary(args.dryRun);
    const log = args.log ?? (() => undefined);

    for await (const customer of args.customers) {
        if (args.limit !== undefined && summary.scanned >= args.limit) break;
        summary.scanned += 1;

        let existing: ExistingMapping | null;
        try {
            existing = await args.readMapping(customer.id);
        } catch (err) {
            summary.errors += 1;
            log("readMapping_error", { customerId: customer.id, err: String(err) });
            continue;
        }

        const action = classifyCustomer(customer, existing);
        switch (action) {
            case "skip-no-uid":
                summary.skippedNoUid += 1;
                log("skip_no_uid", { customerId: customer.id });
                continue;
            case "skip-existing-match":
                summary.skippedExistingMatch += 1;
                continue;
            case "skip-existing-conflict":
                summary.skippedExistingConflict += 1;
                log("skip_conflict", {
                    customerId: customer.id,
                    existingUid: existing?.uid,
                    metadataUid: customer.metadata?.uid,
                });
                continue;
            case "create": {
                const uid = String(customer.metadata?.uid ?? "").trim();
                if (args.dryRun) {
                    summary.created += 1;
                    log("dry_run_create", { customerId: customer.id, uid });
                    continue;
                }
                try {
                    await args.writeMapping(customer.id, uid);
                    summary.created += 1;
                    log("created", { customerId: customer.id, uid });
                } catch (err) {
                    summary.errors += 1;
                    log("writeMapping_error", { customerId: customer.id, err: String(err) });
                }
                continue;
            }
        }
    }

    return summary;
}

// ── CLI runner ────────────────────────────────────────────────────────────────

function parseArgs(argv: string[]): { dryRun: boolean; limit?: number } {
    let dryRun = false;
    let limit: number | undefined;
    for (const arg of argv.slice(2)) {
        if (arg === "--dry-run") dryRun = true;
        else if (arg.startsWith("--limit=")) {
            const n = parseInt(arg.slice("--limit=".length), 10);
            if (!Number.isNaN(n) && n > 0) limit = n;
        }
    }
    return { dryRun, limit };
}

async function main(): Promise<void> {
    const stripeKey = process.env.STRIPE_SECRET_KEY;
    if (!stripeKey) {
        console.error("STRIPE_SECRET_KEY is required.");
        process.exit(2);
    }
    if (!process.env.GOOGLE_APPLICATION_CREDENTIALS && admin.apps.length === 0) {
        console.error("GOOGLE_APPLICATION_CREDENTIALS is required (or initialize admin manually).");
        process.exit(2);
    }
    const { dryRun, limit } = parseArgs(process.argv);

    if (admin.apps.length === 0) {
        admin.initializeApp({
            projectId: process.env.FIREBASE_PROJECT_ID ?? process.env.GCLOUD_PROJECT,
        });
    }
    const db = admin.firestore();
    const stripe = new Stripe(stripeKey, { apiVersion: "2024-06-20" });

    async function* customerIterator(): AsyncGenerator<Stripe.Customer> {
        for await (const customer of stripe.customers.list({ limit: 100 })) {
            yield customer;
        }
    }

    async function readMapping(customerId: string): Promise<ExistingMapping | null> {
        const snap = await db.collection("stripeCustomers").doc(customerId).get();
        if (!snap.exists) return null;
        const data = snap.data() ?? {};
        return { uid: String(data.uid ?? ""), provider: data.provider as string | undefined };
    }

    async function writeMapping(customerId: string, uid: string): Promise<void> {
        await db.collection("stripeCustomers").doc(customerId).set({
            uid,
            provider: "stripe",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            backfilledAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    }

    function log(message: string, extra?: Record<string, unknown>): void {
        console.log(JSON.stringify({ event: message, ...extra }));
    }

    const summary = await runBackfill({
        customers: customerIterator(),
        readMapping,
        writeMapping,
        dryRun,
        log,
        limit,
    });

    console.log("BACKFILL_SUMMARY=" + JSON.stringify(summary));
}

// Only run if invoked as a script.
if (require.main === module) {
    main().catch((err) => {
        console.error(err);
        process.exit(1);
    });
}
