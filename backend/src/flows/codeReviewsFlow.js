import { ai } from "../ai.js";
import { z } from "genkit";
import { gemini20Flash } from "@genkit-ai/googleai"; // or any other model

// Define input schema
const CodeReviewInputSchema = z.object({
  code: z.string().describe("The code snippet to review"),
  language: z.string().describe("Programming language of the code"),
  focusAreas: z
    .string()
    .optional()
    .describe(
      "Specific areas to focus on (e.g., security, performance, readability)"
    ),
});

// Define output schema
const CodeReviewOutputSchema = z.object({
  summary: z.string().describe("General feedback summary"),
  suggestions: z.array(z.string()).describe("List of suggested improvements"),
  correctedCode: z
    .string()
    .describe(
      "The revised version of the input code with inline comments explaining changes"
    ),
});

export const codeReviewFlow = ai.defineFlow(
  {
    name: "codeReviewFlow",
    inputSchema: CodeReviewInputSchema,
  },
  async (input) => {
    const response = await ai.generate({
      prompt: `
You are a senior ${input.language} software engineer performing a code review.

Focus on: ${input.focusAreas || "General Code Quality"}

---
Input Code:
\`\`\`${input.language}
${input.code}
\`\`\`
---

Respond in this exact JSON format:
{
  "summary": "Brief summary of issues or observations.",
  "suggestions": ["Improvement 1", "Improvement 2"],
  "correctedCode": "Improved code with inline comments explaining changes."
}
`,
      model: gemini20Flash,
      output: { schema: CodeReviewOutputSchema },
    });

    return response.output;
  }
);
