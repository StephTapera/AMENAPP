import * as admin from "firebase-admin";
import AdmZip from "adm-zip";
import * as zlib from "zlib";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

const db = admin.firestore();
const now = () => admin.firestore.FieldValue.serverTimestamp();

const allowedKinds = new Set([
    "publicK12School",
    "privateK12School",
    "higherEducation",
    "church",
    "nonprofit",
    "ministry",
    "business",
    "campusGroup",
    "bibleStudy",
    "creatorCommunity",
    "communityGroup",
]);

const allowedSources = new Set([
    "ncesCCD",
    "ncesPSS",
    "ncesIPEDS",
    "irsEOBMF",
    "censusGeocoder",
    "osmStaticExtract",
    "googlePlaces",
    "claimedAmenProfile",
    "partnerImport",
]);
const sourceAllowedKinds: Record<string, Set<string>> = {
    ncesCCD: new Set(["publicK12School"]),
    ncesPSS: new Set(["privateK12School"]),
    ncesIPEDS: new Set(["higherEducation"]),
    irsEOBMF: new Set(["church", "nonprofit", "ministry"]),
    censusGeocoder: allowedKinds,
    osmStaticExtract: new Set(["church", "publicK12School", "privateK12School", "higherEducation", "nonprofit", "ministry", "business", "bibleStudy", "creatorCommunity", "communityGroup"]),
    googlePlaces: allowedKinds,
    claimedAmenProfile: allowedKinds,
    partnerImport: allowedKinds,
};

const billingPlans = new Set(["free", "plus", "pro"]);
const paidBillingPlans = new Set(["plus", "pro"]);
const DEFAULT_IMPORT_BATCH_SIZE = 500;
const DEFAULT_DAILY_IMPORT_LIMIT = 2000;

export interface AmenNationalDirectoryRecord {
    id: string;
    source: string;
    sourceRecordId: string;
    sourceIds?: string[];
    kind: string;
    displayName: string;
    normalizedName: string;
    description?: string;
    city?: string;
    state?: string;
    postalCode?: string;
    websiteURL?: string;
    phone?: string;
    latitude?: number;
    longitude?: number;
    verificationStatus: "sourceImported" | "claimed" | "verified" | "rejected";
    claimStatus: "unclaimed" | "pending" | "claimed" | "verified" | "rejected";
    claimedBy?: string | null;
    amenProfileId?: string;
    amenSpaceId?: string;
    subscriptionEligible: boolean;
    billingPlan?: "free" | "plus" | "pro";
    billingStatus?: string;
    safetyStatus?: string;
    visibility?: string;
    moderationStatus?: string;
    lastSourceRefreshAt?: admin.firestore.Timestamp;
}

export interface DirectoryImportManifestItem {
    source: string;
    kind: string;
    label: string;
    storagePath?: string;
    url?: string;
    cadence: string;
}

export const nationalDirectorySources = [
    {
        id: "ncesCCD",
        name: "NCES Common Core of Data",
        datasetPurpose: "Public elementary and secondary schools and districts.",
        allowedKinds: ["publicK12School"],
        refreshCadence: "Annual public release",
    },
    {
        id: "ncesPSS",
        name: "NCES Private School Universe Survey",
        datasetPurpose: "Private elementary and secondary schools.",
        allowedKinds: ["privateK12School"],
        refreshCadence: "Periodic public release",
    },
    {
        id: "ncesIPEDS",
        name: "NCES IPEDS",
        datasetPurpose: "Postsecondary institutions and campuses.",
        allowedKinds: ["higherEducation"],
        refreshCadence: "Annual public release",
    },
    {
        id: "irsEOBMF",
        name: "IRS Exempt Organizations Business Master File",
        datasetPurpose: "Tax-exempt churches, ministries, nonprofits, schools, and organizations.",
        allowedKinds: ["church", "nonprofit", "ministry"],
        refreshCadence: "IRS public extract update",
    },
    {
        id: "censusGeocoder",
        name: "U.S. Census Geocoder",
        datasetPurpose: "U.S. address geocoding and enrichment.",
        allowedKinds: Array.from(allowedKinds),
        refreshCadence: "On import or correction review",
    },
    {
        id: "osmStaticExtract",
        name: "OpenStreetMap Static Extract",
        datasetPurpose: "License-compliant public POI enrichment with attribution.",
        allowedKinds: Array.from(sourceAllowedKinds.osmStaticExtract),
        refreshCadence: "Controlled static extract refresh",
    },
];

export function normalizeDirectoryName(value: string): string {
    return value.trim().toLowerCase().replace(/[^a-z0-9]+/g, " ").trim().replace(/\s+/g, " ");
}

export function isSourceKindAllowed(source: string, kind: string): boolean {
    return Boolean(sourceAllowedKinds[source]?.has(kind));
}

export function isGooglePlacesStoredSafely(input: Partial<AmenNationalDirectoryRecord>): boolean {
    if (input.source !== "googlePlaces") return true;
    return !input.displayName && !input.city && !input.state && !input.postalCode && !input.websiteURL && !input.phone && input.latitude === undefined && input.longitude === undefined;
}

export function classifyOrganizationKind(input: { source?: string; nteeCode?: string; activityCode?: string; level?: string; name?: string }): string {
    if (input.source === "ncesCCD") return "publicK12School";
    if (input.source === "ncesPSS") return "privateK12School";
    if (input.source === "ncesIPEDS") return "higherEducation";
    const ntee = (input.nteeCode || "").toUpperCase();
    const activity = input.activityCode || "";
    const name = (input.name || "").toLowerCase();
    if (ntee.startsWith("X") || /^(00[1-9]|0[1-2][0-9])$/.test(activity) || name.includes("church")) return "church";
    if (name.includes("ministry") || name.includes("mission")) return "ministry";
    if (name.includes("bible study")) return "bibleStudy";
    return "nonprofit";
}

