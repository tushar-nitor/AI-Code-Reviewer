import { ai } from "../ai.js";
import {
  RefactorFileInputSchema,
  RefactorFileOutputSchema,
} from "../schema/schema.js";
import { fetchFileContentTool, getPRInfoTool } from "../tools/github_tools.js";
import { gemini20Flash } from "@genkit-ai/googleai";

export const refactorFileAgent = ai.definePrompt({
  name: "refactorFilePrompt",
  description:
    "Fetches PR HEAD SHA and file content from a GitHub pull request, returning structured output.",
  inputSchema: RefactorFileInputSchema,
  model: gemini20Flash,
  tools: [getPRInfoTool, fetchFileContentTool],
  system: `You are an AI agent that fetches the HEAD SHA of a GitHub Pull Request and retrieves a file's content at that SHA. Your job is to call the required tools, gather data, and return RefactorFileOutputSchema `,
  outputSchema: RefactorFileOutputSchema,

  prompt: ({ owner, repo, pull_number, path }) => {
    return `
You are fetching content for:
- Repository: ${owner}/${repo}
- PR: #${pull_number}
- File: ${path}

### Required Steps:
1. Call getPRInfoTool with:
\`\`\`json
${JSON.stringify({ owner, repo, pull_number }, null, 2)}
\`\`\`

2. Then call fetchFileContentTool with:
\`\`\`json
${JSON.stringify({ owner, repo, path, ref: "<head_sha_from_step_1>" }, null, 2)}
\`\`\`

3. Return results in exact format:
\`\`\`json
{
  "originalContent": "<content>",
  "refactoredContent": "",
  "diff": "",
  "message": "Success"
}
\`\`\`
`;
  },
});
