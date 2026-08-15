/**
 * Tests for the server-side response validators.
 *
 * These need no emulator and no network — they are pure functions over a
 * parsed model response, which is the whole reason they are worth having in a
 * repository whose Swift cannot be compiled here.
 *
 * The emphasis is on rejection. `validateRecommendation` is the last thing
 * between a model response and a card the user is invited to act on, so the
 * interesting cases are the ones it must refuse.
 */
import { describe, expect, it } from "vitest";
import {
  checkForbiddenContent,
  validateAsk,
  validateRecommendation,
} from "../src/schema";

/** A minimal response that passes, so each test can vary one thing. */
function recommendation(overrides: Record<string, unknown> = {}) {
  return {
    headline: "Take it easy today",
    summary: "You slept six hours after four training days. A rest day is the useful move.",
    category: "recovery",
    actionType: "rest",
    relatedItemId: null,
    durationMinutes: null,
    priority: "medium",
    confidence: "high",
    evidence: [{ label: "Sleep", explanation: "6h 02m against your 7h 30m baseline" }],
    ...overrides,
  };
}

describe("validateRecommendation — the basics still hold", () => {
  it("accepts a well-formed recommendation", () => {
    expect(validateRecommendation(recommendation())).toEqual({ ok: true });
  });

  it("rejects an unknown actionType", () => {
    const result = validateRecommendation(
      recommendation({ actionType: "sendEmail" })
    );
    expect(result.ok).toBe(false);
  });

  it("rejects a response containing a URL", () => {
    const result = validateRecommendation(
      recommendation({ summary: "Read more at https://example.com/sleep" })
    );
    expect(result).toEqual({ ok: false, reason: "response contained a URL" });
  });

  it("rejects an overlong headline", () => {
    const result = validateRecommendation(
      recommendation({ headline: "x".repeat(81) })
    );
    expect(result.ok).toBe(false);
  });
});

describe("validateRecommendation — the custom action gate", () => {
  /**
   * `custom` was added to ACTION_TYPES with its constraints stated only in the
   * system prompt. Prompt text is guidance in the same channel as user input;
   * these tests exist because it is not a control.
   */
  it("accepts a custom action with a sane duration", () => {
    const result = validateRecommendation(
      recommendation({
        actionType: "custom",
        durationMinutes: 20,
        headline: "Lay your kit out for tomorrow",
        summary: "Two minutes now removes the decision that usually stops you.",
      })
    );
    expect(result).toEqual({ ok: true });
  });

  it("accepts both ends of the permitted range", () => {
    for (const durationMinutes of [1, 240]) {
      expect(
        validateRecommendation(
          recommendation({ actionType: "custom", durationMinutes })
        )
      ).toEqual({ ok: true });
    }
  });

  it("rejects a custom action with no duration at all", () => {
    const result = validateRecommendation(
      recommendation({ actionType: "custom", durationMinutes: null })
    );
    expect(result.ok).toBe(false);
  });

  it("rejects a custom action longer than four hours", () => {
    const result = validateRecommendation(
      recommendation({ actionType: "custom", durationMinutes: 241 })
    );
    expect(result.ok).toBe(false);
  });

  it("rejects a zero or negative duration", () => {
    for (const durationMinutes of [0, -30]) {
      expect(
        validateRecommendation(
          recommendation({ actionType: "custom", durationMinutes })
        ).ok
      ).toBe(false);
    }
  });

  it("rejects a fractional duration", () => {
    const result = validateRecommendation(
      recommendation({ actionType: "custom", durationMinutes: 12.5 })
    );
    expect(result.ok).toBe(false);
  });

  it("still allows a null duration on non-custom actions", () => {
    expect(
      validateRecommendation(
        recommendation({ actionType: "rest", durationMinutes: null })
      )
    ).toEqual({ ok: true });
  });
});

describe("checkForbiddenContent — medical and commercial language", () => {
  const forbidden: ReadonlyArray<[string, string]> = [
    ["prescribes medication", "Ask your GP about medication for this"],
    ["names a prescription", "A prescription would help you sleep"],
    ["gives a dose", "Try 400mg before bed"],
    ["gives a dose with a space", "Try 5 mg of it"],
    ["recommends a supplement", "A magnesium supplement helps recovery"],
    ["names melatonin", "Melatonin would fix your sleep timing"],
    ["names creatine", "Start taking creatine daily"],
    ["suggests a pill", "Take a pill an hour before bed"],
    ["suggests buying", "Buy a sunrise alarm clock"],
    ["suggests a purchase", "Worth a purchase if you can"],
    ["suggests subscribing", "Subscribe to a meditation app"],
    ["adds to a basket", "Add to basket and try it tonight"],
    ["quotes a price", "It costs about £30"],
    ["quotes a dollar price", "Around $19 for a decent one"],
  ];

  for (const [description, summary] of forbidden) {
    it(`rejects a response that ${description}`, () => {
      expect(checkForbiddenContent({ summary }).ok).toBe(false);
      expect(validateRecommendation(recommendation({ summary })).ok).toBe(false);
    });
  }

  it("allows ordinary coaching language", () => {
    const allowed = [
      "A twenty minute walk after lunch would help.",
      "Your resting heart rate is four beats above baseline.",
      "Go to bed half an hour earlier tonight.",
      "Skip the heavy set and keep the session short.",
      "You have two important tasks still open.",
    ];
    for (const summary of allowed) {
      expect(checkForbiddenContent({ summary })).toEqual({ ok: true });
    }
  });

  it("catches the term wherever it appears, not only in the summary", () => {
    expect(
      validateRecommendation(
        recommendation({ headline: "Try 200mg of caffeine" })
      ).ok
    ).toBe(false);

    expect(
      validateRecommendation(
        recommendation({
          evidence: [{ label: "Note", explanation: "Buy a heart rate strap" }],
        })
      ).ok
    ).toBe(false);
  });
});

describe("validateAsk — the same floor applies to free prose", () => {
  // The answer travels in `summary`, not `answer` — the field is shared with
  // the recommendation schema.
  function ask(overrides: Record<string, unknown> = {}) {
    return {
      summary: "You slept six hours, which is about ninety minutes under your baseline.",
      proposals: [],
      ...overrides,
    };
  }

  it("accepts an ordinary answer", () => {
    expect(validateAsk(ask())).toEqual({ ok: true });
  });

  it("rejects an answer recommending a supplement", () => {
    expect(
      validateAsk(ask({ summary: "A magnesium supplement before bed would help." })).ok
    ).toBe(false);
  });

  it("rejects an answer containing a URL", () => {
    expect(validateAsk(ask({ summary: "See https://example.com" })).ok).toBe(false);
  });

  it("rejects a supplement mentioned in a proposal label", () => {
    expect(
      validateAsk(
        ask({
          proposals: [{ type: "addTask", label: "Buy magnesium tablets" }],
        })
      ).ok
    ).toBe(false);
  });
});
