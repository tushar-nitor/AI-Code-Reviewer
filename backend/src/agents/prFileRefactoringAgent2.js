// agents/codeRefactorAgent.js (create this new file)
import { ai } from "../ai.js";
import { gemini20Flash } from "@genkit-ai/googleai";
import {
  CodeRefactorInputSchema,
  CodeRefactorOutputSchema,
} from "../schema/schema.js";
import { refactorCodeTool } from "../tools/github_tools.js";
import { createDiffTool } from "../tools/diffTool.js";

export const codeRefactorAgent = ai.definePrompt({
  name: "codeRefactorPrompt",
  description:
    "Applies refactoring suggestions to code and generates a unified diff.",
  inputSchema: CodeRefactorInputSchema,
  model: gemini20Flash,
  // This agent orchestrates the refactoring and diff generation tools
  tools: [refactorCodeTool, createDiffTool],
  system: `You are an AI orchestrator for code refactoring. Your task is to:
  1. Use the 'refactorCodeTool' to apply given suggestions to the original code.
  2. Use the 'createDiffTool' to generate a unified diff between the original and refactored code.
  3. Combine the refactored code and the generated diff into the final structured output.
  You must ensure all data is correctly passed between steps and formatted for the final output.`,
  outputSchema: CodeRefactorOutputSchema, // The expected output schema

  prompt: ({ fileName, originalContent, suggestions, language }) => {
    // IMPORTANT: The AI's job is to chain these tool calls using placeholders.
    return `
You are managing a code refactoring task for the file "${fileName}" (language: ${language}).

### Workflow Steps:

1.  **Refactor Code:** Call the \`refactorCodeTool\` to apply the provided suggestions to the original content.
    \`\`\`json
    {
      "fileName": "${fileName}",
      "fileContent": ${JSON.stringify(
        originalContent
      )}, // Pass originalContent directly
      "suggestions": ${JSON.stringify(suggestions)},
      "language": "${language}"
    }
    \`\`\`
    Extract the \`refactoredContent\` (the complete refactored code) from the tool's response.

2.  **Generate Diff:** Call the \`createDiffTool\` to generate a unified diff between the original and the refactored code.
    \`\`\`json
    {
      "fileName": "${fileName}",
      "originalContent": ${JSON.stringify(
        originalContent
      )}, // Original content again
      "refactoredContent": "<refactored_content_from_step_1>" // Use placeholder for refactored content
    }
    \`\`\`
    Extract the \`diff\` string from the tool's response.

3.  **Construct Final Output:** Provide a single JSON object that strictly adheres to the \`CodeRefactorOutputSchema\`.
    -   \`refactoredContent\`: The refactored code obtained from Step 1.
    -   \`diff\`: The diff string obtained from Step 2.
    -   \`message\`: A summary string like "Code refactored and diff generated successfully."

    **IMPORTANT: Your response MUST be ONLY this JSON object, enclosed within a markdown code block (i.e., \`\`\`json\n...\n\`\`\` ). Do NOT include any other text or conversational remarks outside of this JSON block.**
`;
  },
});
