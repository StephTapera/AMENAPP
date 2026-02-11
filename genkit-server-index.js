// ============================================================================
// AMEN App - Complete Genkit Server with All AI Flows
// ============================================================================

import { genkit, z } from 'genkit';
import { googleAI, gemini15Flash } from '@genkit-ai/googleai';

// Initialize Genkit with Google AI
const ai = genkit({
  plugins: [
    googleAI({
      apiKey: process.env.GOOGLE_AI_API_KEY,
    }),
  ],
});

// ============================================================================
// 1. BIBLE CHAT FLOW
// ============================================================================

export const bibleChat = ai.defineFlow(
  {
    name: 'bibleChat',
    inputSchema: z.object({
      message: z.string(),
      history: z.array(z.object({
        role: z.string(),
        content: z.string(),
      })).optional(),
    }),
    outputSchema: z.object({
      response: z.string(),
    }),
  },
  async (input) => {
    const { message, history = [] } = input;

    const systemPrompt = `You are a knowledgeable and compassionate Biblical AI assistant for the AMEN app.

Your purpose:
- Help users understand Scripture with historical and cultural context
- Answer theological questions with biblical accuracy
- Provide spiritual guidance rooted in Scripture
- Explore original Greek and Hebrew when relevant
- Always cite Scripture references (book, chapter, verse)

Guidelines:
- Respect different Christian traditions
- Be encouraging and faith-building
- Use clear, accessible language
- Focus on Jesus Christ as the center
- Admit when questions are beyond biblical scope

Tone: Warm, reverent, scholarly yet accessible`;

    // Build conversation context
    const messages = [
      { role: 'system', content: systemPrompt },
      ...history.map(h => ({ role: h.role, content: h.content })),
      { role: 'user', content: message },
    ];

    const response = await ai.generate({
      model: gemini15Flash,
      prompt: messages.map(m => m.content).join('\n\n'),
      config: {
        temperature: 0.7,
        maxOutputTokens: 1024,
      },
    });

    return {
      response: response.text(),
    };
  }
);

// ============================================================================
// 2. GENERATE DEVOTIONAL FLOW
// ============================================================================

export const generateDevotional = ai.defineFlow(
  {
    name: 'generateDevotional',
    inputSchema: z.object({
      topic: z.string().optional(),
    }),
    outputSchema: z.object({
      title: z.string(),
      scripture: z.string(),
      content: z.string(),
      prayer: z.string(),
    }),
  },
  async (input) => {
    const { topic } = input;

    const prompt = topic
      ? `Create a daily devotional on the topic of "${topic}".`
      : `Create an inspiring daily devotional for today.`;

    const fullPrompt = `${prompt}

Format your response as JSON with these fields:
{
  "title": "Engaging title for the devotional",
  "scripture": "Main verse with reference (e.g., John 3:16 - 'For God so loved...')",
  "content": "2-3 paragraphs of biblical insight and reflection",
  "prayer": "Short closing prayer (2-3 sentences)"
}

Make it personal, encouraging, and biblically sound.`;

    const response = await ai.generate({
      model: gemini15Flash,
      prompt: fullPrompt,
      config: {
        temperature: 0.8,
        maxOutputTokens: 1024,
      },
    });

    // Parse JSON response
    const text = response.text();
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    
    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      return {
        title: parsed.title || "Today's Devotional",
        scripture: parsed.scripture || "Philippians 4:13",
        content: parsed.content || text,
        prayer: parsed.prayer || "Lord, guide us through Your Word. Amen.",
      };
    }

    // Fallback if JSON parsing fails
    return {
      title: "Daily Devotional",
      scripture: "Philippians 4:13 - 'I can do all things through Christ who strengthens me.'",
      content: text,
      prayer: "Lord, strengthen us through Your Word. Amen.",
    };
  }
);

// ============================================================================
// 3. GENERATE STUDY PLAN FLOW
// ============================================================================

