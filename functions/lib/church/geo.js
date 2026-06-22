"use strict";
// geo.ts — geohash query bounds + distance, via geofire-common (spec §3).
//
// Geohash queries use geofire-common so Firestore range queries on
// `location.geohash` match the standard encoding (precision 9). Radius is
// clamped to [1000, 80000] m before any query. Approximate-location churches
// are coarsened so exact lat/lng never reaches a client.
Object.defineProperty(exports, "__esModule", { value: true });
exports.clampRadius = clampRadius;
exports.isValidCenter = isValidCenter;
exports.queryBounds = queryBounds;
exports.distanceMeters = distanceMeters;
exports.coarsenDistanceMeters = coarsenDistanceMeters;
exports.coarseGeohash = coarseGeohash;
const geofire_common_1 = require("geofire-common");
const ranking_1 = require("./ranking");
/** Clamp radius to the server-enforced window. */
function clampRadius(radiusMeters) {
    if (!Number.isFinite(radiusMeters))
        return ranking_1.RADIUS_CLAMP_METERS.min;
    return Math.min(ranking_1.RADIUS_CLAMP_METERS.max, Math.max(ranking_1.RADIUS_CLAMP_METERS.min, radiusMeters));
}
/** Validate a client-supplied center; throws-style callers map to invalid-argument. */
function isValidCenter(center) {
    if (typeof center !== "object" || center === null)
        return false;
    const c = center;
    return typeof c.lat === "number" && typeof c.lng === "number" &&
        c.lat >= -90 && c.lat <= 90 && c.lng >= -180 && c.lng <= 180;
}
/** geofire-common bounds for [center, radius]; each is a [start,end] geohash. */
function queryBounds(center, radiusMeters) {
    return (0, geofire_common_1.geohashQueryBounds)([center.lat, center.lng], clampRadius(radiusMeters));
}
/** Exact great-circle distance in METERS (geofire returns km). */
function distanceMeters(a, b) {
    return (0, geofire_common_1.distanceBetween)([a.lat, a.lng], [b.lat, b.lng]) * 1000;
}
/**
 * Coarsen a distance for display when the church is approximate-location-only.
 * Snaps to ~1 km buckets so the exact figure can't be back-solved to a precise
 * pin. (§5.1 — exact location never leaves the server for approx churches.)
 */
function coarsenDistanceMeters(meters, approxOnly) {
    if (!approxOnly)
        return Math.round(meters);
    return Math.round(meters / 1000) * 1000;
}
/**
 * Coarse geohash (≤ precision 6, ~1.2 km cell) for anything that may be logged
 * or shared. Used to avoid persisting a precise user location (§5.1).
 */
function coarseGeohash(geohash) {
    return (geohash || "").slice(0, 6);
}