export function canCreatePaidCheckout(record: AmenNationalDirectoryRecord): boolean {
    return ["claimed", "verified"].includes(record.claimStatus) && record.subscriptionEligible === true;
}

export function domainFromEmail(email?: string): string | undefined {
    const domain = email?.split("@")[1]?.trim().toLowerCase();
    return domain && domain.includes(".") ? domain : undefined;
}

export function domainFromWebsite(url?: string): string | undefined {
    if (!url) return undefined;
    try {
        const parsed = new URL(url.startsWith("http") ? url : `https://${url}`);
        return parsed.hostname.replace(/^www\./, "").toLowerCase();
    } catch {
        return undefined;
    }
}

export function isDomainVerifiedClaim(email?: string, websiteURL?: string): boolean {
    const emailDomain = domainFromEmail(email);
    const websiteDomain = domainFromWebsite(websiteURL);
    return Boolean(emailDomain && websiteDomain && (emailDomain === websiteDomain || emailDomain.endsWith(`.${websiteDomain}`)));
}

export function stripePriceIdForPlan(plan: string, env: NodeJS.ProcessEnv = process.env): string | undefined {
    if (plan === "plus") return env.ORGANIZATION_PLUS_PRICE_ID;
    if (plan === "pro") return env.ORGANIZATION_PRO_PRICE_ID;
    return undefined;
}

export function shouldIndexDirectoryRecord(record: AmenNationalDirectoryRecord): boolean {
    if (record.visibility !== "public") return false;
    if (!["approved", "sourceImported"].includes(record.moderationStatus || "")) return false;
    if (["claimed", "verified"].includes(record.claimStatus)) return true;
    return record.source !== "irsEOBMF" && Boolean(record.latitude && record.longitude);
}

export function buildAlgoliaDirectoryRecord(record: AmenNationalDirectoryRecord): Record<string, unknown> {
    return {
        objectID: record.id,
        displayName: record.displayName,
        normalizedName: record.normalizedName,
        kind: record.kind,
        source: record.source,
        city: record.city,
        state: record.state,
        claimStatus: record.claimStatus,
        verificationStatus: record.verificationStatus,
        _geoloc: record.latitude && record.longitude ? { lat: record.latitude, lng: record.longitude } : undefined,
    };
}

export function buildDirectoryImportManifest(env: NodeJS.ProcessEnv = process.env): DirectoryImportManifestItem[] {
    const configured = env.AMEN_DIRECTORY_IMPORT_MANIFEST_JSON;
    if (configured) {
        const parsed = JSON.parse(configured);
        if (!Array.isArray(parsed)) throw new HttpsError("invalid-argument", "Directory import manifest must be an array.");
        return parsed.map(validateImportManifestItem);
    }
    return [
        { source: "ncesCCD", kind: "publicK12School", label: "NCES CCD public K-12 schools", cadence: "annual", storagePath: env.NCES_CCD_STORAGE_PATH },
        { source: "ncesPSS", kind: "privateK12School", label: "NCES PSS private K-12 schools", cadence: "periodic", storagePath: env.NCES_PSS_STORAGE_PATH },
        { source: "ncesIPEDS", kind: "higherEducation", label: "NCES IPEDS postsecondary institutions", cadence: "annual", storagePath: env.NCES_IPEDS_STORAGE_PATH },
        { source: "irsEOBMF", kind: "church", label: "IRS EO BMF religion/ministry candidates", cadence: "monthly", storagePath: env.IRS_EO_BMF_STORAGE_PATH },
    ].map(validateImportManifestItem);
}

export function extractTextFilesFromDirectoryImportBuffer(buffer: Buffer, sourcePath: string): string[] {
    const lower = sourcePath.toLowerCase();
    if (lower.endsWith(".zip")) {
        const zip = new AdmZip(buffer);
        return zip.getEntries()
            .filter((entry) => !entry.isDirectory && /\.(csv|txt)$/i.test(entry.entryName))
            .map((entry) => entry.getData().toString("utf8"));
    }
    if (lower.endsWith(".gz")) {
        return [zlib.gunzipSync(buffer).toString("utf8")];
    }
    if (/\.(csv|txt)$/i.test(lower)) {
        return [buffer.toString("utf8")];
    }
    throw new HttpsError("invalid-argument", "Directory import files must be CSV, TXT, GZIP, or ZIP containing CSV/TXT.");
}

export function parseCsvRows(csv: string): Record<string, string>[] {
    const rows: string[][] = [];
    let current = "";
    let row: string[] = [];
    let inQuotes = false;
    for (let i = 0; i < csv.length; i += 1) {
        const char = csv[i];
        const next = csv[i + 1];
        if (char === "\"" && inQuotes && next === "\"") {
            current += "\"";
            i += 1;
        } else if (char === "\"") {
            inQuotes = !inQuotes;
        } else if (char === "," && !inQuotes) {
            row.push(current);
            current = "";
        } else if ((char === "\n" || char === "\r") && !inQuotes) {
            if (char === "\r" && next === "\n") i += 1;
            row.push(current);
            if (row.some((value) => value.trim().length > 0)) rows.push(row);
            row = [];
            current = "";
        } else {
            current += char;
        }
    }
    row.push(current);
    if (row.some((value) => value.trim().length > 0)) rows.push(row);
    if (rows.length < 2) return [];
    const headers = rows[0].map((value) => value.trim());
    return rows.slice(1).map((values) => {
        const out: Record<string, string> = {};
        headers.forEach((header, index) => {
            out[header] = (values[index] || "").trim();
        });
        return out;
    });
}

