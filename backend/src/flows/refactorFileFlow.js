// flows/batchRefactorFileFlow.js
import { ai } from "../ai.js";
import { refactorFileAgent } from "../agents/prFileRefactorAgent.js"; // This agent now only fetches original content
import { codeRefactorAgent } from "../agents/prFileRefactoringAgent2.js"; // Import the new refactor agent
import {
  RefactorFileInputSchema,
  RefactorFileOutputSchema,
} from "../schema/schema.js";

function parseAndSanitizeAgentResponse(responseText) {
  // Try direct JSON parse first (simplest case)
  try {
    return JSON.parse(responseText);
  } catch (directError) {
    console.debug("Direct parse failed, trying other methods:", directError);
  }

  // Extract content from potential code blocks
  let jsonContent = extractJsonContent(responseText);
  console.debug(
    "Extracted JSON content:",
    jsonContent.substring(0, 200) + "..."
  );

  // First attempt with basic sanitization
  try {
    const basicSanitized = basicSanitizeJson(jsonContent);
    return JSON.parse(basicSanitized);
  } catch (basicError) {
    console.warn("Basic sanitization failed:", basicError);
  }

  // Second attempt with advanced sanitization
  try {
    const advancedSanitized = advancedSanitizeJson(jsonContent);
    const parsed = JSON.parse(advancedSanitized);
    return processContentFields(parsed);
  } catch (advancedError) {
    console.warn("Advanced sanitization failed:", advancedError);
  }

  // Final attempt with field-by-field extraction
  try {
    const extracted = extractFieldsFromMalformedJson(jsonContent);
    if (extracted) {
      return processContentFields(extracted);
    }
  } catch (extractionError) {
    console.error("Field extraction failed:", extractionError);
  }

  throw new Error(
    `Failed to parse AI response after all attempts.\n` +
      `Original error position: ${getErrorPositionContext(
        jsonContent,
        919
      )}\n` +
      `Response start: ${jsonContent.substring(0, 300)}...`
  );
}

// Helper function to extract JSON from code blocks
function extractJsonContent(text) {
  let content = text.trim();

  // Remove code block markers if present
  if (content.startsWith("```")) {
    content = content.slice(content.indexOf("\n") + 1);
    const lastBackticks = content.lastIndexOf("```");
    if (lastBackticks > -1) {
      content = content.slice(0, lastBackticks);
    }
  }

  return content.trim();
}

