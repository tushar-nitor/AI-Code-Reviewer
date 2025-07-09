import express from "express";
import cors from "cors";
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
const PORT = process.env.PORT || 4444; // Render typically provides PORT, so 4444 is a good fallback.

app.use(cors()); // Add CORS globally

// 1. Define the health check route immediately.
app.get("/health", (req, res) => {
  console.log("Health check called");
  res.status(200).json({ status: "OK" });
});

console.log("Starting Genkit...");

// **CRITICAL CHANGE HERE:**
// 2. Initialize Genkit directly on your main 'app' instance.
//    Remove the 'port' property from startFlowServer, as 'app.listen' handles the port.
//    Genkit will now serve its flows on the same port as your main Express app.
startFlowServer({
  app: app, // Pass your main 'app' instance directly
  // Remove the 'port' property here. It's only needed if you want Genkit to start
  // its OWN *separate* server. We want it to integrate with THIS server.
  port: 3333, // <--- REMOVE THIS LINE
  // If you need specific CORS for Genkit flows, define it here.
  // Otherwise, the global app.use(cors()) will suffice.
  // cors: {
  //   origin: "*",
  // },
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

// 3. Start the main Express server.
// This is the ONLY server that Render will expose.
app.listen(PORT, () => {
  console.log(`🚀 Server is running and listening on port ${PORT}`);
});