export function mapSourceRowToDirectoryRecord(source: string, row: Record<string, string>): Partial<AmenNationalDirectoryRecord> {
    const pick = (...keys: string[]) => keys.map((key) => row[key]).find((value) => value && value.trim().length > 0);
    const sourceRecordId = pick("NCESSCH", "SCHID", "UNITID", "EIN", "sourceRecordId", "id") || "";
    const displayName = pick("SCH_NAME", "INSTNM", "NAME", "NAME1", "displayName", "name") || "";
    const state = pick("LSTATE", "STABBR", "STATE", "state");
    const kind = source === "ncesCCD"
        ? "publicK12School"
        : source === "ncesPSS"
            ? "privateK12School"
            : source === "ncesIPEDS"
                ? "higherEducation"
                : classifyOrganizationKind({ source, nteeCode: pick("NTEE_CD", "NTEE"), activityCode: pick("ACTIVITY", "ACTIVITY_CODE"), name: displayName });
    return {
        source,
        sourceRecordId,
        kind,
        displayName,
        city: pick("LCITY", "CITY", "city"),
        state,
        postalCode: pick("LZIP", "ZIP", "ZIP5", "postalCode"),
        websiteURL: pick("WEBADDR", "URL", "websiteURL"),
        phone: pick("PHONE", "phone"),
        latitude: numericValue(pick("LAT", "LATITUDE", "latitude")),
        longitude: numericValue(pick("LON", "LONGITUD", "LONGITUDE", "longitude")),
    };
}

export function buildCensusGeocoderUrl(record: Pick<AmenNationalDirectoryRecord, "city" | "state" | "postalCode"> & { address?: string }): string {
    const params = new URLSearchParams({
        benchmark: "Public_AR_Current",
        format: "json",
    });
    const address = record.address || [record.city, record.state, record.postalCode].filter(Boolean).join(" ");
    params.set("address", address);
    return `https://geocoding.geo.census.gov/geocoder/locations/onelineaddress?${params.toString()}`;
}

export function parseCensusGeocoderResponse(profileId: string, json: any): { profileId: string; latitude: number; longitude: number } | undefined {
    const match = json?.result?.addressMatches?.[0];
    const x = Number(match?.coordinates?.x);
    const y = Number(match?.coordinates?.y);
    if (!Number.isFinite(x) || !Number.isFinite(y)) return undefined;
    return { profileId, latitude: y, longitude: x };
}

export function buildDirectoryRecord(input: Partial<AmenNationalDirectoryRecord>): AmenNationalDirectoryRecord {
    const source = stringValue(input.source, "source");
    const kind = stringValue(input.kind, "kind");
    if (!allowedSources.has(source)) throw new HttpsError("invalid-argument", "Unsupported directory source.");
    if (!allowedKinds.has(kind)) throw new HttpsError("invalid-argument", "Unsupported directory kind.");
    if (!isSourceKindAllowed(source, kind)) throw new HttpsError("failed-precondition", "Directory source cannot publish this kind.");
    if (!isGooglePlacesStoredSafely(input)) throw new HttpsError("failed-precondition", "Google Places entries may persist place_id only.");

    const sourceRecordId = stringValue(input.sourceRecordId, "sourceRecordId");
    const displayName = stringValue(input.displayName, "displayName");
    const id = input.id || `${source}_${sourceRecordId}`.replace(/[^A-Za-z0-9_-]/g, "_");

    return {
        id,
        source,
        sourceRecordId,
        sourceIds: input.sourceIds || [`${source}:${sourceRecordId}`],
        kind,
        displayName,
        normalizedName: input.normalizedName || normalizeDirectoryName(displayName),
        description: input.description,
        city: input.city,
        state: input.state,
        postalCode: input.postalCode,
        websiteURL: input.websiteURL,
        phone: input.phone,
        latitude: input.latitude,
        longitude: input.longitude,
        verificationStatus: input.verificationStatus || "sourceImported",
        claimStatus: input.claimStatus || "unclaimed",
        claimedBy: input.claimedBy || null,
        amenProfileId: input.amenProfileId,
        amenSpaceId: input.amenSpaceId,
        subscriptionEligible: input.subscriptionEligible ?? false,
        billingPlan: input.billingPlan || "free",
        billingStatus: input.billingStatus || "none",
        safetyStatus: input.safetyStatus || "allowed",
        visibility: input.visibility || "public",
        moderationStatus: input.moderationStatus || "sourceImported",
        lastSourceRefreshAt: input.lastSourceRefreshAt,
    };
}

export const getAmenNationalDirectorySources = onCall({ enforceAppCheck: true }, async (request) => {
    requireAuth(request.auth?.uid);
    return nationalDirectorySources;
});

export const searchAmenNationalDirectory = onCall({ enforceAppCheck: true }, async (request) => {
    requireAuth(request.auth?.uid);
    const data = request.data || {};
    const query = normalizeDirectoryName(String(data.query || "")).slice(0, 80);
    const kind = typeof data.kind === "string" && allowedKinds.has(data.kind) ? data.kind : undefined;
    const state = typeof data.state === "string" ? data.state.toUpperCase().slice(0, 2) : undefined;

    let ref: FirebaseFirestore.Query = db.collection("amenNationalDirectory")
        .where("visibility", "==", "public")
        .where("moderationStatus", "in", ["approved", "sourceImported"])
        .limit(40);

    if (kind) ref = ref.where("kind", "==", kind);
    if (state) ref = ref.where("state", "==", state);
    if (query) {
        ref = ref.orderBy("normalizedName").startAt(query).endAt(`${query}\uf8ff`);
    }

    const snapshot = await ref.get();
    return snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
});

export const searchOrganizations = searchAmenNationalDirectory;

