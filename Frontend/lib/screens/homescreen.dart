// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'package:ai_code_reviewer/widgets/pr_diff_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:highlight/languages/all.dart';
import 'package:http/http.dart' as http;
import 'package:highlight/languages/dart.dart'; // Ensure a default language is imported for CodeController

class CodeReviewScreen extends StatefulWidget {
  const CodeReviewScreen({super.key});

  @override
  State<CodeReviewScreen> createState() => _CodeReviewScreenState();
}

enum ReviewInputType { pasteCode, githubPr }

class _CodeReviewScreenState extends State<CodeReviewScreen> {
  ReviewInputType _selectedInputType = ReviewInputType.pasteCode;

  final _languageController = TextEditingController();
  final _focusController = TextEditingController();
  final _prUrlController = TextEditingController();

  final CodeController _codeController = CodeController(text: '// Enter your code\n ', language: dart);
  CodeController _correctedCodeEditor = CodeController(text: '', language: dart);

  String? summary;
  List<Map<String, dynamic>> suggestions = []; // Now expects list of maps: {'fileName', 'suggestionText'}
  List<Map<String, dynamic>>? parsedDiff; // Stores the file-by-file parsed diff
  bool isLoading = false;
  String? error;
  String prDiff = "";
  // Helper to extract owner, repo, and pull_number from GitHub PR URL
  Map<String, dynamic>? _parseGitHubPrUrl(String url) {
    final RegExp githubPrRegex = RegExp(r'github\.com/([^/]+)/([^/]+)/(?:pulls|pull)/(\d+)', caseSensitive: false);
    final match = githubPrRegex.firstMatch(url);
    if (match != null && match.groupCount == 3) {
      return {'owner': match.group(1), 'repo': match.group(2), 'pull_number': int.tryParse(match.group(3)!)};
    }
    return null;
  }

  Future<void> submitReview() async {
    final language = _languageController.text.trim();
    final focusAreas = _focusController.text.trim();

    if (language.isEmpty) {
      setState(() {
        error = "Programming language is required.";
        _resetReviewState();
      });
      return;
    }

    if (_selectedInputType == ReviewInputType.pasteCode && _codeController.text.trim().isEmpty) {
      setState(() {
        error = "Please paste the code to review.";
        _resetReviewState();
      });
      return;
    }

    if (_selectedInputType == ReviewInputType.githubPr) {
      final prUrl = _prUrlController.text.trim();
      if (prUrl.isEmpty) {
        setState(() {
          error = "Please enter the GitHub PR URL.";
          _resetReviewState();
        });
        return;
      }
      final parsedPr = _parseGitHubPrUrl(prUrl);
      if (parsedPr == null ||
          parsedPr['owner'] == null ||
          parsedPr['repo'] == null ||
          parsedPr['pull_number'] == null) {
        setState(() {
          error = "Invalid GitHub PR URL format. Expected: github.com/owner/repo/pull/number";
          _resetReviewState();
        });
        return;
      }
    }

    setState(() {
      isLoading = true;
      _resetReviewState(); // Reset all previous review data
    });

    try {
      Uri url;
      Map<String, dynamic> requestData;

      if (_selectedInputType == ReviewInputType.pasteCode) {
        url = Uri.http("localhost:3333", 'codeReviewFlow'); // Assumes you have a 'codeReviewFlow'
        requestData = {"code": _codeController.text.trim(), "language": language};
        if (focusAreas.isNotEmpty) requestData["focusAreas"] = focusAreas;
      } else {
        // ReviewInputType.githubPr
        url = Uri.http("localhost:3333", 'prReviewFlow'); // Use the 'prReviewFlow'
        final parsedPr = _parseGitHubPrUrl(_prUrlController.text.trim());
        requestData = {
          "owner": parsedPr!['owner'],
          "repo": parsedPr['repo'],
          "pull_number": parsedPr['pull_number'],
          "language": language,
        };
        if (focusAreas.isNotEmpty) requestData["focusAreas"] = focusAreas;
      }

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'data': requestData}), // Wrap in 'data' as per Genkit's default
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data["result"]; // Genkit response usually has 'result' field

        final correctedCode = result['correctedCode'] as String? ?? '';

