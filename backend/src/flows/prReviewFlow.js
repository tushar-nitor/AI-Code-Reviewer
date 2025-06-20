import { ai } from "../ai.js";
import { z } from "genkit";
import { prReviewerAgent } from "../agents/prReviewerAgent.js";
import { CodeReviewResultSchema } from "../schema/schema.js";
import { fetchPRDiffTool } from "../tools/github_tools.js";

export const prReviewFlow = ai.defineFlow(
  {
    name: "prReviewFlow",
    inputSchema: z.object({
      owner: z.string(),
      repo: z.string(),
      pull_number: z.number(),
      language: z.string(),
      focusAreas: z.string().optional(),
    }),
    outputSchema: CodeReviewResultSchema,
  },
  async (input) => {
    const rawResponse = await prReviewerAgent(input);

    const contentArray = rawResponse?.message?.content;
    const textContent = Array.isArray(contentArray)
      ? contentArray.map((c) => c.text).join("\n")
      : typeof rawResponse === "string"
      ? rawResponse
      : "";

    console.log("Text content=============== >>>", textContent);
    if (!textContent) {
      throw new Error("No valid text content returned from the agent");
    }

    const jsonMatch = textContent.match(/```json\s*([\s\S]*?)\s*```/i);
    if (!jsonMatch) {
      throw new Error("Could not extract JSON from agent response.");
    }

    let parsed;
    try {
      parsed = JSON.parse(jsonMatch[1]);
    } catch (e) {
      console.error("Bad JSON from model:\n", jsonMatch[1].slice(0, 500));
      throw new Error("Failed to parse JSON from agent response: " + e.message);
    }

    if (!parsed?.summary || !Array.isArray(parsed?.suggestions)) {
      throw new Error(
        "Agent response missing required fields: 'summary' or 'suggestions'"
      );
    }

    const diff = await fetchPRDiffTool({
      owner: input.owner,
      repo: input.repo,
      pull_number: input.pull_number,
    });

    return {
      summary: parsed.summary,
      suggestions: parsed.suggestions,
      parsedDiff: diff,
      message: parsed.message || "PR review completed successfully by agent.",
    };
  }
);
