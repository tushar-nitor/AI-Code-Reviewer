// prompts/postPRCommentsPrompt.js
import { ai } from "../ai.js";
import { z } from "genkit";
import { postGitHubPRCommentTool } from "../tools/github_tools.js";
import { gemini20Flash } from "@genkit-ai/googleai";
import {
  PostPRCommentsInputSchema,
  PostPRCommentOutputSchema,
  IssueTypeEnum,
  SeverityTypeEnum,
} from "../schema/schema.js";

// Prompt-based PR comment poster
export const postPRCommentsPrompt = ai.definePrompt(
  {
    name: "postPRCommentsPrompt",
    description: "Post code suggestions as comments on a GitHub PR.",
    inputSchema: PostPRCommentsInputSchema,
    tools: [postGitHubPRCommentTool],
    model: gemini20Flash,
    outputSchema: PostPRCommentOutputSchema,
  },
  `
You are a GitHub bot that posts AI-generated review suggestions on a pull request.

Use the tool \`postGitHubPRCommentTool\` to post suggestions:
You are given:
- owner: The GitHub repo owner
- repo: The GitHub repo name
- pull_number: The pull request number
- postAsSingleComment: Boolean
- suggestions: An array of suggestions. Each suggestion includes:
  - fileName
  - suggestionText

Here is the data:
{
  "owner": {{owner}},
  "repo": {{repo}},
  "pull_number": {{pull_number}},
  "suggestions" :{{suggestions}},
  "postAsSingleComment" :{{postAsSingleComment}}
}

{{#if postAsSingleComment}}
  ## AI Code Review Suggestions

  {{#each suggestions}}1. **\`{{this.fileName}}\`**: {{this.suggestionText}}
{{/each}}
{{else}}
  {{#each suggestions}}
    ### Suggestion for \`{{this.fileName}}\`

    {{this.suggestionText}}
  {{/each}}
{{/if}}

Track how many comments succeeded or failed, and collect URLs of posted comments.

Return the result in this format:

{
  "success": true | false,
  "message": "Summary of the result",
  "commentsPostedCount": 2,
  "failedCommentsCount": 1,
  "commentUrls": ["https://github.com/..."]
}
`
);
