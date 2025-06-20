// In tools/github_tools.js
import { ai } from "../ai.js";
import { z } from "genkit";
import * as Diff from "diff"; // Use the 'diff' package

// ... all your other tools ...

// --- Tool to Create a Diff String using the 'diff' package ---

export const createDiffTool = ai.defineTool(
  {
    name: "createDiffTool",
    description:
      "Compares two blocks of text and creates a unified diff string.",
    inputSchema: z.object({
      fileName: z
        .string()
        .describe("The name/path of the file being compared."),
      originalContent: z.string().describe("The original source code."),
      refactoredContent: z.string().describe("The refactored source code."),
    }),
    outputSchema: z
      .string()
      .describe("The resulting diff in the unified format."),
  },
  async ({ fileName, originalContent, refactoredContent }) => {
    // The createPatch function from 'diff' works identically to the one in 'jsdiff'
    const diffString = Diff.createPatch(
      fileName, // The original filename
      originalContent, // The original content
      refactoredContent, // The new content
      "Original", // Optional: header for the original version
      "Refactored" // Optional: header for the new version
    );

    return diffString;
  }
);
