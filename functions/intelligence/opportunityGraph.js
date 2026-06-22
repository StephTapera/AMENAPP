/**
 * functions/intelligence/opportunityGraph.js
 *
 * AMEN Living Intelligence — Opportunity Graph
 *
 * Firestore collection: opportunity_graph
 * Graph nodes: churches, orgs, events, prayer_requests, needs, people
 *
 * Exports:
 *   getNode(nodeId)
 *   upsertNode(nodeId, data)
 *   getEdges(nodeId, type)
 *   resolveBackingEntity(kind, id)
 *   routeSupplyDemand({ kind, needId, userId })
 *
 * Privacy-first: user identity is anonymized in graph nodes.
 * Opt-in signals only — never infer need from behaviour.
 */

"use strict";

const admin = require('firebase-admin');
const { BACKING_KIND } = require('./contracts');

// ─── Collection paths ─────────────────────────────────────────────────────────

/** Map BackingKind → canonical Firestore collection */
const KIND_COLLECTION = {
  [BACKING_KIND.CHURCH]:         'churches',
  [BACKING_KIND.ORG]:            'organizations',
  [BACKING_KIND.EVENT]:          'events',
  [BACKING_KIND.PRAYER_REQUEST]: 'prayers',
  [BACKING_KIND.STUDY]:          null,  // dual-collection — see resolveBackingEntity
  [BACKING_KIND.NEED]:           'volunteerOpportunities',
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

function db() {
  return admin.firestore();
}

function graphCollection() {
  return db().collection('opportunity_graph');
}

/** Anonymize a user in a graph node — store a one-way hash, not the UID. */
function anonymizeUserId(userId) {
  const { createHash } = require('crypto');
  return createHash('sha256').update(`intel_graph:${userId}`).digest('hex').slice(0, 16);
}

// ─── Graph CRUD ───────────────────────────────────────────────────────────────

/**
 * getNode — fetch a single opportunity_graph node by its ID.
 *
 * @param {string} nodeId
 * @returns {Promise<object|null>}  Document data or null if not found
 */
async function getNode(nodeId) {
  const snap = await graphCollection().doc(nodeId).get();
  if (!snap.exists) return null;
  return { id: snap.id, ...snap.data() };
}

/**
 * upsertNode — create or merge a node into opportunity_graph.
 * Always writes serverTimestamp for updatedAt.
 *
 * @param {string} nodeId
 * @param {object} data
 * @returns {Promise<void>}
 */
async function upsertNode(nodeId, data) {
  const nodeRef = graphCollection().doc(nodeId);
  await nodeRef.set(
    {
      ...data,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

/**
 * getEdges — fetch all adjacent node IDs of a given relationship type.
 *
 * Edge documents live at: opportunity_graph/{nodeId}/edges/{edgeId}
 * Each edge doc: { type: string, targetNodeId: string, weight: number, createdAt: Timestamp }
 *
 * @param {string} nodeId
 * @param {'supplies'|'needs'|'attends'|'volunteers'} type
 * @returns {Promise<string[]>}  Array of target node IDs
 */
async function getEdges(nodeId, type) {
  const VALID_TYPES = new Set(['supplies', 'needs', 'attends', 'volunteers']);
  if (!VALID_TYPES.has(type)) {
    console.warn(`[opportunityGraph.getEdges] Unknown edge type: ${type}`);
    return [];
  }

  const snap = await graphCollection()
    .doc(nodeId)
    .collection('edges')
    .where('type', '==', type)
    .get();

  if (snap.empty) return [];
  return snap.docs.map((d) => d.data().targetNodeId).filter(Boolean);
}

// ─── BackingEntity resolver ───────────────────────────────────────────────────

/**
 * resolveBackingEntity — verify that a backing entity actually exists in Firestore.
 *
 * @param {string} kind   BACKING_KIND value
 * @param {string} id     Firestore document ID
 * @returns {Promise<{ verified: boolean, doc: object|null }>}
 */
async function resolveBackingEntity(kind, id) {
  if (!kind || !id) {
    return { verified: false, doc: null };
  }

  try {
    if (kind === BACKING_KIND.STUDY) {
      // STUDY can live in bereanInsights or bereanProjects
      const [insightSnap, projectSnap] = await Promise.all([
        db().collection('bereanInsights').doc(id).get(),
        db().collection('bereanProjects').doc(id).get(),
      ]);
      const snap = insightSnap.exists ? insightSnap : (projectSnap.exists ? projectSnap : null);
      if (!snap) return { verified: false, doc: null };
      return { verified: true, doc: { id: snap.id, ...snap.data() } };
    }

    const collection = KIND_COLLECTION[kind];
    if (!collection) {
      console.warn(`[resolveBackingEntity] Unknown kind: ${kind}`);
      return { verified: false, doc: null };
    }

    const snap = await db().collection(collection).doc(id).get();
    if (!snap.exists) return { verified: false, doc: null };
    return { verified: true, doc: { id: snap.id, ...snap.data() } };
  } catch (err) {
    console.error(`[resolveBackingEntity] Error resolving ${kind}/${id}:`, err.message);
    return { verified: false, doc: null };
  }
}

// ─── Supply/Demand Router ─────────────────────────────────────────────────────

/**
 * routeSupplyDemand — find the best match in the graph for a given need.
 *
 * Supports:
 *   people  → resources: find people offering what the need requires
 *   churches → needs: find needs a church could address
 *   volunteers → opportunities: match volunteer to open volunteer slots
 *   donors → causes: match donor signal to active fundraising needs
 *
 * Privacy: userId is anonymized before any graph lookup.
 * Opt-in only: if user has no opt-in node in the graph, no matching occurs.
 *
 * @param {{ kind: string, needId: string, userId: string }}
 * @returns {Promise<{ match: object|null, score: number, reasons: string[] }>}
 */
async function routeSupplyDemand({ kind, needId, userId }) {
  const anonId = anonymizeUserId(userId);

  // Check opt-in: user node must exist and have optIn: true
  const userNode = await getNode(`user_${anonId}`);
  if (!userNode || !userNode.optIn) {
    return {
      match: null,
      score: 0,
      reasons: ['User has not opted in to opportunity matching'],
    };
  }

  try {
    let matchCandidates = [];
    let matchReason = '';

    switch (kind) {
      case 'people_resources': {
        // Find nodes that supply what this need requires
        const needNode = await getNode(`need_${needId}`);
        if (!needNode) {
          return { match: null, score: 0, reasons: ['Need not found in graph'] };
        }
        const requiredSkills = needNode.requiredSkills || [];
        // Find supplier nodes adjacent to this need with 'supplies' edges
        const supplierIds = await getEdges(`need_${needId}`, 'supplies');
        if (supplierIds.length === 0) {
          return { match: null, score: 0, reasons: ['No matching suppliers found in graph'] };
        }
        matchCandidates = supplierIds.slice(0, 5);
        matchReason = `Suppliers for need: ${requiredSkills.join(', ') || 'general'}`;
        break;
      }

      case 'churches_needs': {
        const churchNode = await getNode(`church_${needId}`);
        if (!churchNode) {
          return { match: null, score: 0, reasons: ['Church not found in graph'] };
        }
        // Find active needs adjacent to this church
        const needIds = await getEdges(`church_${needId}`, 'needs');
        if (needIds.length === 0) {
          return { match: null, score: 0, reasons: ['No needs found for this church'] };
        }
        matchCandidates = needIds.slice(0, 5);
        matchReason = 'Active needs matching church capacity';
        break;
      }

      case 'volunteers_opportunities': {
        // Find volunteer opportunity nodes the user is adjacent to
        const volunteerEdges = await getEdges(`user_${anonId}`, 'volunteers');
        if (volunteerEdges.length > 0) {
          matchCandidates = volunteerEdges.slice(0, 5);
          matchReason = 'Volunteer opportunities matching your profile';
        } else {
          // Fall back to open opportunities near the given needId context
          const snap = await db()
            .collection('volunteerOpportunities')
            .where('status', '==', 'open')
            .limit(5)
            .get();
          matchCandidates = snap.docs.map((d) => `opportunity_${d.id}`);
          matchReason = 'Open volunteer opportunities in your network';
        }
        break;
      }

      case 'donors_causes': {
        // Find causes the user has signaled interest in
        const donorEdges = await getEdges(`user_${anonId}`, 'supplies');
        if (donorEdges.length > 0) {
          matchCandidates = donorEdges.slice(0, 5);
          matchReason = 'Causes aligned with your giving history';
        } else {
          return { match: null, score: 0, reasons: ['No donor signal found — please opt in to giving matching'] };
        }
        break;
      }

      default:
        return { match: null, score: 0, reasons: [`Unknown routing kind: ${kind}`] };
    }

    if (matchCandidates.length === 0) {
      return { match: null, score: 0, reasons: ['No candidates found'] };
    }

    // Score candidates by their graph weight and return best
    const candidateNodes = await Promise.all(
      matchCandidates.map((id) => getNode(id)),
    );
    const validCandidates = candidateNodes.filter(Boolean);

    if (validCandidates.length === 0) {
      return { match: null, score: 0, reasons: ['No valid candidates resolved'] };
    }

    // Simple scoring: prefer nodes with higher weight or more edges
    validCandidates.sort((a, b) => (b.weight || 0) - (a.weight || 0));
    const best = validCandidates[0];

    const score = Math.min(100, Math.round((best.weight || 50)));
    return {
      match: best,
      score,
      reasons: [matchReason, `Match quality: ${score}/100`],
    };
  } catch (err) {
    console.error('[routeSupplyDemand] Error:', err.message);
    return { match: null, score: 0, reasons: ['Matching temporarily unavailable'] };
  }
}

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = {
  getNode,
  upsertNode,
  getEdges,
  resolveBackingEntity,
  routeSupplyDemand,
};
