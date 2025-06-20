// flows/postPRCommentsFlow.ts
import { ai } from "../ai.js";
import { postPRCommentsPrompt } from "../agents/prCommentAgent.js";

// Correct path to your prompt
import {
  PostPRCommentsInputSchema,
  PostPRCommentOutputSchema,
} from "../schema/schema.js"; // Ensure output schema is imported

export const postPRCommentsFlow = ai.defineFlow(
  {
    name: "postPRCommentsFlow",
    inputSchema: PostPRCommentsInputSchema,
    outputSchema: PostPRCommentOutputSchema, // This should be the schema for the *final* output JSON, not the prompt's full response
  },
  async (input) => {
    const rawResult = await postPRCommentsPrompt(input); // This is the full Genkit response object

    const jsonStringWithMarkdown = rawResult.message.content[0].text;

    const jsonMatch = jsonStringWithMarkdown.match(/```json\n([\s\S]*?)\n```/);

    if (!jsonMatch || jsonMatch.length < 2) {
      console.error(
        "Failed to extract JSON from AI response:",
        jsonStringWithMarkdown
      );
      // Return an error conforming to the output schema
      return {
        success: false,
        message: "Failed to parse AI model's response.",
        commentsPostedCount: 0,
        failedCommentsCount: 1,
        commentUrls: [],
      };
    }

    const jsonContent = jsonMatch[1];
    let parsedResponse;

    try {
      parsedResponse = JSON.parse(jsonContent);
    } catch (parseError) {
      console.error("Failed to parse JSON content:", jsonContent, parseError);
      // Return an error conforming to the output schema
      return {
        success: false,
        message: `Invalid JSON received from AI: ${parseError.message}`,
        commentsPostedCount: 0,
        failedCommentsCount: 1,
        commentUrls: [],
      };
    }

    console.error("Parsed Response======>", parsedResponse);

    return parsedResponse;
  }
);
