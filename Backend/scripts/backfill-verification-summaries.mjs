#!/usr/bin/env node
/*
 * Backfills users/{uid}.publicVerificationSummary and
 * organizations/{orgId}/publicVerificationSummary/main from server-owned
 * verification records.
 *
 * Dry-run by default. Add --write to mutate Firestore.
 *
 * Required auth:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 * or any firebase-admin supported application default credentials.
 */

import admin from "firebase-admin";

const args = new Set(process.argv.slice(2));
const write = args.has("--write");
const limitArg = process.argv.find((arg) => arg.startsWith("--limit="));
const limit = limitArg ? Number(limitArg.split("=")[1]) : 500;

if (!admin.apps.length) {
    admin.initializeApp();
}

const db = admin.firestore();

function arraysEqual(a, b) {
    return JSON.stringify(a || []) === JSON.stringify(b || []);
}

function summaryChanged(current = {}, next = {}) {
    return current.emailVerified !== next.emailVerified ||
        current.phoneVerified !== next.phoneVerified ||
        current.identityVerified !== next.identityVerified ||
        current.creatorVerified !== next.creatorVerified ||
        current.safetyStanding !== next.safetyStanding ||
        !arraysEqual(current.visibleBadges, next.visibleBadges);
}

async function userSummary(uid, userData) {
    const privateSnap = await db.collection("users").doc(uid)
        .collection("privateVerification")
        .doc("main")
        .get();
    const creatorSnap = await db.collection("users").doc(uid)
        .collection("verificationRequests")
        .where("type", "==", "creator")
        .where("status", "==", "approved")
        .limit(1)
        .get();

    const privateData = privateSnap.exists ? privateSnap.data() : {};
    const emailVerified = userData.publicVerificationSummary?.emailVerified === true ||
        userData.emailVerified === true;
    const phoneVerified = userData.phoneVerified === true ||
        userData.publicVerificationSummary?.phoneVerified === true;
    const identityVerified = privateData?.identityVerified === true ||
        privateData?.reviewStatus === "approved";
    const creatorVerified = !creatorSnap.empty;
    const safetyStanding = typeof userData.safetyStanding === "string"
        ? userData.safetyStanding
        : "active";

    const visibleBadges = [];
    if (identityVerified) visibleBadges.push("identity_verified");
    if (creatorVerified) visibleBadges.push("creator_verified");
    if (emailVerified) visibleBadges.push("email_verified");
    if (phoneVerified) visibleBadges.push("phone_verified");

    return {
        emailVerified,
        phoneVerified,
        identityVerified,
        creatorVerified,
        safetyStanding,
        visibleBadges,
    };
}

async function backfillUsers() {
    let changed = 0;
    let scanned = 0;
    const snap = await db.collection("users").limit(limit).get();

    for (const doc of snap.docs) {
        scanned += 1;
        const data = doc.data();
        const next = await userSummary(doc.id, data);
        const current = data.publicVerificationSummary || {};

        if (!summaryChanged(current, next)) continue;
        changed += 1;

        console.log(`${write ? "UPDATE" : "DRY-RUN"} user ${doc.id}`, next);
        if (write) {
            await doc.ref.set({
                publicVerificationSummary: {
                    ...next,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                },
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        }
    }

    return { scanned, changed };
}

async function organizationSummary(orgId) {
    const privateSnap = await db.collection("organizations").doc(orgId)
        .collection("privateVerification")
        .doc("main")
        .get();
    const privateData = privateSnap.exists ? privateSnap.data() : {};
    const organizationVerified =
        privateData?.organizationVerified === true ||
        privateData?.manualReviewStatus === "approved";

    const visibleBadges = organizationVerified ? ["organization_verified"] : [];
    return {
        organizationVerified,
        verifiedName: privateData?.verifiedName || null,
        verifiedDomain: privateData?.verifiedDomain || null,
        visibleBadges,
    };
}

async function backfillOrganizations() {
    let changed = 0;
    let scanned = 0;
    const snap = await db.collection("organizations").limit(limit).get();

    for (const doc of snap.docs) {
        scanned += 1;
        const next = await organizationSummary(doc.id);
        const currentSnap = await doc.ref.collection("publicVerificationSummary").doc("main").get();
        const current = currentSnap.exists ? currentSnap.data() : {};

        if (!summaryChanged(current, next) &&
            current.verifiedName === next.verifiedName &&
            current.verifiedDomain === next.verifiedDomain) {
            continue;
        }

        changed += 1;
        console.log(`${write ? "UPDATE" : "DRY-RUN"} organization ${doc.id}`, next);
        if (write) {
            await doc.ref.collection("publicVerificationSummary").doc("main").set({
                ...next,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        }
    }

    return { scanned, changed };
}

async function main() {
    console.log(`Verification summary backfill starting (${write ? "WRITE" : "DRY-RUN"}, limit=${limit})`);
    const users = await backfillUsers();
    const organizations = await backfillOrganizations();
    console.log("Backfill complete", { users, organizations, write });
    if (!write) {
        console.log("No writes were made. Re-run with --write after reviewing dry-run output.");
    }
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
