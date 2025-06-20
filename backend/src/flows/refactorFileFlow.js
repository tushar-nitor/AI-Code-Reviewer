// flows/batchRefactorFileFlow.js
import { ai } from "../ai.js";
import { refactorFileAgent } from "../agents/prFileRefactorAgent.js"; // This agent now only fetches original content
import { codeRefactorAgent } from "../agents/prFileRefactoringAgent2.js"; // Import the new refactor agent
import {
  RefactorFileInputSchema,
  RefactorFileOutputSchema,
} from "../schema/schema.js";

// Keep your utility function. We'll use it for both agents if they output raw text.
// If your agents are now consistently returning structured data due to `outputSchema`
// and you *don't* get the '```json' wrapper, you can remove this utility function and
// simplify the response extraction. But for robustness, let's keep it for now.
function parseAndSanitizeAgentResponse(responseText) {
  const jsonMatch = responseText.match(/```json\n([\s\S]*?)\n```/);

  if (!jsonMatch || !jsonMatch[1]) {
    // If no ```json block, try parsing directly as the whole response might be JSON
    try {
      return JSON.parse(responseText);
    } catch (directParseError) {
      throw new Error(
        `AI response did not contain a valid JSON code block or direct JSON as expected. Raw response: ${responseText.substring(
          0,
          200
        )}...`
      );
    }
  }

  let rawJsonContent = jsonMatch[1];
  let parsedData;

  try {
    // Attempt to parse the JSON as is
    parsedData = JSON.parse(rawJsonContent);

    // Only attempt unescaping if 'originalContent' exists (for refactorFileAgent's output)
    if (
      parsedData.originalContent &&
      typeof parsedData.originalContent === "string"
    ) {
      let content = parsedData.originalContent;
      try {
        content = JSON.parse(`"${content}"`);
      } catch (unescapeError) {
        console.warn(
          `Failed to unescape originalContent using JSON.parse method: ${unescapeError.message}`
        );
        content = content.replace(/\\\\/g, "\\");
        content = content.replace(/\\'/g, "'");
        content = content.replace(/\\"/g, '"');
        content = content.replace(/\\n/g, "\n");
        content = content.replace(/\\t/g, "\t");
      }
      parsedData.originalContent = content;
    }
  } catch (e) {
    console.warn(
      "Attempting to fix bad JSON escaping in originalContent field from primary parse failure..."
    );

    const originalContentRegex =
      /("originalContent"\s*:\s*)("((?:[^"\\]|\\.)*)")/s;
    const matchOriginalContent = rawJsonContent.match(originalContentRegex);

    if (matchOriginalContent && matchOriginalContent[3] !== undefined) {
      let problematicContentValue = matchOriginalContent[3];

      try {
        problematicContentValue = JSON.parse(`"${problematicContentValue}"`);
      } catch (unescapeError) {
        console.warn(
          `Failed to unescape problematicContentValue for re-stringifying: ${unescapeError.message}. Proceeding with simpler cleanup.`
        );
        problematicContentValue = problematicContentValue.replace(
          /\\\\/g,
          "\\"
        );
        problematicContentValue = problematicContentValue.replace(/\\'/g, "'");
        problematicContentValue = problematicContentValue.replace(/\\"/g, '"');
        problematicContentValue = problematicContentValue.replace(/\\n/g, "\n");
        problematicContentValue = problematicContentValue.replace(/\\t/g, "\t");
      }

      const correctedContentValueForJson = JSON.stringify(
        problematicContentValue
      ).slice(1, -1);

      const correctedJsonContent = rawJsonContent.replace(
        originalContentRegex,
        `$1"${correctedContentValueForJson}"`
      );
      parsedData = JSON.parse(correctedJsonContent);
    } else {
      throw e;
    }
  }
  return parsedData;
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
