// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'package:ai_code_reviewer/common/methods.dart';
import 'package:ai_code_reviewer/service/document_service.dart';
import 'package:ai_code_reviewer/widgets/code_rules_dialog.dart';
import 'package:ai_code_reviewer/widgets/gradient_button.dart';
import 'package:ai_code_reviewer/widgets/pr_charts.dart';
import 'package:ai_code_reviewer/widgets/pr_diff_viewer.dart';
import 'package:ai_code_reviewer/widgets/refactor_diff_viewer.dart';
import 'package:ai_code_reviewer/widgets/text_to_speech_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final _languageController = TextEditingController();
  final _focusController = TextEditingController();
  final _prUrlController = TextEditingController();
  final Map<String, bool> _isRefactoringFile = {};

  String _originalCodeForDiff = "";
  String _refactoredCodeForDiff = "";
  String _summarySuggestions = "";
  bool _isLoading = false;
  static final Map<String, Color> typeColors = {
    'SECURITY': Colors.red.shade700,
    'PERFORMANCE': Colors.deepOrange.shade500,
    'READABILITY': Colors.blue.shade600,
    'BUG': Colors.purple.shade600,
    'STYLE': Colors.green.shade600,
    'BEST_PRACTICE': Colors.teal.shade500,
    'TYPO': Colors.brown.shade400,
    'OTHER': Colors.grey.shade500,
    // Add 'N/A type' or similar if your AI might return null type frequently
    'N/A type': Colors.blueGrey.shade200, // Fallback for when type is null
  };

  final CodeController _codeController = CodeController(text: '// Enter your code\n', language: dart);
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

    // --- CHANGED: Reset state and start loading FIRST ---
    setState(() {
      isLoading = true;
      _resetReviewState(); // Reset all previous review data at the beginning
    });

    // --- All Validation Blocks Updated ---
    if (language.isEmpty) {
      setState(() {
        error = "Programming language is required.";
        isLoading = false; // Stop loading on validation failure
      });
      return;
    }

    if (_selectedInputType == ReviewInputType.pasteCode && _codeController.text.trim().isEmpty) {
      setState(() {
        error = "Please paste the code to review.";
        isLoading = false; // Stop loading on validation failure
      });
      return;
    }

    if (_selectedInputType == ReviewInputType.githubPr) {
      final prUrl = _prUrlController.text.trim();
      if (prUrl.isEmpty) {
        setState(() {
          error = "Please enter the GitHub PR URL.";
          isLoading = false; // Stop loading on validation failure
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
          isLoading = false; // Stop loading on validation failure
        });
        return;
      }
    }

    // The loading state is already true, no need for another setState here.

    try {
      Uri url;
      Map<String, dynamic> requestData;

      if (_selectedInputType == ReviewInputType.pasteCode) {
        url = Uri.http("localhost:3333", 'codeReviewFlow');
        requestData = {"code": _codeController.text.trim(), "language": language};
        if (focusAreas.isNotEmpty) requestData["focusAreas"] = focusAreas;
      } else {
        url = Uri.http("localhost:3333", 'prReviewFlow');
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
        body: jsonEncode({'data': requestData}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data["result"];

        final correctedCode = result['correctedCode'] as String? ?? '';

        setState(() {
          summary = result['summary'] as String?;
          _summarySuggestions = (result['suggestions_summary'] as String?) ?? "";
          if (_selectedInputType == ReviewInputType.pasteCode) {
            suggestions =
                (result['suggestions'] as List?)
                    ?.map((s) => {'fileName': "", 'suggestionText': s as String})
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
                        'type': s['type'],
                        // 'severity': s['severity'],
                      },
                    )
                    .toList() ??
                [];
          }
          _correctedCodeEditor = CodeController(
            text: correctedCode,
            language: allLanguages[_languageController.text.trim().toLowerCase()] ?? dart,
          );
        });
      } else {
        // This part correctly sets the error.
        setState(() {
          error = 'Server error: ${response.statusCode}. ${response.body}';
        });
      }
    } catch (e) {
      // This part also correctly sets the error.
      setState(() {
        error = 'Request failed: $e';
      });
    } finally {
      // This correctly stops the loading indicator after success or failure.
      setState(() {
        isLoading = false;
      });
    }
  }
  // In _CodeReviewScreenState class

  Future<void> _handleRefactorRequest(String fileName, List<String> suggestionsToApply) async {
    // --- 1. Set Loading State ---
    setState(() {
      _isRefactoringFile[fileName] = true;
      error = null; // Clear previous errors
    });

    try {
      // --- 2. Gather all suggestions for the given file ---
      if (suggestionsToApply.isEmpty) {
        throw Exception("No suggestions were selected to apply.");
      }

      // --- 3. Prepare the request for the new flow ---
      final uri = Uri.http("localhost:3333", 'refactorFileFlow');
      final headers = {'Content-Type': 'application/json'};
      final parsedPr = _parseGitHubPrUrl(_prUrlController.text.trim());

      if (parsedPr == null) {
        throw Exception("Invalid PR URL");
      }

      final body = {
        "owner": parsedPr['owner'],
        "repo": parsedPr['repo'],
        "pull_number": parsedPr['pull_number'],
        "path": fileName,
        "suggestions": suggestionsToApply,
        "language": _languageController.text.trim(),
      };

      // --- 4. Make the API Call ---
      final response = await http.post(uri, headers: headers, body: jsonEncode({'data': body}));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data["result"];
        if ((result['originalContent'] as String).isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'])));
          return;
        }

        // --- 5. Store results for the modal and show it ---
        setState(() {
          _originalCodeForDiff = extractCodeFromMarkdown(result['originalContent']);
          _refactoredCodeForDiff = extractCodeFromMarkdown(result['refactoredContent']);
        });

        _showRefactorDiffModal(fileName, extractCodeFromMarkdown(result['diff']));
      } else {
        throw Exception('Server error: ${response.statusCode}. ${response.body}');
      }
    } catch (e) {
      setState(() {
        error = 'Failed to refactor: $e';
      });
    } finally {
      // --- 6. Unset Loading State ---
      setState(() {
        _isRefactoringFile[fileName] = false;
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
    prDiff = ""; // Clear parsed diff
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
      key: _scaffoldKey,
      drawer: Drawer(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              const SizedBox(height: 20),

              CircleAvatar(
                child: Center(
                  child: IconButton(
                    onPressed: () {
                      _scaffoldKey.currentState?.closeDrawer();
                    },
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
              const SizedBox(height: 40),

              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    setState(() => _isLoading = true);
                    final result = await DocumentService.uploadDocument();
                    _scaffoldKey.currentState?.closeDrawer();

                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Success! Doument uplaoded')));
                  } catch (e) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Error: in uplaoding document')));
                  } finally {
                    setState(() => _isLoading = false);
                  }
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadiusGeometry.circular(10)),
                ),
                label: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Upload Document', style: TextStyle(color: Colors.white)),
                icon: const Icon(Icons.upload_file_rounded, color: Colors.white),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        title: SelectableText(
          'Review Code',
          style: theme.textTheme.headlineSmall!.copyWith(color: Colors.black),
          textAlign: TextAlign.center,
        ),
      ),
      body: Center(
        child: Container(
          height: MediaQuery.sizeOf(context).height,
          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.white, Color.fromARGB(255, 222, 236, 246)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const SizedBox(height: 40),

              // --- End Radio Button Row ---
              // GradientAiButton(
              //   onPressed: () {
              //     FloatingAudioPlayer.show(
              //       context,
              //       textToSpeak:
              //           "It looks like your code is designed to swap two variables. To improve it, I recommend the following: first, use simultaneous assignment. This is more concise and Pythonic. Next, if you plan to take user inputs, consider adding input validation to prevent errors. Finally, adding comments to explain each section of the code would improve readability.",
              //     );
              //   },
              //   text: ('Expert Advice'),
              // ),

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
                      title: const SelectableText('Code'),
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
                  height: 320,
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
                        maxLines: null,
                        minLines: null,
                        readOnly: false,
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
                  label: Text(
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
                if (suggestions.isNotEmpty && _selectedInputType == ReviewInputType.githubPr)
                  PRChartsWidget(suggestions: suggestions),
                // Suggestions and Refactored Code (side-by-side)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionHeader('Suggestions'),
                          const SizedBox(height: 8),
                          _suggestionList(suggestions),
                        ],
                      ),
                    ),
                    if (_correctedCodeEditor.text.isNotEmpty) const SizedBox(width: 24),
                    if (_correctedCodeEditor.text.isNotEmpty)
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionHeader('Refactored Code'),
                            const SizedBox(height: 8),

                            Stack(
                              children: [
                                // Code Editor Container
                                Container(
                                  height: 520,
                                  padding: const EdgeInsets.all(5),
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
                                      readOnly: false,
                                    ),
                                  ),
                                ),

                                // Copy Button Positioned at Top Right
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Material(
                                    color: Colors.white,
                                    shape: const CircleBorder(),
                                    elevation: 2,
                                    child: IconButton(
                                      icon: const Icon(Icons.copy, size: 20, color: Colors.blue),
                                      tooltip: 'Copy code',
                                      onPressed: () {
                                        final codeText = _correctedCodeEditor.text;
                                        Clipboard.setData(ClipboardData(text: codeText));
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(const SnackBar(content: Text('Code copied to clipboard')));
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),

                // --- Display Parsed Diff (only for GitHub PRs) ---
                // if (_selectedInputType == ReviewInputType.githubPr && parsedDiff != null && parsedDiff!.isNotEmpty) ...[
                //   _sectionHeader('Original PR Changes (File by File)'),
                //   const SizedBox(height: 8),
                //   // Map each file diff to a display widget
                //   ...parsedDiff!.map((fileDiff) {
                //     return Padding(
                //       padding: const EdgeInsets.only(bottom: 16.0),
                //       child: Column(
                //         crossAxisAlignment: CrossAxisAlignment.start,
                //         children: [
                //           SelectableText(
                //             fileDiff['filePath'] ?? 'Unknown File', // Display file path
                //             style: theme.textTheme.titleMedium!.copyWith(color: Colors.blueGrey[700]),
                //           ),
                //           const Divider(color: Colors.blueGrey),
                //           Container(
                //             padding: const EdgeInsets.all(8),
                //             decoration: BoxDecoration(
                //               border: Border.all(color: Colors.grey[300]!),
                //               borderRadius: BorderRadius.circular(8),
                //               color: Colors.white,
                //             ),
                //             child: Column(
                //               crossAxisAlignment: CrossAxisAlignment.start,
                //               children: [
                //                 // Display deleted lines in red
                //                 if (fileDiff['deletedLines'].isNotEmpty)
                //                   ...fileDiff['deletedLines'].map(
                //                     (line) => SelectableText(
                //                       '- ${line}',
                //                       style: const TextStyle(
                //                         fontFamily: 'SourceCodePro',
                //                         fontSize: 12,
                //                         color: Colors.red,
                //                       ),
                //                     ),
                //                   ),
                //                 // Display added lines in green
                //                 if (fileDiff['addedLines'].isNotEmpty)
                //                   ...fileDiff['addedLines'].map(
                //                     (line) => SelectableText(
                //                       '+ $line',
                //                       style: const TextStyle(
                //                         fontFamily: 'SourceCodePro',
                //                         fontSize: 12,
                //                         color: Colors.blue,
                //                       ),
                //                     ),
                //                   ),
                //                 // Message if no significant line changes (e.g., file rename)
                //                 if (fileDiff['addedLines'].isEmpty && fileDiff['deletedLines'].isEmpty)
                //                   const SelectableText(
                //                     'No significant line changes detected in this file (e.g., file rename or content-only changes).',
                //                     style: TextStyle(fontFamily: 'SourceCodePro', fontSize: 12, color: Colors.grey),
                //                   ),
                //               ],
                //             ),
                //           ),
                //         ],
                //       ),
                //     );
                //   }),
                //   const SizedBox(height: 24),
                // ],
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
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(width: 1)),
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
            child: Text(
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
                    ).showSnackBar(const SnackBar(content: SelectableText("No suggestions Available!")));
                  }
                },
                icon: const Icon(Icons.comment),
                label: const Text("Post Suggestions", style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  iconColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10), // fixed: use BorderRadius.circular
                  ),
                ),
              )
            else if (text == "Summary" && _selectedInputType == ReviewInputType.pasteCode)
              ElevatedButton.icon(
                onPressed: () async {
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      // The AlertDialog now contains our stateful content widget.
                      return AlertDialog(
                        title: Text('Coding Standards for ${_languageController.text}'),
                        // The content is wide enough to avoid overflow and is scrollable internally.
                        content: SizedBox(
                          width: double.maxFinite,
                          child: StandardsDialogContent(language: _languageController.text),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: const Text('Close'),
                          ),
                        ],
                      );
                    },
                  );
                },
                icon: const Icon(Icons.comment),
                label: const Text("Show Best Practices", style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  iconColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10), // fixed: use BorderRadius.circular
                  ),
                ),
              ),
            if (text == "Summary" && _selectedInputType == ReviewInputType.pasteCode)
              GradientAiButton(
                onPressed: () {
                  FloatingAudioPlayer.show(context, textToSpeak: _summarySuggestions);
                },
                text: ('Expert Advice'),
              ),

            //               void _showStandardsDialog(BuildContext context, String language) {
            //   showDialog(
            //     context: context,
            //     builder: (BuildContext context) {
            //       // The AlertDialog now contains our stateful content widget.
            //       return AlertDialog(
            //         title: Text('Coding Standards for $language'),
            //         // The content is wide enough to avoid overflow and is scrollable internally.
            //         content: SizedBox(
            //           width: double.maxFinite,
            //           child: _StandardsDialogContent(language: language),
            //         ),
            //         actions: [
            //           TextButton(
            //             onPressed: () {
            //               Navigator.of(context).pop();
            //             },
            //             child: const Text('Close'),
            //           ),
            //         ],
            //       );
            //     },
            //   );
            // }
          ],
        ),
        const Divider(color: Colors.blue),
        const SizedBox(height: 8),
      ],
    );
  }

  // Updated _suggestionList to display filename
  // Ensure _buildTypeBadge and _formatFileNameAndLine are accessible in this scope.
  // If this _suggestionList method is part of a State class, ensure these helpers are too.

  Widget _suggestionList(List<Map<String, dynamic>> suggestions) {
    if (suggestions.isEmpty) {
      return const SelectableText("No suggestions available.", style: TextStyle(color: Colors.grey));
    }

    if (_selectedInputType == ReviewInputType.pasteCode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: suggestions.map((s) {
          final String? suggestionText = s['suggestionText'] as String?;

          return Container(
            margin: const EdgeInsets.symmetric(vertical: 6.0),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  // Optional: Add onTap behavior here
                },
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SelectableText(
                    suggestionText ?? 'No suggestion text provided.',
                    style: TextStyle(fontSize: 14, height: 1.5, color: Theme.of(context).textTheme.bodyMedium?.color),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      );
    } else {
      // Group suggestions by fileName
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final s in suggestions) {
        final fileName = s['fileName'] ?? 'Unknown File';
        grouped.putIfAbsent(fileName, () => []).add(s);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: grouped.entries.map((entry) {
          final fileName = entry.key;
          final fileSuggestions = entry.value;

          return Padding(
            padding: const EdgeInsets.only(bottom: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // MODIFICATION: Wrap the file name and button in a Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // File Name
                    Expanded(
                      child: SelectableText(
                        fileName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    // NEW: "Apply & Preview" Button
                    _isRefactoringFile[fileName] ?? false
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 3)),
                          )
                        : GradientAiButton(
                            onPressed: () => _showSuggestionSelectionDialog(fileName),
                            text: "Apply & Preview",
                          ),
                    //  ElevatedButton.icon(
                    //     onPressed: () => _showSuggestionSelectionDialog(fileName),
                    //     icon: const Icon(Icons.auto_awesome, size: 16),
                    //     label: const Text("Apply & Preview"),
                    //     style: ElevatedButton.styleFrom(
                    //       foregroundColor: Colors.white,
                    //       backgroundColor: const Color.fromARGB(255, 62, 164, 65),
                    //       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    //     ),
                    //   ),
                  ],
                ),
                const SizedBox(height: 10),
                ...fileSuggestions.map((s) {
                  //  final int? lineNumber = s['lineNumber'] as int?;
                  final String? suggestionText = s['suggestionText'] as String?;
                  final String? type = s['type'] as String?;

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(vertical: 6.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          // Optional action on tap
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTypeBadge(type),

                              const SizedBox(height: 10),
                              SelectableText(
                                suggestionText ?? 'No suggestion text provided.',
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: Theme.of(context).textTheme.bodyMedium?.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        }).toList(),
      );
    }
  }

  Widget _buildTypeBadge(String? type) {
    // Replace underscores for better readability (e.g., "BEST_PRACTICE" -> "BEST PRACTICE")
    final String displayType = type?.replaceAll('_', ' ') ?? 'N/A Type';
    final Color backgroundColor = typeColors[type] ?? Colors.grey.shade400; // Default color for unmapped types

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(4)),
      child: Text(
        displayType,
        style: const TextStyle(
          color: Colors.white, // Text color should contrast well with background
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
  // In _CodeReviewScreenState class

  // In _CodeReviewScreenState class

  void _showRefactorDiffModal(String fileName, String diff) {
    // Create controllers for the two code editors in the dialog
    final originalController = CodeController(
      text: _originalCodeForDiff,
      language: allLanguages[_languageController.text.trim().toLowerCase()] ?? dart,
    );
    final refactoredController = CodeController(
      text: _refactoredCodeForDiff,
      language: allLanguages[_languageController.text.trim().toLowerCase()] ?? dart,
    );
    bool showDiffOnly = false;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (context) {
        // StatefulBuilder allows the dialog's content to have its own state.
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // This state is local to the dialog

            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              // The title now includes the toggle switch
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.difference, color: Colors.blue),
                      const SizedBox(width: 8),
                      // Use Flexible to prevent long filenames from causing an overflow
                      Flexible(child: Text('Preview: $fileName', overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                  // The Toggle Switch to change views
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(showDiffOnly ? 'Diff View' : 'Side-by-Side', style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Transform.scale(
                        scale: .7,
                        child: Switch.adaptive(
                          value: showDiffOnly,
                          onChanged: (value) {
                            // Use the dialog's own setState to rebuild its content
                            setDialogState(() {
                              showDiffOnly = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.85,
                height: MediaQuery.of(context).size.height * 0.65,
                // Conditionally display the correct view based on the toggle state
                child: showDiffOnly
                    // --- A. THE DIFF VIEW ---
                    ? DiffViewer(diffText: diff)
                    // --- B. THE SIDE-BY-SIDE VIEW (Your working layout) ---
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Original Code Viewer
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Original", style: TextStyle(fontWeight: FontWeight.bold)),
                                const Divider(),
                                Expanded(
                                  child: CodeTheme(
                                    data: CodeThemeData(styles: githubTheme),
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.vertical,
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: SizedBox(
                                          width: 1200,
                                          child: CodeField(
                                            controller: originalController,
                                            readOnly: true,
                                            textStyle: const TextStyle(fontFamily: 'SourceCodePro'),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Refactored Code Viewer
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Refactored", style: TextStyle(fontWeight: FontWeight.bold)),
                                const Divider(),
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.blue.shade200),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: CodeTheme(
                                      data: CodeThemeData(styles: githubTheme),
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.vertical,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: SizedBox(
                                            width: 1200,
                                            child: CodeField(
                                              controller: refactoredController,
                                              readOnly: false,
                                              textStyle: const TextStyle(fontFamily: 'SourceCodePro'),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Close")),
                ElevatedButton.icon(
                  // The button's label and action change based on the view
                  icon: const Icon(Icons.copy),
                  label: const Text("Copy Refactored Code"),
                  onPressed: () {
                    final textToCopy = refactoredController.text;
                    Clipboard.setData(ClipboardData(text: textToCopy));
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(showDiffOnly ? 'Diff copied!' : 'Refactored code copied!')));
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      originalController.dispose();
      refactoredController.dispose();
    });
  }

  // In _CodeReviewScreenState class

  // In _CodeReviewScreenState class

  Future<void> _showSuggestionSelectionDialog(String fileName) async {
    final List<Map<String, dynamic>> suggestionsForFile = suggestions
        .where((s) => s['fileName'] == fileName)
        .map((s) => Map<String, dynamic>.from(s..['isSelected'] = true))
        .toList();

    final customSuggestionController = TextEditingController();

    final List<Map<String, dynamic>>? finalSuggestions =
        await showDialog<List<Map<String, dynamic>>>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
                void addCustomSuggestion() {
                  final text = customSuggestionController.text.trim();
                  if (text.isNotEmpty) {
                    setDialogState(() {
                      suggestionsForFile.add({
                        'fileName': fileName,
                        'suggestionText': text,
                        'type': 'CUSTOM',
                        'isSelected': true,
                      });
                      customSuggestionController.clear();
                    });
                  }
                }

                return AlertDialog(
                  backgroundColor: Colors.grey[50],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  titlePadding: const EdgeInsets.all(0),
                  title: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                      border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.checklist_rtl, color: Colors.green),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Select Suggestions for: $fileName",
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  content: SizedBox(
                    width: MediaQuery.of(context).size.width * 0.5,
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.only(top: 10),
                            // decoration: BoxDecoration(
                            //   color: Colors.white,
                            //   borderRadius: BorderRadius.circular(8),
                            //   border: Border.all(color: Colors.grey.shade300),
                            // ),
                            // Use ClipRRect to ensure the ListView respects the border radius
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: ListView.builder(
                                padding: const EdgeInsets.all(8), // Add padding for the list itself
                                itemCount: suggestionsForFile.length,
                                itemBuilder: (context, index) {
                                  final suggestion = suggestionsForFile[index];
                                  // --- CHANGED: Replaced Card with a custom styled Container ---
                                  return Container(
                                    margin: const EdgeInsets.symmetric(vertical: 5.0),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey.shade200, width: 1),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.grey.withOpacity(0.1),
                                          spreadRadius: 1,
                                          blurRadius: 5,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    // NEW: Use a Column for a custom layout (Header + CheckboxListTile)
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // NEW: Header section for the type badge
                                        Padding(
                                          padding: const EdgeInsets.only(left: 20, top: 8, bottom: 8),
                                          child: _buildTypeBadge(suggestion['type']),
                                        ),
                                        const Divider(height: 1),
                                        // CheckboxListTile for the main content
                                        CheckboxListTile(
                                          controlAffinity: ListTileControlAffinity.leading,
                                          activeColor: Colors.blue,
                                          value: suggestion['isSelected'],
                                          dense: true,
                                          onChanged: (bool? value) {
                                            setDialogState(() {
                                              suggestion['isSelected'] = value ?? false;
                                            });
                                          },
                                          title: Text(suggestion['suggestionText']),
                                          // Subtitle is no longer needed here
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: customSuggestionController,
                                decoration: _inputDecoration('Add a custom suggestion', Icons.task_alt_rounded),

                                onSubmitted: (_) => addCustomSuggestion(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              icon: const Icon(Icons.add),
                              onPressed: addCustomSuggestion,
                              tooltip: 'Add Suggestion',
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.blue,
                                padding: const EdgeInsets.all(16),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text("Cancel")),
                    GradientAiButton(
                      onPressed: () {
                        final selected = suggestionsForFile.where((s) => s['isSelected']).toList();
                        Navigator.of(context).pop(selected);
                      },
                      text: "Apply & Preview",
                    ),
                    // ElevatedButton.icon(
                    //   icon: const Icon(Icons.auto_awesome),
                    //   label: const Text("Apply & Preview"),
                    //   onPressed: () {
                    //     final selected = suggestionsForFile.where((s) => s['isSelected']).toList();
                    //     Navigator.of(context).pop(selected);
                    //   },
                    //   style: ElevatedButton.styleFrom(
                    //     backgroundColor: Colors.green,
                    //     foregroundColor: Colors.white,
                    //     padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    //     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    //   ),
                    // ),
                  ],
                );
              },
            );
          },
        ).whenComplete(() {
          customSuggestionController.dispose();
        });

    if (finalSuggestions != null && finalSuggestions.isNotEmpty) {
      final suggestionTexts = finalSuggestions.map((s) => s['suggestionText'] as String).toList();
      _handleRefactorRequest(fileName, suggestionTexts);
    }
  }
}
