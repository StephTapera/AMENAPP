import { genkit, z } from 'genkit';
import { googleAI, gemini20FlashExp } from '@genkit-ai/googleai';

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
