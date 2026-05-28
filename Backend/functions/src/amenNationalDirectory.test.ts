import {
    buildDirectoryRecord,
    buildDirectoryImportManifest,
    buildAlgoliaDirectoryRecord,
    buildCensusGeocoderUrl,
    canCreatePaidCheckout,
    classifyOrganizationKind,
    extractTextFilesFromDirectoryImportBuffer,
    domainFromEmail,
    domainFromWebsite,
    isDomainVerifiedClaim,
    isGooglePlacesStoredSafely,
    isSourceKindAllowed,
    mapSourceRowToDirectoryRecord,
    nationalDirectorySources,
    normalizeDirectoryName,
    parseCensusGeocoderResponse,
    parseCsvRows,
    shouldIndexDirectoryRecord,
    stripePriceIdForPlan,
} from "./amenNationalDirectory";

describe("Amen national directory", () => {
    test("official source registry covers schools, higher education, and exempt organizations", () => {
        expect(nationalDirectorySources.map((source) => source.id)).toEqual(["ncesCCD", "ncesPSS", "ncesIPEDS", "irsEOBMF", "censusGeocoder", "osmStaticExtract"]);
        expect(nationalDirectorySources[0].allowedKinds).toContain("publicK12School");
        expect(nationalDirectorySources[1].allowedKinds).toContain("privateK12School");
        expect(nationalDirectorySources[2].allowedKinds).toContain("higherEducation");
        expect(nationalDirectorySources[3].allowedKinds).toContain("church");
    });

    test("normalization creates stable search keys", () => {
        expect(normalizeDirectoryName("  St. Mary's   Christian-School!! ")).toBe("st mary s christian school");
    });

    test("source kind guard prevents unsupported imports", () => {
        expect(isSourceKindAllowed("ncesCCD", "publicK12School")).toBe(true);
        expect(isSourceKindAllowed("ncesCCD", "church")).toBe(false);
        expect(isSourceKindAllowed("ncesPSS", "privateK12School")).toBe(true);
        expect(isSourceKindAllowed("irsEOBMF", "church")).toBe(true);
    });

    test("directory records default to imported and unclaimed", () => {
        const record = buildDirectoryRecord({
            source: "ncesIPEDS",
            sourceRecordId: "123456",
            kind: "higherEducation",
            displayName: "Example University",
            state: "GA",
        });

        expect(record.id).toBe("ncesIPEDS_123456");
        expect(record.normalizedName).toBe("example university");
        expect(record.verificationStatus).toBe("sourceImported");
        expect(record.claimStatus).toBe("unclaimed");
        expect(record.subscriptionEligible).toBe(false);
    });

    test("classification maps official sources and religion signals", () => {
        expect(classifyOrganizationKind({ source: "ncesCCD" })).toBe("publicK12School");
        expect(classifyOrganizationKind({ source: "ncesPSS" })).toBe("privateK12School");
        expect(classifyOrganizationKind({ source: "ncesIPEDS" })).toBe("higherEducation");
        expect(classifyOrganizationKind({ source: "irsEOBMF", nteeCode: "X20" })).toBe("church");
        expect(classifyOrganizationKind({ source: "irsEOBMF", name: "Hope Mission" })).toBe("ministry");
    });

    test("Google Places persistence is place-id only", () => {
        expect(isGooglePlacesStoredSafely({ source: "googlePlaces", sourceRecordId: "place_123" })).toBe(true);
        expect(isGooglePlacesStoredSafely({ source: "googlePlaces", sourceRecordId: "place_123", displayName: "Copied Name" })).toBe(false);
    });

    test("paid checkout requires claimed or verified eligible profiles", () => {
        const base = buildDirectoryRecord({
            source: "ncesCCD",
            sourceRecordId: "school-1",
            kind: "publicK12School",
            displayName: "Example School",
            subscriptionEligible: true,
        });

        expect(canCreatePaidCheckout(base)).toBe(false);
        expect(canCreatePaidCheckout({ ...base, claimStatus: "claimed" })).toBe(true);
        expect(canCreatePaidCheckout({ ...base, claimStatus: "verified" })).toBe(true);
        expect(canCreatePaidCheckout({ ...base, claimStatus: "verified", subscriptionEligible: false })).toBe(false);
    });

    test("domain verification matches claimant email to organization website", () => {
        expect(domainFromEmail("admin@school.edu")).toBe("school.edu");
        expect(domainFromWebsite("https://www.school.edu/about")).toBe("school.edu");
        expect(isDomainVerifiedClaim("admin@school.edu", "https://www.school.edu")).toBe(true);
        expect(isDomainVerifiedClaim("admin@mail.school.edu", "school.edu")).toBe(true);
        expect(isDomainVerifiedClaim("admin@gmail.com", "school.edu")).toBe(false);
    });

    test("CSV parser handles quoted commas and source row mapping", () => {
        const rows = parseCsvRows("NCESSCH,SCH_NAME,LCITY,LSTATE\n123,\"Grace, Academy\",Atlanta,GA\n");
        const mapped = mapSourceRowToDirectoryRecord("ncesCCD", rows[0]);

        expect(rows[0].SCH_NAME).toBe("Grace, Academy");
        expect(mapped.sourceRecordId).toBe("123");
        expect(mapped.kind).toBe("publicK12School");
        expect(mapped.displayName).toBe("Grace, Academy");
        expect(mapped.state).toBe("GA");
    });

    test("Census geocoder URL uses public endpoint and encoded address", () => {
        const url = buildCensusGeocoderUrl({ address: "1600 Pennsylvania Ave NW Washington DC 20500" });

        expect(url).toContain("https://geocoding.geo.census.gov/geocoder/locations/onelineaddress");
        expect(url).toContain("format=json");
        expect(url).toContain("1600+Pennsylvania");
    });

    test("Census geocoder response parser returns Firestore-ready coordinates", () => {
        const parsed = parseCensusGeocoderResponse("profile-1", {
            result: { addressMatches: [{ coordinates: { x: -84.39, y: 33.75 } }] },
        });

        expect(parsed).toEqual({ profileId: "profile-1", latitude: 33.75, longitude: -84.39 });
        expect(parseCensusGeocoderResponse("profile-1", { result: { addressMatches: [] } })).toBeUndefined();
    });

    test("import manifest validates source and kind ownership", () => {
        const manifest = buildDirectoryImportManifest({
            NCES_CCD_STORAGE_PATH: "gs://amen/ccd.csv",
            IRS_EO_BMF_STORAGE_PATH: "gs://amen/irs.csv",
        } as NodeJS.ProcessEnv);

        expect(manifest.find((item) => item.source === "ncesCCD")?.storagePath).toBe("gs://amen/ccd.csv");
        expect(() => buildDirectoryImportManifest({
            AMEN_DIRECTORY_IMPORT_MANIFEST_JSON: JSON.stringify([{ source: "ncesCCD", kind: "church" }]),
        } as NodeJS.ProcessEnv)).toThrow("source/kind mismatch");
    });

    test("directory import file extraction supports csv, gzip, and zip text files", () => {
        const csv = "NCESSCH,SCH_NAME\n1,Grace School\n";
        const zip = new (require("adm-zip"))();
        zip.addFile("schools.csv", Buffer.from(csv));

        expect(extractTextFilesFromDirectoryImportBuffer(Buffer.from(csv), "schools.csv")).toEqual([csv]);
        expect(extractTextFilesFromDirectoryImportBuffer(require("zlib").gzipSync(Buffer.from(csv)), "schools.csv.gz")).toEqual([csv]);
        expect(extractTextFilesFromDirectoryImportBuffer(zip.toBuffer(), "schools.zip")).toEqual([csv]);
    });

    test("Stripe plan config requires explicit paid price ids", () => {
        expect(stripePriceIdForPlan("free", {} as NodeJS.ProcessEnv)).toBeUndefined();
        expect(stripePriceIdForPlan("plus", { ORGANIZATION_PLUS_PRICE_ID: "price_plus" } as NodeJS.ProcessEnv)).toBe("price_plus");
        expect(stripePriceIdForPlan("pro", { ORGANIZATION_PRO_PRICE_ID: "price_pro" } as NodeJS.ProcessEnv)).toBe("price_pro");
    });

    test("Algolia indexing policy avoids the unclaimed IRS long tail", () => {
        const school = buildDirectoryRecord({
            source: "ncesCCD",
            sourceRecordId: "school-1",
            kind: "publicK12School",
            displayName: "Example School",
            latitude: 33.75,
            longitude: -84.39,
        });
        const church = buildDirectoryRecord({
            source: "irsEOBMF",
            sourceRecordId: "church-1",
            kind: "church",
            displayName: "Example Church",
        });

        expect(shouldIndexDirectoryRecord(school)).toBe(true);
        expect(shouldIndexDirectoryRecord(church)).toBe(false);
        expect(shouldIndexDirectoryRecord({ ...church, claimStatus: "verified" })).toBe(true);
        expect(buildAlgoliaDirectoryRecord(school)).toMatchObject({ objectID: school.id, kind: "publicK12School" });
    });
});
