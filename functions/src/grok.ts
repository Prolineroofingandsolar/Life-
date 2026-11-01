/**
 * The only file that reads the xAI (Grok) API key.
 *
 * The twin of `gemini.ts`, with the same rules: the key is a Cloud Functions
 * secret, read here at call time, and never logged, echoed or stored. The iOS
 * app doesn't know it exists and doesn't know which provider answered.
 *
 * xAI's API is OpenAI-compatible (`/v1/chat/completions`), so the request
 * below follows that shape. If the contract changes, this is the one file to
 * correct.
 */

import type { GeminiRequest, GeminiResult } from "./gemini";

/** Same inputs and outputs as the Gemini client, so `index.ts` can pick either. */
export type GrokRequest = GeminiRequest;
export type GrokResult = GeminiResult;

const GROK_URL = "https://api.x.ai/v1/chat/completions";

/**
 * Calls Grok and returns the parsed JSON.
 *
 * Live search is deliberately off (it is opt-in on xAI and never requested
 * here), for the same reason it is off for Gemini: a coach that can reach the
 * open web can bring back health claims nobody vetted.
 */
export async function generateJSONWithGrok(request: GrokRequest): Promise<GrokResult> {
  const apiKey = request.apiKey.trim();
  if (!apiKey) {
    throw new GrokError(401, "no API key was supplied to the request");
  }

  // The image goes first when there is one, matching the Gemini client: the
  // prompt refers to "this photograph", and reads better after it.
  const userParts: Array<Record<string, unknown>> = [];
  if (request.inlineImageBase64) {
    const mime = request.inlineImageMimeType ?? "image/jpeg";
    userParts.push({
      type: "image_url",
      image_url: { url: `data:${mime};base64,${request.inlineImageBase64}`, detail: "high" },
    });
  }
  userParts.push({ type: "text", text: request.userContent });

  const schema = toJSONSchema(request.responseSchema);

  const structuredBody = {
    model: request.model,
    messages: [
      { role: "system", content: request.systemInstruction },
      { role: "user", content: userParts },
    ],
    temperature: request.temperature,
    max_tokens: request.maxOutputTokens,
    response_format: {
      type: "json_schema",
      json_schema: { name: "coach_response", schema },
    },
  };

  // The fallback if xAI won't take the schema: plain JSON mode, with the
  // schema written into the system prompt. The validators on the way back are
  // the real guarantee either way.
  const jsonModeBody = {
    ...structuredBody,
    messages: [
      {
        role: "system",
        content:
          `${request.systemInstruction}\n\nReply with a single JSON object only, ` +
          `matching this JSON Schema exactly:\n${JSON.stringify(schema)}`,
      },
      { role: "user", content: userParts },
    ],
    response_format: { type: "json_object" },
  };

  let response = await post(structuredBody, apiKey, request.timeoutMs);
  if (response.status === 400 || response.status === 422) {
    const reason = await errorSummary(response);
    // xAI answers a bad key with 400, not 401. Reported as an auth failure so
    // the app says "check the key" rather than blaming the model or schema.
    if (/api key/i.test(reason)) {
      console.error(`[grok] key rejected: ${reason} (key length ${apiKey.length})`);
      throw new GrokError(401, "xAI rejected the API key");
    }
    console.error(
      `[grok] ${response.status} with structured output: ${reason}. Retrying in JSON mode.`
    );
    response = await post(jsonModeBody, apiKey, request.timeoutMs);
  }

  if (!response.ok) {
    if (response.status === 400 || response.status === 422) {
      console.error(`[grok] ${response.status} in JSON mode: ${await errorSummary(response)}`);
    }
    // As with Gemini, the body can echo the prompt, so only the status travels.
    if (response.status === 401 || response.status === 403) {
      console.error(
        `[grok] auth failure ${response.status}: key length ${apiKey.length}` +
        `, untrimmed length ${request.apiKey.length}, model "${request.model}"`
      );
    }
    throw new GrokError(response.status);
  }

  const payload = (await response.json()) as GrokResponseBody;
  const choice = payload?.choices?.[0];

  if (choice?.finish_reason === "length") {
    // Named rather than left to surface as "not valid JSON", which would
    // blame the model for a budget we set.
    throw new GrokError(502, "response was cut off at the output token limit");
  }

  const text = choice?.message?.content;
  if (typeof text !== "string") {
    throw new GrokError(502, "no text in response");
  }

  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw new GrokError(502, "response was not valid JSON");
  }

  const usage = payload.usage;
  const promptTokens = usage?.prompt_tokens ?? 0;
  const totalTokens = usage?.total_tokens ?? 0;
  // Reasoning models spend "thinking" tokens that are billed as output but
  // may not be counted in `completion_tokens`. Taking output as total minus
  // prompt counts them either way, so the monthly ceiling stays honest.
  const outputTokens = totalTokens > 0
    ? Math.max(totalTokens - promptTokens, usage?.completion_tokens ?? 0)
    : usage?.completion_tokens ?? 0;

  return {
    value,
    usage: {
      promptTokens,
      outputTokens,
      totalTokens: totalTokens || promptTokens + outputTokens,
    },
  };
}

