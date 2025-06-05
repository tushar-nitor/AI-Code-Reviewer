// flows/postPRCommentsFlow.js
import { ai } from "../ai.js";
import { z } from "genkit";
import { postGitHubPRCommentTool } from "../tools/github_tools.js"; // Import the new tool

// Define the IssueTypeEnum for consistency
const IssueTypeEnum = z
  .enum([
    "SECURITY",
    "PERFORMANCE",
    "READABILITY",
    "BUG",
    "STYLE",
    "BEST_PRACTICE",
    "TYPO",
    "OTHER",
  ])
  .describe("Type of the issue identified in the suggestion.");

// Define the schema for a single suggestion (consistent with your prReviewFlow output)
const SuggestionSchema = z.object({
  fileName: z
    .string()
    .describe("The name of the file the suggestion applies to."),
  suggestionText: z.string().describe("The suggestion for improvement."),
  type: IssueTypeEnum.optional(), // Make type optional in case LLM misses it sometimes

  // lineNumber: z
  //   .number()
  //   .optional()
  //   .describe(
  //     "Optional line number in the NEW file where the suggestion applies."
  //   ),
});

export const postPRCommentsFlow = ai.defineFlow(
  {
    name: "postPRCommentsFlow",
    inputSchema: z.object({
      owner: z.string().describe("Repository owner (e.g., 'octocat')"),
      repo: z.string().describe("Repository name (e.g., 'Spoon-Knife')"),
      pull_number: z.number().describe("Pull request number"),
      suggestions: z
        .array(SuggestionSchema)
        .describe(
          "An array of suggestions to be posted as comments on the PR."
        ),
      // Optional: Choose to post all suggestions as one large comment
      postAsSingleComment: z
        .boolean()
        .optional()
        .default(false)
        .describe(
          "If true, all suggestions are combined into a single comment; otherwise, each is a separate comment."
        ),
    }),
    outputSchema: z.object({
      success: z.boolean().describe("True if the operation was successful."),
      message: z.string().describe("A summary message of the operation."),
      commentsPostedCount: z
        .number()
        .describe("The number of comments successfully posted."),
      failedCommentsCount: z
        .number()
        .describe("The number of comments that failed to post."),
      commentUrls: z
        .array(z.string())
        .optional()
        .describe("URLs of the successfully posted comments."),
    }),
  },
  async (input) => {
    let commentsPostedCount = 0;
    let failedCommentsCount = 0;
    const commentUrls = [];
    let overallSuccess = true;
    let overallMessage = "";

    if (!input.suggestions || input.suggestions.length === 0) {
      return {
        success: true,
        message: "No suggestions provided to post.",
        commentsPostedCount: 0,
        failedCommentsCount: 0,
        commentUrls: [],
      };
    }

    if (input.postAsSingleComment) {
      // Option 1: Combine all suggestions into one large comment
      let combinedCommentBody = "## AI Code Review Suggestions\n\n";
      input.suggestions.forEach((s, index) => {
        const lineNumberText = s.lineNumber ? ` (Line ${s.lineNumber})` : "";
        combinedCommentBody += `${index + 1}. **\`${
          s.fileName
        }\`**${lineNumberText}: ${s.suggestionText}\n\n`;
      });

      console.log("Posting combined comment...");
      const result = await postGitHubPRCommentTool({
        owner: input.owner,
        repo: input.repo,
        pull_number: input.pull_number,
        commentBody: combinedCommentBody,
      });

      if (result.success) {
        commentsPostedCount = 1;
        if (result.commentUrl) commentUrls.push(result.commentUrl);
        overallMessage =
          "All suggestions combined and posted as a single comment.";
      } else {
        failedCommentsCount = 1;
        overallSuccess = false;
        overallMessage = `Failed to post combined comment: ${result.message}`;
      }
    } else {
      // Option 2: Post each suggestion as an individual comment
      for (const suggestion of input.suggestions) {
        const lineNumberText = suggestion.lineNumber
          ? ` (Line ${suggestion.lineNumber})`
          : "";
        const commentBody = `### Suggestion for \`${suggestion.fileName}\`${lineNumberText}\n\n${suggestion.suggestionText}`;

        console.log(
          `Posting comment for ${suggestion.fileName}${lineNumberText}...`
        );
        const result = await postGitHubPRCommentTool({
          owner: input.owner,
          repo: input.repo,
          pull_number: input.pull_number,
          commentBody: commentBody,
        });

        if (result.success) {
          commentsPostedCount++;
          if (result.commentUrl) commentUrls.push(result.commentUrl);
        } else {
          failedCommentsCount++;
          console.error(
            `Failed to post comment for ${suggestion.fileName}: ${result.message}`
          );
          overallSuccess = false; // If any fails, the overall operation is considered failed
        }
      }

      if (commentsPostedCount > 0 && failedCommentsCount === 0) {
        overallMessage = `Successfully posted ${commentsPostedCount} comments.`;
      } else if (commentsPostedCount > 0 && failedCommentsCount > 0) {
        overallMessage = `Posted ${commentsPostedCount} comments, but ${failedCommentsCount} failed. Check logs for details.`;
      } else {
        overallMessage = `Failed to post any comments. Total failures: ${failedCommentsCount}.`;
      }
    }

    return {
      success: overallSuccess,
      message: overallMessage,
      commentsPostedCount,
      failedCommentsCount,
      commentUrls: commentUrls.filter(Boolean), // Filter out any undefined/null URLs
    };
  }
);
