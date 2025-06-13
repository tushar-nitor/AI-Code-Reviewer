// flows/codingStandardsFlow.js
import { ai } from "../ai.js";
import { z } from "genkit";
import { gemini20Flash } from "@genkit-ai/googleai";

// --- Schemas ---

// The schema for the final, structured output of the flow.
const CodingStandardsResultSchema = z.object({
  language: z
    .string()
    .describe("The programming language for which standards were generated."),
  summary: z
    .string()
    .describe(
      "A high-level summary of the coding philosophy and key principles for the language."
    ),
  bestPractices: z
    .array(
      z.object({
        ruleName: z
          .string()
          .describe(
            "A short, descriptive name for the rule (e.g., 'avoid-dynamic', 'prefer-const')."
          ),
        description: z
          .string()
          .describe("A brief explanation of what the rule enforces and why."),
      })
    )
    .describe("A list of key best practices and coding rules."),
  implementationGuide: z
    .string()
    .describe(
      "Actionable, step-by-step instructions on how to create and use a configuration file (like analysis_options.yaml or .eslintrc.js) to enforce these rules."
    ),
});

// --- Flow Definition ---

export const codingStandardsFlow = ai.defineFlow(
  {
    name: "codingStandardsFlow",
    inputSchema: z.object({
      language: z
        .string()
        .describe(
          "The programming language to generate standards for (e.g., 'Dart', 'JavaScript', 'Python')."
        ),
    }),
    outputSchema: CodingStandardsResultSchema,
  },
  async (input) => {
    try {
      // 1. Generate the prompt for the LLM
      const prompt = `
You are an expert software architect and a specialist in creating clear, actionable coding standards for development teams.

Based on the provided programming language, generate a set of key coding best practices, a summary, and a practical implementation guide. Your response must be comprehensive and tailored to the modern ecosystem of the language.

For example, for 'Dart', the implementation guide should focus on setting up an \`analysis_options.yaml\` file. For 'JavaScript' or 'TypeScript', it should focus on \`.eslintrc.js\` with popular plugins. For 'Python', it could be \`pyproject.toml\` with 'ruff' or 'flake8'.

---
## Content to Generate

1.  **Summary**: A brief, high-level overview of the coding standards.
2.  **Best Practices**: A list of important, specific rules. For each rule, provide a name and a clear description.
3.  **Implementation Guide**: A step-by-step guide that a developer can follow to create a configuration file and apply these standards to their project. Include example code for the configuration file itself.

---
📦 **Provide your entire output in the following strict JSON format**:

\\\json
{
  "summary": "A concise overview of the coding philosophy...",
  "bestPractices": [
    {
      "ruleName": "example-rule-name",
      "description": "A clear explanation of why this rule is important."
    }
  ],
  "implementationGuide": "A multi-line string, formatted with markdown, containing step-by-step setup instructions and a complete code block for the configuration file."
}
\\\

---

Here is the programming language: **${input.language}**

Provide a robust and professional set of standards.
`;

      // 2. Send to LLM to generate the standards
      const aiResponse = await ai.generate({
        model: gemini20Flash,
        prompt,
        output: {
          format: "json",
          // The schema here must match the structure you requested in the prompt
          schema: z.object({
            summary: CodingStandardsResultSchema.shape.summary,
            bestPractices: CodingStandardsResultSchema.shape.bestPractices,
            implementationGuide:
              CodingStandardsResultSchema.shape.implementationGuide,
          }),
        },
      });

      const output = aiResponse.output;

      if (!output) {
        throw new Error("Model returned null or malformed output.");
      }

      // 3. Return the structured results, adding back the language
      return {
        language: input.language,
        summary: output.summary,
        bestPractices: output.bestPractices,
        implementationGuide: output.implementationGuide,
      };
    } catch (error) {
      console.error("Coding Standards Flow Error:", error);
      const errorMessage = `Failed to generate coding standards: ${error.message}`;
      // Return an error structure that still conforms to the output schema
      return {
        language: input.language,
        summary: "Error generating standards.",
        bestPractices: [],
        implementationGuide: errorMessage,
      };
    }
  }
);
