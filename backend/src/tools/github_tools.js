// tools/github_tools.js
import { ai } from "../ai.js";
import { z } from "genkit";
import { Octokit } from "@octokit/rest"; // Correct import for Octokit class
// gemini20Flash import is not needed in a tools file, it belongs where the model is used (e.g., in prompts or flows)
import { gemini20Flash } from "@genkit-ai/googleai"; // Remove this line

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
      token: z.string(), // ✅ Add token here
    }),
    outputSchema: z
      .string()
      .describe("The diff content of the pull request as a string."),
  },
  async ({ owner, repo, pull_number, token }) => {
    const octokit = new Octokit({
      auth: token,
    });
    // Add check if octokit is valid before proceeding
    if (!octokit || typeof octokit.pulls?.get !== "function") {
      const msg = `Octokit or its 'pulls.get' method is not initialized. Check GITHUB_TOKEN and Octokit setup.`;
      console.error(`[fetchPRDiffTool] ${msg}`);
      throw new Error(msg); // Throw specific error to be caught by Genkit
    }
    try {
      console.log(
        `[fetchPRDiffTool] Attempting to fetch PR info for: ${owner}/${repo} Pull #${pull_number}`
      );
      const response = await octokit.pulls.get({
        owner,
        repo,
        pull_number,
        mediaType: {
          format: "diff", // Request the diff format
        },
      });
      return response.data;
    } catch (error) {
      console.error(
        `[fetchPRDiffTool] Failed to fetch PR diff for ${owner}/${repo}#${pull_number}:`,
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
      token: z.string().describe("GitHub personal access token"),
    }),
    outputSchema: z.object({
      success: z.boolean(),
      message: z.string(),
      commentUrl: z.string().optional(), // URL of the posted comment
    }),
  },
  async ({ owner, repo, pull_number, commentBody, token }) => {
    // Add check if octokit is valid before proceeding
    const octokit = new Octokit({
      auth: token,
    });
    if (!octokit || typeof octokit.rest?.issues?.createComment !== "function") {
      const msg = `Octokit or its 'rest.issues.createComment' method is not initialized. Check GITHUB_TOKEN and Octokit setup.`;
      console.error(`[postGitHubPRCommentTool] ${msg}`);
      throw new Error(msg);
    }
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
        `[postGitHubPRCommentTool] Error posting comment to PR ${owner}/${repo}#${pull_number}:`,
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
      owner: z
        .string()
        .describe("The owner of the repository (e.g., 'octocat')."),
      repo: z
        .string()
        .describe("The name of the repository (e.g., 'Spoon-Knife')."),
      pull_number: z.number().describe("The pull request number."),
      token: z.string().describe("GitHub personal access token"),
    }),
    outputSchema: z.object({
      head_sha: z
        .string()
        .describe("The SHA of the head of the source branch."),
    }),
  },
  async ({ owner, repo, pull_number, token }) => {
    const octokit = new Octokit({
      auth: token,
    });

    // Add check if octokit is valid before proceeding
    if (!octokit || typeof octokit.pulls?.get !== "function") {
      const msg = `Octokit or its 'pulls.get' method is not initialized. Check GITHUB_TOKEN and Octokit setup.`;
      console.error(`[getPRInfoTool] ${msg}`);
      throw new Error(msg);
    }
    try {
      console.log(
        `[getPRInfoTool] Attempting to fetch PR info for: ${owner}/${repo} Pull #${pull_number} Token: ${token}` // Log the token for debugging
      );
      const response = await octokit.pulls.get({
        owner,
        repo,
        pull_number,
      });

      console.log(
        `[getPRInfoTool] Raw GitHub API response.data keys: ${Object.keys(
          response.data
        ).join(", ")}`
      );
      if (response.data.head) {
        console.log(
          `[getPRInfoTool] Raw GitHub API response.data.head keys: ${Object.keys(
            response.data.head
          ).join(", ")}`
        );
      } else {
        console.log(
          `[getPRInfoTool] WARNING: response.data.head is missing for ${owner}/${repo}#${pull_number}`
        );
      }

      const head_sha = response.data.head?.sha; // Use optional chaining for safety

      if (!head_sha) {
        const msg = `Head SHA not found or is empty for ${owner}/${repo}#${pull_number}. Full head data: ${JSON.stringify(
          response.data.head || "N/A"
        )}`;
        console.error(`[getPRInfoTool] Error: ${msg}`);
        throw new Error(msg);
      }

      console.log(
        `[getPRInfoTool] Successfully retrieved head_sha: ${head_sha} for ${owner}/${repo}#${pull_number}`
      );
      return { head_sha };
    } catch (error) {
      console.error(
        `[getPRInfoTool] FATAL ERROR fetching PR info for ${owner}/${repo}#${pull_number}:`,
        error
      );
      // Re-throw with more detail, including the original error message if available
      throw new Error(`Failed to fetch PR info: ${error.message || error}`); // <--- This line is key
    }
  }
);

