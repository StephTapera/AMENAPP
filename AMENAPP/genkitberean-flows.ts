/**
 * Berean AI - Genkit Flows for Bible Study
 * 
 * This file contains all the AI flows for the Berean Bible study feature.
 * Deploy to Firebase using: `genkit deploy`
 */

import { genkit, z } from 'genkit';
import { googleAI, gemini20FlashExp } from '@genkit-ai/googleai';
import { firebase } from '@genkit-ai/firebase';

// Initialize Genkit with Firebase and Google AI
const ai = genkit({
  plugins: [
    googleAI({
      apiKey: process.env.GOOGLE_AI_API_KEY,
    }),
    firebase(),
  ],
  model: gemini20FlashExp, // Using Gemini 2.0 Flash
});

// System prompt for Biblical AI
const BEREAN_SYSTEM_PROMPT = `You are a knowledgeable and compassionate Biblical AI assistant for the AMEN app, a Christian community platform.

Your purpose is to:
- Help users understand Scripture passages with historical and cultural context
- Answer theological questions with biblical accuracy and wisdom
- Provide spiritual guidance rooted in Scripture
- Explore original Greek and Hebrew when relevant
- Generate personalized devotionals based on God's Word
- Create custom Bible study plans
- Analyze biblical themes and connections
- Help users memorize Scripture

Guidelines:
- Always cite Scripture references (book, chapter, verse)
- Respect different Christian traditions and denominations
- Be encouraging and faith-building
- Admit when questions are beyond biblical scope
- Avoid controversial or divisive topics when possible
- Focus on Jesus Christ as the center of faith
- Use clear, accessible language
- Provide practical application when appropriate

Your tone should be:
- Warm and approachable
- Reverent toward Scripture
- Scholarly yet accessible
- Encouraging and uplifting
- Patient with all questions`;

// =============================================================================
// FLOW: Bible Chat (Main conversational AI)
// =============================================================================

export const bibleChat = ai.defineFlow(
  {
    name: 'bibleChat',
    inputSchema: z.object({
      message: z.string().describe('User message'),
      history: z
        .array(
          z.object({
            role: z.enum(['user', 'assistant']),
            content: z.string(),
          })
        )
        .optional()
        .describe('Conversation history'),
    }),
    outputSchema: z.object({
      response: z.string().describe('AI response'),
    }),
  },
  async ({ message, history = [] }) => {
    // Build conversation messages
    const messages = [
      { role: 'system', content: BEREAN_SYSTEM_PROMPT },
      ...history.map((msg) => ({
        role: msg.role,
        content: msg.content,
      })),
      { role: 'user', content: message },
    ];

    // Generate response
    const result = await ai.generate({
      messages,
      config: {
        temperature: 0.7,
        maxOutputTokens: 2048,
      },
    });

    return {
      response: result.text,
    };
  }
);

// =============================================================================
// FLOW: Generate Devotional
// =============================================================================

export const generateDevotional = ai.defineFlow(
  {
    name: 'generateDevotional',
    inputSchema: z.object({
      topic: z.string().optional().describe('Optional devotional topic'),
    }),
    outputSchema: z.object({
      title: z.string(),
      scripture: z.string(),
      content: z.string(),
      prayer: z.string(),
    }),
  },
  async ({ topic }) => {
    const prompt = topic
      ? `Create a daily devotional on the topic of "${topic}".`
      : `Create an inspiring daily devotional for today.`;

    const fullPrompt = `${prompt}

Format your response as JSON with these fields:
{
  "title": "Engaging title",
  "scripture": "Key verse with reference (e.g., John 3:16)",
  "content": "2-3 paragraphs of biblical reflection",
  "prayer": "Short closing prayer"
}

Make it personal, encouraging, and biblically sound.`;

    const result = await ai.generate({
      messages: [
        { role: 'system', content: BEREAN_SYSTEM_PROMPT },
        { role: 'user', content: fullPrompt },
      ],
      config: {
        temperature: 0.8,
        maxOutputTokens: 1024,
      },
      output: {
        format: 'json',
        schema: z.object({
          title: z.string(),
          scripture: z.string(),
          content: z.string(),
          prayer: z.string(),
        }),
      },
    });

    return result.output;
  }
);

