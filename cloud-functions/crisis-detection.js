/**
 * Vertex AI Crisis Detection Cloud Function
 *
 * Analyzes text for crisis indicators and provides appropriate resources
 */

const {onCall} = require("firebase-functions/v2/https");
const {VertexAI} = require("@google-cloud/vertexai");

// Initialize Vertex AI
const vertexAI = new VertexAI({
  project: process.env.GCLOUD_PROJECT,
  location: "us-central1",
});

const model = vertexAI.getGenerativeModel({
  model: "gemini-1.5-flash",
});

/**
 * Detect crisis indicators in text
 */
exports.detectCrisis = onCall(
    {
      region: "us-central1",
      memory: "512MiB",
      timeoutSeconds: 30,
    },
    async (request) => {
      const {text, userId} = request.data;

      if (!text) {
        throw new Error("Text is required");
      }

      console.log(`🔍 [CRISIS DETECTION] Analyzing text for user: ${userId}`);

      const prompt = `You are a mental health crisis detection AI. Analyze this text for crisis indicators.

Check for:
1. Suicidal ideation (thoughts of death, suicide)
2. Self-harm indicators (cutting, hurting oneself)
3. Severe depression or hopelessness
4. Violence or threats to others
5. Substance abuse crisis
6. Panic or severe anxiety

Text: "${text}"

Respond in JSON format:
{
  "level": "none|low|medium|high|critical",
  "confidence": 0.0-1.0,
  "indicators": ["indicator1", "indicator2"],
  "recommendedActions": ["action1", "action2"],
  "resourceLinks": ["link1", "link2"],
  "shouldAlert": true/false
}

Guidelines:
- "critical": Immediate life-threatening danger (suicide, self-harm)
- "high": Serious risk requiring urgent intervention
- "medium": Significant distress, professional help recommended
- "low": Mild stress or worry
- "none": No crisis indicators

Be sensitive and err on the side of caution. If unsure, classify as higher risk.`;

      try {
        const result = await model.generateContent({
          contents: [{role: "user", parts: [{text: prompt}]}],
          generationConfig: {
            temperature: 0.1, // Low temperature for consistent, reliable results
            maxOutputTokens: 1024,
            responseMimeType: "application/json",
          },
        });

        const response = result.response;
        const analysisText = response.candidates[0].content.parts[0].text;
        const analysis = JSON.parse(analysisText);

        console.log(`✅ [CRISIS DETECTION] Level: ${analysis.level}, Confidence: ${analysis.confidence}`);

        // Add default crisis resources based on level
        if (analysis.level === "critical" || analysis.level === "high") {
          analysis.resourceLinks = [
            "https://988lifeline.org",
            "https://crisistextline.org",
            "https://www.samhsa.gov/find-help/national-helpline",
          ];

          if (analysis.level === "critical") {
            analysis.recommendedActions = [
              "Call 988 Suicide & Crisis Lifeline immediately",
              "Text HOME to 741741 for Crisis Text Line",
              "Go to nearest emergency room if in immediate danger",
              "Reach out to a trusted friend or family member now",
              ...analysis.recommendedActions,
            ];
            analysis.shouldAlert = true;
          }
        }

        return analysis;
      } catch (error) {
        console.error("❌ [CRISIS DETECTION] Error:", error);

        // Fallback response - assume medium risk if AI fails
        return {
          level: "medium",
          confidence: 0.5,
          indicators: ["Unable to fully analyze"],
          recommendedActions: [
            "If you're in crisis, call 988",
            "Consider talking to a mental health professional",
          ],
          resourceLinks: [
            "https://988lifeline.org",
          ],
          shouldAlert: false,
        };
      }
    }
);
