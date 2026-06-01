/**
 * churchSearchProxy.js
 * AMEN App — Find a Church proxy callable (Phase 1 / Master Run)
 *
 * Purpose:
 *   Acts as the sole backend proxy for church search. The iOS client sends a
 *   structured query here; no API keys, Google Places keys, or geo credentials
 *   ever touch the device.
 *
 * Security:
 *   - App Check enforced (enforceAppCheck: true) — invalid/spoofed apps are
 *     rejected before the function body runs.
 *   - Auth required — unauthenticated callers receive HttpsError('unauthenticated').
 *
 * Input (req.data):
 *   {
 *     query:              string,          // free-text search term (may be empty string)
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
 *   Queries the Firestore `churches` collection directly (no Algolia — there is
 *   no dedicated church index). Geo filtering uses a lat/lng bounding box on
 *   `location.latitude` (single-field range Firestore supports) with a
 *   post-fetch longitude range check. Haversine distance is computed server-side
 *   for each result. Text search falls back to a case-insensitive substring
 *   match on `name` and `address`. All filters (denomination, openNow,
 *   maxDistanceMeters, sortBy) are applied after the Firestore fetch.
 *
 * Emulator usage:
 *   firebase emulators:start --only functions
 *   (iOS points to http://localhost:5001 via useEmulator in AppDelegate)
 */

'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const REGION = 'us-central1';

// ─── Geo helpers ──────────────────────────────────────────────────────────────

/**
 * Compute Haversine distance in metres between two lat/lng points.
 * @param {number} lat1
 * @param {number} lng1
 * @param {number} lat2
 * @param {number} lng2
 * @returns {number} distance in metres
 */