export const claimAmenNationalDirectoryProfile = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request.auth?.uid);
    const profileId = stringValue(request.data?.profileId, "profileId");
    const role = stringValue(request.data?.role, "role").slice(0, 60);
    const email = typeof request.auth?.token?.email === "string" ? request.auth.token.email : undefined;

    const profileRef = db.collection("amenNationalDirectory").doc(profileId);
    const claimRef = profileRef.collection("claims").doc(uid);
    await assertClaimRateLimit(uid);
    await db.runTransaction(async (tx) => {
        const profile = await tx.get(profileRef);
        if (!profile.exists) throw new HttpsError("not-found", "Directory profile not found.");
        const profileData = profile.data() as AmenNationalDirectoryRecord;
        const autoVerified = isDomainVerifiedClaim(email, profileData.websiteURL);
        const status = autoVerified ? "approved" : "pending";
        tx.set(claimRef, {
            uid,
            role,
            status,
            verificationMethod: autoVerified ? "email_domain" : "manual_review",
            createdAt: now(),
            updatedAt: now(),
        }, { merge: true });
        tx.set(profileRef, {
            claimStatus: autoVerified ? "verified" : "pending",
            verificationStatus: autoVerified ? "verified" : profileData.verificationStatus,
            claimedBy: autoVerified ? uid : profileData.claimedBy || null,
            subscriptionEligible: autoVerified ? true : profileData.subscriptionEligible,
            updatedAt: now(),
        }, { merge: true });
    });

    return { status: isDomainVerifiedClaim(email, (await profileRef.get()).data()?.websiteURL) ? "verified" : "pending" };
});

export const createOrganizationClaim = claimAmenNationalDirectoryProfile;

export const approveOrganizationClaim = onCall({ enforceAppCheck: true }, async (request) => {
    requireAdmin(request.auth?.token);
    const profileId = stringValue(request.data?.profileId, "profileId");
    const uid = stringValue(request.data?.uid, "uid");
    const profileRef = db.collection("amenNationalDirectory").doc(profileId);
    await db.runTransaction(async (tx) => {
        const profile = await tx.get(profileRef);
        if (!profile.exists) throw new HttpsError("not-found", "Directory profile not found.");
        tx.set(profileRef, {
            claimStatus: "verified",
            verificationStatus: "verified",
            claimedBy: uid,
            subscriptionEligible: true,
            updatedAt: now(),
        }, { merge: true });
        tx.set(profileRef.collection("claims").doc(uid), { status: "approved", reviewedAt: now(), updatedAt: now() }, { merge: true });
    });
    return { status: "verified" };
});

export const rejectOrganizationClaim = onCall({ enforceAppCheck: true }, async (request) => {
    requireAdmin(request.auth?.token);
    const profileId = stringValue(request.data?.profileId, "profileId");
    const uid = stringValue(request.data?.uid, "uid");
    const reason = typeof request.data?.reason === "string" ? request.data.reason.slice(0, 500) : "";
    const profileRef = db.collection("amenNationalDirectory").doc(profileId);
    await db.runTransaction(async (tx) => {
        tx.set(profileRef, { claimStatus: "unclaimed", verificationStatus: "sourceImported", claimedBy: null, updatedAt: now() }, { merge: true });
        tx.set(profileRef.collection("claims").doc(uid), { status: "rejected", reason, reviewedAt: now(), updatedAt: now() }, { merge: true });
    });
    return { status: "rejected" };
});

export const listOrganizationReviewQueue = onCall({ enforceAppCheck: true }, async (request) => {
    requireAdmin(request.auth?.token);
    const queue = typeof request.data?.queue === "string" ? request.data.queue : "all";
    const limit = Math.min(Number(request.data?.limit) || 50, 100);
    const result: Record<string, unknown[]> = {};

    if (queue === "all" || queue === "claims") {
        const claims = await db.collectionGroup("claims").where("status", "==", "pending").limit(limit).get();
        result.claims = claims.docs.map((doc) => ({ id: doc.id, path: doc.ref.path, ...doc.data() }));
    }
    if (queue === "all" || queue === "suggestedEdits") {
        const edits = await db.collectionGroup("suggestedEdits").where("status", "==", "pending").limit(limit).get();
        result.suggestedEdits = edits.docs.map((doc) => ({ id: doc.id, path: doc.ref.path, ...doc.data() }));
    }
    if (queue === "all" || queue === "banners") {
        const banners = await db.collection("amenNationalDirectory").where("bannerModerationStatus", "==", "pending").limit(limit).get();
        result.banners = banners.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    }

    return result;
});

export const suggestOrganizationEdit = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request.auth?.uid);
    const profileId = stringValue(request.data?.profileId, "profileId");
    const fields = request.data?.fields;
    if (!fields || typeof fields !== "object" || Array.isArray(fields)) throw new HttpsError("invalid-argument", "fields map is required.");
    const editRef = db.collection("amenNationalDirectory").doc(profileId).collection("suggestedEdits").doc();
    await editRef.set({
        uid,
        fields,
        status: "pending",
        createdAt: now(),
        updatedAt: now(),
    });
    return { editId: editRef.id };
});

export const approveOrganizationEdit = onCall({ enforceAppCheck: true }, async (request) => {
    requireAdmin(request.auth?.token);
    const profileId = stringValue(request.data?.profileId, "profileId");
    const editId = stringValue(request.data?.editId, "editId");
    const profileRef = db.collection("amenNationalDirectory").doc(profileId);
    const editRef = profileRef.collection("suggestedEdits").doc(editId);
    await db.runTransaction(async (tx) => {
        const edit = await tx.get(editRef);
        if (!edit.exists) throw new HttpsError("not-found", "Suggested edit not found.");
        const fields = edit.data()?.fields || {};
        tx.set(profileRef, { ...fields, updatedAt: now() }, { merge: true });
        tx.set(editRef, { status: "approved", reviewedAt: now(), updatedAt: now() }, { merge: true });
    });
    return { status: "approved" };
});

export const rejectOrganizationEdit = onCall({ enforceAppCheck: true }, async (request) => {
    requireAdmin(request.auth?.token);
    const profileId = stringValue(request.data?.profileId, "profileId");
    const editId = stringValue(request.data?.editId, "editId");
    const reason = typeof request.data?.reason === "string" ? request.data.reason.slice(0, 500) : "";
    await db.collection("amenNationalDirectory").doc(profileId).collection("suggestedEdits").doc(editId).set({
        status: "rejected",
        reason,
        reviewedAt: now(),
        updatedAt: now(),
    }, { merge: true });
    return { status: "rejected" };
});

