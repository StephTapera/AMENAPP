// givingModels.ts
// AMEN Giving — shared TypeScript models for Firestore collections.

export interface GivingProfile {
  causePreferences: string[];
  geographicPreference: 'Local-first' | 'Balanced' | 'Global';
  theologicalAlignment: string;
  givingStylePreferences: string[];
  locationMode: 'system_location' | 'zip' | 'manual' | 'none';
  zipCode?: string;
  homeRegion?: {
    state?: string;
    county?: string;
    metro?: string;
  };
  completedIntentFlowAt?: FirebaseFirestore.Timestamp;
  rankProfileVersion: number;
  updatedAt: FirebaseFirestore.Timestamp;
}

export interface Organization {
  id: string;
  name: string;
  slug: string;
  description: string;
  causeCategories: string[];
  serviceRegions: ServiceRegion[];
  theologicalAffiliations: string[];
  givingStylesSupported: string[];
  websiteUrl?: string;
  donationUrl?: string;
  volunteerUrl?: string;
  logoUrl?: string;
  isActive: boolean;
  isLocalPartner: boolean;
  isDisasterResponder: boolean;
  trustScore: number;          // 0.0 – 1.0
  rankingEligibility: boolean;
  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
}

export interface ServiceRegion {
  country?: string;
  state?: string;
  county?: string;
  metro?: string;
  zipCodes?: string[];
  isLocal: boolean;
  isGlobal: boolean;
}

export interface OrgTransparency {
  programExpenseRatio?: number;   // e.g. 0.82
  adminExpenseRatio?: number;
  fundraisingExpenseRatio?: number;
  fiscalYear?: string;
  sourceProviders: string[];
  sourceUrls: string[];
  verificationStatus: 'verified' | 'in_progress' | 'stale' | 'unavailable';
  verifiedAt?: FirebaseFirestore.Timestamp;
  confidence: 'high' | 'medium' | 'low' | 'unverified';
  notes?: string;
}

export interface GiftImpact {
  amount: number;        // dollars
  description: string;
  fiscalYear: string;
  sourceUrl?: string;
  verifiedAt?: FirebaseFirestore.Timestamp;
  confidence: string;
  displayPriority: number;
}

export interface OrgRecentAction {
  title: string;
  summary: string;
  region: string;
  eventType: string;
  occurredAt?: FirebaseFirestore.Timestamp;
  verifiedAt?: FirebaseFirestore.Timestamp;
  sourceUrl?: string;
  confidence: string;
  isDisplayable: boolean;
}

export interface DisasterEvent {
  id: string;
  title: string;
  eventType: 'hurricane' | 'earthquake' | 'wildfire' | 'flood' | 'refugee_displacement' | 'other';
  sourceProvider: string;
  sourceUrl?: string;
  severity: 'critical' | 'high' | 'moderate';
  regions: string[];
  summary: string;
  startedAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
  isActive: boolean;
  linkedOrgIds: string[];
}

export interface BenevolenceRequest {
  requesterUserId: string;
  churchId?: string;
  verificationType: 'church_admin' | 'pastor_elder' | 'benevolence_team' | 'local_partner';
  verificationReferenceId?: string;
  category: string;
  title: string;
  summary: string;
  requestedAmount: number;   // cents
  approvedCapAmount?: number; // cents
  currency: string;
  status: RequestStatus;
  guardianStatus: 'pending' | 'cleared' | 'flagged' | 'escalated';
  humanReviewStatus?: 'pending' | 'approved' | 'denied';
  needsReceipts: boolean;
  expiresAt?: FirebaseFirestore.Timestamp;
  fulfillmentState: 'not_started' | 'partially_funded' | 'fully_funded' | 'distributed';
  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
}

export type RequestStatus =
  | 'draft'
  | 'verification_pending'
  | 'guardian_review'
  | 'human_review'
  | 'approved'
  | 'active'
  | 'fulfilled'
  | 'expired'
  | 'closed'
  | 'denied';

export interface GivingSession {
  userId: string;
  orgId?: string;
  requestId?: string;
  destinationType: 'org' | 'request' | 'church';
  amount: number;    // cents
  currency: string;
  status: 'pending' | 'processing' | 'completed' | 'failed' | 'refunded';
  processor?: string;
  processorPaymentIntentId?: string;
  receiptId?: string;
  createdAt: FirebaseFirestore.Timestamp;
  completedAt?: FirebaseFirestore.Timestamp;
}

export interface GivingReceipt {
  userId: string;
  destinationType: string;
  destinationId: string;
  destinationName: string;
  amount: number;   // cents
  currency: string;
  receiptUrl?: string;
  taxYear: number;
  issuedAt: FirebaseFirestore.Timestamp;
  provider: string;
}

export interface CauseBrief {
  title: string;
  slug: string;
  causeCategory: string;
  regionScope?: string;
  summary: string;
  body: string;
  scriptureRefs: string[];
  linkedOrgIds: string[];
  linkedPrayerTopics: string[];
  linkedVolunteerActions: string[];
  publishedAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
  isActive: boolean;
}

export interface RankingToken {
  key: string;
  label: string;
}

export interface RankedOrg {
  orgId: string;
  score: number;
  tokens: RankingToken[];
}