export const generateStudyPlan = ai.defineFlow(
  {
    name: 'generateStudyPlan',
    inputSchema: z.object({
      topic: z.string(),
      duration: z.number(),
    }),
    outputSchema: z.object({
      id: z.string(),
      title: z.string(),
      description: z.string(),
    }),
  },
  async (input) => {
    const { topic, duration } = input;

    const prompt = `Create a ${duration}-day Bible study plan on "${topic}".

For each day, provide:
1. Day number and title
2. Scripture readings (1-3 passages)
3. Key themes
4. Reflection questions (2-3)

Make it progressive, building knowledge day by day.
Keep it biblically comprehensive and engaging.

Format as a clear, structured plan.`;

    const response = await ai.generate({
      model: gemini15Flash,
      prompt: prompt,
      config: {
        temperature: 0.7,
        maxOutputTokens: 2048,
      },
    });

    return {
      id: `plan_${Date.now()}`,
      title: `${topic} - ${duration} Day Study`,
      description: response.text(),
    };
  }
);

// ============================================================================
// 4. ANALYZE SCRIPTURE FLOW
// ============================================================================

export const analyzeScripture = ai.defineFlow(
  {
    name: 'analyzeScripture',
    inputSchema: z.object({
      reference: z.string(),
      analysisType: z.string(),
    }),
    outputSchema: z.object({
      analysis: z.string(),
    }),
  },
  async (input) => {
    const { reference, analysisType } = input;

    const prompts = {
      Contextual: `Provide a comprehensive contextual analysis of ${reference}.

Include:
1. Historical context (when, where, who)
2. Cultural background
3. Literary context (what comes before/after)
4. Purpose of the passage
5. How it fits in the broader biblical narrative`,

      Thematic: `Analyze the themes in ${reference}.

Include:
1. Main themes
2. Supporting themes
3. Related passages with similar themes
4. How these themes appear throughout Scripture
5. Theological significance`,

      Linguistic: `Provide a linguistic analysis of ${reference}.

Include:
1. Key Greek/Hebrew words and their meanings
2. Transliteration and pronunciation
3. Word studies (how these words are used elsewhere)
4. Nuances lost in translation
5. Literary devices used`,

      'Cross-References': `Find and explain cross-references for ${reference}.

Include:
1. Direct quotations or allusions
2. Parallel passages
3. Thematically related verses
4. Fulfillment passages (if prophecy)
5. How these connections deepen understanding`,
    };

    const prompt = prompts[analysisType] || prompts.Contextual;

    const response = await ai.generate({
      model: gemini15Flash,
      prompt: prompt,
      config: {
        temperature: 0.7,
        maxOutputTokens: 1536,
      },
    });

    return {
      analysis: response.text(),
    };
  }
);

// ============================================================================
// 5. GENERATE MEMORY AID FLOW
// ============================================================================

export const generateMemoryAid = ai.defineFlow(
  {
    name: 'generateMemoryAid',
    inputSchema: z.object({
      verse: z.string(),
      reference: z.string(),
    }),
    outputSchema: z.object({
      techniques: z.string(),
    }),
  },
  async (input) => {
    const { verse, reference } = input;

    const prompt = `Help users memorize this verse: "${verse}" (${reference})

Provide:
1. Mnemonic device (memory trick)
2. Word associations
3. Visualization suggestion
4. Breaking it into chunks
5. Repetition pattern
6. Application to help remember it

Make it practical and easy to use.`;

    const response = await ai.generate({
      model: gemini15Flash,
      prompt: prompt,
      config: {
        temperature: 0.8,
        maxOutputTokens: 1024,
      },
    });

    return {
      techniques: response.text(),
    };
  }
);

// ============================================================================
// 6. GENERATE INSIGHTS FLOW
// ============================================================================

