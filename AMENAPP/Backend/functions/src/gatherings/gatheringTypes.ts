// gatheringTypes.ts
// Amen Gatherings — TypeScript type contracts (matches iOS AmenGatheringModels.swift)

import * as admin from "firebase-admin";

export type AmenGatheringType =
  | "prayerNight"
  | "bibleStudy"
  | "worshipNight"
  | "churchService"
  | "smallGroup"
  | "volunteerOpportunity"
  | "retreat"
  | "class"
  | "missionTrip"
  | "custom";

export type AmenGatheringHostType = "user" | "church" | "organization" | "smallGroup";

export type AmenGatheringStatus = "draft" | "published" | "cancelled" | "completed" | "archived";

export type AmenGatheringVisibility = "public" | "unlisted" | "private" | "roleGated";

export type AmenGatheringLocationType = "physical" | "online" | "hybrid" | "tbd";

export type AmenGatheringAccessMode = "preview" | "join" | "request" | "checkIn" | "roleGated";

export type AmenGatheringRsvpStatus = "going" | "maybe" | "declined" | "waitlisted" | "pending";

export type AmenGatheringGuestListVisibility = "public" | "attendeesOnly" | "hostsOnly";

export type AmenGatheringAnswersVisibility = "hostsOnly" | "attendeeSummary" | "private";

export type AmenGatheringQuestionType =
  | "shortText"
  | "longText"
  | "singleChoice"
  | "multiChoice"
  | "boolean";

// MARK: - Location

export interface AmenGatheringLocation {
  type: AmenGatheringLocationType;
  name?: string;
  address?: string;
  city?: string;
  region?: string;
  country?: string;
  geoHash?: string;
  lat?: number;
  lng?: number;
  onlineUrl?: string;
  directionsUrl?: string;
}

// MARK: - Theme

export interface AmenGatheringTheme {
  coverImageUrl?: string;
  coverStoragePath?: string;
  gradientName?: string;
  templateId?: string;
  iconName?: string;
  scriptureReference?: string;
  scriptureTextPreview?: string;
}

// MARK: - Details

export interface AmenGatheringDetails {
  speaker?: string;
  leader?: string;
  whatToBring?: string;
  childcare?: string;
  parking?: string;
  accessibilityNotes?: string;
  contactEmail?: string;
  contactPhone?: string;
}

// MARK: - Spiritual

export interface AmenGatheringSpiritual {
  prayerFocus?: string;
  scriptureReference?: string;
  allowPrayerRequests: boolean;
  allowPastoralFollowUp: boolean;
  allowTestimonies: boolean;
}

// MARK: - RSVP Settings

export interface AmenGatheringRsvpSettings {
  allowGoing: boolean;
  allowMaybe: boolean;
  allowDecline: boolean;
  questionsEnabled: boolean;
  guestListVisibility: AmenGatheringGuestListVisibility;
  answersVisibility: AmenGatheringAnswersVisibility;
}

// MARK: - Access Config

export interface AmenGatheringAccessConfig {
  accessPassEnabled: boolean;
  defaultAccessPassId?: string;
  mode: AmenGatheringAccessMode;
  requiresApproval: boolean;
  allowGuestPreview: boolean;
  allowUnauthenticatedRsvp: boolean;
}

// MARK: - Connected Targets

export interface AmenGatheringConnectedTargets {
  spaceId?: string;
  discussionId?: string;
  churchId?: string;
  organizationId?: string;
  smallGroupId?: string;
  prayerRoomId?: string;
  sermonNotesId?: string;
}

// MARK: - Counts

export interface AmenGatheringCounts {
  going: number;
  maybe: number;
  declined: number;
  invited: number;
  pendingRequests: number;
  waitlisted: number;
  checkedIn: number;
  comments: number;
  photos: number;
}

// MARK: - Safety

export interface AmenGatheringSafety {
  isSensitive: boolean;
  isYouthRelated: boolean;
  requiresModeration: boolean;
  allowPublicComments: boolean;
  prayerRequestsPrivateByDefault: boolean;
}

// MARK: - Core Gathering Document

export interface AmenGathering {
  gatheringId: string;
  title: string;
  description?: string;
  type: AmenGatheringType;
  hostType: AmenGatheringHostType;
  hostId: string;
  hostName: string;
  hostVerified: boolean;
  createdByUid: string;
  startAt: admin.firestore.Timestamp;
  endAt?: admin.firestore.Timestamp;
  timezone?: string;
  location: AmenGatheringLocation;
  visibility: AmenGatheringVisibility;
  status: AmenGatheringStatus;
  capacity?: number;
  waitlistEnabled: boolean;
  access: AmenGatheringAccessConfig;
  connectedTargets: AmenGatheringConnectedTargets;
  theme: AmenGatheringTheme;
  details: AmenGatheringDetails;
  spiritual: AmenGatheringSpiritual;
  rsvpSettings: AmenGatheringRsvpSettings;
  counts: AmenGatheringCounts;
  safety: AmenGatheringSafety;
  audit: {
    createdAt: admin.firestore.Timestamp;
    updatedAt: admin.firestore.Timestamp;
    publishedAt?: admin.firestore.Timestamp;
    cancelledAt?: admin.firestore.Timestamp;
    cancelledByUid?: string;
  };
}

// MARK: - RSVP Record

export interface AmenGatheringRsvp {
  uid: string;
  gatheringId: string;
  status: AmenGatheringRsvpStatus;
  displayName?: string;
  photoURL?: string;
  // answers is stored but never returned without host privilege check
  answers?: Record<string, unknown>;
  requestedPrayer?: boolean;
  requestedPastoralFollowUp?: boolean;
  checkedInAt?: admin.firestore.Timestamp;
  createdAt: admin.firestore.Timestamp;
  updatedAt: admin.firestore.Timestamp;
}

// MARK: - Question

export interface AmenGatheringQuestion {
  questionId: string;
  prompt: string;
  type: AmenGatheringQuestionType;
  options?: string[];
  required: boolean;
  sensitive: boolean;
  visibility: "hostsOnly" | "private";
  sortOrder: number;
}

// MARK: - Feed Card (privacy-shaped)

export interface AmenGatheringFeedCard {
  gatheringId: string;
  title: string;
  type: AmenGatheringType;
  hostName: string;
  hostVerified: boolean;
  hostPhotoURL?: string;
  coverImageUrl?: string;
  gradientName?: string;
  startAt: number; // ms since epoch for easy iOS decode
  location: {
    type: AmenGatheringLocationType;
    name?: string;
    city?: string;
    onlineUrl?: string;
    displaySummary: string;
  };
  visibility: AmenGatheringVisibility;
  accessMode: AmenGatheringAccessMode;
  rsvpCount: number;
  userRsvpStatus?: AmenGatheringRsvpStatus;
  isSaved: boolean;
  scriptureReference?: string;
}