// =============================================================================
// FLOW: Generate Study Plan
// =============================================================================

export const generateStudyPlan = ai.defineFlow(
  {
    name: 'generateStudyPlan',
    inputSchema: z.object({
      topic: z.string().describe('Study plan topic'),
      duration: z.number().int().describe('Duration in days'),
    }),
    outputSchema: z.object({
      id: z.string(),
      title: z.string(),
      description: z.string(),
      days: z.array(
        z.object({
          day: z.number(),
          title: z.string(),
          scripture: z.array(z.string()),
          themes: z.array(z.string()),
          questions: z.array(z.string()),
        })
      ),
    }),
  },
  async ({ topic, duration }) => {
    const prompt = `Create a ${duration}-day Bible study plan on the topic of "${topic}".

For each day, provide:
1. Day number
2. Title
3. Scripture readings (1-3 passages)
4. Key themes
5. Reflection questions (2-3 questions)

Make it progressive, building knowledge day by day.
Ensure it's biblically comprehensive and engaging.

Format as JSON with this structure:
{
  "id": "unique-id",
  "title": "Study plan title",
  "description": "Overview of the study plan",
  "days": [
    {
      "day": 1,
      "title": "Day title",
      "scripture": ["John 3:16-21", "Romans 5:8"],
      "themes": ["God's Love", "Salvation"],
      "questions": ["How does God's love transform us?", "What does it mean to be saved?"]
    }
  ]
}`;

    const result = await ai.generate({
      messages: [
        { role: 'system', content: BEREAN_SYSTEM_PROMPT },
        { role: 'user', content: prompt },
      ],
      config: {
        temperature: 0.7,
        maxOutputTokens: 3072,
      },
      output: { format: 'json' },
    });

    return {
      ...result.output,
      id: crypto.randomUUID(),
    };
  }
);

// =============================================================================
// FLOW: Analyze Scripture
// =============================================================================

