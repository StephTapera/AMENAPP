import { DiscoverItemDoc } from "./discoverTypes";

export function applyDiversity(items: DiscoverItemDoc[]): DiscoverItemDoc[] {
  const creatorSeen = new Map<string, number>();
  const topicSeen = new Set<string>();
  const output: DiscoverItemDoc[] = [];

  for (const item of items) {
    const creatorId = item.author?.id ?? item.church?.id ?? "";
    const creatorCount = creatorSeen.get(creatorId) ?? 0;
    const hasTopicRepeat = (item.topics ?? []).some((t) => topicSeen.has(t));

    if (creatorId && creatorCount >= 2) continue;
    if (hasTopicRepeat && output.length > 6) continue;

    output.push(item);
    if (creatorId) creatorSeen.set(creatorId, creatorCount + 1);
    for (const topic of item.topics ?? []) topicSeen.add(topic);
  }

  return output;
}
