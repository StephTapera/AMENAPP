import {validateRawTextOutput} from "../berean/services/SafetyValidator";
import {AmenDailyHolidayContext, AmenDailyWeatherContext} from "./amenDailyTypes";
import {VerseSelection} from "./dailyVerseResolver";

const OPENAI_CHAT_COMPLETIONS_URL = "https://api.openai.com/v1/chat/completions";
const MAX_REFLECTION_CHARS = 280;

export interface AmenDailyAIReflectionInput {
  dateKey: string;
  verse: VerseSelection;
  holiday?: AmenDailyHolidayContext;
  weather?: AmenDailyWeatherContext;
}

interface OpenAIChatResponse {
  choices?: Array<{message?: {content?: string}}>;
}

export function buildAmenDailyAIReflectionPrompt(input: AmenDailyAIReflectionInput): string {
  const context = [
    input.holiday ? `Holiday or Christian calendar context: ${input.holiday.name}. ${input.holiday.message}` : "",
    input.weather?.summary ? `Practical weather context: ${input.weather.summary}` : "",
  ].filter(Boolean).join("\n");

  return [
    "Write one short Amen Daily reflection for a Christian app.",
    "Rules:",
    "- Scripture first; do not replace or reinterpret the verse.",
    "- Do not claim God caused today's weather or holiday circumstances.",
    "- Do not make personal claims about the user's emotions, week, pain, calling, future, or private life.",
    "- Do not give medical, legal, financial, crisis, or pastoral-directive advice.",
    "- Do not say 'God is telling you' or speak with prophetic authority.",
    "- Keep it calm, practical, and under 45 words.",
    "- Return plain text only.",
    "",
    `Date key: ${input.dateKey}`,
    `Verse: ${input.verse.verseReference} — ${input.verse.verseText}`,
    context ? `Context:\n${context}` : "Context: General daily encouragement.",
  ].join("\n");
}

export function sanitizeAmenDailyAIReflection(text: string): string | null {
  const normalized = text
    .replace(/\s+/g, " ")
    .replace(/^["'“”]+|["'“”]+$/g, "")
    .trim();
  if (normalized.length < 20 || normalized.length > MAX_REFLECTION_CHARS) return null;
  if (/^\s*(prayer|verse|reflection)\s*:/i.test(normalized)) return null;
  if (/\b(i know|i sense|you had|you are struggling|your difficult week|god sent|god caused)\b/i.test(normalized)) return null;

  const validated = validateRawTextOutput(normalized);
  if (!validated.isValid) return null;

  return `AI-assisted reflection: ${validated.sanitizedText}`;
}

export async function generateAmenDailyAIReflection(
  apiKey: string,
  input: AmenDailyAIReflectionInput,
): Promise<string | null> {
  if (!apiKey) return null;

  const response = await fetch(OPENAI_CHAT_COMPLETIONS_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "system",
          content: "You write careful, humble, concise Christian reflections for a daily scripture banner.",
        },
        {
          role: "user",
          content: buildAmenDailyAIReflectionPrompt(input),
        },
      ],
      max_tokens: 90,
      temperature: 0.3,
    }),
  });

  if (!response.ok) return null;

  const json = await response.json() as OpenAIChatResponse;
  const content = json.choices?.[0]?.message?.content;
  return content ? sanitizeAmenDailyAIReflection(content) : null;
}