export const createAmenSpaceFromDirectoryProfile = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request.auth?.uid);
    const profileId = stringValue(request.data?.profileId, "profileId");
    const groupName = stringValue(request.data?.groupName, "groupName").slice(0, 90);

    const profileRef = db.collection("amenNationalDirectory").doc(profileId);
    const profile = await profileRef.get();
    if (!profile.exists) throw new HttpsError("not-found", "Directory profile not found.");
    const data = profile.data() as AmenNationalDirectoryRecord;
    if (!["claimed", "verified"].includes(data.claimStatus) || data.claimedBy !== uid) {
        throw new HttpsError("permission-denied", "Claim approval is required before creating official spaces.");
    }

    const spaceRef = db.collection("amenSpaces").doc();
    await spaceRef.set({
        name: groupName,
        sourceDirectoryProfileId: profileId,
        organizationType: data.kind,
        ownerUserId: uid,
        visibility: "public",
        monetizationEligible: data.subscriptionEligible,
        createdAt: now(),
        updatedAt: now(),
    });
    await profileRef.set({ amenSpaceId: spaceRef.id, updatedAt: now() }, { merge: true });

    return { spaceId: spaceRef.id };
});

export const createSpaceForOrganization = createAmenSpaceFromDirectoryProfile;

export const updateOrganizationBanner = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request.auth?.uid);
    const profileId = stringValue(request.data?.profileId, "profileId");
    const bannerConfig = request.data?.bannerConfig;
    if (!bannerConfig || typeof bannerConfig !== "object" || Array.isArray(bannerConfig)) throw new HttpsError("invalid-argument", "bannerConfig map is required.");
    const profileRef = db.collection("amenNationalDirectory").doc(profileId);
    const profile = await profileRef.get();
    const data = profile.data() as AmenNationalDirectoryRecord | undefined;
    if (!data || data.claimedBy !== uid) throw new HttpsError("permission-denied", "Only verified owners can update banners.");
    await profileRef.set({ bannerConfig, bannerModerationStatus: "pending", updatedAt: now() }, { merge: true });
    return { status: "pending" };
});

export const moderateOrganizationBanner = onCall({ enforceAppCheck: true }, async (request) => {
    requireAdmin(request.auth?.token);
    const profileId = stringValue(request.data?.profileId, "profileId");
    const status = stringValue(request.data?.status, "status");
    if (!["approved", "rejected", "pending"].includes(status)) throw new HttpsError("invalid-argument", "Unsupported banner moderation status.");
    await db.collection("amenNationalDirectory").doc(profileId).set({ bannerModerationStatus: status, updatedAt: now() }, { merge: true });
    return { status };
});

export const createDirectorySubscriptionCheckout = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request.auth?.uid);
    const profileId = stringValue(request.data?.profileId, "profileId");
    const plan = typeof request.data?.plan === "string" && billingPlans.has(request.data.plan) ? request.data.plan : "plus";
    const priceId = stripePriceIdForPlan(plan);
    if (paidBillingPlans.has(plan) && !priceId) {
        throw new HttpsError("failed-precondition", `Missing Stripe price configuration for ${plan}.`);
    }
    const profile = await db.collection("amenNationalDirectory").doc(profileId).get();
    if (!profile.exists) throw new HttpsError("not-found", "Directory profile not found.");
    const data = profile.data() as AmenNationalDirectoryRecord;
    if (!canCreatePaidCheckout(data)) {
        throw new HttpsError("failed-precondition", "Profile is not eligible for paid AMEN tools yet.");
    }

    const checkoutRef = db.collection("amenDirectorySubscriptionCheckouts").doc();
    await checkoutRef.set({
        uid,
        profileId,
        plan,
        priceId: priceId || null,
        status: "created",
        createdAt: now(),
        updatedAt: now(),
    });
    const baseUrl = process.env.ORGANIZATION_CHECKOUT_BASE_URL || "amen://organization-checkout";
    const checkoutUrl = `${baseUrl}?checkoutId=${encodeURIComponent(checkoutRef.id)}&profileId=${encodeURIComponent(profileId)}&plan=${encodeURIComponent(plan)}`;
    return { checkoutId: checkoutRef.id, checkoutUrl };
});

export const createCheckoutSessionForOrganizationPlan = createDirectorySubscriptionCheckout;

export const handleOrganizationBillingWebhook = onCall({ enforceAppCheck: true }, async (request) => {
    requireAdmin(request.auth?.token);
    const eventId = stringValue(request.data?.eventId, "eventId");
    const profileId = stringValue(request.data?.profileId, "profileId");
    const tier = stringValue(request.data?.tier, "tier");
    const status = stringValue(request.data?.status, "status");
    if (!billingPlans.has(tier)) throw new HttpsError("invalid-argument", "Unsupported billing tier.");
    const eventRef = db.collection("amenBillingWebhookEvents").doc(eventId);
    const profileRef = db.collection("amenNationalDirectory").doc(profileId);
    await db.runTransaction(async (tx) => {
        const event = await tx.get(eventRef);
        if (event.exists) return;
        tx.set(eventRef, { profileId, tier, status, handledAt: now() });
        tx.set(profileRef, { billingPlan: tier, billingStatus: status, updatedAt: now() }, { merge: true });
    });
    return { status: "handled" };
});

export const ingestSchoolDirectoryBatch = onCall({ enforceAppCheck: true, timeoutSeconds: 540, memory: "1GiB" }, async (request) => {
    requireAdmin(request.auth?.token);
    return ingestDirectoryBatch(request.data, new Set(["ncesCCD", "ncesPSS", "ncesIPEDS"]), "schoolDirectory");
});

export const ingestNonprofitDirectoryBatch = onCall({ enforceAppCheck: true, timeoutSeconds: 540, memory: "1GiB" }, async (request) => {
    requireAdmin(request.auth?.token);
    return ingestDirectoryBatch(request.data, new Set(["irsEOBMF", "osmStaticExtract", "partnerImport"]), "nonprofitDirectory");
});

