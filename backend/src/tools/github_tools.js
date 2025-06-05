// tools/github_tools.js
import { ai } from "../ai.js"; // Assuming your ai instance is in ai.js
import { z } from "genkit";
import { Octokit } from "@octokit/rest";

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
