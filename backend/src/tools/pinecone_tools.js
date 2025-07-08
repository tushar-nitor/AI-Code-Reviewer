import { ai } from "../ai.js";
import { z } from "genkit";
import { Pinecone } from "@pinecone-database/pinecone";
import { textEmbedding004 } from "@genkit-ai/googleai";

const pinecone = new Pinecone({ apiKey: process.env.PINECONE_API_KEY });

// In pinecone_tools.js
export const pineconeRetrievalTool = ai.defineTool(
  {
    name: "pineconeRetrievalTool",
    description:
      "Retrieves documents from Pinecone with guaranteed null safety",
    inputSchema: z.object({
      query: z.string(),
      namespace: z.string().default("default"),
      k: z.number().int().min(1).max(20).default(5),
    }),
    outputSchema: z.array(/*...*/),
  },
  async ({ query, namespace, k, filter = {} }) => {
    // 1. Validate filter is pure object
    const safeFilter =
      filter && typeof filter === "object" && !Array.isArray(filter)
        ? filter
        : {};

    // 2. Prepare query with debug logging
    const queryPayload = {
      vector: await getEmbedding(query), // Extracted to separate function
      topK: k,
      includeMetadata: true,
      ...(Object.keys(safeFilter).length > 0 && { filter: safeFilter }),
    };

    console.log(
      "Pinecone query payload:",
      JSON.stringify({
        namespace,
        ...queryPayload,
        vector: "<truncated>",
      })
    );

    // 3. Execute query
    const index = pinecone.index(process.env.PINECONE_INDEX);
    const results = await index.namespace(namespace).query(queryPayload);

    return formatResults(results);
  }
);

// Helper functions
async function getEmbedding(query) {
  const res = await ai.embed({ embedder: textEmbedding004, content: query });
  if (!res[0]?.embedding) throw new Error("Embedding failed");
  return res[0].embedding;
}

function formatResults(results) {
  return results.matches.map((match) => ({
    id: match.id,
    content: match.metadata?.text || "",
    score: match.score,
    metadata: match.metadata,
    // Add guideline ID if available
    guidelineId: match.metadata?.documentId,
  }));
}
