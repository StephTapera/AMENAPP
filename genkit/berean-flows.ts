import { genkit, z } from 'genkit';
import { googleAI, gemini20FlashExp } from '@genkit-ai/googleai';
import { GOVERNED_SYSTEM_PROMPT } from './governed-prompt';

const ai = genkit({
  plugins: [
    googleAI({
      apiKey: process.env.GOOGLE_AI_API_KEY,
    }),
  ],
  model: gemini20FlashExp,
});

// Governance (G-3): the prior hard-coded three-line prompt was ungoverned.
// Berean now emits under the canonical clauses (grounding / Companion Boundary /
// epistemic honesty) mirrored in ./governed-prompt.ts.
const SYSTEM_PROMPT = GOVERNED_SYSTEM_PROMPT;

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
    const messages = [
      { role: 'system', content: SYSTEM_PROMPT },
      ...history,
      { role: 'user', content: message },
    ];

    const result = await ai.generate({
      messages,
      config: {
        temperature: 0.7,
        maxOutputTokens: 2048,
      },
    });

    return { response: result.text };
  }
);
