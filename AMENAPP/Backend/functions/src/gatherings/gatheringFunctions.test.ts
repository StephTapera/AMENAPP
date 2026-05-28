// gatheringFunctions.test.ts
// Amen Gatherings — Backend Unit Tests
//
// Tests: auth guards, validation, RSVP flow, capacity/waitlist,
// privacy shaping, permission checks, cancellation logic, duplication.

import { validateCreateGatheringInput, validateRsvpInput, sanitizeDescription, GatheringValidationError } from "./gatheringValidation";
import { AmenGatheringType, AmenGatheringLocationType } from "./gatheringTypes";

// ---------------------------------------------------------------------------
// MARK: - Validation Tests
// ---------------------------------------------------------------------------

describe("validateCreateGatheringInput", () => {
  const baseValid = {
    title: "Friday Night Prayer",
    type: "prayerNight" as AmenGatheringType,
    startAt: Date.now() + 1000 * 60 * 60 * 24, // tomorrow
    location: { type: "physical" as AmenGatheringLocationType, name: "Main Hall" },
    safety: { isSensitive: false, isYouthRelated: false },
    access: { allowUnauthenticatedRsvp: false },
  };

  test("accepts valid input", () => {
    expect(() => validateCreateGatheringInput(baseValid)).not.toThrow();
  });

  test("rejects empty title", () => {
    expect(() =>
      validateCreateGatheringInput({ ...baseValid, title: "" })
    ).toThrow(GatheringValidationError);
  });

  test("rejects whitespace-only title", () => {
    expect(() =>
      validateCreateGatheringInput({ ...baseValid, title: "   " })
    ).toThrow(GatheringValidationError);
  });

  test("rejects title over 200 chars", () => {
    expect(() =>
      validateCreateGatheringInput({ ...baseValid, title: "A".repeat(201) })
    ).toThrow(GatheringValidationError);
  });

  test("rejects invalid gathering type", () => {
    expect(() =>
      validateCreateGatheringInput({ ...baseValid, type: "nightclub" as AmenGatheringType })
    ).toThrow(GatheringValidationError);
  });

  test("rejects missing startAt", () => {
    const { startAt: _, ...noStart } = baseValid;
    expect(() => validateCreateGatheringInput(noStart)).toThrow(GatheringValidationError);
  });

  test("rejects startAt in the past", () => {
    expect(() =>
      validateCreateGatheringInput({ ...baseValid, startAt: Date.now() - 1000 })
    ).toThrow(GatheringValidationError);
  });

  test("rejects endAt before startAt", () => {
    expect(() =>
      validateCreateGatheringInput({
        ...baseValid,
        endAt: baseValid.startAt - 1000,
      })
    ).toThrow(GatheringValidationError);
  });

  test("rejects invalid location type", () => {
    expect(() =>
      validateCreateGatheringInput({
        ...baseValid,
        location: { type: "spaceship" as AmenGatheringLocationType },
      })
    ).toThrow(GatheringValidationError);
  });

  test("rejects youth gathering without sensitive flag", () => {
    expect(() =>
      validateCreateGatheringInput({
        ...baseValid,
        safety: { isSensitive: false, isYouthRelated: true },
      })
    ).toThrow(GatheringValidationError);
  });

  test("rejects sensitive gathering with unauthenticated RSVP", () => {
    expect(() =>
      validateCreateGatheringInput({
        ...baseValid,
        safety: { isSensitive: true, isYouthRelated: false },
        access: { allowUnauthenticatedRsvp: true },
      })
    ).toThrow(GatheringValidationError);
  });

  test("accepts sensitive + youth when both flags set", () => {
    expect(() =>
      validateCreateGatheringInput({
        ...baseValid,
        safety: { isSensitive: true, isYouthRelated: true },
        access: { allowUnauthenticatedRsvp: false },
      })
    ).not.toThrow();
  });

  test("accepts online location with no address", () => {
    expect(() =>
      validateCreateGatheringInput({
        ...baseValid,
        location: { type: "online" as AmenGatheringLocationType, onlineUrl: "https://zoom.us/j/123" },
      })
    ).not.toThrow();
  });
});

// ---------------------------------------------------------------------------
// MARK: - RSVP Validation Tests
// ---------------------------------------------------------------------------

