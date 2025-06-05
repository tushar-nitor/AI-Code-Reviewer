import { startFlowServer } from "@genkit-ai/express";
import { codeReviewFlow } from "./flows/codeReviewsFlow.js";
import { prReviewFlow } from "./flows/prReviewFlow.js";
import { postPRCommentsFlow } from "./flows/prCommentFlow.js";
import {
  fetchPRDiffTool,
  postGitHubPRCommentTool,
} from "./tools/github_tools.js";
startFlowServer({
  port: 3333,
  cors: {
    origin: "*",
  },
  flows: [codeReviewFlow, prReviewFlow, postPRCommentsFlow],
  tools: [fetchPRDiffTool, postGitHubPRCommentTool],
});
