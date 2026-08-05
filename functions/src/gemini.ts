/**
 * The only file that reads the Gemini API key.
 *
 * Isolated deliberately. The key exists as a Cloud Functions secret, is read
 * here at call time, and never travels further — not into logs, not into the
 * response, not into Firestore. The iOS app has no idea it exists.
 *
 * The request shape below follows Google's Generative Language REST API. If the
 * contract changes, this is the one file to correct.
 */

export interface GeminiUsage {
  promptTokens: number;
  outputTokens: number;
  totalTokens: number;
}

export interface GeminiResult {
  /** The parsed JSON object the model returned. */
  value: unknown;
  usage: GeminiUsage;
}

export interface GeminiRequest {
  apiKey: string;
  model: string;
  systemInstruction: string;
  userContent: string;
  responseSchema: unknown;
  maxOutputTokens: number;
  /** Low by default — this is guidance from data, not creative writing. */
  temperature: number;
  timeoutMs: number;
}

/**
 * Calls Gemini and returns the parsed JSON.
 *
 * Search grounding is deliberately absent: the brief forbids it, and a coach
 * that can reach the open web is a coach that can bring back health claims
 * nobody vetted.
 */
export async function generateJSON(request: GeminiRequest): Promise<GeminiResult> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/` +
    `${encodeURIComponent(request.model)}:generateContent`;

  const body = {
    systemInstruction: {
      parts: [{ text: request.systemInstruction }],
    },
    contents: [
      {
        role: "user",
        parts: [{ text: request.userContent }],
      },
    ],
    generationConfig: {
      temperature: request.temperature,
      maxOutputTokens: request.maxOutputTokens,
      responseMimeType: "application/json",
      responseSchema: request.responseSchema,
    },
  };

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), request.timeoutMs);

  let response: Response;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        // Header rather than a query parameter: query strings turn up in
        // access logs and proxy traces, and this one is a credential.
        "x-goog-api-key": request.apiKey,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timeout);
  }

  if (!response.ok) {
    // The body can echo the request, so it is not surfaced to the client or
    // logged. Only the status travels.
    throw new GeminiError(response.status);
  }

  const payload = (await response.json()) as GeminiResponseBody;

  const text = payload?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== "string") {
    throw new GeminiError(502, "no text part in response");
  }

  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw new GeminiError(502, "response was not valid JSON");
  }

  const usage = payload.usageMetadata;
  return {
    value,
    usage: {
      promptTokens: usage?.promptTokenCount ?? 0,
      outputTokens: usage?.candidatesTokenCount ?? 0,
      totalTokens: usage?.totalTokenCount ?? 0,
    },
  };
}

export class GeminiError extends Error {
  constructor(
    public readonly status: number,
    message = `Gemini returned ${status}`
  ) {
    super(message);
    this.name = "GeminiError";
  }
}

interface GeminiResponseBody {
  candidates?: Array<{
    content?: { parts?: Array<{ text?: string }> };
    finishReason?: string;
  }>;
  usageMetadata?: {
    promptTokenCount?: number;
    candidatesTokenCount?: number;
    totalTokenCount?: number;
  };
}
