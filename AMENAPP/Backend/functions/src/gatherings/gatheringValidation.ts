// gatheringValidation.ts
// Input validation for Gathering callables.
// Called before any Firestore write. Throws on invalid input.

import { AmenGatheringType, AmenGatheringLocationType } from "./gatheringTypes";

export class GatheringValidationError extends Error {
  constructor(
    message: string,
    public readonly code: string = "invalid-input"
  ) {
    super(message);
    this.name = "GatheringValidationError";
  }
}

export function validateCreateGatheringInput(data: Record<string, unknown>): void {
  const title = data["title"];
  if (!title || typeof title !== "string" || title.trim().length === 0) {
    throw new GatheringValidationError("Title is required.", "invalid-title");
  }
  if (title.trim().length > 200) {
    throw new GatheringValidationError("Title must be 200 characters or fewer.", "title-too-long");
  }

  const type = data["type"] as AmenGatheringType | undefined;
  const validTypes: AmenGatheringType[] = [
    "prayerNight", "bibleStudy", "worshipNight", "churchService",
    "smallGroup", "volunteerOpportunity", "retreat", "class", "missionTrip", "custom"
  ];
  if (!type || !validTypes.includes(type)) {
    throw new GatheringValidationError("Invalid gathering type.", "invalid-type");
  }

  const startAt = data["startAt"];
  if (!startAt || typeof startAt !== "number") {
    throw new GatheringValidationError("Start time is required.", "invalid-start-time");
  }
  const startDate = new Date(startAt);
  if (isNaN(startDate.getTime())) {
    throw new GatheringValidationError("Invalid start time.", "invalid-start-time");
  }
  if (startDate < new Date()) {
    throw new GatheringValidationError("Start time must be in the future.", "start-time-past");
  }

  const endAt = data["endAt"];
  if (endAt !== undefined && endAt !== null) {
    if (typeof endAt !== "number" || new Date(endAt) <= startDate) {
      throw new GatheringValidationError("End time must be after start time.", "invalid-end-time");
    }
  }

  const location = data["location"] as Record<string, unknown> | undefined;
  if (!location || typeof location !== "object") {
    throw new GatheringValidationError("Location is required.", "invalid-location");
  }
  const validLocationTypes: AmenGatheringLocationType[] = ["physical", "online", "hybrid", "tbd"];
  if (!validLocationTypes.includes(location["type"] as AmenGatheringLocationType)) {
    throw new GatheringValidationError("Invalid location type.", "invalid-location-type");
  }

  const safety = data["safety"] as Record<string, unknown> | undefined;
  if (safety?.["isYouthRelated"] === true && safety?.["isSensitive"] !== true) {
    throw new GatheringValidationError(
      "Youth-related gatherings must be marked sensitive.",
      "youth-must-be-sensitive"
    );
  }

  const access = data["access"] as Record<string, unknown> | undefined;
  if (safety?.["isSensitive"] === true && access?.["allowUnauthenticatedRsvp"] === true) {
    throw new GatheringValidationError(
      "Sensitive gatherings cannot allow unauthenticated RSVPs.",
      "sensitive-unauth-blocked"
    );
  }
}

export function validateRsvpInput(data: Record<string, unknown>): void {
  const gatheringId = data["gatheringId"];
  if (!gatheringId || typeof gatheringId !== "string") {
    throw new GatheringValidationError("gatheringId is required.", "missing-gathering-id");
  }

  const status = data["status"];
  const validStatuses = ["going", "maybe", "declined"];
  if (!status || !validStatuses.includes(status as string)) {
    throw new GatheringValidationError("Invalid RSVP status.", "invalid-rsvp-status");
  }
}

export function validatePublishInput(data: Record<string, unknown>): void {
  const gatheringId = data["gatheringId"];
  if (!gatheringId || typeof gatheringId !== "string") {
    throw new GatheringValidationError("gatheringId is required.", "missing-gathering-id");
  }
}

export function sanitizeDescription(input: string | undefined): string | undefined {
  if (!input) return undefined;
  return input.trim().slice(0, 5000) || undefined;
}