// Basic JSON sanitization
function basicSanitizeJson(jsonString) {
  return (
    jsonString
      // Remove BOM if present
      .replace(/^\uFEFF/, "")
      // Fix common escape sequences
      .replace(/\\'/g, "'")
      .replace(/\\"/g, '"')
      .replace(/\\\n/g, "\n")
      .replace(/\\\t/g, "\t")
      .replace(/\\\r/g, "\r")
      .replace(/\\\\/g, "\\")
  );
}

// Advanced JSON sanitization
function advancedSanitizeJson(jsonString) {
  let sanitized = jsonString;

  // 1. Fix unicode escapes
  sanitized = sanitized.replace(
    /\\u([0-9a-fA-F]{0,3}[^0-9a-fA-F])/g,
    (match, group) => {
      return group.length === 4
        ? match
        : `\\u${"0".repeat(4 - group.length)}${group}`;
    }
  );

  // 2. Fix hex escapes
  sanitized = sanitized.replace(
    /\\x([0-9a-fA-F]{0,1}[^0-9a-fA-F])/g,
    (match, group) => {
      return group.length === 2
        ? match
        : `\\x${"0".repeat(2 - group.length)}${group}`;
    }
  );

  // 3. Fix malformed control characters
  sanitized = sanitized.replace(/\\([^"\\/bfnrtu0-9x])/g, "\\\\$1");

  // 4. Balance quotes in string values
  sanitized = sanitized.replace(/"([^"\\]*(?:\\.[^"\\]*)*)(?=")/g, (match) => {
    return match.replace(/"/g, '\\"');
  });

  // 5. Fix trailing commas
  sanitized = sanitized.replace(/,(\s*[}\]])/g, "$1");

  // 6. Ensure proper field separators
  sanitized = sanitized.replace(
    /"\s*:\s*([^"{}\[\],\s]+)([,\s}])/g,
    '" : "$1"$2'
  );

  return sanitized;
}

// Process content fields with proper unescaping
function processContentFields(parsedData) {
  const contentFields = [
    "originalContent",
    "refactoredContent",
    "diff",
    "message",
  ];

  contentFields.forEach((field) => {
    if (parsedData[field] && typeof parsedData[field] === "string") {
      parsedData[field] = parsedData[field]
        .replace(/\\n/g, "\n")
        .replace(/\\t/g, "\t")
        .replace(/\\"/g, '"')
        .replace(/\\\\/g, "\\")
        .replace(/\\r/g, "\r")
        .replace(/\\'/g, "'");
    }
  });

  return parsedData;
}

// Extract fields from malformed JSON
function extractFieldsFromMalformedJson(text) {
  const fields = ["originalContent", "refactoredContent", "diff", "message"];
  const result = {};
  let hasData = false;

  fields.forEach((field) => {
    const regex = new RegExp(
      `"${field}"\\s*:\\s*((?:"((?:\\\\"|[^"])*)"|([^",}\\s]+)))`,
      "g"
    );
    let match;
    while ((match = regex.exec(text)) !== null) {
      const value = match[2] || match[3];
      if (value) {
        result[field] = value.replace(/\\\\/g, "\\").replace(/\\"/g, '"');
        hasData = true;
      }
    }
  });

  return hasData ? result : null;
}

// Get context around error position
function getErrorPositionContext(text, position) {
  const start = Math.max(0, position - 20);
  const end = Math.min(text.length, position + 20);
  return `...${text.substring(start, position)}[ERROR HERE]${text.substring(
    position,
    end
  )}...`;
}
export const refactorFileFlow = ai.defineFlow(
  {
    name: "refactorFileFlow",
    inputSchema: RefactorFileInputSchema, // This schema includes all input for the whole flow
    outputSchema: RefactorFileOutputSchema, // This is the final combined output schema
  },
  async (input) => {
    try {
      // --- Step 1: Fetch Original File Content ---
      const rawFetchAgentResponse = await refactorFileAgent({
        owner: input.owner,
        repo: input.repo,
        pull_number: input.pull_number,
        path: input.path,
        token: input.token,
      });

      // Extract text content from raw response
      let fetchResponseText = "";
      if (
        rawFetchAgentResponse.message &&
        Array.isArray(rawFetchAgentResponse.message.content) &&
        rawFetchAgentResponse.message.content.length > 0
      ) {
        const textPart = rawFetchAgentResponse.message.content.find(
          (item) => item.text !== undefined
        );
        if (textPart) {
          fetchResponseText = textPart.text;
        }
      } else if (
        rawFetchAgentResponse.message &&
        rawFetchAgentResponse.message.content &&
        typeof rawFetchAgentResponse.message.content.text === "string"
      ) {
        fetchResponseText = rawFetchAgentResponse.message.content.text;
      } else if (typeof rawFetchAgentResponse.originalContent === "string") {
        // Direct output if schema parsing worked
        fetchResponseText = JSON.stringify(rawFetchAgentResponse);
      }

      if (!fetchResponseText) {
        throw new Error("Fetch agent response did not contain text content.");
      }

      // Parse and sanitize the output of refactorFileAgent
      const fetchedContentData =
        parseAndSanitizeAgentResponse(fetchResponseText);
      const originalContent = fetchedContentData.originalContent;
      const fetchMessage =
        fetchedContentData.message || "Original file fetched.";

      console.log("Original Content Fetched Length:", originalContent.length);

      // --- Step 2: Refactor Code and Generate Diff using the new agent ---
      const rawRefactorAgentResponse = await codeRefactorAgent({
        fileName: input.path,
        originalContent: originalContent, // Pass the cleaned original content
        suggestions: input.suggestions,
        language: input.language,
      });

      // Extract text content from raw refactor agent response
      let refactorResponseText = "";
      if (
        rawRefactorAgentResponse.message &&
        Array.isArray(rawRefactorAgentResponse.message.content) &&
        rawRefactorAgentResponse.message.content.length > 0
      ) {
        const textPart = rawRefactorAgentResponse.message.content.find(
          (item) => item.text !== undefined
        );
        if (textPart) {
          refactorResponseText = textPart.text;
        }
      } else if (
        rawRefactorAgentResponse.message &&
        rawRefactorAgentResponse.message.content &&
        typeof rawRefactorAgentResponse.message.content.text === "string"
      ) {
        refactorResponseText = rawRefactorAgentResponse.message.content.text;
      } else if (
        typeof rawRefactorAgentResponse.refactoredContent === "string"
      ) {
        // Direct output if schema parsing worked (from codeRefactorAgent's outputSchema)
        refactorResponseText = JSON.stringify(rawRefactorAgentResponse);
      }

      if (!refactorResponseText) {
        throw new Error(
          "Refactor agent response did not contain text content."
        );
      }

      // Parse and sanitize the output of codeRefactorAgent
      // The parseAndSanitizeAgentResponse is robust enough to handle the CodeRefactorOutputSchema structure
      const refactoredData =
        parseAndSanitizeAgentResponse(refactorResponseText);

      console.log(
        "Refactored Content Length:",
        refactoredData.refactoredContent.length
      );
      console.log("Diff Length:", refactoredData.diff.length);

      // --- Step 3: Merge and Return Final Output ---
      return {
        originalContent: originalContent, // From step 1
        refactoredContent: refactoredData.refactoredContent, // From step 2
        diff: refactoredData.diff, // From step 2
        message: `File fetch: ${fetchMessage}. Code refactoring: ${
          refactoredData.message || "Completed."
        }`,
      };
    } catch (error) {
      console.error("Error in refactorFileFlow:", error);
      return {
        originalContent: "",
        refactoredContent: "",
        diff: "",
        message: `Flow Error: ${error.message}`,
      };
    }
  }
);