        setState(() {
          summary = result['summary'] as String?;
          // Correctly parse suggestions into List<Map<String, String>>
          if (_selectedInputType == ReviewInputType.pasteCode) {
            suggestions =
                (result['suggestions'] as List?)
                    ?.map(
                      (s) => {
                        'fileName': "",
                        'suggestionText': s as String,
                        // "lineNumber": s['lineNumber'] as int,
                      },
                    )
                    .toList() ??
                [];
          } else {
            prDiff = result['parsedDiff'];

            suggestions =
                (result['suggestions'] as List?)
                    ?.map(
                      (s) => {
                        'fileName': s['fileName'] as String,
                        'suggestionText': s['suggestionText'] as String,
                        // "lineNumber": s['lineNumber'] as int,
                      },
                    )
                    .toList() ??
                [];
          }

          //   parsedDiff = (jsonDecode(result['parsedDiff']) as List).map((item) => item as Map<String, dynamic>).toList();
          _correctedCodeEditor = CodeController(
            text: correctedCode,
            language: allLanguages[_languageController.text.trim().toLowerCase()] ?? dart,
          );
        });
      } else {
        setState(() {
          error = 'Server error: ${response.statusCode}. ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        error = 'Request failed: $e';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> postPrCommentsFlow({required BuildContext context}) async {
    final uri = Uri.http("localhost:3333", 'postPRCommentsFlow');
    final headers = {'Content-Type': 'application/json'};
    final parsedPr = _parseGitHubPrUrl(_prUrlController.text.trim());
    final body = {
      "owner": parsedPr!['owner'],
      "repo": parsedPr['repo'],
      "pull_number": parsedPr['pull_number'],
      'suggestions': suggestions,
      'postAsSingleComment': true,
    };

    try {
      final response = await http.post(uri, headers: headers, body: jsonEncode({'data': body}));

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody = jsonDecode(response.body) as Map<String, dynamic>;
        bool success = responseBody["result"]['success'] ?? false;
        final String message = responseBody["result"]['message'] ?? 'Operation completed.';

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: SelectableText(success ? message : 'Failed to post comments: $message')));
        return responseBody;
      } else {
        // Handle API errors
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: SelectableText('Failed to post PR comments: ${response.statusCode} - ${response.body}')),
        );
        return null;
      }
    } catch (e) {
      // Handle network or other unexpected errors
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: SelectableText('Error during post PR comments API call: $e')));
      return null;
    }
  }

  // Helper to reset all review-related state variables
  void _resetReviewState() {
    summary = null;
    suggestions = [];
    parsedDiff = null; // Clear parsed diff
    error = null;
    _correctedCodeEditor = CodeController(text: '', language: dart);
  }

  @override
  void dispose() {
    _codeController.dispose();
    _languageController.dispose();
    _focusController.dispose();
    _prUrlController.dispose();
    _correctedCodeEditor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Container(
          height: MediaQuery.sizeOf(context).height,
          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white, const Color.fromARGB(255, 222, 236, 246)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              SelectableText(
                'Review Code',
                style: theme.textTheme.headlineSmall!.copyWith(color: Colors.black),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),
              // --- End Radio Button Row ---

              // Common inputs for both types
              TextField(
                controller: _languageController,
                decoration: _inputDecoration('Programming Language *', Icons.code),

                onChanged: (value) {
                  // Safely set language, default to dart if not found
                  _codeController.language = allLanguages[value.toLowerCase()] ?? dart;
                  _correctedCodeEditor.language = allLanguages[value.toLowerCase()] ?? dart;
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _focusController,
                decoration: _inputDecoration('Focus Areas (optional)', Icons.filter_list),
              ),
              const SizedBox(height: 16),

              // --- Radio Button Row for Input Type ---
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 200,
                    child: RadioListTile<ReviewInputType>.adaptive(
                      title: const SelectableText('Paste Code'),
                      value: ReviewInputType.pasteCode,
                      groupValue: _selectedInputType,
                      onChanged: (ReviewInputType? value) {
                        setState(() {
                          _selectedInputType = value!;
                          _resetReviewState(); // Reset review results when switching
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 200,

                    child: RadioListTile<ReviewInputType>.adaptive(
                      title: const SelectableText('GitHub PR'),
                      value: ReviewInputType.githubPr,
                      groupValue: _selectedInputType,
                      onChanged: (ReviewInputType? value) {
                        setState(() {
                          _selectedInputType = value!;
                          _resetReviewState(); // Reset review results when switching
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Conditionally display Code Editor or PR URL Field based on selected type
              if (_selectedInputType == ReviewInputType.pasteCode)
                Container(
                  height: 300,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blue),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white,
                  ),
                  child: CodeTheme(
                    data: CodeThemeData(styles: githubTheme),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: CodeField(
                        controller: _codeController,
                        textStyle: const TextStyle(fontFamily: 'SourceCodePro'),
                        expands: false,
                        minLines: 14,
                        maxLines: null,
                      ),
                    ),
                  ),
                )
              else // _selectedInputType == ReviewInputType.githubPr
                TextField(
                  controller: _prUrlController,
                  decoration: _inputDecoration('GitHub PR URL *', Icons.link),
                  keyboardType: TextInputType.url,
                ),

              if (error != null) ...[const SizedBox(height: 24), _errorWidget(error!)],
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  icon: isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                        )
                      : const SizedBox(),
                  label: SelectableText(
                    isLoading ? 'Reviewing...' : 'Submit for Review',
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isLoading ? null : submitReview,
                ),
              ),
              const SizedBox(height: 32),

              // --- Displaying Results ---
              if (summary != null) ...[
                _sectionHeader('Summary'),
                SelectableText(summary!),
                const SizedBox(height: 24),
                // Suggestions and Refactored Code (side-by-side)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [_sectionHeader('Suggestions'), const SizedBox(height: 8), _suggestionList()],
                      ),
                    ),
                    const SizedBox(width: 24),
                    if (_correctedCodeEditor.text.isNotEmpty)
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionHeader('Refactored Code'),
                            const SizedBox(height: 8),
                            Container(
                              height: 500,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.blue),
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.white,
                              ),
                              child: CodeTheme(
                                data: CodeThemeData(styles: githubTheme),
                                child: CodeField(
                                  controller: _correctedCodeEditor,
                                  textStyle: const TextStyle(fontFamily: 'SourceCodePro'),
                                  expands: true,
                                  maxLines: null,
                                  minLines: null,
                                  readOnly: true, // Refactored code should typically be read-only
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),

                // --- Display Parsed Diff (only for GitHub PRs) ---
                if (_selectedInputType == ReviewInputType.githubPr && parsedDiff != null && parsedDiff!.isNotEmpty) ...[
                  _sectionHeader('Original PR Changes (File by File)'),
                  const SizedBox(height: 8),
                  // Map each file diff to a display widget
                  ...parsedDiff!.map((fileDiff) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            fileDiff['filePath'] ?? 'Unknown File', // Display file path
                            style: theme.textTheme.titleMedium!.copyWith(color: Colors.blueGrey[700]),
                          ),
                          const Divider(color: Colors.blueGrey),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Display deleted lines in red
                                if (fileDiff['deletedLines'].isNotEmpty)
                                  ...fileDiff['deletedLines'].map(
                                    (line) => SelectableText(
                                      '- ${line}',
                                      style: const TextStyle(
                                        fontFamily: 'SourceCodePro',
                                        fontSize: 12,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                                // Display added lines in green
                                if (fileDiff['addedLines'].isNotEmpty)
                                  ...fileDiff['addedLines'].map(
                                    (line) => SelectableText(
                                      '+ $line',
                                      style: const TextStyle(
                                        fontFamily: 'SourceCodePro',
                                        fontSize: 12,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ),
                                // Message if no significant line changes (e.g., file rename)
                                if (fileDiff['addedLines'].isEmpty && fileDiff['deletedLines'].isEmpty)
                                  const SelectableText(
                                    'No significant line changes detected in this file (e.g., file rename or content-only changes).',
                                    style: TextStyle(fontFamily: 'SourceCodePro', fontSize: 12, color: Colors.grey),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                ],
                if (prDiff.isNotEmpty || _selectedInputType == ReviewInputType.githubPr) GitDiffWidget(prDiff: prDiff),

                // --- End Display Parsed Diff ---
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --- Helper Methods ---

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(width: 1)),
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.white,
    );
  }

  Widget _errorWidget(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.red[100], borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              message,
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: 20,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SelectableText(text, style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Colors.blue)),
            if (text == "Suggestions" && _selectedInputType == ReviewInputType.githubPr)
              ElevatedButton.icon(
                onPressed: () async {
                  if (suggestions.isNotEmpty) {
                    await postPrCommentsFlow(context: context);
                  } else {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: SelectableText("No suggestions Available!")));
                  }
                },
                icon: const Icon(Icons.comment),
                label: SelectableText("Post Suggestions", style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  iconColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10), // fixed: use BorderRadius.circular
                  ),
                ),
              ),
          ],
        ),
        const Divider(color: Colors.blue),
        const SizedBox(height: 8),
      ],
    );
  }

  // Updated _suggestionList to display filename
  Widget _suggestionList() {
    if (suggestions.isEmpty) {
      return const SelectableText("No suggestions available.", style: TextStyle(color: Colors.grey));
    }
    return Container(
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(width: 1, color: Colors.blue),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: suggestions
            .map(
              (s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (s['fileName'].isNotEmpty)
                            SelectableText(
                              s['fileName'] ?? 'Unknown File', // Display file name
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          SelectableText(s['suggestionText']!), // Display suggestion text
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