// --- Activate the File Content Tool ---
export const fetchFileContentTool = ai.defineTool(
  {
    name: "fetchFileContentTool",
    description:
      "Fetches the content of a specific file from a GitHub repository.",
    inputSchema: z.object({
      owner: z.string(),
      repo: z.string(),
      path: z.string().describe("Path to the file in the repository."),
      token: z.string().describe("GitHub personal access token"),
      ref: z
        .string()
        .optional()
        .describe(
          "The name of the commit/branch/tag. Defaults to the default branch."
        ),
    }),
    outputSchema: z.string().describe("The content of the file."),
  },
  async ({ owner, repo, path, ref, token }) => {
    const octokit = new Octokit({
      auth: token,
    });
    // Add check if octokit is valid before proceeding
    if (!octokit || typeof octokit.repos?.getContent !== "function") {
      const msg = `Octokit or its 'repos.getContent' method is not initialized. Check GITHUB_TOKEN and Octokit setup.`;
      console.error(`[fetchFileContentTool] ${msg}`);
      throw new Error(msg);
    }
    try {
      console.log(
        `[fetchFileContentTool] Attempting to fetch file: ${owner}/${repo}/${path} at ref ${ref}`
      );
      const response = await octokit.repos.getContent({
        owner,
        repo,
        path,
        ref,
      });
      if (response.data && response.data.type === "file") {
        return Buffer.from(response.data.content, "base64").toString("utf8");
      }
      throw new Error("Path does not point to a file or content not found.");
    } catch (error) {
      console.error(
        `[fetchFileContentTool] Failed to fetch file content for ${owner}/${repo}/${path}:`,
        error
      );
      throw new Error(`Failed to fetch file content: ${error.message}`);
    }
  }
);

// --- NEW: AI-Powered Refactoring Tool ---
export const refactorCodeTool = ai.defineTool(
  {
    name: "refactorCodeTool",
    description:
      "Applies a list of suggested changes to a block of code and returns the single, final version of the refactored code.",
    inputSchema: z.object({
      fileName: z
        .string()
        .describe("The name/path of the file being refactored."),
      fileContent: z
        .string()
        .describe("The entire original source code of the file."),
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
  async ({ fileName, fileContent, suggestions, language, token }) => {
    if (!ai || typeof ai.generate !== "function") {
      // Check if 'ai' is available for LLM call
      const msg = `AI generation client is not initialized for refactorCodeTool.`;
      console.error(`[refactorCodeTool] ${msg}`);
      throw new Error(msg);
    }
    console.error(
      `[refactorCodeTool] Started ======================>>>>>>>>>>>>>>>>>`,
      error
    );
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
    try {
      const llmResponse = await ai.generate({
        model: gemini20Flash, // This is explicitly defined here
        prompt: prompt,
        config: { temperature: 0.3 },
      });

      if (!llmResponse.text) {
        throw new Error("LLM response was empty or null.");
      }
      return llmResponse.text;
    } catch (llmError) {
      console.error(
        `[refactorCodeTool] LLM generation failed for ${fileName}:`,
        llmError
      );
      throw new Error(`AI refactoring failed: ${llmError.message}`);
    }
  }
);