function haversineMeters(lat1, lng1, lat2, lng2) {
  const R = 6371000; // Earth radius in metres
  const toRad = (deg) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

/**
 * Build bounding-box degree offsets from a distance in metres.
 * @param {number} distanceMeters
 * @param {number} latRad  latitude of centre point in radians
 * @returns {{ latDelta: number, lngDelta: number }}
 */
function boundingBoxDeltas(distanceMeters, latRad) {
  const latDelta = distanceMeters / 111320;
  const lngDelta = distanceMeters / (111320 * Math.cos(latRad));
  return { latDelta, lngDelta };
}

// ─── isOpenNow helper ─────────────────────────────────────────────────────────

/**
 * Check whether any serviceTime for this church falls within the current
 * day/hour window.
 *
 * ChurchServiceTime weekday convention: 1=Sunday … 7=Saturday
 * JS Date.getDay():                      0=Sunday … 6=Saturday
 * Mapping: jsDay + 1 === churchWeekday
 *
 * A service is considered "open now" when:
 *   - The service is today (weekday matches), AND
 *   - The current time is within a SERVICE_WINDOW_MINUTES window after
 *     the service start time.
 *
 * @param {Array} serviceTimes  Array of { weekday, start, label? }
 * @returns {boolean}
 */
function computeIsOpenNow(serviceTimes) {
  if (!Array.isArray(serviceTimes) || serviceTimes.length === 0) return false;

  const SERVICE_WINDOW_MINUTES = 120; // treat service as "open" for 2 hours after start
  const now = new Date();
  const jsDay = now.getDay(); // 0=Sunday
  const churchWeekday = jsDay + 1; // 1=Sunday … 7=Saturday
  const nowMinutes = now.getHours() * 60 + now.getMinutes();

  for (const st of serviceTimes) {
    if (typeof st.weekday !== 'number') continue;
    if (st.weekday !== churchWeekday) continue;

    // Parse the start time — it may be an ISO string like "2000-01-02T10:00:00Z"
    // We only care about the hour/minute portion (treat as local clock time).
    let startMinutes = null;
    if (typeof st.start === 'string') {
      const match = st.start.match(/T(\d{2}):(\d{2})/);
      if (match) {
        startMinutes = parseInt(match[1], 10) * 60 + parseInt(match[2], 10);
      }
    }
    if (startMinutes === null) continue;

    if (nowMinutes >= startMinutes && nowMinutes < startMinutes + SERVICE_WINDOW_MINUTES) {
      return true;
    }
  }
  return false;
}

// ─── Shape a Firestore doc into a ChurchRecord ────────────────────────────────

/**
 * Map a Firestore document + computed fields to the ChurchRecord shape
 * expected by Phase0Contracts.swift.
 *
 * @param {FirebaseFirestore.DocumentSnapshot} doc
 * @param {number|null} distanceMeters
 * @returns {object}
 */
function toChurchRecord(doc, distanceMeters) {
  const data = doc.data();
  const serviceTimes = data.serviceTimes ?? [];
  return {
    id: doc.id,
    name: data.name ?? '',
    denomination: data.denomination ?? null,
    coordinate: {
      latitude: data.location?.latitude ?? null,
      longitude: data.location?.longitude ?? null,
    },
    address: data.address ?? '',
    serviceTimes,
    distanceMeters: distanceMeters ?? null,
    rating: data.rating ?? null,
    isOpenNow: computeIsOpenNow(serviceTimes),
    verified: data.verified ?? false,
  };
}

// ─── Validate + sanitise input ────────────────────────────────────────────────

function validateInput(data) {
  if (!data || typeof data !== 'object') {
    throw new HttpsError('invalid-argument', 'Request data must be an object.');
  }
  // query is required but may be an empty string (browse mode)
  if (typeof data.query !== 'string') {
    throw new HttpsError('invalid-argument', 'query must be a string.');
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
      query = '',
      lat,
      lng,
      openNow,
      denomination,
      maxDistanceMeters = 40000,
      sortBy = 'bestMatch',
    } = data;

    const hasGeo = typeof lat === 'number' && isFinite(lat) &&
                   typeof lng === 'number' && isFinite(lng);
    const hasTextQuery = query.trim().length > 0;

    // 3. Build Firestore query
    let firestoreQuery = db.collection('churches').where('isActive', '==', true);

    // Denomination filter — safe to add before the range filter
    if (denomination) {
      firestoreQuery = firestoreQuery.where('denomination', '==', denomination);
    }

    let docs = [];

    if (hasGeo) {
      // Geo bounding-box: filter on location.latitude (single range field)
      // Longitude range is applied post-fetch (Firestore limitation: only one
      // inequality field per query).
      const latRad = (lat * Math.PI) / 180;
      const { latDelta, lngDelta } = boundingBoxDeltas(maxDistanceMeters, latRad);
      const minLat = lat - latDelta;
      const maxLat = lat + latDelta;
      const minLng = lng - lngDelta;
      const maxLng = lng + lngDelta;

      const snapshot = await firestoreQuery
        .where('location.latitude', '>=', minLat)
        .where('location.latitude', '<=', maxLat)
        .limit(200)
        .get();

      // Post-filter: longitude range + compute Haversine distance
      for (const doc of snapshot.docs) {
        const d = doc.data();
        const docLng = d.location?.longitude;
        if (typeof docLng !== 'number') continue;
        if (docLng < minLng || docLng > maxLng) continue;

        const dist = haversineMeters(lat, lng, d.location.latitude, docLng);
        if (dist > maxDistanceMeters) continue; // prune bounding-box corners

        docs.push({ doc, distanceMeters: dist });
      }
    } else {
      // No geo — text search only: fetch up to 50 active churches and
      // post-filter by query string if non-empty.
      const snapshot = await firestoreQuery.limit(50).get();
      for (const doc of snapshot.docs) {
        docs.push({ doc, distanceMeters: null });
      }
    }

    // 4. Text search post-filter (applied whenever a query is present, regardless
    //    of whether geo was used, so users can narrow geo results by name too).
    if (hasTextQuery) {
      const q = query.trim().toLowerCase();
      docs = docs.filter(({ doc }) => {
        const d = doc.data();
        const name = (d.name ?? '').toLowerCase();
        const address = (d.address ?? '').toLowerCase();
        return name.includes(q) || address.includes(q);
      });
    }

    // 5. Shape results into ChurchRecord objects
    let results = docs.map(({ doc, distanceMeters }) =>
      toChurchRecord(doc, distanceMeters)
    );

    // 6. openNow filter
    if (openNow === true) {
      results = results.filter((c) => c.isOpenNow === true);
    }

    // 7. Sort
    if (sortBy === 'distance') {
      results.sort((a, b) => (a.distanceMeters ?? Infinity) - (b.distanceMeters ?? Infinity));
    } else if (sortBy === 'rating') {
      results.sort((a, b) => (b.rating ?? 0) - (a.rating ?? 0));
    } else {
      // bestMatch: when geo is available prefer distance, otherwise keep Firestore
      // natural order (most recently created first tends to be most relevant).
      if (hasGeo) {
        results.sort((a, b) => (a.distanceMeters ?? Infinity) - (b.distanceMeters ?? Infinity));
      }
      // Without geo, Firestore fetch order is used as-is.
    }

    return { churches: results };
  }
);