export const ingestDirectoryManifestSource = onCall({ enforceAppCheck: true, timeoutSeconds: 540, memory: "1GiB" }, async (request) => {
    requireAdmin(request.auth?.token);
    const source = stringValue(request.data?.source, "source");
    const dryRun = Boolean(request.data?.dryRun);
    const manifest = buildDirectoryImportManifest();
    const item = manifest.find((candidate) => candidate.source === source);
    if (!item) throw new HttpsError("not-found", "Directory import source is not configured.");
    return ingestManifestItem(item, dryRun, Math.min(Number(request.data?.limit) || DEFAULT_DAILY_IMPORT_LIMIT, DEFAULT_DAILY_IMPORT_LIMIT));
});

export const dedupeOrganizations = onCall({ enforceAppCheck: true }, async (request) => {
    requireAdmin(request.auth?.token);
    const normalizedName = normalizeDirectoryName(stringValue(request.data?.normalizedName, "normalizedName"));
    const snapshot = await db.collection("amenNationalDirectory")
        .where("normalizedName", "==", normalizedName)
        .limit(20)
        .get();
    return { candidates: snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() })) };
});

export const geocodeOrganizationBatch = onCall({ enforceAppCheck: true }, async (request) => {
    requireAdmin(request.auth?.token);
    const dryRun = Boolean(request.data?.dryRun);
    const rows = Array.isArray(request.data?.rows) ? request.data.rows.slice(0, 500) : [];
    let updated = 0;
    let skipped = 0;
    const errors: string[] = [];
    const batch = db.batch();
    for (const row of rows) {
        try {
            const profileId = stringValue(row.profileId, "profileId");
            const latitude = Number(row.latitude);
            const longitude = Number(row.longitude);
            if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
                skipped += 1;
                continue;
            }
            if (!dryRun) {
                batch.set(db.collection("amenNationalDirectory").doc(profileId), {
                    latitude,
                    longitude,
                    geocodeSource: "censusGeocoder",
                    updatedAt: now(),
                }, { merge: true });
            }
            updated += 1;
        } catch (error) {
            errors.push(error instanceof Error ? error.message : String(error));
        }
    }
    if (!dryRun && updated > 0) await batch.commit();
    return writeOpsRun("geocodeOrganizationBatch", "censusGeocoder", dryRun, { created: 0, updated, skipped, errors });
});

export const runCensusGeocoderWorker = onCall({ enforceAppCheck: true, timeoutSeconds: 540, memory: "1GiB" }, async (request) => {
    requireAdmin(request.auth?.token);
    const dryRun = Boolean(request.data?.dryRun);
    const limit = Math.min(Number(request.data?.limit) || 25, 100);
    const snapshot = await db.collection("amenNationalDirectory")
        .where("visibility", "==", "public")
        .where("latitude", "==", null)
        .limit(limit)
        .get();
    const rows: { profileId: string; latitude: number; longitude: number }[] = [];
    const errors: string[] = [];
    for (const doc of snapshot.docs) {
        const data = doc.data() as AmenNationalDirectoryRecord;
        try {
            const url = buildCensusGeocoderUrl({ address: [data.displayName, data.city, data.state, data.postalCode].filter(Boolean).join(" ") });
            if (dryRun) {
                errors.push(`dryRun:${doc.id}:${url}`);
                continue;
            }
            const response = await fetch(url);
            const json = await response.json();
            const parsed = parseCensusGeocoderResponse(doc.id, json);
            if (parsed) rows.push(parsed);
        } catch (error) {
            errors.push(error instanceof Error ? error.message : String(error));
        }
    }
    if (rows.length > 0) {
        const batch = db.batch();
        for (const row of rows) {
            batch.set(db.collection("amenNationalDirectory").doc(row.profileId), {
                latitude: row.latitude,
                longitude: row.longitude,
                geocodeSource: "censusGeocoder",
                updatedAt: now(),
            }, { merge: true });
        }
        await batch.commit();
    }
    return writeOpsRun("runCensusGeocoderWorker", "censusGeocoder", dryRun, { created: 0, updated: rows.length, skipped: snapshot.size - rows.length, errors });
});

export const syncAmenNationalDirectoryToAlgolia = onCall({ enforceAppCheck: true, timeoutSeconds: 540, memory: "1GiB" }, async (request) => {
    requireAdmin(request.auth?.token);
    return syncDirectoryAlgoliaBatch(Boolean(request.data?.dryRun), Math.min(Number(request.data?.limit) || 500, 1000));
});

export const classifyOrganizationTypeCallable = onCall({ enforceAppCheck: true }, async (request) => {
    requireAdmin(request.auth?.token);
    return { kind: classifyOrganizationKind(request.data || {}) };
});

export { classifyOrganizationTypeCallable as classifyOrganizationType };

export const getOrganizationDirectoryImportManifest = onCall({ enforceAppCheck: true }, async (request) => {
    requireAdmin(request.auth?.token);
    return { manifest: buildDirectoryImportManifest() };
});

// NOTE: Add a Firestore TTL policy on `system/scheduledJobLocks` collection
// with field `expiresAt` set to 7 days. This automatically cleans up old lock documents.

