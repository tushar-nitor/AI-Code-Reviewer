// agents/prReviewerAgent.js
import { ai } from "../ai.js";
import { gemini20Flash } from "@genkit-ai/googleai";
import {
  CodeReviewResultSchema,
  CodeReviewerInputSchema,
} from "../schema/schema.js";
import { fetchPRDiffTool } from "../tools/github_tools.js";
import { pineconeRetrievalTool } from "../tools/pinecone_tools.js";

export const prReviewerAgent = ai.definePrompt({
  name: "prReviewerAgent",
  description:
    "Orchestrates code review by retrieving guidelines and analyzing PR diffs",
  inputSchema: CodeReviewerInputSchema,
  model: gemini20Flash,
  tools: [fetchPRDiffTool, pineconeRetrievalTool],
  outputSchema: CodeReviewResultSchema,

  system: `You are an AI orchestrator for code reviews. Your task is to:
  1. Retrieve relevant coding guidelines using pineconeRetrievalTool
  2. Fetch PR changes using fetchPRDiffTool
  3. ONLY reviews files that appear in the PR diff
  4. Analyze changes against guidelines
  5. Produce structured review output
  Maintain professional tone and prioritize security/performance issues.`,

  prompt: ({ owner, repo, pull_number, language, focusAreas,token }) => `
### Code Review Workflow for ${repo}#${pull_number} (${language})

1. **Retrieve Guidelines**:
   Call \`pineconeRetrievalTool\` to get ${language} best practices${
    focusAreas ? ` focusing on ${focusAreas}` : ""
  }:
   \`\`\`json
   {
     "query": "${language} coding guidelines${
    focusAreas ? ` ${focusAreas}` : ""
  }",
     "namespace": "flutter_uploads",
     "k": 5
   }
   \`\`\`

2. **Get PR Changes**:
   Call \`fetchPRDiffTool\` to retrieve changes:
   \`\`\`json
   {
     "owner": "${owner}",
     "repo": "${repo}",
     "pull_number": ${pull_number},
     "token": "${token}"
   }
   \`\`\`
3. REVIEW ONLY THESE FILES FROM THE DIFF:
   <List of files from the diff will appear here>


4. **Conduct Review**:
   - Analyze ALL files completely
   - Cross-reference changes with guidelines
   - Prioritize: Security > Performance > Maintainability > Style

### Output Requirements:
\`\`\`json
{
  "summary": "Concise overall assessment",
  "suggestions": [
    {
      "fileName": "MUST MATCH EXACT PATH FROM DIFF",
      "suggestionText": "Clear improvement suggestion",
      "lineNumber": 123,
      "type": "SECURITY|PERFORMANCE|READABILITY|BUG|STYLE|BEST_PRACTICE|TYPO|OTHER"
    }
  ]
}
\`\`\`

**Rules**:
1. Never skip files/sections
2. Include specific line references
3. Maintain constructive tone
4. Output MUST be valid JSON within \`\`\`json block`,
});
