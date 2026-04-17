/**
 * Topic Enrichment Cloud Function (System 11)
 *
 * Belt-and-suspenders: enriches posts with normalizedTopicKeys
 * if the iOS client didn't set them at creation time.
 *
 * Trigger: onDocumentCreated for posts/{postId}
 * Region: us-central1
 */

const admin = require("firebase-admin");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");

const db = admin.firestore();

// ============================================================================
// Cluster keyword map — mirrors SemanticTopicService on iOS
// ============================================================================
const CLUSTER_KEYWORDS = {
  scripture: [
    "bible", "scripture", "verse", "chapter", "psalm",
    "proverbs", "gospel", "genesis", "exodus", "revelation",
    "testament", "devotional", "word of god",
  ],
  prayer: [
    "prayer", "pray", "praying", "intercession", "petition",
    "supplication", "prayer request", "prayer wall",
  ],
  testimony: [
    "testimony", "testimonies", "praise report", "god story",
    "answered prayer", "miracle", "breakthrough",
  ],
  discipleship: [
    "discipleship", "mentor", "accountability", "spiritual growth",
    "small group", "bible study", "follow jesus",
  ],
  worship: [
    "worship", "praise", "hymn", "song", "singing",
    "adoration", "glorify",
  ],
  theology: [
    "theology", "doctrine", "apologetics", "hermeneutics",
    "systematic", "reformed", "calvinist", "arminian",
  ],
  community: [
    "community", "fellowship", "church family", "small groups",
    "congregation", "body of christ",
  ],
  "faith-and-work": [
    "faith and work", "marketplace", "vocation", "career",
    "workplace", "calling", "profession",
  ],
  "mental-health": [
    "mental health", "anxiety", "depression", "wellness",
    "self care", "therapy", "counseling", "stress",
  ],
  family: [
    "family", "parenting", "marriage", "children", "husband",
    "wife", "relationship", "home",
  ],
  evangelism: [
    "evangelism", "missions", "outreach", "share faith",
    "gospel", "witness", "unreached",
  ],
  servanthood: [
    "serving", "service", "volunteer", "ministry",
    "helping", "servant", "missions",
  ],
  grief: [
    "grief", "loss", "mourning", "bereavement",
    "passing", "death", "comfort",
  ],
  healing: [
    "healing", "restoration", "recovery", "deliverance",
    "wholeness", "renew",
  ],
  prophetic: [
    "prophetic", "prophecy", "revelation", "vision",
    "word from god", "dream",
  ],
};

// ============================================================================
// ENRICH POST TOPICS
// ============================================================================
exports.enrichPostTopics = onDocumentCreated(
    {
      document: "posts/{postId}",
      region: "us-central1",
    },
    async (event) => {
      const postId = event.params.postId;
      const data = event.data.data();

      // Skip if client already enriched
      if (data.normalizedTopicKeys &&
          Array.isArray(data.normalizedTopicKeys) &&
          data.normalizedTopicKeys.length > 0) {
        return null;
      }

      const content = data.content;
      if (!content || typeof content !== "string" || content.trim().length === 0) {
        return null;
      }

      console.log(`🏷️ Enriching topics for post ${postId} (server-side fallback)`);

      try {
        const lower = content.toLowerCase();
        const scoreMap = {};
        const keys = [];

        for (const [cluster, keywords] of Object.entries(CLUSTER_KEYWORDS)) {
          const matchCount = keywords.filter((kw) => lower.includes(kw)).length;
          if (matchCount === 0) continue;

          const confidence = Math.min(1.0, (matchCount / 3) * 0.8 + 0.20);
          scoreMap[cluster] = confidence;
          keys.push(cluster);
        }

        if (keys.length === 0) {
          keys.push("general");
          scoreMap["general"] = 0.10;
        }

        // Sort by confidence descending
        keys.sort((a, b) => (scoreMap[b] || 0) - (scoreMap[a] || 0));

        const updateData = {
          normalizedTopicKeys: keys,
          topicScoreMap: scoreMap,
          primaryTopicKey: keys[0] || null,
        };

        await db.collection("posts").doc(postId).update(updateData);
        console.log(`✅ Enriched post ${postId} with topics: [${keys.join(", ")}]`);
        return {success: true};
      } catch (error) {
        console.error(`❌ Error enriching topics for post ${postId}:`, error);
        return null;
      }
    },
);
