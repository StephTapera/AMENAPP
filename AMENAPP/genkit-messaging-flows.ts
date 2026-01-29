// File: genkit/src/messaging-flows.ts
//
// AI-powered messaging features for AMENAPP
// Add these flows to your existing berean-flows.ts or create a new file

import { genkit, z } from 'genkit';
import { firebase } from '@genkit-ai/firebase';
import { googleAI, gemini15Flash } from '@genkit-ai/google-ai';

const ai = genkit({
  plugins: [
    firebase(),
    googleAI({ apiKey: process.env.GOOGLE_API_KEY }),
  ],
});

// =============================================================================
// FLOW: Generate Ice Breakers
// =============================================================================

export const generateIceBreakers = ai.defineFlow(
  {
    name: 'generateIceBreakers',
    inputSchema: z.object({
      recipientName: z.string(),
      recipientBio: z.string().optional(),
      sharedInterests: z.array(z.string()),
      context: z.string().default('first message'),
    }),
    outputSchema: z.object({
      suggestions: z.array(
        z.object({
          message: z.string(),
          context: z.string(),
          sharedInterest: z.string().optional(),
        })
      ),
    }),
  },
  async (input) => {
    const sharedInterestsText = input.sharedInterests.length > 0
      ? `You both share: ${input.sharedInterests.join(', ')}`
      : 'No shared interests identified yet';

    const prompt = `You are a Christian dating app assistant helping users start meaningful conversations.

Recipient: ${input.recipientName}
${input.recipientBio ? `Bio: ${input.recipientBio}` : ''}
${sharedInterestsText}
Context: ${input.context}

Generate 3 warm, faith-centered ice breaker messages that:
- Reference shared interests when available
- Are friendly and respectful
- Include a question to encourage response
- Are 1-2 sentences max
- Feel natural, not formulaic
- Reflect Christian values

Return JSON with array of suggestions, each with: message, context, sharedInterest (if applicable)`;

    const result = await ai.generate({
      model: gemini15Flash,
      prompt,
      config: { temperature: 0.8 },
    });

    try {
      const jsonMatch = result.text().match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        return JSON.parse(jsonMatch[0]);
      }
    } catch (e) {
      console.warn('Failed to parse JSON, using fallback');
    }

    // Fallback
    return {
      suggestions: [
        {
          message: `Hi ${input.recipientName}! I noticed we both share an interest in ${input.sharedInterests[0] || 'faith'}. What drew you to AMEN?`,
          context: 'Shared interest opener',
          sharedInterest: input.sharedInterests[0],
        },
      ],
    };
  }
);

// =============================================================================
// FLOW: Generate Smart Replies
// =============================================================================

export const generateSmartReplies = ai.defineFlow(
  {
    name: 'generateSmartReplies',
    inputSchema: z.object({
      message: z.string(),
      conversationHistory: z.array(
        z.object({
          role: z.string(),
          content: z.string(),
        })
      ).optional(),
      recipientName: z.string(),
    }),
    outputSchema: z.object({
      replies: z.array(
        z.object({
          text: z.string(),
          type: z.enum(['response', 'question', 'encouragement', 'scriptural']),
        })
      ),
    }),
  },
  async (input) => {
    const historyText = input.conversationHistory
      ? input.conversationHistory.map(h => `${h.role}: ${h.content}`).join('\n')
      : 'No history';

    const prompt = `You are a Christian dating app assistant helping craft thoughtful responses.

Recent message from ${input.recipientName}:
"${input.message}"

Conversation history:
${historyText}

Generate 3 different reply options that are:
- Warm and genuine
- Appropriate for Christian dating
- Keep conversation flowing
- Show interest in them
- Max 2 sentences each

Include these types:
1. Direct response (answer their message)
2. Follow-up question (learn more about them)
3. Encouraging/supportive message

Return JSON with replies array, each with: text, type`;

    const result = await ai.generate({
      model: gemini15Flash,
      prompt,
      config: { temperature: 0.7 },
    });

    try {
      const jsonMatch = result.text().match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        return JSON.parse(jsonMatch[0]);
      }
    } catch (e) {
      console.warn('Failed to parse JSON, using fallback');
    }

    // Fallback
    return {
      replies: [
        {
          text: "That's wonderful! Tell me more about that.",
          type: 'question',
        },
        {
          text: "I appreciate you sharing that with me.",
          type: 'response',
        },
      ],
    };
  }
);

// =============================================================================
// FLOW: Analyze Conversation
// =============================================================================