export const scheduledAmenNationalDirectoryImports = onSchedule({ schedule: "every 24 hours", timeoutSeconds: 540, memory: "1GiB" }, async () => {
    const today = new Date().toISOString().slice(0, 10);
    const lockRef = db.doc(`system/scheduledJobLocks/amenNationalDirectoryImports_${today}`);

    const lockAcquired = await db.runTransaction(async (tx) => {
        const snap = await tx.get(lockRef);
        if (snap.exists && snap.data()?.status === "completed") {
            return false;
        }
        tx.set(lockRef, {
            status: "running",
            startedAt: now(),
            date: today,
            expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
        });
        return true;
    });

    if (!lockAcquired) {
        console.info("[amenNationalDirectory] scheduledAmenNationalDirectoryImports already completed today, skipping", { date: today });
        return;
    }

    try {
        const manifest = buildDirectoryImportManifest();
        const ready = manifest.filter((item) => item.storagePath || item.url);
        if (ready.length === 0) {
            await writeOpsRun("scheduledAmenNationalDirectoryImports", "", true, {
                created: 0,
                updated: 0,
                skipped: manifest.length,
                errors: ["No directory source file locations configured."],
            });
        } else {
            for (const item of ready) {
                await ingestManifestItem(item, false, DEFAULT_DAILY_IMPORT_LIMIT);
            }
        }

        await lockRef.update({
            status: "completed",
            completedAt: now(),
        });
    } catch (err) {
        await lockRef.update({
            status: "failed",
            error: String(err),
            failedAt: now(),
        });
        throw err;
    }
});

export const scheduledAmenNationalDirectoryGeocoding = onSchedule({ schedule: "every 24 hours", timeoutSeconds: 540, memory: "1GiB" }, async () => {
    const today = new Date().toISOString().slice(0, 10);
    const lockRef = db.doc(`system/scheduledJobLocks/amenNationalDirectoryGeocoding_${today}`);

    const lockAcquired = await db.runTransaction(async (tx) => {
        const snap = await tx.get(lockRef);
        if (snap.exists && snap.data()?.status === "completed") {
            return false;
        }
        tx.set(lockRef, {
            status: "running",
            startedAt: now(),
            date: today,
            expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
        });
        return true;
    });

    if (!lockAcquired) {
        console.info("[amenNationalDirectory] scheduledAmenNationalDirectoryGeocoding already completed today, skipping", { date: today });
        return;
    }

    try {
        await writeOpsRun("scheduledAmenNationalDirectoryGeocoding", "censusGeocoder", true, {
            created: 0,
            updated: 0,
            skipped: 0,
            errors: ["Scheduled geocoder requires explicit callable execution with admin review to control Census usage and data quality."],
        });

        await lockRef.update({
            status: "completed",
            completedAt: now(),
        });
    } catch (err) {
        await lockRef.update({
            status: "failed",
            error: String(err),
            failedAt: now(),
        });
        throw err;
    }
});

export const scheduledAmenNationalDirectoryAlgoliaSync = onSchedule({ schedule: "every 24 hours", timeoutSeconds: 540, memory: "1GiB" }, async () => {
    const today = new Date().toISOString().slice(0, 10);
    const lockRef = db.doc(`system/scheduledJobLocks/amenNationalDirectoryAlgoliaSync_${today}`);

    const lockAcquired = await db.runTransaction(async (tx) => {
        const snap = await tx.get(lockRef);
        if (snap.exists && snap.data()?.status === "completed") {
            return false;
        }
        tx.set(lockRef, {
            status: "running",
            startedAt: now(),
            date: today,
            expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
        });
        return true;
    });

    if (!lockAcquired) {
        console.info("[amenNationalDirectory] scheduledAmenNationalDirectoryAlgoliaSync already completed today, skipping", { date: today });
        return;
    }

    try {
        await syncDirectoryAlgoliaBatch(false, 1000);

        await lockRef.update({
            status: "completed",
            completedAt: now(),
        });
    } catch (err) {
        await lockRef.update({
            status: "failed",
            error: String(err),
            failedAt: now(),
        });
        throw err;
    }
});

async function ingestDirectoryBatch(data: any, allowedBatchSources: Set<string>, job: string) {
    const dryRun = Boolean(data?.dryRun);
    const source = typeof data?.source === "string" ? data.source : undefined;
    const parsedRows = typeof data?.csv === "string" && source
        ? parseCsvRows(data.csv).map((row) => mapSourceRowToDirectoryRecord(source, row))
        : [];
    const rows = (Array.isArray(data?.rows) ? data.rows : parsedRows).slice(0, DEFAULT_IMPORT_BATCH_SIZE);
    let created = 0;
    let updated = 0;
    let skipped = 0;
    const errors: string[] = [];
    const batch = db.batch();

    for (const raw of rows) {
        try {
            const record = buildDirectoryRecord(raw);
            if (!allowedBatchSources.has(record.source)) {
                skipped += 1;
                continue;
            }
            const ref = db.collection("amenNationalDirectory").doc(record.id);
            if (!dryRun) {
                batch.set(ref, { ...record, updatedAt: now(), createdAt: now() }, { merge: true });
            }
            const existing = !dryRun ? await ref.get() : undefined;
            if (existing?.exists) updated += 1;
            else created += 1;
        } catch (error) {
            errors.push(error instanceof Error ? error.message : String(error));
        }
    }

    if (!dryRun && created > 0) await batch.commit();
    return writeOpsRun(job, Array.from(allowedBatchSources).join(","), dryRun, { created, updated, skipped, errors });
}

async function ingestManifestItem(item: DirectoryImportManifestItem, dryRun: boolean, limit: number) {
    const sourcePath = item.url || item.storagePath;
    if (!sourcePath) {
        return writeOpsRun("ingestDirectoryManifestSource", item.source, dryRun, {
            created: 0,
            updated: 0,
            skipped: 1,
            errors: [`${item.source} has no url or storagePath configured.`],
        });
    }
    const buffer = await readDirectoryImportBuffer(sourcePath);
    const files = extractTextFilesFromDirectoryImportBuffer(buffer, sourcePath);
    let created = 0;
    let updated = 0;
    let skipped = 0;
    const errors: string[] = [];
    let remaining = limit;

    for (const csv of files) {
        if (remaining <= 0) break;
        const rows = parseCsvRows(csv)
            .map((row) => mapSourceRowToDirectoryRecord(item.source, row))
            .filter((row) => row.kind === item.kind)
            .slice(0, remaining);
        const result = await ingestDirectoryBatch({ rows, dryRun }, new Set([item.source]), `manifest:${item.source}`) as any;
        created += Number(result.created || 0);
        updated += Number(result.updated || 0);
        skipped += Number(result.skipped || 0);
        if (Array.isArray(result.errors)) errors.push(...result.errors);
        remaining -= rows.length;
    }

    return writeOpsRun("ingestDirectoryManifestSource", item.source, dryRun, { created, updated, skipped, errors });
}

