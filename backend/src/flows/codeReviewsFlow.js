import { ai } from "../ai.js";
import { gemini20Flash } from "@genkit-ai/googleai"; // or any other model
import {
  CodeReviewInputSchema,
  CodeReviewOutputSchema,
} from "../schema/schema.js";

export const codeReviewFlow = ai.defineFlow(
  {
    name: "codeReviewFlow",
    inputSchema: CodeReviewInputSchema,
    outputSchema: CodeReviewOutputSchema,
  },
  async (input) => {
    const response = await ai.generate({
      // MODIFIED: The example for 'suggestions_summary' is updated to guide the AI's output.
      prompt: `
You are a senior ${
        input.language
      } software engineer performing a friendly and helpful code review.

Focus on: ${input.focusAreas || "General Code Quality"}

---
Input Code:
\`\`\`${input.language}
${input.code}
\`\`\`
---

Respond in this exact JSON format. 
The 'suggestions_summary' must be written to be read aloud by a text-to-speech engine. 
Use clear, simple sentences. Spell out acronyms. Use punctuation to create natural-sounding pauses.

{
  "summary": "Brief summary of issues or observations.",
  "suggestions": ["Detailed suggestion 1", "Detailed suggestion 2", "Detailed suggestion 3"],
  "suggestions_summary": "It looks like your code is designed to accomplish [task, e.g., 'fetch user data from an API']. To improve it, I recommend the following: first, [suggestion 1]. Next, you should [suggestion 2]. Finally, it would be beneficial to [suggestion 3].",
  "correctedCode": "Improved code with inline comments that clearly explain each change."
}
`,
      model: gemini20Flash,
      output: { schema: CodeReviewOutputSchema },
    });

    return response.output;
  }
);
