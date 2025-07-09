import express from "express";
import cors from "cors";
import { startFlowServer } from "@genkit-ai/express";
// Import all your flows and tools back
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
app.use(cors());

// Add a general logger for all requests
app.use((req, res, next) => {
  console.log(
    `[${new Date().toISOString()}] Incoming Request: ${req.method} ${
      req.originalUrl
    }`
  );
  next();
});

// Health check route
app.get("/health", (req, res) => {
  console.log(`[${new Date().toISOString()}] Health check called.`);
  res.status(200).json({ status: "OK", message: "Express is alive!" });
});

// Test route to ensure basic Express routing works
app.get("/test", (req, res) => {
  console.log(`[${new Date().toISOString()}] Test route called.`);
  res.status(200).json({ status: "OK", message: "Test route is working!" });
});

console.log(`[${new Date().toISOString()}] Express app initialized.`);

try {
  console.log(
    `[${new Date().toISOString()}] Attempting to start Genkit flow server...`
  );
  startFlowServer({
    app: app, // Pass the Express app instance
    // DO NOT include 'port' here for Vercel/Render
    // pathPrefix: "/", // Only use if you explicitly want to remove /api/
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
  console.log(
    `[${new Date().toISOString()}] Genkit startFlowServer function called successfully.`
  );
  // Log all registered routes after Genkit has added them
  app._router.stack.forEach((middleware) => {
    if (middleware.route) {
      // Routes registered directly
      console.log(
        `[Route Registered] ${Object.keys(middleware.route.methods)
          .join(",")
          .toUpperCase()} ${middleware.route.path}`
      );
    } else if (middleware.name === "router" && middleware.handle.stack) {
      // Router middleware (like Genkit's)
      middleware.handle.stack.forEach((handler) => {
        if (handler.route) {
          console.log(
            `[Nested Route Registered] ${Object.keys(handler.route.methods)
              .join(",")
              .toUpperCase()} ${handler.route.path}`
          );
        }
      });
    }
  });
} catch (error) {
  console.error(
    `[${new Date().toISOString()}] ERROR: Failed to start Genkit flow server:`,
    error
  );
  // Log specific properties of the error
  if (error.stack) console.error(error.stack);
  if (error.message) console.error(error.message);
  if (error.code) console.error(error.code);
}

console.log(
  `[${new Date().toISOString()}] Express app configured and ready for export.`
);

// Export the app for Vercel
export default app;