export const generateInsights = ai.defineFlow(
  {
    name: 'generateInsights',
    inputSchema: z.object({
      topic: z.string().optional(),
    }),
    outputSchema: z.object({
      insights: z.array(z.object({
        title: z.string(),
        verse: z.string(),
        content: z.string(),
        icon: z.string(),
      })),
    }),
  },
  async (input) => {
    const { topic } = input;

    const prompt = topic
      ? `Provide 5 biblical insights about "${topic}".`
      : `Provide 5 inspiring biblical insights for today.`;

    const fullPrompt = `${prompt}

For each insight, provide:
1. Title (concise and clear)
2. Key Scripture reference
3. Brief explanation (2-3 sentences)
4. Icon name (like "lightbulb.fill", "heart.fill", "star.fill")

Format as JSON array:
[
  {
    "title": "Insight Title",
    "verse": "John 3:16",
    "content": "Explanation text...",
    "icon": "lightbulb.fill"
  }
]

Make them practical and encouraging.`;

    const response = await ai.generate({
      model: gemini15Flash,
      prompt: fullPrompt,
      config: {
        temperature: 0.8,
        maxOutputTokens: 1536,
      },
    });

    // Try to parse JSON
    const text = response.text();
    const jsonMatch = text.match(/\[[\s\S]*\]/);
    
    if (jsonMatch) {
      try {
        const insights = JSON.parse(jsonMatch[0]);
        return { insights };
      } catch (e) {
        // Fallback
      }
    }

    // Fallback insights
    return {
      insights: [
        {
          title: "God's Love",
          verse: "John 3:16",
          content: "God's love for us is unconditional and eternal. He gave His only Son so that we might have eternal life.",
          icon: "heart.fill",
        },
      ],
    };
  }
);

// ============================================================================
// 7. GENERATE FUN BIBLE FACT FLOW
// ============================================================================

export const generateFunBibleFact = ai.defineFlow(
  {
    name: 'generateFunBibleFact',
    inputSchema: z.object({
      category: z.string().optional(),
    }),
    outputSchema: z.object({
      fact: z.string(),
    }),
  },
  async (input) => {
    const { category = 'random' } = input;

    const prompt = `Generate a fascinating and surprising Bible fact.

Category: ${category}

The fact should be:
- Historically accurate
- Interesting and engaging
- Something most people don't know
- Appropriate for all ages
- 2-3 sentences long

Include the biblical reference if applicable.`;

    const response = await ai.generate({
      model: gemini15Flash,
      prompt: prompt,
      config: {
        temperature: 0.9,
        maxOutputTokens: 256,
      },
    });

    return {
      fact: response.text(),
    };
  }
);

// ============================================================================
// 8. GENERATE SEARCH SUGGESTIONS FLOW
// ============================================================================

export const generateSearchSuggestions = ai.defineFlow(
  {
    name: 'generateSearchSuggestions',
    inputSchema: z.object({
      query: z.string(),
      context: z.string().optional(),
    }),
    outputSchema: z.object({
      suggestions: z.array(z.string()),
      relatedTopics: z.array(z.string()),
    }),
  },
  async (input) => {
    const { query, context = 'general' } = input;

    const prompt = `For the search query "${query}" in a Bible study app:

Provide:
1. 5 search suggestions (related queries users might want to try)
2. 5 related biblical topics

Format as JSON:
{
  "suggestions": ["suggestion 1", "suggestion 2", ...],
  "relatedTopics": ["topic 1", "topic 2", ...]
}`;

    const response = await ai.generate({
      model: gemini15Flash,
      prompt: prompt,
      config: {
        temperature: 0.7,
        maxOutputTokens: 512,
      },
    });

    const text = response.text();
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    
    if (jsonMatch) {
      try {
        const parsed = JSON.parse(jsonMatch[0]);
        return {
          suggestions: parsed.suggestions || [],
          relatedTopics: parsed.relatedTopics || [],
        };
      } catch (e) {
        // Fallback
      }
    }

    return {
      suggestions: [`More about ${query}`, `${query} in context`, `${query} explained`],
      relatedTopics: [`Biblical ${query}`, `Scripture on ${query}`],
    };
  }
);

// ============================================================================
// 9. ENHANCE BIBLICAL SEARCH FLOW
// ============================================================================

