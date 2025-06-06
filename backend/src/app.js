import { startFlowServer } from "@genkit-ai/express";
import { codeReviewFlow } from "./flows/codeReviewsFlow.js";
import { prReviewFlow } from "./flows/prReviewFlow.js";
import { postPRCommentsFlow } from "./flows/prCommentFlow.js";
import { refactorFileFlow } from "./flows/refactorFileFlow.js";

import {
  fetchPRDiffTool,
  postGitHubPRCommentTool,
  refactorCodeTool,
  fetchFileContentTool,
  getPRInfoTool,
} from "./tools/github_tools.js";
startFlowServer({
  port: 3333,
  cors: {
    origin: "*",
  },
  flows: [codeReviewFlow, prReviewFlow, postPRCommentsFlow, refactorFileFlow],
  tools: [
    fetchPRDiffTool,
    postGitHubPRCommentTool,
    refactorCodeTool,
    fetchFileContentTool,
    getPRInfoTool,
  ],
});
