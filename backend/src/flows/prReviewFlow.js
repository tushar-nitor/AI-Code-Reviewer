// flows/prReviewFlow.js
import { ai } from "../ai.js";
import { z } from "genkit";
import { fetchPRDiffTool } from "../tools/github_tools.js";
import { gemini20Flash } from "@genkit-ai/googleai";
import parseDiff from "parse-diff";

// --- Schemas ---

// Schema for a single file's changes within the parsed diff
// Sticking to your desired simple format: filePath, addedLines, deletedLines
const FileDiffSchema = z.object({
  filePath: z
    .string()
    .describe("Path of the file that was changed (e.g., 'src/index.js')."),
  addedLines: z
    .array(z.string())
    .describe("Lines added in this file (without '+ ' prefix)."),
  deletedLines: z
    .array(z.string())
    .describe("Lines deleted in this file (without '- ' prefix)."),
});

// Overall schema for the structured code review result
const CodeReviewResultSchema = z.object({
  summary: z
    .string()
    .describe("A concise summary of the code review findings."),
  suggestions: z
    .array(
      z.object({
        fileName: z
          .string()
          .describe(
            "The name of the file the suggestion applies to (e.g., 'src/main.py')."
          ),
        suggestionText: z.string().describe("The suggestion for improvement."),
        lineNumber: z
          .number()
          .optional()
          .describe(
            "Optional line number in the NEW file where the suggestion applies, if relevant."
          ),
      })
    )
    .describe(
      "An itemized list of specific suggestions for improvement with file names and optional line numbers."
    ),
  // This `parsedDiff` array MUST match the `FileDiffSchema` exactly as the LLM is asked to return it.
  parsedDiff: z
    .any()
    .describe(
      "The parsed diff content, separated by file, as provided to the AI and expected back."
    ),
  message: z
    .string()
    .optional()
    .describe("A general message about the review process."),
});

// --- Flow Definition ---

export const prReviewFlow = ai.defineFlow(
  {
    name: "prReviewFlow",
    inputSchema: z.object({
      owner: z.string().describe("Repository owner (e.g., 'octocat')"),
      repo: z.string().describe("Repository name (e.g., 'Spoon-Knife')"),
      pull_number: z.number().describe("Pull request number"),
      language: z
        .string()
        .describe(
          "Programming language of the code to review (e.g., 'JavaScript', 'Python')"
        ),
      focusAreas: z
        .string()
        .optional()
        .describe(
          "Optional areas to focus on (e.g., 'security', 'performance')"
        ),
    }),
    outputSchema: CodeReviewResultSchema,
  },
  async (input) => {
    try {
      // 1. Fetch the raw PR diff content
      const rawDiffContent = await fetchPRDiffTool({
        owner: input.owner,
        repo: input.repo,
        pull_number: input.pull_number,
      });

      if (!rawDiffContent) {
        throw new Error(
          "Failed to fetch PR diff: Diff content was empty or null."
        );
      }

      // 2. Parse the raw diff content into your desired structured format
      const files = parseDiff(rawDiffContent);
      const parsedDiffForLLM = files.map((file) => {
        // Use 'to' for new files, 'from' for deleted, otherwise for modified.
        // Provide 'unknown' if both are null (shouldn't happen with valid diffs).
        const filePath = file.to || file.from || "unknown";

        const addedLines = [];
        const deletedLines = [];

        // Ensure chunks exist before iterating
        if (file.chunks) {
          file.chunks.forEach((chunk) => {
            chunk.changes.forEach((change) => {
              // 'parse-diff' uses 'add' and 'del' for inserted/deleted lines
              if (change.type === "add") {
                // Remove the '+' prefix if present, as your schema wants just the content
                addedLines.push(
                  change.content.startsWith("+")
                    ? change.content.substring(1)
                    : change.content
                );
              } else if (change.type === "del") {
                // Remove the '-' prefix if present
                deletedLines.push(
                  change.content.startsWith("-")
                    ? change.content.substring(1)
                    : change.content
                );
              }
              // 'normal' type is for context lines, which you've opted not to include in this simplified format.
            });
          });
        }

        return {
          filePath,
          addedLines,
          deletedLines,
        };
      });

      // console.log(
      //   "Parsed diff content (simplified for LLM):",
      //   JSON.stringify(parsedDiffForLLM, null, 2)
      // );

      // 3. Generate the prompt for the LLM
      const prompt = `You are an expert code reviewer. Your task is to provide a comprehensive review of the following ${
        input.language
      } code changes.
        The diff is provided as a structured array of file changes, where each file object contains its 'filePath', 'addedLines' (lines added without '+ ' prefix), and 'deletedLines' (lines removed without '- ' prefix).
        Focus your review on ${
          input.focusAreas ||
          "general best practices, code quality, potential bugs, and adherence to best practices"
        }.

Here are the file changes diff:
${rawDiffContent}


\`\`\`json
{
  "summary": "A concise overview of your key findings.",
  "suggestions": [
    {
      "fileName": "path/to/file.js",
      "suggestionText": "Specific, actionable improvement suggestion.",
      "lineNumber": 123
    }
  ],
  "parsedDiff":"",
  "message": "Optional general message about the review process or next steps."
}
\`\`\`

When populating the "parsedDiff" field, **re-include the exact parsed diff JSON you received above**. Do NOT modify, summarize, or omit any part of it. This is crucial for consistency and downstream processing. Ensure all fields in the output JSON are present, even if empty (e.g., an empty 'suggestions' array if no suggestions).`;

      // 4. Send to LLM for review
      const aiResponse = await ai.generate({
        model: gemini20Flash,
        prompt,
        output: {
          format: "json",
          schema: CodeReviewResultSchema, // Genkit uses this to validate and parse the LLM's output
        },
      });

      const output = aiResponse.output;
      // Genkit's `ai.generate` with output schema already validates the output.
      // If it reaches here, the output *should* conform to the schema.
      // If it doesn't, Genkit would have thrown an error earlier.
      if (!output) {
        // This block might be redundant if Genkit throws on validation failure,
        // but it's a good safeguard for unexpected nulls.
        throw new Error(
          "Model returned null or malformed output after Genkit's validation."
        );
      }

      // 5. Return the structured results
      return {
        summary: output.summary,
        suggestions: output.suggestions,
        parsedDiff: rawDiffContent,
        //JSON.stringify(parsedDiffForLLM, null, 2), // This will be the parsedDiff that the LLM returned, which should match your input.
        message: output.message || "PR review completed successfully.",
      };
    } catch (error) {
      console.error("PR Review Flow Error:", error);
      // More specific error message for schema validation failures
      let errorMessage = "An unexpected error occurred during PR review.";
      if (error.message && error.message.includes("Schema validation failed")) {
        errorMessage = `Schema validation failed for AI model output. This often means the AI did not return the expected JSON format. Details: ${error.message}`;
      } else {
        errorMessage = `PR review failed: ${error.message}`;
      }

      // Ensure the error return matches the outputSchema for consistency
      return {
        summary: `Review failed: ${errorMessage}`,
        suggestions: [],
        parsedDiff: [], // Return empty array on failure to match schema
        message: errorMessage,
      };
    }
  }
);
