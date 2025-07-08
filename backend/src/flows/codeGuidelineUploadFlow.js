import { ai } from "../ai.js";
import { textEmbedding004 } from "@genkit-ai/googleai";
import { RecursiveCharacterTextSplitter } from "@langchain/textsplitters";
import { Pinecone } from "@pinecone-database/pinecone";
import { z } from "genkit";
import mammoth from "mammoth";
import { PDFExtract } from "pdf.js-extract";

const pdfExtract = new PDFExtract();
const options = {};
// Initialize Pinecone
const pinecone = new Pinecone({
  apiKey: process.env.PINECONE_API_KEY,
});

const QueryOptions = z.object({
  namespace: z.string().default("default"),
  k: z.number().int().min(1).max(20).default(5),
  filter: z.record(z.unknown()).optional().default({}),
  includeValues: z.boolean().default(false),
  includeMetadata: z.boolean().default(true),
});

export const pineconeRetriever = ai.defineRetriever(
  {
    name: "pineconeRetriever",
    configSchema: QueryOptions,
  },
  async (query, options) => {
    // 1. Validate inputs with additional checks
    if (!query?.trim()) throw new Error("Query cannot be empty");

    // 2. Ensure filter is always a valid object
    const finalFilter =
      options.filter &&
      typeof options.filter === "object" &&
      !Array.isArray(options.filter)
        ? options.filter
        : {};

    // 3. Generate embedding with error handling
    let embedding;
    try {
      const embeddingResponse = await ai.embed({
        embedder: textEmbedding004,
        content: query,
      });
      embedding = embeddingResponse[0]?.embedding;
      if (!embedding?.length) throw new Error("Empty embedding received");
    } catch (e) {
      throw new Error(`Embedding failed: ${e.message}`);
    }

    // 4. Prepare the query payload
    const queryPayload = {
      vector: embedding,
      topK: options.k,
      includeMetadata: options.includeMetadata,
      includeValues: options.includeValues,
    };

    // Only add filter if it has properties
    if (Object.keys(finalFilter).length > 0) {
      queryPayload.filter = finalFilter;
    }

    // 5. Execute Pinecone query
    try {
      const index = pinecone.index(process.env.PINECONE_INDEX);
      const queryResponse = await index
        .namespace(options.namespace)
        .query(queryPayload);

      return {
        documents: queryResponse.matches.map((match) => ({
          id: match.id,
          content: match.metadata?.text || "",
          score: match.score,
          metadata: options.includeMetadata ? match.metadata : undefined,
          values: options.includeValues ? match.values : undefined,
        })),
      };
    } catch (e) {
      console.error("Pinecone query failed:", {
        query: query.substring(0, 100),
        options,
        error: e.message,
        stack: e.stack,
      });
      throw new Error(`Pinecone query failed: ${e.message}`);
    }
  }
);
export const ingestCodingGuidelinesFlow = ai.defineFlow(
  {
    name: "ingestCodingGuidelinesFlow",
    inputSchema: z.object({
      documentId: z.string(),
      content: z.string(),
      namespace: z.string().default("default"), // Added default namespace
    }),
  },
  async ({ documentId, content, namespace }) => {
    try {
      // Validate input
      if (!content || typeof content !== "string") {
        throw new Error("Invalid content: must be a non-empty string");
      }

      // Split content
      const splitter = new RecursiveCharacterTextSplitter({
        chunkSize: 1000,
        chunkOverlap: 200,
      });
      const chunks = await splitter.splitText(content);

      // Process chunks
      const vectors = await Promise.all(
        chunks.map(async (chunk, index) => {
          const embeddingResponse = await ai.embed({
            embedder: textEmbedding004,
            content: chunk,
          });

          return {
            id: `${documentId}-chunk-${index}`,
            values: embeddingResponse[0].embedding,
            metadata: {
              documentId,
              chunkIndex: index,
              text: chunk,
              chunkPreview: chunk.substring(0, 200),
              timestamp: new Date().toISOString(),
            },
          };
        })
      );

      // Upsert to Pinecone
      const index = pinecone.index(process.env.PINECONE_INDEX);
      await index.namespace(namespace).upsert(vectors);

      return {
        status: "success",
        chunksProcessed: chunks.length,
        firstChunkId: vectors[0]?.id,
        namespace, // Return the namespace used
      };
    } catch (error) {
      console.error("Ingestion error:", error);
      throw new Error(`Document ingestion failed: ${error.message}`);
    }
  }
);

export const ingestDocument = ai.defineFlow(
  {
    name: "ingestDocument",
    inputSchema: z.object({
      fileName: z.string(),
      mimeType: z.string(),
      fileData: z.string(), // base64
      documentId: z.string().optional(),
      namespace: z.string().default("default").optional(),
    }),
  },
  async ({ fileName, mimeType, fileData, documentId, namespace }) => {
    // 1. Validate input
    if (!fileData) throw new Error("Base64 file data is required");

    // 2. Decode file
    const buffer = Buffer.from(fileData, "base64");
    console.log("PDF Buffer Size:", buffer.length); // Should be > 0

    // 3. Extract text based on file type
    let content;
    try {
      if (mimeType.includes("pdf")) {
        const data = await extractTextFromPdfJsExtract(buffer);

        content = data;
      } else if (mimeType.includes("word") || mimeType.includes("docx")) {
        const result = await mammoth.extractRawText({ buffer });
        content = result.value;
      } else {
        content = buffer.toString("utf-8");
      }
    } catch (e) {
      throw new Error(`Text extraction failed: ${e.message}`);
    }

    // 4. Process with existing flow
    return ingestCodingGuidelinesFlow.run({
      documentId: documentId || `doc_${Date.now()}`,
      content,
      namespace,
    });
  }
);

// Text extraction helpers
async function extractTextFromPdfJsExtract(buffer) {
  if (!buffer || !Buffer.isBuffer(buffer) || buffer.length === 0) {
    throw new Error("Invalid or empty PDF buffer passed");
  }
  try {
    const data = await pdfExtract.extractBuffer(buffer, options);
    let fullText = "";
    // data.pages is an array of pages
    for (const page of data.pages) {
      // page.content is an array of text items with x, y, str properties
      for (const item of page.content) {
        fullText += item.str;
      }
      fullText += "\n"; // Add a newline between pages
    }
    return fullText;
  } catch (error) {
    console.error("pdf.js-extract failed:", error);
    throw new Error(`Text extraction failed: ${error.message}`);
  }
}
