import express from "express";
import { startFlowServer } from "@genkit-ai/express";
import { codeReviewFlow } from "./flows/codeReviewsFlow.js";
import { prReviewFlow } from "./flows/prReviewFlow.js";
import { postPRCommentsFlow } from "./flows/prCommentFlow.js";
import { refactorFileFlow } from "./flows/refactorFileFlow.js";
import { codingStandardsFlow } from "./flows/codingStandards.js";
import { createDiffTool } from "./tools/diffTool.js";
import { pineconeRetrievalTool } from "./tools/pinecone_tools.js";
import {
  ingestCodingGuidelinesFlow,
  ingestDocument,
} from "./flows/codeGuidelineUploadFlow.js";
import {
  fetchPRDiffTool,
  postGitHubPRCommentTool,
  refactorCodeTool,
  fetchFileContentTool,
  getPRInfoTool,
} from "./tools/github_tools.js";

const app = express();
const PORT = process.env.PORT || 4444; // Must use 10000 for Render

// **1. Define the health check route immediately.**
// This makes it available as soon as the server starts.
app.get("/health", (req, res) => {
  console.log("Health check called");
  res.status(200).json({ status: "OK" });
});

const genkitRouter = express.Router();

// **2. Mount the Genkit router to the main app.**
app.use(genkitRouter);

console.log("Starting Genkit...");

// **3. Initialize Genkit on the separate router.**
// Note: The 'port' property is removed as app.listen() now controls this.
startFlowServer({
  app: genkitRouter,
  port: 3333,
  cors: {
    origin: "*",
  },
  flows: [
    codeReviewFlow,
    prReviewFlow,
    postPRCommentsFlow,
    refactorFileFlow,
    codingStandardsFlow,
    ingestCodingGuidelinesFlow,
    ingestDocument,
  ],
  tools: [
    fetchPRDiffTool,
    postGitHubPRCommentTool,
    getPRInfoTool,
    refactorCodeTool,
    fetchFileContentTool,
    createDiffTool,
    pineconeRetrievalTool,
  ],
});

// **4. Start the main Express server.**
// This makes the /health endpoint live and able to respond to Render.
app.listen(PORT, () => {
  console.log(`🚀 Server is running and listening on port ${PORT}`);
});
