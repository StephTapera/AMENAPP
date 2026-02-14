/**
 * Cloud Functions 2nd Gen for Content Moderation
 *
 * Automatically moderates posts, comments, and messages using Vertex AI
 */

const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onCall} = require("firebase-functions/v2/https");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {VertexAI} = require("@google-cloud/vertexai");

initializeApp();
const db = getFirestore();

// Initialize Vertex AI
const vertexAI = new VertexAI({
  project: process.env.GCLOUD_PROJECT,
  location: "us-central1",
});

const model = vertexAI.getGenerativeModel({
  model: "gemini-1.5-flash",
});

/**
 * Moderate text content using Vertex AI
 */
async function moderateText(text) {
  const prompt = `Analyze this text for inappropriate content. Check for:
- Hate speech
- Explicit content
- Harassment or bullying
- Violence or threats
- Spam or scams
- Self-harm mentions

Text: "${text}"

Respond in JSON format:
{
  "isAppropriate": true/false,
  "reason": "explanation",
  "severity": "none|low|medium|high",
  "categories": ["category1", "category2"]
}`;

  try {
    const result = await model.generateContent({
      contents: [{role: "user", parts: [{text: prompt}]}],
      generationConfig: {
        temperature: 0.2,
        maxOutputTokens: 512,
        responseMimeType: "application/json",
      },
    });

    const response = result.response;
    const text = response.candidates[0].content.parts[0].text;
    return JSON.parse(text);
  } catch (error) {
    console.error("❌ Moderation error:", error);
    // Default to allowing if moderation fails
    return {
      isAppropriate: true,
      reason: "Moderation service unavailable",
      severity: "none",
      categories: [],
    };
  }
}

/**
 * Auto-moderate new posts
 */
exports.moderatePost = onDocumentCreated(
    {
      document: "posts/{postId}",
      region: "us-central1",
      memory: "512MiB",
      timeoutSeconds: 60,
    },
    async (event) => {
      const postData = event.data.data();
      const postId = event.params.postId;

      console.log(`🔍 Moderating post: ${postId}`);

      // Moderate text content
      const moderation = await moderateText(postData.text || "");

      // Update post with moderation result
      await event.data.ref.update({
        moderation: {
          isApproved: moderation.isAppropriate,
          reason: moderation.reason,
          severity: moderation.severity,
          categories: moderation.categories,
          moderatedAt: new Date().toISOString(),
        },
      });

      // Flag for manual review if inappropriate
      if (!moderation.isAppropriate) {
        console.log(`⚠️ Post ${postId} flagged: ${moderation.reason}`);

        await db.collection("moderationQueue").add({
          type: "post",
          contentId: postId,
          userId: postData.userId,
          text: postData.text,
          moderation: moderation,
          status: "pending",
          createdAt: new Date().toISOString(),
        });

        // Notify user if severe
        if (moderation.severity === "high") {
          await db.collection("notifications").add({
            userId: postData.userId,
            type: "moderation_warning",
            title: "Content Flagged",
            message: "Your post was flagged for review.",
            createdAt: new Date().toISOString(),
          });
        }
      }

      console.log(`✅ Post ${postId} moderated: ${moderation.isAppropriate ? "✓" : "✗"}`);
    }
);

/**
 * Auto-moderate new comments
 */
exports.moderateComment = onDocumentCreated(
    {
      document: "comments/{commentId}",
      region: "us-central1",
      memory: "256MiB",
      timeoutSeconds: 30,
    },
    async (event) => {
      const commentData = event.data.data();
      const commentId = event.params.commentId;

      console.log(`🔍 Moderating comment: ${commentId}`);

      const moderation = await moderateText(commentData.text || "");

      await event.data.ref.update({
        moderation: {
          isApproved: moderation.isAppropriate,
          reason: moderation.reason,
          moderatedAt: new Date().toISOString(),
        },
      });

      if (!moderation.isAppropriate && moderation.severity === "high") {
        // Auto-delete severe violations
        await event.data.ref.delete();
        console.log(`🗑️ Comment ${commentId} auto-deleted (severity: ${moderation.severity})`);
      }
    }
);

/**
 * Callable function for real-time moderation check
 */
exports.checkContent = onCall(
    {
      region: "us-central1",
      memory: "256MiB",
    },
    async (request) => {
      const {text} = request.data;

      if (!text) {
        throw new Error("Text is required");
      }

      console.log("🔍 Checking content for user input...");

      const moderation = await moderateText(text);

      return {
        isAppropriate: moderation.isAppropriate,
        reason: moderation.reason,
        severity: moderation.severity,
      };
    }
);