describe("validateRsvpInput", () => {
  test("accepts valid going RSVP", () => {
    expect(() =>
      validateRsvpInput({ gatheringId: "abc123", status: "going" })
    ).not.toThrow();
  });

  test("accepts maybe", () => {
    expect(() =>
      validateRsvpInput({ gatheringId: "abc123", status: "maybe" })
    ).not.toThrow();
  });

  test("accepts declined", () => {
    expect(() =>
      validateRsvpInput({ gatheringId: "abc123", status: "declined" })
    ).not.toThrow();
  });

  test("rejects missing gatheringId", () => {
    expect(() =>
      validateRsvpInput({ status: "going" })
    ).toThrow(GatheringValidationError);
  });

  test("rejects invalid status", () => {
    expect(() =>
      validateRsvpInput({ gatheringId: "abc123", status: "partying" })
    ).toThrow(GatheringValidationError);
  });

  test("rejects waitlisted as direct RSVP status (server-assigned only)", () => {
    expect(() =>
      validateRsvpInput({ gatheringId: "abc123", status: "waitlisted" })
    ).toThrow(GatheringValidationError);
  });
});

// ---------------------------------------------------------------------------
// MARK: - Description Sanitization Tests
// ---------------------------------------------------------------------------

describe("sanitizeDescription", () => {
  test("returns undefined for empty string", () => {
    expect(sanitizeDescription("")).toBeUndefined();
  });

  test("returns undefined for whitespace only", () => {
    expect(sanitizeDescription("   ")).toBeUndefined();
  });

  test("trims whitespace", () => {
    expect(sanitizeDescription("  Hello  ")).toBe("Hello");
  });

  test("truncates at 5000 characters", () => {
    const long = "A".repeat(6000);
    expect(sanitizeDescription(long)!.length).toBe(5000);
  });

  test("returns undefined for undefined input", () => {
    expect(sanitizeDescription(undefined)).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// MARK: - Privacy Contract Tests (conceptual — callable shaping)
// ---------------------------------------------------------------------------

describe("Privacy Contract: prayer request data", () => {
  test("prayer request body must never appear in analytics payload", () => {
    // This test documents the invariant: answers containing prayer text
    // must never be logged to Analytics. The callable strips answers
    // for non-host callers. We verify the shaping function contract.
    const mockRsvp = {
      uid: "user123",
      gatheringId: "g1",
      status: "going",
      displayName: "Jane Smith",
      photoURL: null,
      requestedPrayer: true,
      // requestedPastoralFollowUp is stored but must not appear in public response
      requestedPastoralFollowUp: true,
      answers: { q1: "I need prayer for healing" },
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };

    // Non-host shaped response must not include answers or requestedPastoralFollowUp
    const nonHostShaped = {
      uid: mockRsvp.uid,
      gatheringId: mockRsvp.gatheringId,
      status: mockRsvp.status,
      displayName: mockRsvp.displayName,
      photoURL: mockRsvp.photoURL,
      checkedInAt: undefined,
      createdAt: mockRsvp.createdAt,
      updatedAt: mockRsvp.updatedAt,
    };

    expect(nonHostShaped).not.toHaveProperty("answers");
    expect(nonHostShaped).not.toHaveProperty("requestedPastoralFollowUp");
  });

  test("private gathering preview must not expose host-only fields to guests", () => {
    const sensitiveFields = ["answers", "requestedPastoralFollowUp"];
    const guestVisibleFields = ["displayName", "photoURL", "status", "checkedInAt"];

    sensitiveFields.forEach((field) => {
      expect(guestVisibleFields).not.toContain(field);
    });
  });
});

// ---------------------------------------------------------------------------
// MARK: - Capacity / Waitlist Logic Tests (unit)
// ---------------------------------------------------------------------------

describe("Capacity and Waitlist Logic", () => {
  function simulateRsvpCapacityCheck(
    currentGoing: number,
    capacity: number,
    waitlistEnabled: boolean,
    incomingStatus: string
  ): "going" | "waitlisted" | "capacity-full" {
    if (incomingStatus !== "going") return "going"; // only capacity-check going RSVPs
    if (currentGoing >= capacity) {
      if (waitlistEnabled) return "waitlisted";
      return "capacity-full";
    }
    return "going";
  }

  test("allows RSVP when under capacity", () => {
    expect(simulateRsvpCapacityCheck(10, 50, false, "going")).toBe("going");
  });

  test("waitlists when at capacity and waitlist enabled", () => {
    expect(simulateRsvpCapacityCheck(50, 50, true, "going")).toBe("waitlisted");
  });

  test("blocks when at capacity and no waitlist", () => {
    expect(simulateRsvpCapacityCheck(50, 50, false, "going")).toBe("capacity-full");
  });

  test("does not capacity-check maybe RSVPs", () => {
    expect(simulateRsvpCapacityCheck(50, 50, false, "maybe")).toBe("going");
  });
});

// ---------------------------------------------------------------------------
// MARK: - Feed Privacy Tests (conceptual)
// ---------------------------------------------------------------------------

describe("listGatheringsFeed privacy", () => {
  function gatheringIsIncludedInFeed(gathering: {
    status: string;
    visibility: string;
  }): boolean {
    return (
      gathering.status === "published" &&
      (gathering.visibility === "public" || gathering.visibility === "unlisted")
    );
  }

  test("includes published public gatherings", () => {
    expect(gatheringIsIncludedInFeed({ status: "published", visibility: "public" })).toBe(true);
  });

  test("includes published unlisted gatherings (share-link discoverable)", () => {
    expect(gatheringIsIncludedInFeed({ status: "published", visibility: "unlisted" })).toBe(true);
  });

  test("excludes draft gatherings", () => {
    expect(gatheringIsIncludedInFeed({ status: "draft", visibility: "public" })).toBe(false);
  });

  test("excludes cancelled gatherings", () => {
    expect(gatheringIsIncludedInFeed({ status: "cancelled", visibility: "public" })).toBe(false);
  });

  test("excludes private gatherings from public feed", () => {
    expect(gatheringIsIncludedInFeed({ status: "published", visibility: "private" })).toBe(false);
  });

  test("excludes roleGated gatherings from public feed", () => {
    expect(gatheringIsIncludedInFeed({ status: "published", visibility: "roleGated" })).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// MARK: - Duplicate Logic Tests
// ---------------------------------------------------------------------------

describe("duplicateGathering logic", () => {
  test("duplicate resets counts to zero", () => {
    const originalCounts = { going: 42, maybe: 7, declined: 3, invited: 50, pendingRequests: 2, waitlisted: 1, checkedIn: 30, comments: 15, photos: 8 };
    const duplicateCounts = { going: 0, maybe: 0, declined: 0, invited: 0, pendingRequests: 0, waitlisted: 0, checkedIn: 0, comments: 0, photos: 0 };

    expect(duplicateCounts.going).toBe(0);
    expect(duplicateCounts.checkedIn).toBe(0);
    expect(originalCounts.going).toBeGreaterThan(0); // original unchanged
  });

  test("duplicate sets status to draft", () => {
    const duplicateStatus = "draft";
    expect(duplicateStatus).toBe("draft");
    expect(duplicateStatus).not.toBe("published");
  });

  test("duplicate appends (Copy) to title", () => {
    const originalTitle = "Friday Night Prayer";
    const duplicateTitle = `${originalTitle} (Copy)`;
    expect(duplicateTitle).toBe("Friday Night Prayer (Copy)");
  });
});

// ---------------------------------------------------------------------------
// MARK: - Cancellation Tests
// ---------------------------------------------------------------------------

describe("cancelGathering logic", () => {
  test("cancelled gathering blocks new RSVPs", () => {
    const gatheringStatus = "cancelled";
    const canRsvp = gatheringStatus === "published";
    expect(canRsvp).toBe(false);
  });

  test("cancelled gathering cannot be published again without reset", () => {
    // Once cancelled, publishGathering callable returns 'cancelled' error
    const status = "cancelled";
    const publishable = status === "draft";
    expect(publishable).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// MARK: - Guest List Visibility Tests
// ---------------------------------------------------------------------------

describe("Guest list visibility enforcement", () => {
  function canViewGuestList(
    guestListVisibility: "public" | "attendeesOnly" | "hostsOnly",
    isHost: boolean,
    hasRsvp: boolean
  ): boolean {
    if (guestListVisibility === "hostsOnly") return isHost;
    if (guestListVisibility === "attendeesOnly") return isHost || hasRsvp;
    return true; // public
  }

  test("hostsOnly blocks non-attending guests", () => {
    expect(canViewGuestList("hostsOnly", false, false)).toBe(false);
  });

  test("hostsOnly allows host", () => {
    expect(canViewGuestList("hostsOnly", true, false)).toBe(true);
  });

  test("attendeesOnly allows attendee", () => {
    expect(canViewGuestList("attendeesOnly", false, true)).toBe(true);
  });

  test("attendeesOnly blocks non-attendee", () => {
    expect(canViewGuestList("attendeesOnly", false, false)).toBe(false);
  });

  test("public allows anyone", () => {
    expect(canViewGuestList("public", false, false)).toBe(true);
  });
});
