// BenevolenceGuardian.ts
// AMEN Giving — Guardian AI classifier for benevolence requests.
// Scans for fraud risk, manipulated narratives, coercive language, and theological manipulation.
// Returns a moderation decision with reasons. Never auto-approves on first pass.

import { BenevolenceRequest } from '../models/givingModels';

export interface GuardianDecision {
  decision: 'cleared' | 'flagged' | 'escalate_human';
  confidence: 'high' | 'medium' | 'low';
  reasons: string[];
  riskFlags: RiskFlag[];
}

export interface RiskFlag {
  type: RiskFlagType;
  severity: 'critical' | 'high' | 'medium' | 'low';
  excerpt?: string;
}

export type RiskFlagType =
  | 'prosperity_gospel'
  | 'coercive_spiritual_manipulation'
  | 'fabricated_emergency_language'
  | 'repeat_request_pattern'
  | 'narrative_inconsistency'
  | 'urgency_coercion'
  | 'excessive_amount'
  | 'suspicious_payment_behavior'
  | 'duplicate_beneficiary'
  | 'copied_scam_language';

export async function guardianReview(
  request: Pick<BenevolenceRequest, 'title' | 'summary' | 'requestedAmount' | 'category'>,
  requesterId: string,
  db: FirebaseFirestore.Firestore
): Promise<GuardianDecision> {
  const flags: RiskFlag[] = [];
  const reasons: string[] = [];

  // --- 1. Excessive amount check
  const MAX_AMOUNTS: Record<string, number> = {
    car_repair: 300000,          // $3,000
    grocery_support: 50000,      // $500
    funeral_expenses: 1000000,   // $10,000
    rent_bridge: 500000,         // $5,000
    school_supplies: 30000,      // $300
    utility_support: 40000,      // $400
    medical_support: 500000,     // $5,000
    other: 100000,               // $1,000
  };
  const maxForCategory = MAX_AMOUNTS[request.category] ?? 100000;
  if (request.requestedAmount > maxForCategory) {
    flags.push({
      type: 'excessive_amount',
      severity: 'high',
      excerpt: `Requested ${request.requestedAmount} cents exceeds category cap of ${maxForCategory} cents`
    });
    reasons.push('Requested amount exceeds the approved cap for this category.');
  }

  // --- 2. Urgency coercion patterns
  const urgencyPatterns = [
    /must act (now|today|immediately)/i,
    /running out of time/i,
    /final (notice|warning|chance)/i,
    /or (else|we will|I will)/i,
    /god (told|told me|said)/i,
    /if you don't/i,
    /act fast/i,
  ];
  for (const pattern of urgencyPatterns) {
    if (pattern.test(request.summary) || pattern.test(request.title)) {
      flags.push({ type: 'urgency_coercion', severity: 'high', excerpt: pattern.toString() });
      reasons.push('Request contains urgency coercion language.');
      break;
    }
  }

  // --- 3. Prosperity gospel / theological manipulation
  const prosperityPatterns = [
    /god will bless you (100|ten|thousand)/i,
    /seed (faith|money|gift)/i,
    /sow into/i,
    /your (harvest|blessing|miracle)/i,
    /breakthrough/i,
    /if you give, god will/i,
  ];
  for (const pattern of prosperityPatterns) {
    if (pattern.test(request.summary)) {
      flags.push({ type: 'prosperity_gospel', severity: 'critical', excerpt: pattern.toString() });
      reasons.push('Request contains prosperity-gospel or theological manipulation language.');
      break;
    }
  }

  // --- 4. Copied scam language indicators
  const scamPatterns = [
    /western union/i,
    /money order/i,
    /wire transfer/i,
    /gift card/i,
    /bitcoin|crypto/i,
    /foreign diplomat/i,
    /inheritance/i,
    /lottery/i,
  ];
  for (const pattern of scamPatterns) {
    if (pattern.test(request.summary)) {
      flags.push({ type: 'copied_scam_language', severity: 'critical', excerpt: pattern.toString() });
      reasons.push('Request contains language associated with financial scams.');
      break;
    }
  }

  // --- 5. Repeat request check
  const sixtyDaysAgo = new Date();
  sixtyDaysAgo.setDate(sixtyDaysAgo.getDate() - 60);
  const recentRequests = await db.collection('benevolence_requests')
    .where('requesterUserId', '==', requesterId)
    .where('status', 'in', ['approved', 'active', 'fulfilled'])
    .get();
  if (!recentRequests.empty) {
    flags.push({ type: 'repeat_request_pattern', severity: 'high' });
    reasons.push('Requester has had a recent approved or active request.');
  }

  // --- Determine decision
  const criticalFlags = flags.filter(f => f.severity === 'critical');
  const highFlags = flags.filter(f => f.severity === 'high');

  if (criticalFlags.length > 0) {
    return { decision: 'escalate_human', confidence: 'high', reasons, riskFlags: flags };
  } else if (highFlags.length >= 2) {
    return { decision: 'escalate_human', confidence: 'medium', reasons, riskFlags: flags };
  } else if (highFlags.length === 1) {
    return { decision: 'flagged', confidence: 'medium', reasons, riskFlags: flags };
  } else {
    return { decision: 'cleared', confidence: flags.length === 0 ? 'high' : 'medium', reasons, riskFlags: flags };
  }
}
