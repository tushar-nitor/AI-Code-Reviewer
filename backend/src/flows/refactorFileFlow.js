// flows/batchRefactorFileFlow.js
import { ai } from "../ai.js";
import { z } from "genkit";
import {
  fetchFileContentTool,
  getPRInfoTool,
  refactorCodeTool,
  // Import our new batch tool
} from "../tools/github_tools.js";
import { createDiffTool } from "../tools/diffTool.js";

export const refactorFileFlow = ai.defineFlow(
  {
    name: "refactorFileFlow",
    inputSchema: z.object({
      owner: z.string().describe("Repository owner"),
      repo: z.string().describe("Repository name"),
      pull_number: z.number().describe("The pull request number"),
      path: z.string().describe("Path to the file to refactor"),
      // The schema now expects an array of suggestions
      suggestions: z
        .array(z.string())
        .describe("A list of suggestions from the code review to apply."),
      language: z.string().describe("The programming language of the file."),
    }),
    outputSchema: z.object({
      originalContent: z.string(),
      refactoredContent: z.string(),
      diff: z.string().describe("The unified diff string showing the changes."),
      message: z.string(),
    }),
  },
  async (input) => {
    try {
      // Step 1: Get the PR's head SHA (no changes here)
      const prInfo = await getPRInfoTool({
        owner: input.owner,
        repo: input.repo,
        pull_number: input.pull_number,
      });
      const headSha = prInfo.head_sha;

      // Step 2: Fetch the original file content (no changes here)
      const originalContent = await fetchFileContentTool({
        owner: input.owner,
        repo: input.repo,
        path: input.path,
        ref: headSha,
      });

      if (!originalContent) {
        throw new Error(`Could not fetch content for file: ${input.path}`);
      }

      // Step 3: Use the NEW batch tool to generate the refactored code
      const refactoredContent = await refactorCodeTool({
        fileName: input.path,
        fileContent: originalContent,
        suggestions: input.suggestions, // Pass the whole array
        language: input.language,
      });
      // 4. NEW STEP: Generate the diff string
      const diff = await createDiffTool({
        fileName: input.path,
        originalContent: originalContent,
        refactoredContent: refactoredContent,
      });

      return {
        originalContent,
        refactoredContent,
        diff,
        message: `${input.suggestions.length} suggestions successfully applied.`,
      };
    } catch (error) {
      console.error("Batch Refactor File Flow Error:", error);
      return {
        originalContent: "",
        refactoredContent: "",
        message: `Error during batch refactoring: ${error.message}`,
      };
    }
  }
);
