// 🚀 Complete Genkit Server for AMEN App
// Supports all 10 AI flows for Bible study

const { genkit, z } = require('genkit');
const { googleAI } = require('@genkit-ai/googleai');
const express = require('express');

// Initialize Genkit with Google AI
const ai = genkit({
  plugins: [googleAI({ apiKey: process.env.GOOGLE_AI_API_KEY })],
  model: 'googleai/gemini-2.0-flash-exp',
});

// Create Express app
const app = express();
app.use(express.json());

// Health check endpoint
app.get('/', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'AMEN Genkit AI Server',
    version: '1.0.0',
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
      'suggestSearchFilters'
    ]
  });
});

// ============================================================================
// FLOW 1: Bible Chat
// ============================================================================
const bibleChatFlow = ai.defineFlow(
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
    
    const prompt = `You are a knowledgeable Bible study assistant. Provide thoughtful, biblically-grounded responses.
    
User's question: ${message}

Previous conversation:
${history.map(h => `${h.role}: ${h.content}`).join('\n')}

Provide a helpful, accurate response based on biblical teachings.`;

    const result = await ai.generate({
      model: 'googleai/gemini-2.0-flash-exp',
      prompt,
    });

    return { response: result.text };
  }
);

app.post('/bibleChat', async (req, res) => {
  try {
    const result = await bibleChatFlow(req.body.data);
    res.json({ result });
  } catch (error) {
    console.error('Bible Chat error:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// FLOW 2: Generate Devotional
// ============================================================================
const generateDevotionalFlow = ai.defineFlow(
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
    const topic = input.topic || 'faith';
    
    const prompt = `Generate a daily devotional about "${topic}". 

Format the response as JSON with these fields:
- title: A compelling title for the devotional
- scripture: A relevant Bible verse with reference
- content: 2-3 paragraphs of devotional content with practical application
- prayer: A short closing prayer

Make it inspiring, practical, and biblically sound.`;

    const result = await ai.generate({
      model: 'googleai/gemini-2.0-flash-exp',
      prompt,
      output: { format: 'json' },
    });

    return JSON.parse(result.text);
  }
);

app.post('/generateDevotional', async (req, res) => {
  try {
    const result = await generateDevotionalFlow(req.body.data || {});
    res.json({ result });
  } catch (error) {
    console.error('Generate Devotional error:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// FLOW 3: Generate Study Plan
// ============================================================================
const generateStudyPlanFlow = ai.defineFlow(
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

Format as JSON with:
- id: A unique identifier (use the topic as base)
- title: Study plan title
- description: Brief overview of what the study will cover

Be comprehensive but concise.`;

    const result = await ai.generate({
      model: 'googleai/gemini-2.0-flash-exp',
      prompt,
      output: { format: 'json' },
    });

    return JSON.parse(result.text);
  }
);

app.post('/generateStudyPlan', async (req, res) => {
  try {
    const result = await generateStudyPlanFlow(req.body.data);
    res.json({ result });
  } catch (error) {
    console.error('Generate Study Plan error:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// FLOW 4: Analyze Scripture
// ============================================================================
const analyzeScriptureFlow = ai.defineFlow(
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
    
    const prompt = `Provide a ${analysisType} analysis of ${reference}.

Include:
- Historical context
- Literary analysis
- Theological significance
- Practical application

Be scholarly yet accessible.`;

    const result = await ai.generate({
      model: 'googleai/gemini-2.0-flash-exp',
      prompt,
    });

    return { analysis: result.text };
  }
);

app.post('/analyzeScripture', async (req, res) => {
  try {
    const result = await analyzeScriptureFlow(req.body.data);
    res.json({ result });
  } catch (error) {
    console.error('Analyze Scripture error:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// FLOW 5: Generate Memory Aid
// ============================================================================
const generateMemoryAidFlow = ai.defineFlow(
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
    
    const prompt = `Create memory aids for memorizing this Bible verse:

"${verse}" - ${reference}

Provide 3-4 creative techniques such as:
- Acronyms
- Visual imagery
- Rhythm/rhyme patterns
- Association techniques

Make them practical and easy to remember.`;

    const result = await ai.generate({
      model: 'googleai/gemini-2.0-flash-exp',
      prompt,
    });

    return { techniques: result.text };
  }
);

app.post('/generateMemoryAid', async (req, res) => {
  try {
    const result = await generateMemoryAidFlow(req.body.data);
    res.json({ result });
  } catch (error) {
    console.error('Generate Memory Aid error:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// FLOW 6: Generate Insights
// ============================================================================
const generateInsightsFlow = ai.defineFlow(
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
    const topic = input.topic || 'spiritual growth';
    
    const prompt = `Generate 3 spiritual insights about "${topic}".

Format as JSON array with:
- title: Insight title
- verse: Relevant Bible verse
- content: 1-2 sentences explaining the insight
- icon: SF Symbol name (e.g., "lightbulb.fill", "heart.fill", "star.fill")

Make them profound yet practical.`;

    const result = await ai.generate({
      model: 'googleai/gemini-2.0-flash-exp',
      prompt,
      output: { format: 'json' },
    });

    return { insights: JSON.parse(result.text) };
  }
);

app.post('/generateInsights', async (req, res) => {
  try {
    const result = await generateInsightsFlow(req.body.data || {});
    res.json({ result });
  } catch (error) {
    console.error('Generate Insights error:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// FLOW 7: Generate Fun Bible Fact
// ============================================================================
const generateFunBibleFactFlow = ai.defineFlow(
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
    const category = input.category || 'random';
    
    const prompt = `Share an interesting, lesser-known Bible fact about ${category}.

Make it:
- Fascinating and educational
- Accurate and well-sourced
- 2-3 sentences long
- Engaging for modern readers

Example categories: people, places, numbers, languages, culture, archaeology`;

    const result = await ai.generate({
      model: 'googleai/gemini-2.0-flash-exp',
      prompt,
    });

    return { fact: result.text };
  }
);

app.post('/generateFunBibleFact', async (req, res) => {
  try {
    const result = await generateFunBibleFactFlow(req.body.data || {});
    res.json({ result });
  } catch (error) {
    console.error('Generate Fun Bible Fact error:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// FLOW 8: Generate Search Suggestions
// ============================================================================
const generateSearchSuggestionsFlow = ai.defineFlow(
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
    
    const prompt = `Generate smart search suggestions for the query: "${query}"

Context: ${context}

Return JSON with:
- suggestions: 4-5 refined search suggestions
- relatedTopics: 3-4 related biblical topics to explore

Make suggestions specific and helpful for Bible study.`;

    const result = await ai.generate({
      model: 'googleai/gemini-2.0-flash-exp',
      prompt,
      output: { format: 'json' },
    });

    return JSON.parse(result.text);
  }
);

app.post('/generateSearchSuggestions', async (req, res) => {
  try {
    const result = await generateSearchSuggestionsFlow(req.body.data);
    res.json({ result });
  } catch (error) {
    console.error('Generate Search Suggestions error:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// FLOW 9: Enhance Biblical Search
// ============================================================================
const enhanceBiblicalSearchFlow = ai.defineFlow(
  {
    name: 'enhanceBiblicalSearch',
    inputSchema: z.object({
      query: z.string(),
      type: z.enum(['person', 'place', 'event']),
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
    
    const prompt = `Enhance biblical search for ${type}: "${query}"

Return JSON with:
- summary: Brief overview (2-3 sentences)
- keyVerses: 3-4 key Bible verses with references
- relatedPeople: 3-4 related biblical figures
- funFacts: 2-3 interesting facts

Be comprehensive and accurate.`;

    const result = await ai.generate({
      model: 'googleai/gemini-2.0-flash-exp',
      prompt,
      output: { format: 'json' },
    });

    return JSON.parse(result.text);
  }
);

app.post('/enhanceBiblicalSearch', async (req, res) => {
  try {
    const result = await enhanceBiblicalSearchFlow(req.body.data);
    res.json({ result });
  } catch (error) {
    console.error('Enhance Biblical Search error:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// FLOW 10: Suggest Search Filters
// ============================================================================
const suggestSearchFiltersFlow = ai.defineFlow(
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
    
    const prompt = `Suggest helpful search filters for the query: "${query}"

Return JSON with:
- suggestedFilters: 3-5 filter options (e.g., "Old Testament", "Prophets", "Parables")
- explanation: Brief explanation of why these filters are relevant

Make filters actionable and biblically relevant.`;

    const result = await ai.generate({
      model: 'googleai/gemini-2.0-flash-exp',
      prompt,
      output: { format: 'json' },
    });

    return JSON.parse(result.text);
  }
);

app.post('/suggestSearchFilters', async (req, res) => {
  try {
    const result = await suggestSearchFiltersFlow(req.body.data);
    res.json({ result });
  } catch (error) {
    console.error('Suggest Search Filters error:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// Start Server
// ============================================================================
const PORT = process.env.PORT || 8080;

app.listen(PORT, () => {
  console.log('🚀 AMEN Genkit Server Started');
  console.log(`✅ Listening on port ${PORT}`);
  console.log(`✅ Health check: http://localhost:${PORT}/`);
  console.log('');
  console.log('Available flows:');
  console.log('  1. POST /bibleChat');
  console.log('  2. POST /generateDevotional');
  console.log('  3. POST /generateStudyPlan');
  console.log('  4. POST /analyzeScripture');
  console.log('  5. POST /generateMemoryAid');
  console.log('  6. POST /generateInsights');
  console.log('  7. POST /generateFunBibleFact');
  console.log('  8. POST /generateSearchSuggestions');
  console.log('  9. POST /enhanceBiblicalSearch');
  console.log(' 10. POST /suggestSearchFilters');
  console.log('');
  console.log('🎯 Ready for requests!');
});

// Export for Cloud Run
module.exports = app;