/**
 * Converts the Gemini-style schemas in `schema.ts` and `workoutSchema.ts`
 * (OpenAPI subset: upper-case types, `nullable: true`) into standard JSON
 * Schema, which is what xAI's structured outputs accept. Converting here means
 * the schemas stay declared once, and the validators on the way back are
 * unchanged whichever provider answered.
 */
export function toJSONSchema(schema: unknown): unknown {
  if (Array.isArray(schema)) return schema.map(toJSONSchema);
  if (!schema || typeof schema !== "object") return schema;

  const source = schema as Record<string, unknown>;
  const out: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(source)) {
    if (key === "nullable" || key === "propertyOrdering") continue;
    if (key === "type" && typeof value === "string") {
      out.type = value.toLowerCase();
    } else if (key === "properties" && value && typeof value === "object") {
      out.properties = Object.fromEntries(
        Object.entries(value as Record<string, unknown>).map(([k, v]) => [k, toJSONSchema(v)])
      );
    } else if (key === "items") {
      out.items = toJSONSchema(value);
    } else {
      out[key] = value;
    }
  }

  // Deliberately the plainest JSON Schema there is: no type arrays, no null
  // in enums, no additionalProperties. xAI rejected the richer form with a
  // 400. Every nullable field in our schemas is also optional (none is in a
  // `required` list), so "may be null" becomes "may be left out", which the
  // validators already treat the same way.
  return out;
}

async function post(body: unknown, apiKey: string, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(GROK_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timeout);
  }
}

/**
 * xAI's own one-line reason for rejecting a request, for the log.
 *
 * Only the `error` field, cut short. That field describes what was wrong with
 * the request shape ("invalid schema at ..."); the prompt itself is never
 * logged.
 */
async function errorSummary(response: Response): Promise<string> {
  try {
    const payload = (await response.json()) as { error?: unknown; code?: unknown };
    const error = payload?.error;
    const text = typeof error === "string"
      ? error
      : typeof (error as { message?: unknown })?.message === "string"
        ? (error as { message: string }).message
        : String(payload?.code ?? "no error field");
    return text.replace(/xai-[A-Za-z0-9]+/g, "[redacted]").slice(0, 300);
  } catch {
    return "unreadable error body";
  }
}

export class GrokError extends Error {
  constructor(
    public readonly status: number,
    message = `Grok returned ${status}`
  ) {
    super(message);
    this.name = "GrokError";
  }
}

interface GrokResponseBody {
  choices?: Array<{
    message?: { content?: string | null };
    finish_reason?: string;
  }>;
  usage?: {
    prompt_tokens?: number;
    completion_tokens?: number;
    total_tokens?: number;
  };
}
