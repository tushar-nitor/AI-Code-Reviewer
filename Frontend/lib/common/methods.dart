String extractCodeFromMarkdown(String markdownString) {
  // Regex to match and capture content within a markdown code block (e.g., ```lang\ncontent\n```)
  // It's crucial to handle the potential '\' escaping of newlines if the string itself came JSON-escaped.
  // The AI already JSON-escapes '\n' to '\\n' in the values.
  // We need to unescape these first, then apply markdown extraction.

  // Step 1: Unescape JSON newlines (if they are present from the AI's output)
  String unescapedString = markdownString.replaceAll('\\n', '\n');

  // Step 2: Extract from markdown fences
  final RegExp codeBlockRegex = RegExp(r'^```(?:\w+)?\n([\s\S]*)\n```$');
  final match = codeBlockRegex.firstMatch(unescapedString);

  // If a match is found, return the captured group (the content), otherwise return the original string
  // Also, remove any trailing newline that might be part of the captured group.
  return match != null && match.groupCount >= 1 ? match.group(1)!.trimRight() : unescapedString;
}
