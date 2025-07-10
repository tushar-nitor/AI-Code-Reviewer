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

console.log("Starting Genkit...");

// --- CRITICAL CHANGE: Pass 'app' and REMOVE 'port' ---
const server = startFlowServer({
  // DO NOT include 'port' here when deploying to Vercel/Render!
  port: 3333, // <-- REMOVE THIS LINE
  // pathPrefix: "/", // Only if you want to remove '/api' from URL
  cors: {
    origin: "*", // This can stay for Genkit's internal CORS
  },
  jsonParserOptions: {
    // Body parser options
    limit: "10mb", // Default: '100kb'
    strict: false,
    type: "application/json",
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

server.server.on("request", (req, res) => {
  if (req.url === "/health" && req.method === "GET") {
    res.writeHead(200);
    res.end("OK");
  }
});

// Vercel needs this export
// Vercel-compatible export
export default async (req, res) => {
  // Forward all requests to Genkit's server
  server.server.emit("request", req, res);
};
