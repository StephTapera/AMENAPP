import { DiscoverItemDoc, DiscoverMetadata } from "./discoverTypes";

export function isDiscoverEligible(item: DiscoverItemDoc, meta: DiscoverMetadata): boolean {
  if (item.discoverVisibility === "hidden") return false;
  if (!meta.recommendationEligible) return false;
  if (meta.moderationStatus !== "approved") return false;
  if (meta.safetyCategory === "blocked" || meta.safetyCategory === "restricted_from_discover") return false;
  return true;
}