export const analyzeScripture = ai.defineFlow(
  {
    name: 'analyzeScripture',
    inputSchema: z.object({
      reference: z.string().describe('Scripture reference (e.g., John 3:16)'),
      analysisType: z
        .enum(['Contextual', 'Thematic', 'Linguistic', 'Cross-References'])
        .describe('Type of analysis'),
    }),
    outputSchema: z.object({
      analysis: z.string().describe('Detailed analysis'),
    }),
  },
  async ({ reference, analysisType }) => {
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
5. Literary devices used (metaphor, parallelism, etc.)`,

      'Cross-References': `Find and explain cross-references for ${reference}.

Include:
1. Direct quotations or allusions
2. Parallel passages
3. Thematically related verses
4. Fulfillment passages (if prophecy)
5. How these connections deepen understanding`,
    };

    const result = await ai.generate({
      messages: [
        { role: 'system', content: BEREAN_SYSTEM_PROMPT },
        { role: 'user', content: prompts[analysisType] },
      ],
      config: {
        temperature: 0.6,
        maxOutputTokens: 2048,
      },
    });

    return {
      analysis: result.text,
    };
  }
);

// =============================================================================
// FLOW: Generate Memory Aid
// =============================================================================

export const generateMemoryAid = ai.defineFlow(
  {
    name: 'generateMemoryAid',
    inputSchema: z.object({
      verse: z.string().describe('The verse text'),
      reference: z.string().describe('Scripture reference'),
    }),
    outputSchema: z.object({
      techniques: z.string().describe('Memory techniques'),
    }),
  },
  async ({ verse, reference }) => {
    const prompt = `Help users memorize this verse: "${verse}" (${reference})

Provide:
1. Mnemonic device (memory trick)
2. Word associations
3. Visualization suggestion
4. Breaking it into chunks
5. Repetition pattern
6. Application to help remember it

Make it practical and easy to follow.`;

    const result = await ai.generate({
      messages: [
        { role: 'system', content: BEREAN_SYSTEM_PROMPT },
        { role: 'user', content: prompt },
      ],
      config: {
        temperature: 0.8,
        maxOutputTokens: 1024,
      },
    });

    return {
      techniques: result.text,
    };
  }
);

// =============================================================================
// FLOW: Generate AI Insights
// =============================================================================

export const generateInsights = ai.defineFlow(
  {
    name: 'generateInsights',
    inputSchema: z.object({
      topic: z.string().optional().describe('Optional topic for insights'),
    }),
    outputSchema: z.object({
      insights: z.array(
        z.object({
          title: z.string(),
          verse: z.string(),
          content: z.string(),
          icon: z.string(),
        })
      ),
    }),
  },
  async ({ topic }) => {
    const prompt = topic
      ? `Provide 5 biblical insights about ${topic}.`
      : `Provide 5 inspiring biblical insights for today.`;

    const fullPrompt = `${prompt}

For each insight:
1. Title (concise and clear)
2. Key Scripture reference
3. Brief explanation (2-3 sentences)
4. Icon name (SF Symbols compatible)

Format as JSON array.

Make them practical and encouraging.`;

    const result = await ai.generate({
      messages: [
        { role: 'system', content: BEREAN_SYSTEM_PROMPT },
        { role: 'user', content: fullPrompt },
      ],
      config: {
        temperature: 0.8,
        maxOutputTokens: 1536,
      },
      output: {
        format: 'json',
        schema: z.object({
          insights: z.array(
            z.object({
              title: z.string(),
              verse: z.string(),
              content: z.string(),
              icon: z.string(),
            })
          ),
        }),
      },
    });

    return result.output;
  }
);

// =============================================================================
// FLOW: Generate Fun Bible Fact
// =============================================================================

export const generateFunBibleFact = ai.defineFlow(
  {
    name: 'generateFunBibleFact',
    inputSchema: z.object({
      category: z.string().optional().describe('Optional category: history, numbers, translation, geography, people, or random'),
    }),
    outputSchema: z.object({
      fact: z.string().describe('A fun and interesting Bible fact'),
      category: z.string().describe('The category of the fact'),
    }),
  },
  async ({ category = 'random' }) => {
    const prompt = `Generate one fascinating and accurate fact about the Bible.

${category !== 'random' ? `Focus on: ${category}` : 'Choose any interesting category'}

Requirements:
- Must be historically and theologically accurate
- Should be surprising or little-known
- Keep it concise (1-2 sentences)
- Make it engaging and memorable
- Include specific details (numbers, names, places when relevant)

Categories to choose from:
- Biblical history and archaeology
- Numbers and statistics
- Translation and manuscripts
- Geography and places
- Biblical people and their lives
- Literary features
- Scientific accuracy
- Cultural insights

Format as JSON:
{
  "fact": "Your fascinating fact here",
  "category": "The category name"
}`;

    const result = await ai.generate({
      messages: [
        { role: 'system', content: BEREAN_SYSTEM_PROMPT },
        { role: 'user', content: prompt },
      ],
      config: {
        temperature: 0.8,
        maxOutputTokens: 256,
      },
      output: {
        format: 'json',
        schema: z.object({
          fact: z.string(),
          category: z.string(),
        }),
      },
    });

    return result.output;
  }
);

// =============================================================================
// FLOW: Smart Search Suggestions
// =============================================================================

export const generateSearchSuggestions = ai.defineFlow(
  {
    name: 'generateSearchSuggestions',
    inputSchema: z.object({
      query: z.string().describe('User search query'),
      context: z.string().optional().describe('App context: people, groups, posts, events, bible'),
    }),
    outputSchema: z.object({
      suggestions: z.array(z.string()).describe('Search suggestions'),
      relatedTopics: z.array(z.string()).describe('Related topics to explore'),
    }),
  },
  async ({ query, context = 'general' }) => {
    const prompt = `Given the search query: "${query}"
${context !== 'general' ? `Context: Searching for ${context}` : ''}

Generate helpful search suggestions and related topics for a Christian community app.

Provide:
1. 5 improved/related search queries
2. 3-5 related topics to explore

Format as JSON:
{
  "suggestions": ["suggestion 1", "suggestion 2", ...],
  "relatedTopics": ["topic 1", "topic 2", ...]
}

Make suggestions:
- More specific and actionable
- Include biblical references when relevant
- Consider common typos/variations
- Be contextually aware`;

    const result = await ai.generate({
      messages: [
        { role: 'system', content: BEREAN_SYSTEM_PROMPT },
        { role: 'user', content: prompt },
      ],
      config: {
        temperature: 0.7,
        maxOutputTokens: 512,
      },
      output: {
        format: 'json',
        schema: z.object({
          suggestions: z.array(z.string()),
          relatedTopics: z.array(z.string()),
        }),
      },
    });

    return result.output;
  }
);

// =============================================================================
// FLOW: Biblical People/Places Search Enhancement
// =============================================================================

export const enhanceBiblicalSearch = ai.defineFlow(
  {
    name: 'enhanceBiblicalSearch',
    inputSchema: z.object({
      query: z.string().describe('Search query (person, place, or event)'),
      type: z.enum(['person', 'place', 'event']).describe('Type of search'),
    }),
    outputSchema: z.object({
      summary: z.string().describe('Brief summary'),
      keyVerses: z.array(z.string()).describe('Related Bible verses'),
      relatedPeople: z.array(z.string()).describe('Related biblical figures'),
      funFacts: z.array(z.string()).describe('Interesting facts'),
    }),
  },
  async ({ query, type }) => {
    const prompt = `Search query: "${query}"
Type: ${type}

Provide biblical information about this ${type}.

Include:
1. A brief 2-sentence summary
2. 3-5 key Bible verse references
3. Related people (if applicable)
4. 2-3 interesting facts

Format as JSON:
{
  "summary": "Brief description",
  "keyVerses": ["John 3:16", "Romans 8:28"],
  "relatedPeople": ["person1", "person2"],
  "funFacts": ["fact1", "fact2"]
}

Be accurate and cite specific verses.`;

    const result = await ai.generate({
      messages: [
        { role: 'system', content: BEREAN_SYSTEM_PROMPT },
        { role: 'user', content: prompt },
      ],
      config: {
        temperature: 0.6,
        maxOutputTokens: 768,
      },
      output: {
        format: 'json',
        schema: z.object({
          summary: z.string(),
          keyVerses: z.array(z.string()),
          relatedPeople: z.array(z.string()),
          funFacts: z.array(z.string()),
        }),
      },
    });

    return result.output;
  }
);

// =============================================================================
// FLOW: Smart Search Filter Suggestions
// =============================================================================

export const suggestSearchFilters = ai.defineFlow(
  {
    name: 'suggestSearchFilters',
    inputSchema: z.object({
      query: z.string().describe('User search query'),
    }),
    outputSchema: z.object({
      suggestedFilters: z.array(z.string()).describe('Recommended filters'),
      explanation: z.string().describe('Why these filters'),
    }),
  },
  async ({ query }) => {
    const prompt = `Analyze this search query: "${query}"

Available filters: people, groups, posts, events, bible

Suggest which filters would be most relevant and explain why.

Format as JSON:
{
  "suggestedFilters": ["people", "bible"],
  "explanation": "This query is asking about..."
}`;

    const result = await ai.generate({
      messages: [
        { role: 'system', content: BEREAN_SYSTEM_PROMPT },
        { role: 'user', content: prompt },
      ],
      config: {
        temperature: 0.5,
        maxOutputTokens: 256,
      },
      output: {
        format: 'json',
        schema: z.object({
          suggestedFilters: z.array(z.string()),
          explanation: z.string(),
        }),
      },
    });

    return result.output;
  }
);

// =============================================================================
// EXPORTS
// =============================================================================

export default {
  bibleChat,
  generateDevotional,
  generateStudyPlan,
  analyzeScripture,
  generateMemoryAid,
  generateInsights,
  generateFunBibleFact,
  generateSearchSuggestions,
  enhanceBiblicalSearch,
  suggestSearchFilters,
};
