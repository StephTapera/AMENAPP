// geo.ts — geohash query bounds + distance, via geofire-common (spec §3).
//
// Geohash queries use geofire-common so Firestore range queries on
// `location.geohash` match the standard encoding (precision 9). Radius is
// clamped to [1000, 80000] m before any query. Approximate-location churches
// are coarsened so exact lat/lng never reaches a client.

import { geohashQueryBounds, distanceBetween } from "geofire-common";
import { RADIUS_CLAMP_METERS } from "./ranking";

export type LatLng = { lat: number; lng: number };

/** Clamp radius to the server-enforced window. */
export function clampRadius(radiusMeters: number): number {
  if (!Number.isFinite(radiusMeters)) return RADIUS_CLAMP_METERS.min;
  return Math.min(RADIUS_CLAMP_METERS.max, Math.max(RADIUS_CLAMP_METERS.min, radiusMeters));
}

/** Validate a client-supplied center; throws-style callers map to invalid-argument. */
export function isValidCenter(center: unknown): center is LatLng {
  if (typeof center !== "object" || center === null) return false;
  const c = center as Record<string, unknown>;
  return typeof c.lat === "number" && typeof c.lng === "number" &&
    c.lat >= -90 && c.lat <= 90 && c.lng >= -180 && c.lng <= 180;
}

/** geofire-common bounds for [center, radius]; each is a [start,end] geohash. */
export function queryBounds(center: LatLng, radiusMeters: number): string[][] {
  return geohashQueryBounds([center.lat, center.lng], clampRadius(radiusMeters));
}

/** Exact great-circle distance in METERS (geofire returns km). */
export function distanceMeters(a: LatLng, b: LatLng): number {
  return distanceBetween([a.lat, a.lng], [b.lat, b.lng]) * 1000;
}

/**
 * Coarsen a distance for display when the church is approximate-location-only.
 * Snaps to ~1 km buckets so the exact figure can't be back-solved to a precise
 * pin. (§5.1 — exact location never leaves the server for approx churches.)
 */
export function coarsenDistanceMeters(meters: number, approxOnly: boolean): number {
  if (!approxOnly) return Math.round(meters);
  return Math.round(meters / 1000) * 1000;
}

/**
 * Coarse geohash (≤ precision 6, ~1.2 km cell) for anything that may be logged
 * or shared. Used to avoid persisting a precise user location (§5.1).
 */
export function coarseGeohash(geohash: string): string {
  return (geohash || "").slice(0, 6);
}