export const analyzeConversation = ai.defineFlow(
  {
    name: 'analyzeConversation',
    inputSchema: z.object({
      messages: z.array(
        z.object({
          sender: z.string(),
          text: z.string(),
          timestamp: z.number(),
        })
      ),
      participants: z.array(z.string()),
    }),
    outputSchema: z.object({
      title: z.string(),
      insight: z.string(),
      tone: z.enum(['encouraging', 'prayerful', 'friendly', 'supportive', 'conversational']),
      scriptureReference: z.string().optional(),
      actionItems: z.array(z.string()),
    }),
  },
  async (input) => {
    const messagesText = input.messages
      .slice(-10)
      .map(m => `${m.sender}: ${m.text}`)
      .join('\n');

    const prompt = `Analyze this conversation from a Christian dating app:

Participants: ${input.participants.join(', ')}

Recent messages:
${messagesText}

Provide:
1. Title (short summary of conversation theme)
2. Insight (what's going well, areas for deeper connection)
3. Tone (overall emotional tone)
4. Scripture reference (relevant verse if applicable)
5. Action items (suggestions for next steps)

Return JSON format`;

    const result = await ai.generate({
      model: gemini15Flash,
      prompt,
      config: { temperature: 0.6 },
    });

    try {
      const jsonMatch = result.text().match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        return JSON.parse(jsonMatch[0]);
      }
    } catch (e) {
      console.warn('Failed to parse JSON, using fallback');
    }

    return {
      title: 'Getting to Know Each Other',
      insight: 'You are building a foundation of trust and shared faith.',
      tone: 'friendly',
      actionItems: ['Continue asking thoughtful questions', 'Share more about your faith journey'],
    };
  }
);

// =============================================================================
// FLOW: Detect Message Tone
// =============================================================================

export const detectMessageTone = ai.defineFlow(
  {
    name: 'detectMessageTone',
    inputSchema: z.object({
      message: z.string(),
    }),
    outputSchema: z.object({
      tone: z.string(),
      confidence: z.number(),
      suggestions: z.array(z.string()),
    }),
  },
  async (input) => {
    const prompt = `Analyze the tone of this message: "${input.message}"

Identify:
- Primary tone (joyful, sad, anxious, grateful, questioning, etc.)
- Confidence level (0-1)
- 2-3 suggestions for responding appropriately

Return JSON format`;

    const result = await ai.generate({
      model: gemini15Flash,
      prompt,
    });

    try {
      const jsonMatch = result.text().match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        return JSON.parse(jsonMatch[0]);
      }
    } catch (e) {
      console.warn('Failed to parse JSON');
    }

    return {
      tone: 'neutral',
      confidence: 0.5,
      suggestions: ['Respond with empathy', 'Ask a follow-up question'],
    };
  }
);

// =============================================================================
// FLOW: Suggest Scripture for Message
// =============================================================================

export const suggestScriptureForMessage = ai.defineFlow(
  {
    name: 'suggestScriptureForMessage',
    inputSchema: z.object({
      context: z.string(),
      mood: z.string().default('encouraging'),
    }),
    outputSchema: z.object({
      verses: z.array(
        z.object({
          reference: z.string(),
          text: z.string(),
          reason: z.string(),
        })
      ),
    }),
  },
  async (input) => {
    const prompt = `Find 2-3 relevant Bible verses for this conversation context:
"${input.context}"

Mood: ${input.mood}

For each verse provide:
- reference (book chapter:verse)
- text (the actual verse)
- reason (why it's relevant to this conversation)

Return JSON format`;

    const result = await ai.generate({
      model: gemini15Flash,
      prompt,
    });

    try {
      const jsonMatch = result.text().match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        return JSON.parse(jsonMatch[0]);
      }
    } catch (e) {
      console.warn('Failed to parse JSON');
    }

    return {
      verses: [
        {
          reference: 'Proverbs 3:5-6',
          text: 'Trust in the LORD with all your heart...',
          reason: 'Encourages faith and trust',
        },
      ],
    };
  }
);

// =============================================================================
// FLOW: Enhance Message
// =============================================================================

export const enhanceMessage = ai.defineFlow(
  {
    name: 'enhanceMessage',
    inputSchema: z.object({
      message: z.string(),
      style: z.enum(['encouraging', 'friendly', 'spiritual', 'professional']),
    }),
    outputSchema: z.object({
      enhancedMessage: z.string(),
    }),
  },
  async (input) => {
    const prompt = `Enhance this message to be more ${input.style}:
"${input.message}"

Guidelines:
- Keep the core meaning
- Make it ${input.style} in tone
- Max 3 sentences
- Natural and conversational
- Appropriate for Christian dating

Return just the enhanced message, no explanation`;

    const result = await ai.generate({
      model: gemini15Flash,
      prompt,
      config: { temperature: 0.7 },
    });

    return {
      enhancedMessage: result.text().trim().replace(/^["']|["']$/g, ''),
    };
  }
);

// =============================================================================
// FLOW: Detect Prayer Request
// =============================================================================

export const detectPrayerRequest = ai.defineFlow(
  {
    name: 'detectPrayerRequest',
    inputSchema: z.object({
      message: z.string(),
    }),
    outputSchema: z.object({
      isPrayerRequest: z.boolean(),
      confidence: z.number(),
      suggestedResponse: z.string().optional(),
      prayerPoints: z.array(z.string()),
    }),
  },
  async (input) => {
    const prompt = `Analyze if this message contains a prayer request:
"${input.message}"

Determine:
- isPrayerRequest (true/false)
- confidence (0-1)
- suggestedResponse (how to respond if it is)
- prayerPoints (what to pray for)

Return JSON format`;

    const result = await ai.generate({
      model: gemini15Flash,
      prompt,
    });

    try {
      const jsonMatch = result.text().match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        return JSON.parse(jsonMatch[0]);
      }
    } catch (e) {
      console.warn('Failed to parse JSON');
    }

    return {
      isPrayerRequest: false,
      confidence: 0,
      prayerPoints: [],
    };
  }
);
