import {
  resolvePostLabels,
  failClosedReceipt,
  prominenceForTier,
  ACCOUNT_TIER_ORDER,
  PostTrustProfile,
  AccountTrustPassport,
} from "./postProvenance";

function makeProfile(overrides: Partial<PostTrustProfile> = {}): PostTrustProfile {
  return {
    postId: "post_1",
    resolvedKind: "real_media",
    confidence: { band: "high", basis: "captured in app" },
    confidentSignal: true,
    sources: [
      { type: "captureSignal", locator: "inAppCaptureBonus", summary: "Captured in app." },
    ],
    ...overrides,
  };
}

function makePassport(overrides: Partial<AccountTrustPassport> = {}): AccountTrustPassport {
  return { uid: "uid_1", tier: "EMAIL", ...overrides };
}

describe("resolvePostLabels — POST precedence (D-I1)", () => {
  it("uses the post-level kind regardless of account tier", () => {
    const profile = makeProfile({ resolvedKind: "synthetic_warning" });
    // A high account tier must NOT flip a synthetic warning into a positive label.
    const receipt = resolvePostLabels(profile, makePassport({ tier: "ORG" }));
    expect(receipt.label.kind).toBe("synthetic_warning");
    expect(receipt.failClosed).toBe(false);
  });

  it("account tier changes prominence only, never the kind", () => {
    const profile = makeProfile({ resolvedKind: "real_media" });
    const emailReceipt = resolvePostLabels(profile, makePassport({ tier: "EMAIL" }));
    const orgReceipt = resolvePostLabels(profile, makePassport({ tier: "ORG" }));

    expect(emailReceipt.label.kind).toBe("real_media");
    expect(orgReceipt.label.kind).toBe("real_media");

    // Same label kind; prominence differs by tier.
    expect(emailReceipt.label.prominence).toBe("subtle");
    expect(orgReceipt.label.prominence).toBe("elevated");
  });

  it("appends the account tier as a provenance source (prominence only)", () => {
    const receipt = resolvePostLabels(makeProfile(), makePassport({ tier: "CHURCH" }));
    const tierSource = receipt.sources.find((s) => s.type === "accountTier");
    expect(tierSource).toBeDefined();
    expect(tierSource?.locator).toBe("CHURCH");
    expect(tierSource?.summary).toMatch(/prominence only/i);
  });
});

describe("resolvePostLabels — fail-closed flat label (D-I3)", () => {
  it("returns a flat pendingReview receipt when the passport is absent", () => {
    const receipt = resolvePostLabels(makeProfile(), null);
    expect(receipt.failClosed).toBe(true);
    expect(receipt.label.kind).toBe("pending_review");
    expect(receipt.label.confident).toBe(false);
    expect(receipt.label.prominence).toBe("subtle");
    expect(receipt.sources).toEqual([]);
    expect(receipt.confidence.band).toBe("low");
    expect(receipt.accountTierWeight).toBe(0);
  });

  it("returns a flat pendingReview receipt when the post profile is absent", () => {
    const receipt = resolvePostLabels(null, makePassport({ tier: "ORG" }));
    expect(receipt.failClosed).toBe(true);
    expect(receipt.label.kind).toBe("pending_review");
    // Even with the highest tier present, no positive label and no elevation.
    expect(receipt.label.prominence).toBe("subtle");
    expect(receipt.accountTierWeight).toBe(0);
  });

  it("preserves the postId when only the passport is missing", () => {
    const receipt = resolvePostLabels(makeProfile({ postId: "post_x" }), undefined);
    expect(receipt.postId).toBe("post_x");
    expect(receipt.failClosed).toBe(true);
  });

  it("failClosedReceipt is never confident and carries a basis", () => {
    const receipt = failClosedReceipt("post_y", "screener unavailable");
    expect(receipt.failClosed).toBe(true);
    expect(receipt.label.confident).toBe(false);
    expect(receipt.confidence.basis).toBe("screener unavailable");
    expect(receipt.confidence.score).toBeUndefined();
  });
});

describe("resolvePostLabels — no public score (D-I2 / D-I4)", () => {
  it("does not place a numeric score on the label", () => {
    const receipt = resolvePostLabels(makeProfile(), makePassport({ tier: "IDENTITY" }));
    expect(receipt.label).not.toHaveProperty("score");
    // confidence.score is omitted unless a real principled signal exists.
    expect(receipt.confidence.score).toBeUndefined();
  });

  it("records the internal tier weight matching ACCOUNT_TIER_ORDER", () => {
    const receipt = resolvePostLabels(makeProfile(), makePassport({ tier: "LEADER" }));
    expect(receipt.accountTierWeight).toBe(ACCOUNT_TIER_ORDER.LEADER);
  });
});

describe("prominenceForTier", () => {
  it("elevates IDENTITY and above, standard for PHONE, subtle for EMAIL", () => {
    expect(prominenceForTier("EMAIL")).toBe("subtle");
    expect(prominenceForTier("PHONE")).toBe("standard");
    expect(prominenceForTier("IDENTITY")).toBe("elevated");
    expect(prominenceForTier("CHURCH")).toBe("elevated");
    expect(prominenceForTier("ORG")).toBe("elevated");
  });
});
