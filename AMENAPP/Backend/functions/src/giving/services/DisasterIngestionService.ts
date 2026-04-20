// DisasterIngestionService.ts
// AMEN Giving — Disaster event ingestion and routing.
// Pulls signals from NOAA, USGS, ReliefWeb. Dedupes. Severity-scores.
// Links vetted responder organizations. Publishes active response cards.
// Hard rule: never surface unverified orgs because they trend.

import * as admin from 'firebase-admin';

const db = admin.firestore();

export interface ExternalDisasterSignal {
  source: 'noaa' | 'usgs' | 'reliefweb';
  externalId: string;
  title: string;
  eventType: string;
  severity: string;
  regions: string[];
  summary: string;
  occurredAt: Date;
  sourceUrl?: string;
}

export async function ingestDisasterSignal(signal: ExternalDisasterSignal): Promise<void> {
  // Dedupe by external ID
  const existing = await db.collection('disaster_events')
    .where('externalId', '==', signal.externalId)
    .limit(1)
    .get();

  if (!existing.empty) {
    // Update severity/status if changed
    await existing.docs[0].ref.update({
      severity: normalizeSeverity(signal.severity, signal.eventType),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return;
  }

  const normalizedSeverity = normalizeSeverity(signal.severity, signal.eventType);
  if (normalizedSeverity === null) return;  // Below threshold — don't surface

  // Find linked responder orgs (only pre-vetted, disaster-flagged orgs)
  const responderOrgs = await db.collection('organizations')
    .where('isActive', '==', true)
    .where('isDisasterResponder', '==', true)
    .where('rankingEligibility', '==', true)
    .get();

  // Match orgs that serve the affected regions
  const linkedOrgIds: string[] = [];
  for (const doc of responderOrgs.docs) {
    const org = doc.data();
    const servesRegion = (org.serviceRegions as any[]).some((r: any) =>
      signal.regions.some(region => r.state === region || r.country === region || r.isGlobal)
    );
    if (servesRegion) linkedOrgIds.push(doc.id);
  }

  // Create disaster event document
  await db.collection('disaster_events').add({
    title: signal.title,
    eventType: normalizeEventType(signal.eventType),
    sourceProvider: signal.source,
    sourceUrl: signal.sourceUrl ?? null,
    externalId: signal.externalId,
    severity: normalizedSeverity,
    regions: signal.regions,
    summary: sanitizeSummary(signal.summary),
    startedAt: admin.firestore.Timestamp.fromDate(signal.occurredAt),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    isActive: true,
    linkedOrgIds: linkedOrgIds.slice(0, 6),  // Max 6 linked orgs
  });
}

// Only surface disasters that clear a severity threshold
function normalizeSeverity(
  rawSeverity: string,
  eventType: string
): 'critical' | 'high' | 'moderate' | null {
  const lower = rawSeverity.toLowerCase();
  const type = eventType.toLowerCase();

  // Earthquakes: only magnitude 6.0+
  if (type.includes('earthquake') && !['major', 'great', 'critical'].includes(lower)) {
    return null;
  }

  if (['extreme', 'catastrophic', 'critical'].includes(lower)) return 'critical';
  if (['major', 'severe', 'high'].includes(lower)) return 'high';
  if (['moderate', 'medium'].includes(lower)) return 'moderate';

  return null;  // Below threshold
}

function normalizeEventType(rawType: string): string {
  const lower = rawType.toLowerCase();
  if (lower.includes('hurricane') || lower.includes('tropical')) return 'hurricane';
  if (lower.includes('earthquake')) return 'earthquake';
  if (lower.includes('fire') || lower.includes('wildfire')) return 'wildfire';
  if (lower.includes('flood')) return 'flood';
  if (lower.includes('refugee') || lower.includes('displacement')) return 'refugee_displacement';
  return 'other';
}

// Strip sensational language from external summaries
function sanitizeSummary(raw: string): string {
  return raw
    .replace(/BREAKING:/gi, '')
    .replace(/URGENT:/gi, '')
    .replace(/CATASTROPHIC/gi, 'significant')
    .replace(/DEVASTATING/gi, 'severe')
    .trim()
    .substring(0, 500);  // Max 500 chars
}