export const enhanceBiblicalSearch = ai.defineFlow(
  {
    name: 'enhanceBiblicalSearch',
    inputSchema: z.object({
      query: z.string(),
      type: z.string(),
    }),
    outputSchema: z.object({
      summary: z.string(),
      keyVerses: z.array(z.string()),
      relatedPeople: z.array(z.string()),
      funFacts: z.array(z.string()),
    }),
  },
  async (input) => {
    const { query, type } = input;

    const prompt = `Enhance this biblical search for a ${type}: "${query}"

Provide:
1. A brief summary (2-3 sentences)
2. 3-5 key Bible verses (just references like "John 3:16")
3. 3-5 related biblical people
4. 2-3 fun facts

Format as JSON:
{
  "summary": "Summary text...",
  "keyVerses": ["John 3:16", "Romans 8:28"],
  "relatedPeople": ["Moses", "David"],
  "funFacts": ["Fact 1", "Fact 2"]
}`;

    const response = await ai.generate({
      model: gemini15Flash,
      prompt: prompt,
      config: {
        temperature: 0.7,
        maxOutputTokens: 1024,
      },
    });

    const text = response.text();
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    
    if (jsonMatch) {
      try {
        const parsed = JSON.parse(jsonMatch[0]);
        return {
          summary: parsed.summary || "",
          keyVerses: parsed.keyVerses || [],
          relatedPeople: parsed.relatedPeople || [],
          funFacts: parsed.funFacts || [],
        };
      } catch (e) {
        // Fallback
      }
    }

    return {
      summary: `Information about ${query}`,
      keyVerses: [],
      relatedPeople: [],
      funFacts: [],
    };
  }
);

// ============================================================================
// 10. SUGGEST SEARCH FILTERS FLOW
// ============================================================================

export const suggestSearchFilters = ai.defineFlow(
  {
    name: 'suggestSearchFilters',
    inputSchema: z.object({
      query: z.string(),
    }),
    outputSchema: z.object({
      suggestedFilters: z.array(z.string()),
      explanation: z.string(),
    }),
  },
  async (input) => {
    const { query } = input;

    const prompt = `For the search query "${query}" in a Bible app, suggest helpful filters.

Examples: Testament (Old/New), Book, Theme, Person, Time Period, etc.

Format as JSON:
{
  "suggestedFilters": ["Filter 1", "Filter 2", "Filter 3"],
  "explanation": "Why these filters are helpful..."
}`;

    const response = await ai.generate({
      model: gemini15Flash,
      prompt: prompt,
      config: {
        temperature: 0.6,
        maxOutputTokens: 512,
      },
    });

    const text = response.text();
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    
    if (jsonMatch) {
      try {
        const parsed = JSON.parse(jsonMatch[0]);
        return {
          suggestedFilters: parsed.suggestedFilters || [],
          explanation: parsed.explanation || "",
        };
      } catch (e) {
        // Fallback
      }
    }

    return {
      suggestedFilters: ["Testament", "Book", "Theme"],
      explanation: "These filters will help narrow your search.",
    };
  }
);

// ============================================================================
// EXPRESS SERVER
// ============================================================================

import express from 'express';

const app = express();
app.use(express.json());

// Health check
app.get('/', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'AMEN Genkit AI',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    flows: [
      'bibleChat',
      'generateDevotional',
      'generateStudyPlan',
      'analyzeScripture',
      'generateMemoryAid',
      'generateInsights',
      'generateFunBibleFact',
      'generateSearchSuggestions',
      'enhanceBiblicalSearch',
      'suggestSearchFilters',
    ],
  });
});

// Start server
const PORT = process.env.PORT || 8080;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`🔥 AMEN Genkit Server running on port ${PORT}`);
  console.log(`📍 Health check: http://localhost:${PORT}/`);
  console.log(`✅ All 10 AI flows ready!`);
});

// Start Genkit flows
ai.startFlowsServer({
  port: PORT,
});
