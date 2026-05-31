/**
 * churchSearchProxy.js
 * AMEN App — Find a Church proxy callable (Phase 1 / Master Run)
 *
 * [NEEDS HUMAN DEPLOY] to production Firebase.
 * Safe to run in the Firebase Emulator Suite only.
 *
 * Purpose:
 *   Acts as the sole backend proxy for church search. The iOS client sends a
 *   structured query here; no Algolia API keys, Google Places keys, or geo
 *   credentials ever touch the device.
 *
 * Security:
 *   - App Check enforced (enforceAppCheck: true) — invalid/spoofed apps are
 *     rejected before the function body runs.
 *   - Auth required — unauthenticated callers receive HttpsError('unauthenticated').
 *
 * Input (req.data):
 *   {
 *     query:              string,          // free-text search term
 *     lat?:               number,          // user latitude (optional)
 *     lng?:               number,          // user longitude (optional)
 *     openNow?:           boolean,
 *     denomination?:      string,          // matches Denomination enum raw values
 *     maxDistanceMeters?: number,
 *     sortBy?:            "bestMatch" | "distance" | "rating"
 *   }
 *
 * Output:
 *   { churches: ChurchRecord[] }
 *
 * Implementation path:
 *   TODO: Replace mockChurches() with real Algolia index query + Firestore geo
 *   filter. Algolia API key must live in Firebase Secrets (defineSecret), never
 *   passed from the client.
 *
 * Emulator usage:
 *   firebase emulators:start --only functions
 *   (iOS points to http://localhost:5001 via useEmulator in AppDelegate)
 */

'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');

const REGION = 'us-central1';

// ─── Mock data ────────────────────────────────────────────────────────────────
// Returns a small set of representative ChurchRecord-shaped objects so the iOS
// client can fully exercise the calling convention end-to-end in the emulator.
// Shape matches ChurchRecord from Phase0Contracts.swift (Codable).

function mockChurches(lat, lng) {
  const baseLat = (typeof lat === 'number' && isFinite(lat)) ? lat : 37.3861;
  const baseLng = (typeof lng === 'number' && isFinite(lng)) ? lng : -122.0839;

  return [
    {
      id: 'mock-001',
      name: 'Grace Community Church',
      denomination: 'nonDenominational',
      coordinate: { latitude: baseLat + 0.01, longitude: baseLng + 0.01 },
      address: '100 Faith Ave, Mountain View, CA 94040',
      serviceTimes: [
        { weekday: 1, start: '2000-01-02T10:00:00Z', label: 'Sunday Morning' },
        { weekday: 1, start: '2000-01-02T18:00:00Z', label: 'Sunday Evening' },
      ],
      distanceMeters: 1500,
      rating: 4.8,
      isOpenNow: false,
      verified: true,
    },
    {
      id: 'mock-002',
      name: 'Calvary Baptist Fellowship',
      denomination: 'baptist',
      coordinate: { latitude: baseLat - 0.02, longitude: baseLng + 0.03 },
      address: '250 Pilgrim Blvd, Sunnyvale, CA 94086',
      serviceTimes: [
        { weekday: 1, start: '2000-01-02T09:30:00Z', label: 'Sunday Service' },
        { weekday: 4, start: '2000-01-05T19:00:00Z', label: 'Wednesday Bible Study' },
      ],
      distanceMeters: 3200,
      rating: 4.6,
      isOpenNow: false,
      verified: true,
    },
    {
      id: 'mock-003',
      name: 'Bethel Pentecostal Ministries',
      denomination: 'pentecostal',
      coordinate: { latitude: baseLat + 0.03, longitude: baseLng - 0.02 },
      address: '77 Spirit Lane, Santa Clara, CA 95050',
      serviceTimes: [
        { weekday: 1, start: '2000-01-02T11:00:00Z', label: 'Sunday Worship' },
        { weekday: 6, start: '2000-01-07T19:30:00Z', label: 'Friday Night Alive' },
      ],
      distanceMeters: 4800,
      rating: 4.9,
      isOpenNow: false,
      verified: false,
    },
    {
      id: 'mock-004',
      name: 'Reformed Presbyterian Church of the Valley',
      denomination: 'presbyterian',
      coordinate: { latitude: baseLat - 0.015, longitude: baseLng - 0.025 },
      address: '320 Covenant Rd, Los Altos, CA 94022',
      serviceTimes: [
        { weekday: 1, start: '2000-01-02T10:30:00Z', label: 'Morning Worship' },
      ],
      distanceMeters: 6100,
      rating: 4.5,
      isOpenNow: false,
      verified: true,
    },
    {
      id: 'mock-005',
      name: 'St. Paul Catholic Parish',
      denomination: 'catholic',
      coordinate: { latitude: baseLat + 0.005, longitude: baseLng - 0.01 },
      address: '450 Holy Cross Way, San Jose, CA 95110',
      serviceTimes: [
        { weekday: 7, start: '2000-01-01T17:00:00Z', label: 'Saturday Vigil Mass' },
        { weekday: 1, start: '2000-01-02T08:00:00Z', label: 'Sunday 8am Mass' },
        { weekday: 1, start: '2000-01-02T10:00:00Z', label: 'Sunday 10am Mass' },
      ],
      distanceMeters: 900,
      rating: 4.7,
      isOpenNow: false,
      verified: true,
    },
  ];
}

