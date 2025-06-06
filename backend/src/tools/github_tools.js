// tools/github_tools.js
import { ai } from "../ai.js"; // Assuming your ai instance is in ai.js
import { z } from "genkit";
import { Octokit } from "@octokit/rest";
import { gemini20Flash } from "@genkit-ai/googleai";

// Initialize Octokit with your GitHub Token from environment variables
// IMPORTANT: Ensure GITHUB_TOKEN is set securely in your deployment environment
const octokit = new Octokit({
  auth: process.env.GITHUB_TOKEN,
});

/**
 * Genkit Tool to fetch the diff of a GitHub Pull Request.
 */
export const fetchPRDiffTool = ai.defineTool(
  {
    name: "fetchPRDiff",
    description: "Fetches the diff content of a GitHub Pull Request.",
    inputSchema: z.object({
      owner: z
        .string()
        .describe("The owner of the repository (e.g., 'octocat')."),
      repo: z
        .string()
        .describe("The name of the repository (e.g., 'Spoon-Knife')."),
      pull_number: z.number().describe("The pull request number."),
    }),
    outputSchema: z
      .string()
      .describe("The diff content of the pull request as a string."),
  },
  async ({ owner, repo, pull_number }) => {
    try {
      const response = await octokit.pulls.get({
        owner,
        repo,
        pull_number,
        mediaType: {
          format: "diff", // Request the diff format
        },
      });
      // Octokit's response.data for diffs is typically a string, but types might show 'unknown'
      return response.data;
    } catch (error) {
      console.error(
        `Failed to fetch PR diff for ${owner}/${repo}#${pull_number}:`,
        error
      );
      throw new Error(`Failed to fetch PR diff: ${error.message}`);
    }
  }
);

// --- New Tool for Posting Comments ---

export const postGitHubPRCommentTool = ai.defineTool(
  {
    name: "postGitHubPRComment",
    description: "Posts a general comment to a GitHub Pull Request.",
    inputSchema: z.object({
      owner: z.string().describe("Repository owner (e.g., 'octocat')"),
      repo: z.string().describe("Repository name (e.g., 'Spoon-Knife')"),
      pull_number: z.number().describe("Pull request number"),
      commentBody: z.string().describe("The content of the comment."),
    }),
    outputSchema: z.object({
      success: z.boolean(),
      message: z.string(),
      commentUrl: z.string().optional(), // URL of the posted comment
    }),
  },
  async ({ owner, repo, pull_number, commentBody }) => {
    try {
      // GitHub API uses 'issues.createComment' for PR comments too
      const response = await octokit.rest.issues.createComment({
        owner,
        repo,
        issue_number: pull_number, // PRs are considered 'issues' in this API context
        body: commentBody,
      });
      return {
        success: true,
        message: `Comment posted successfully to PR #${pull_number}.`,
        commentUrl: response.data.html_url,
      };
    } catch (error) {
      console.error(
        `Error posting comment to PR ${owner}/${repo}#${pull_number}:`,
        error
      );
      return {
        success: false,
        message: `Failed to post comment: ${error.message}`,
      };
    }
  }
);

// --- NEW: Tool to get PR Info, including the head SHA ---
export const getPRInfoTool = ai.defineTool(
  {
    name: "getPRInfo",
    description:
      "Fetches details of a specific GitHub Pull Request, including the head SHA of the source branch.",
    inputSchema: z.object({
      owner: z.string().describe("Repository owner"),
      repo: z.string().describe("Repository name"),
      pull_number: z.number().describe("The pull request number."),
    }),
    outputSchema: z.object({
      head_sha: z
        .string()
        .describe("The SHA of the head of the source branch."),
    }),
  },
  async ({ owner, repo, pull_number }) => {
    try {
      const response = await octokit.pulls.get({
        owner,
        repo,
        pull_number,
      });

      // The response object contains the full details of the PR.
      // We only need the SHA of the head of the source branch.
      const head_sha = response.data.head.sha;
      if (!head_sha) {
        throw new Error("Head SHA not found in PR response.");
      }

      return { head_sha };
    } catch (error) {
      console.error(
        `Failed to fetch PR info for ${owner}/${repo}#${pull_number}:`,
        error
      );
      throw new Error(`Failed to fetch PR info: ${error.message}`);
    }
  }
);

