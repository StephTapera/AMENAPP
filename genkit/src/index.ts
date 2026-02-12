import { genkit, z } from 'genkit';
import { googleAI, gemini20FlashExp } from '@genkit-ai/googleai';
import express from 'express';

// Initialize Genkit with Google AI
const ai = genkit({
  plugins: [
    googleAI({
      apiKey: process.env.GOOGLE_AI_API_KEY,
    }),
  ],
  model: gemini20FlashExp,
});

const SYSTEM_PROMPT = `You are a Biblical AI assistant for the AMEN app. 
Help users understand Scripture with accuracy, compassion, and wisdom.
Always cite Scripture references and be encouraging.`;

// ============================================================================
// FLOW 1: Bible Chat
// ============================================================================
export const bibleChat = ai.defineFlow(
  {
    name: 'bibleChat',
    inputSchema: z.object({
      message: z.string(),
      history: z.array(z.object({
        role: z.enum(['user', 'assistant']),
        content: z.string(),
      })).optional(),
    }),
    outputSchema: z.object({
      response: z.string(),
    }),
  },
  async ({ message, history = [] }) => {
    const prompt = SYSTEM_PROMPT + '\n\n' + 
      history.map(h => `${h.role}: ${h.content}`).join('\n') +
      '\n\nuser: ' + message;

    const result = await ai.generate({
      prompt,
      config: {
        temperature: 0.7,
        maxOutputTokens: 2048,
      },
    });

    return { response: result.text };
  }
);

// ============================================================================
// FLOW 2: Generate Devotional
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
  async ({ topic }) => {
    const prompt = topic
      ? `Create a daily devotional on "${topic}". Include: title, scripture reference with full text, 2-3 paragraphs of reflection, and a closing prayer. Format as JSON.`
      : `Create an inspiring daily devotional. Include: title, scripture reference with full text, 2-3 paragraphs of reflection, and a closing prayer. Format as JSON.`;

    const result = await ai.generate({ prompt });
    const text = result.text;
    
    try {
      const json = JSON.parse(text.match(/\{[\s\S]*\}/)?.[0] || '{}');
      return {
        title: json.title || "Daily Devotional",
        scripture: json.scripture || "Philippians 4:13",
        content: json.content || text,
        prayer: json.prayer || "Lord, guide us. Amen.",
      };
    } catch {
      return {
        title: "Daily Devotional",
        scripture: "Philippians 4:13 - 'I can do all things through Christ'",
        content: text,
        prayer: "Lord, strengthen us. Amen.",
      };
    }
  }
);

// ============================================================================
// FLOW 3: Generate Study Plan
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
  async ({ topic, duration }) => {
    const prompt = `Create a ${duration}-day Bible study plan on "${topic}". 
    For each day provide: title, scripture readings, key themes, and reflection questions.`;

    const result = await ai.generate({ prompt });

    return {
      id: `plan_${Date.now()}`,
      title: `${topic} - ${duration} Day Study`,
      description: result.text,
    };
  }
);

// ============================================================================
// FLOW 4: Analyze Scripture
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
  async ({ reference, analysisType }) => {
    const prompt = `Provide a ${analysisType} analysis of ${reference}. 
    Include historical context, cultural background, and theological significance.`;

    const result = await ai.generate({ prompt });
    return { analysis: result.text };
  }
);

// ============================================================================
// FLOW 5: Generate Memory Aid
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
  async ({ verse, reference }) => {
    const prompt = `Help memorize: "${verse}" (${reference}). 
    Provide: mnemonic device, word associations, visualization, chunking, and repetition pattern.`;

    const result = await ai.generate({ prompt });
    return { techniques: result.text };
  }
);

// ============================================================================
// FLOW 6: Generate Insights
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
  async ({ topic }) => {
    const prompt = `Provide 5 biblical insights${topic ? ` about "${topic}"` : ''}. 
    For each: title, verse reference, 2-3 sentence explanation, SF Symbol icon name. Format as JSON array.`;

    const result = await ai.generate({ prompt });
    
    try {
      const json = JSON.parse(result.text.match(/\[[\s\S]*\]/)?.[0] || '[]');
      return { insights: json };
    } catch {
      return {
        insights: [{
          title: "God's Love",
          verse: "John 3:16",
          content: "God's love is unconditional and eternal.",
          icon: "heart.fill",
        }],
      };
    }
  }
);

// ============================================================================
// FLOW 7: Fun Bible Fact
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
  async ({ category }) => {
    const prompt = `Generate a fascinating Bible fact${category ? ` about ${category}` : ''}. 
    Make it historically accurate, interesting, and 2-3 sentences. Include biblical reference.`;

    const result = await ai.generate({ prompt });
    return { fact: result.text };
  }
);

// ============================================================================
// FLOW 8: Search Suggestions
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
  async ({ query }) => {
    const prompt = `For search query "${query}": provide 5 search suggestions and 5 related biblical topics. Format as JSON.`;

    const result = await ai.generate({ prompt });
    
    try {
      const json = JSON.parse(result.text.match(/\{[\s\S]*\}/)?.[0] || '{}');
      return {
        suggestions: json.suggestions || [],
        relatedTopics: json.relatedTopics || [],
      };
    } catch {
      return {
        suggestions: [`More about ${query}`],
        relatedTopics: [`Biblical ${query}`],
      };
    }
  }
);

// ============================================================================
// FLOW 9: Enhance Biblical Search
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
  async ({ query, type }) => {
    const prompt = `For ${type} "${query}": provide summary, key verses, related people, and fun facts. Format as JSON.`;

    const result = await ai.generate({ prompt });
    
    try {
      const json = JSON.parse(result.text.match(/\{[\s\S]*\}/)?.[0] || '{}');
      return {
        summary: json.summary || "",
        keyVerses: json.keyVerses || [],
        relatedPeople: json.relatedPeople || [],
        funFacts: json.funFacts || [],
      };
    } catch {
      return { summary: "", keyVerses: [], relatedPeople: [], funFacts: [] };
    }
  }
);

// ============================================================================
// FLOW 10: Suggest Search Filters
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
  async ({ query }) => {
    const prompt = `For search "${query}": suggest helpful filters (Testament, Book, Theme, etc.) and explain why. Format as JSON.`;

    const result = await ai.generate({ prompt });
    
    try {
      const json = JSON.parse(result.text.match(/\{[\s\S]*\}/)?.[0] || '{}');
      return {
        suggestedFilters: json.suggestedFilters || [],
        explanation: json.explanation || "",
      };
    } catch {
      return {
        suggestedFilters: ["Testament", "Book"],
        explanation: "These filters help narrow your search.",
      };
    }
  }
);

// ============================================================================
// EXPRESS SERVER
// ============================================================================
const app = express();
app.use(express.json());

app.get('/', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'AMEN Genkit AI',
    version: '2.0.0',
    timestamp: new Date().toISOString(),
    flows: [
      'bibleChat', 'generateDevotional', 'generateStudyPlan',
      'analyzeScripture', 'generateMemoryAid', 'generateInsights',
      'generateFunBibleFact', 'generateSearchSuggestions',
      'enhanceBiblicalSearch', 'suggestSearchFilters'
    ],
  });
});

const PORT = process.env.PORT || 8080;

ai.startFlowsServer({ port: PORT });

console.log(`🔥 AMEN Genkit Server running on port ${PORT}`);
console.log(`✅ All 10 AI flows ready!`);
