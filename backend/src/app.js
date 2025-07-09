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

// --- RE-INTRODUCE EXPRESS APP ---
const app = express();
// The PORT constant is not strictly needed for Vercel, but good practice for local development.
// Vercel handles the port internally.
// const PORT = process.env.PORT || 4444; // No need for app.listen on Vercel

app.use(cors()); // Global CORS is fine

// Health check route - crucial for deployment platforms
app.get("/health", (req, res) => {
  console.log("Health check called");
  res.status(200).json({ status: "OK" });
});
// --- END RE-INTRODUCE EXPRESS APP ---

console.log("Starting Genkit...");

// --- CRITICAL CHANGE: Pass 'app' and REMOVE 'port' ---
startFlowServer({
  app: app, // THIS IS THE EXPRESS INSTANCE VERCEL WILL SERVE
  // DO NOT include 'port' here when deploying to Vercel/Render!
  // port: 3333, // <-- REMOVE THIS LINE
  // pathPrefix: "/", // Only if you want to remove '/api' from URL
  cors: {
    origin: "*", // This can stay for Genkit's internal CORS
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
// --- END CRITICAL CHANGE ---

// --- EXPORT THE APP FOR VERCEL ---
// This is the most crucial part for Vercel to pick up your application.
export default app;

// --- REMOVE app.listen() FOR VERCEL DEPLOYMENT ---
// Vercel manages the server, your app should NOT call app.listen().
// app.listen(PORT, () => {
//   console.log(`🚀 Express Server is running and listening on port ${PORT}`);
// });