// --- Activate the File Content Tool ---
// This tool is essential for the refactoring flow.
export const fetchFileContentTool = ai.defineTool(
  {
    name: "fetchFileContent",
    description:
      "Fetches the content of a specific file from a GitHub repository.",
    inputSchema: z.object({
      owner: z.string(),
      repo: z.string(),
      path: z.string().describe("Path to the file in the repository."),
      ref: z
        .string()
        .optional()
        .describe(
          "The name of the commit/branch/tag. Defaults to the default branch."
        ),
    }),
    outputSchema: z.string().describe("The content of the file."),
  },
  async ({ owner, repo, path, ref }) => {
    try {
      const response = await octokit.repos.getContent({
        owner,
        repo,
        path,
        ref,
      });
      // Content is base64 encoded for files
      if (response.data && response.data.type === "file") {
        return Buffer.from(response.data.content, "base64").toString("utf8");
      }
      throw new Error("Path does not point to a file or content not found.");
    } catch (error) {
      console.error(
        `Failed to fetch file content for ${owner}/${repo}/${path}:`,
        error
      );
      throw new Error(`Failed to fetch file content: ${error.message}`);
    }
  }
);

// --- NEW: AI-Powered Refactoring Tool ---
// This tool takes code and a suggestion, and uses an LLM to perform the refactor.

export const refactorCodeTool = ai.defineTool(
  {
    name: "refactorCode",
    description:
      "Applies a list of suggested changes to a block of code and returns the single, final version of the refactored code.",
    inputSchema: z.object({
      fileName: z
        .string()
        .describe("The name/path of the file being refactored."),
      fileContent: z
        .string()
        .describe("The entire original source code of the file."),
      // It now accepts an array of strings
      suggestions: z
        .array(z.string())
        .describe(
          "A list of natural language suggestions to apply to the code."
        ),
      language: z.string().describe("The programming language of the code."),
    }),
    outputSchema: z
      .string()
      .describe(
        "The complete, final source code for the file after all suggestions have been applied."
      ),
  },
  async ({ fileName, fileContent, suggestions, language }) => {
    // We format the list of suggestions for the prompt.
    const formattedSuggestions = suggestions
      .map((s, index) => `${index + 1}. ${s}`)
      .join("\n");

    const prompt = `You are an expert automated code refactoring engine. Your task is to intelligently apply a list of changes to the given source code while strictly preserving its original functionality.

**CRITICAL INSTRUCTIONS:**
1.  **Do Not Change Functionality:** Your primary goal is to refactor the code for improvement (e.g., readability, style, best practices) based on the suggestions. You must **not** alter the logic, behavior, or output of the code.
2.  **Apply ALL Suggestions:** Synthesize all suggestions from the list into a single, coherent, final version of the file.
3.  **Add Refactoring Comments:** At every location where you apply a change, you **must add a single-line comment** on the line directly above the changed code. The comment should be in the format \`// REFACTOR: [Brief reason for the change based on the suggestion]\`.
4.  **Handle Context Shifts:** Intelligently manage changes in line numbers. A change from an early suggestion might shift the context for a later one; you need to account for this.
5.  **Return Full Raw Code:** The output must be the **ENTIRE, complete source code** for the file. Do not return a diff, a patch, or just the changed lines.
6.  **No Formatting:** **DO NOT** wrap the output in markdown backticks (e.g., \\\`\\\`\\\`javascript) or any other formatting.

---
**Programming Language:** ${language}
**File Name:** ${fileName}
---
**List of Suggestions to Apply:**
${formattedSuggestions}
---
**Original Source Code:**
\\\`\\\`\\\`
${fileContent}
\\\`\\\`\\\`
---

Now, provide the complete and final source code after applying all the suggestions, including the specified \`// REFACTOR:\` comments.`;

    const llmResponse = await ai.generate({
      // For complex tasks like this, a more powerful model is recommended
      model: gemini20Flash,
      prompt: prompt,
      // Increase temperature slightly to give the model more "creativity" in resolving suggestion conflicts
      config: { temperature: 0.3 },
    });

    return llmResponse.text;
  }
);

// You can add more tools here, like fetching individual file contents from a repo:
/*
export const fetchFileContentTool = ai.defineTool(
  {
    name: "fetchFileContent",
    description: "Fetches the content of a specific file from a GitHub repository.",
    inputSchema: z.object({
      owner: z.string(),
      repo: z.string(),
      path: z.string().describe("Path to the file in the repository."),
      ref: z.string().optional().describe("The name of the commit/branch/tag. Defaults to the default branch."),
    }),
    outputSchema: z.string().describe("The content of the file."),
  },
  async ({ owner, repo, path, ref }) => {
    try {
      const response = await octokit.repos.getContent({
        owner,
        repo,
        path,
        ref,
      });
      // Content is base64 encoded for files
      if (response.data && response.data.type === 'file') {
        return Buffer.from(response.data.content, 'base64').toString('utf8');
      }
      throw new Error("Path does not point to a file or content not found.");
    } catch (error) {
      console.error(`Failed to fetch file content for ${owner}/${repo}/${path}:`, error);
      throw new Error(`Failed to fetch file content: ${error.message}`);
    }
  }
);
*/