async function readDirectoryImportBuffer(sourcePath: string): Promise<Buffer> {
    if (/^https:\/\//i.test(sourcePath)) {
        const response = await fetch(sourcePath);
        if (!response.ok) throw new HttpsError("unavailable", `Directory import download failed: ${response.status}`);
        return Buffer.from(await response.arrayBuffer());
    }
    if (sourcePath.startsWith("gs://")) {
        const withoutScheme = sourcePath.slice("gs://".length);
        const slash = withoutScheme.indexOf("/");
        if (slash <= 0) throw new HttpsError("invalid-argument", "Invalid Cloud Storage path.");
        const bucketName = withoutScheme.slice(0, slash);
        const filePath = withoutScheme.slice(slash + 1);
        const [contents] = await admin.storage().bucket(bucketName).file(filePath).download();
        return contents;
    }
    throw new HttpsError("invalid-argument", "Directory import source must be an HTTPS URL or gs:// Cloud Storage path.");
}

async function syncDirectoryAlgoliaBatch(dryRun: boolean, limit: number) {
    const snapshot = await db.collection("amenNationalDirectory")
        .where("visibility", "==", "public")
        .limit(limit)
        .get();
    let updated = 0;
    let skipped = 0;
    const errors: string[] = [];
    for (const doc of snapshot.docs) {
        const record = { id: doc.id, ...doc.data() } as AmenNationalDirectoryRecord;
        if (!shouldIndexDirectoryRecord(record)) {
            skipped += 1;
            continue;
        }
        try {
            if (!dryRun) await writeAlgoliaDirectoryRecord(record);
            updated += 1;
        } catch (error) {
            errors.push(error instanceof Error ? error.message : String(error));
        }
    }
    return writeOpsRun("syncAmenNationalDirectoryToAlgolia", "amenNationalDirectory", dryRun, { created: 0, updated, skipped, errors });
}

async function writeAlgoliaDirectoryRecord(record: AmenNationalDirectoryRecord) {
    const appId = process.env.ALGOLIA_APP_ID;
    const adminKey = process.env.ALGOLIA_ADMIN_API_KEY;
    const indexName = process.env.ALGOLIA_ORGANIZATION_INDEX || "amenOrganizations";
    if (!appId || !adminKey) throw new HttpsError("failed-precondition", "Algolia admin configuration is missing.");
    const response = await fetch(`https://${appId}-dsn.algolia.net/1/indexes/${encodeURIComponent(indexName)}/${encodeURIComponent(record.id)}`, {
        method: "PUT",
        headers: {
            "Content-Type": "application/json",
            "X-Algolia-API-Key": adminKey,
            "X-Algolia-Application-Id": appId,
        },
        body: JSON.stringify(buildAlgoliaDirectoryRecord(record)),
    });
    if (!response.ok) throw new HttpsError("unavailable", `Algolia directory sync failed: ${response.status}`);
}

async function assertClaimRateLimit(uid: string) {
    const ref = db.collection("amenOrganizationClaimRateLimits").doc(uid);
    await db.runTransaction(async (tx) => {
        const snapshot = await tx.get(ref);
        const data = snapshot.data();
        const currentCount = Number(data?.count || 0);
        const windowStartedAt = data?.windowStartedAt as admin.firestore.Timestamp | undefined;
        const windowAgeMs = windowStartedAt ? Date.now() - windowStartedAt.toMillis() : Number.POSITIVE_INFINITY;
        const resetWindow = windowAgeMs > 24 * 60 * 60 * 1000;
        const nextCount = resetWindow ? 1 : currentCount + 1;
        if (nextCount > 5) throw new HttpsError("resource-exhausted", "Too many organization claim requests today.");
        tx.set(ref, {
            count: nextCount,
            windowStartedAt: resetWindow ? now() : windowStartedAt,
            updatedAt: now(),
        }, { merge: true });
    });
}

function validateImportManifestItem(input: any): DirectoryImportManifestItem {
    const source = stringValue(input.source, "source");
    const kind = stringValue(input.kind, "kind");
    if (!isSourceKindAllowed(source, kind)) throw new HttpsError("failed-precondition", "Import manifest source/kind mismatch.");
    return {
        source,
        kind,
        label: typeof input.label === "string" ? input.label : `${source} ${kind}`,
        storagePath: typeof input.storagePath === "string" && input.storagePath.trim().length > 0 ? input.storagePath.trim() : undefined,
        url: typeof input.url === "string" && input.url.trim().length > 0 ? input.url.trim() : undefined,
        cadence: typeof input.cadence === "string" ? input.cadence : "manual",
    };
}

async function writeOpsRun(job: string, source: string, dryRun: boolean, result: { created: number; updated: number; skipped: number; errors: string[] }) {
    const ref = db.collection("opsRuns").doc();
    const payload = {
        job,
        source,
        dryRun,
        startedAt: now(),
        finishedAt: now(),
        ...result,
    };
    await ref.set(payload);
    return { id: ref.id, ...payload };
}

function requireAuth(uid?: string): string {
    if (!uid) throw new HttpsError("unauthenticated", "Authentication is required.");
    return uid;
}

function requireAdmin(token?: any): void {
    if (!token?.admin) throw new HttpsError("permission-denied", "Admin access is required.");
}

function stringValue(value: unknown, field: string): string {
    if (typeof value !== "string" || value.trim().length === 0) {
        throw new HttpsError("invalid-argument", `${field} is required.`);
    }
    return value.trim();
}

function numericValue(value?: string): number | undefined {
    if (!value) return undefined;
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : undefined;
}