// ─── Validate + sanitise input ────────────────────────────────────────────────

function validateInput(data) {
  if (!data || typeof data !== 'object') {
    throw new HttpsError('invalid-argument', 'Request data must be an object.');
  }
  if (typeof data.query !== 'string' || data.query.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'query must be a non-empty string.');
  }
  if (data.query.length > 200) {
    throw new HttpsError('invalid-argument', 'query must not exceed 200 characters.');
  }
  if (data.lat !== undefined && (typeof data.lat !== 'number' || !isFinite(data.lat))) {
    throw new HttpsError('invalid-argument', 'lat must be a finite number.');
  }
  if (data.lng !== undefined && (typeof data.lng !== 'number' || !isFinite(data.lng))) {
    throw new HttpsError('invalid-argument', 'lng must be a finite number.');
  }
  const validSortBy = ['bestMatch', 'distance', 'rating'];
  if (data.sortBy !== undefined && !validSortBy.includes(data.sortBy)) {
    throw new HttpsError('invalid-argument', `sortBy must be one of: ${validSortBy.join(', ')}`);
  }
  if (data.maxDistanceMeters !== undefined) {
    const d = data.maxDistanceMeters;
    if (typeof d !== 'number' || !isFinite(d) || d <= 0 || d > 500000) {
      throw new HttpsError('invalid-argument', 'maxDistanceMeters must be a positive number ≤ 500,000.');
    }
  }
}

// ─── Main export ──────────────────────────────────────────────────────────────

exports.churchSearchProxy = onCall(
  {
    region: REGION,
    enforceAppCheck: true,
    // [NEEDS HUMAN DEPLOY] — emulator only until App Check is fully
    // provisioned in the production Firebase project. Remove this comment
    // and set enforceAppCheck: true before production deploy.
  },
  async (request) => {
    // 1. Auth guard
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'You must be signed in to search for churches.');
    }

    const { data } = request;

    // 2. Input validation
    validateInput(data);

    const {
      query,
      lat,
      lng,
      openNow,
      denomination,
      maxDistanceMeters,
      sortBy = 'bestMatch',
    } = data;

    // 3. TODO: Real implementation
    //    Replace the mock below with:
    //      a. Algolia church index query using the 'query' string + geo filter
    //         (Algolia API key loaded via defineSecret('ALGOLIA_CHURCH_KEY'))
    //      b. Firestore geo filter as a secondary pass if needed
    //      c. Apply openNow, denomination, maxDistanceMeters, sortBy filters
    //    The Algolia key must NEVER be sent to the client device.

    let results = mockChurches(lat, lng);

    // Apply denomination filter if provided (mock filtering)
    if (denomination) {
      results = results.filter((c) => c.denomination === denomination);
    }

    // Apply distance filter if provided (mock filtering)
    if (typeof maxDistanceMeters === 'number') {
      results = results.filter((c) =>
        c.distanceMeters === null || c.distanceMeters === undefined || c.distanceMeters <= maxDistanceMeters
      );
    }

    // Apply openNow filter if requested (mock: all churches are closed in mock data)
    // In real implementation, this checks current time vs serviceTimes
    if (openNow === true) {
      results = results.filter((c) => c.isOpenNow === true);
    }

    // Apply sort
    if (sortBy === 'distance') {
      results = results.sort((a, b) => (a.distanceMeters ?? Infinity) - (b.distanceMeters ?? Infinity));
    } else if (sortBy === 'rating') {
      results = results.sort((a, b) => (b.rating ?? 0) - (a.rating ?? 0));
    }
    // 'bestMatch' keeps the default mock order (highest relevance first)

    return { churches: results };
  }
);
