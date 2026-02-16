/**
 * AI Church Notes Features
 * - Scripture Cross-References
 * - Note Summarization
 *
 * Uses Google Vertex AI for intelligent scripture analysis
 */

const admin = require("firebase-admin");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {VertexAI} = require("@google-cloud/vertexai");

// Initialize Vertex AI
const vertex_ai = new VertexAI({
  project: "amen-5e359",
  location: "us-central1",
});

const model = "gemini-1.5-flash-002";

// ============================================================================
// SCRIPTURE CROSS-REFERENCE SERVICE
// ============================================================================

/**
 * Find related scripture verses using AI
 * Triggered when a new request is created in scriptureReferenceRequests
 */
exports.findScriptureReferences = onDocumentCreated(
    {
      document: "scriptureReferenceRequests/{requestId}",
      region: "us-central1",
    },
    async (event) => {
      const requestId = event.params.requestId;
      const requestData = event.data.data();
      const verse = requestData.verse;

      console.log(`📖 Scripture reference request: ${verse} (ID: ${requestId})`);

      try {
        // Prepare prompt for Vertex AI
        const prompt = `You are a Bible scholar. Given a Bible verse reference, find 5 related verses that connect thematically or theologically.

Input verse: "${verse}"

Return ONLY a JSON array with this exact structure (no markdown, no explanation):
[
  {
    "verse": "Romans 8:28",
    "description": "God works all things for good",
    "relevanceScore": 0.95
  }
]

Rules:
- Return exactly 5 verses
- relevanceScore must be between 0 and 1
- Each description must be under 50 characters
- Focus on theological connections, not just word matches`;

        const generativeModel = vertex_ai.getGenerativeModel({
          model: model,
        });

        const result = await generativeModel.generateContent({
          contents: [{role: "user", parts: [{text: prompt}]}],
          generationConfig: {
            maxOutputTokens: 1000,
            temperature: 0.3,
            topP: 0.8,
          },
        });

        const response = result.response;
        const text = response.candidates[0].content.parts[0].text.trim();

        console.log(`🤖 AI Response: ${text.substring(0, 200)}...`);

        // Parse JSON response
        let references;
        try {
          // Remove markdown code blocks if present
          const cleanedText = text.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
          references = JSON.parse(cleanedText);
        } catch (parseError) {
          console.error("❌ Failed to parse AI response as JSON:", parseError);
          // Fallback to empty array
          references = [];
        }

        // Validate and clean up references
        references = references
            .filter((ref) =>
              ref.verse &&
            ref.description &&
            typeof ref.relevanceScore === "number",
            )
            .slice(0, 5); // Ensure max 5 references

        // Store results in Firestore
        await admin.firestore()
            .collection("scriptureReferenceResults")
            .doc(requestId)
            .set({
              references: references,
              originalVerse: verse,
              processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

        console.log(`✅ Found ${references.length} scripture references for ${verse}`);
        return {success: true, count: references.length};
      } catch (error) {
        console.error(`❌ Error finding scripture references:`, error);

        // Store error result so client doesn't timeout
        await admin.firestore()
            .collection("scriptureReferenceResults")
            .doc(requestId)
            .set({
              references: [],
              originalVerse: verse,
              error: error.message,
              processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

        return {success: false, error: error.message};
      }
    },
);

// ============================================================================
// NOTE SUMMARIZATION SERVICE
// ============================================================================

/**
 * Generate AI summary of sermon notes
 * Triggered when a new request is created in noteSummaryRequests
 */
exports.summarizeNote = onDocumentCreated(
    {
      document: "noteSummaryRequests/{requestId}",
      region: "us-central1",
    },
    async (event) => {
      const requestId = event.params.requestId;
      const requestData = event.data.data();
      const content = requestData.content;

      console.log(`📝 Note summary request (${content.length} chars, ID: ${requestId})`);

      try {
        // Prepare prompt for Vertex AI
        const prompt = `You are a pastoral assistant helping analyze sermon notes. Analyze the following church note and provide a structured summary.

Note content:
"""
${content}
"""

Return ONLY a JSON object with this exact structure (no markdown, no explanation):
{
  "mainTheme": "Brief 1-sentence main theme",
  "scripture": ["John 3:16", "Romans 8:28"],
  "keyPoints": [
    "First key point",
    "Second key point",
    "Third key point"
  ],
  "actionSteps": [
    "First practical action",
    "Second practical action"
  ]
}

Rules:
- mainTheme: Single sentence, max 100 characters
- scripture: Array of 1-5 verse references mentioned
- keyPoints: 2-5 main takeaways from the sermon
- actionSteps: 1-3 practical applications
- Keep each point concise (under 100 characters)`;

        const generativeModel = vertex_ai.getGenerativeModel({
          model: model,
        });

        const result = await generativeModel.generateContent({
          contents: [{role: "user", parts: [{text: prompt}]}],
          generationConfig: {
            maxOutputTokens: 1500,
            temperature: 0.4,
            topP: 0.9,
          },
        });

        const response = result.response;
        const text = response.candidates[0].content.parts[0].text.trim();

        console.log(`🤖 AI Response: ${text.substring(0, 200)}...`);

        // Parse JSON response
        let summary;
        try {
          // Remove markdown code blocks if present
          const cleanedText = text.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
          summary = JSON.parse(cleanedText);
        } catch (parseError) {
          console.error("❌ Failed to parse AI response as JSON:", parseError);
          // Fallback summary
          summary = {
            mainTheme: "Unable to generate summary",
            scripture: [],
            keyPoints: [],
            actionSteps: [],
          };
        }

        // Validate summary structure
        summary = {
          mainTheme: summary.mainTheme || "No theme identified",
          scripture: Array.isArray(summary.scripture) ? summary.scripture.slice(0, 5) : [],
          keyPoints: Array.isArray(summary.keyPoints) ? summary.keyPoints.slice(0, 5) : [],
          actionSteps: Array.isArray(summary.actionSteps) ? summary.actionSteps.slice(0, 3) : [],
        };

        // Store results in Firestore
        await admin.firestore()
            .collection("noteSummaryResults")
            .doc(requestId)
            .set({
              ...summary,
              processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

        console.log(`✅ Generated summary for note: "${summary.mainTheme}"`);
        return {success: true, mainTheme: summary.mainTheme};
      } catch (error) {
        console.error(`❌ Error summarizing note:`, error);

        // Store error result so client doesn't timeout
        await admin.firestore()
            .collection("noteSummaryResults")
            .doc(requestId)
            .set({
              mainTheme: "Error generating summary",
              scripture: [],
              keyPoints: [],
              actionSteps: [],
              error: error.message,
              processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

        return {success: false, error: error.message};
      }
    },
);
