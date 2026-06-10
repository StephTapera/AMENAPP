/**
 * src/features/brief/index.ts — Daily Brief public surface.
 * AMEN Connected Intelligence v1, Agent B (Daily Brief).
 *
 * Mount <DailyBriefCard /> on the home surface. Pull-based, one-per-day cache,
 * server-enforced grants/minor/Sabbath/crisis/9-cap. NEVER a push notification.
 */

export { default as DailyBriefCard } from './DailyBriefCard';
export type { DailyBriefCardProps } from './DailyBriefCard';

export {
  fetchDailyBrief,
  totalItemCount,
  flattenItems,
  type BriefResult,
} from './briefService';
