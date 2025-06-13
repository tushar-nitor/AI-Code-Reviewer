import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import 'package:markdown/markdown.dart' as md;
// Make sure to import your custom widgets

// This helper class is still correct and needed.
class CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final String code = element.textContent;
    return CopyableCodeBlock(text: code);
  }
}

class StandardsDialogContent extends StatefulWidget {
  final String language;
  const StandardsDialogContent({super.key, required this.language});

  @override
  State<StandardsDialogContent> createState() => _StandardsDialogContentState();
}

class _StandardsDialogContentState extends State<StandardsDialogContent> {
  // ... All of your existing state and fetch logic remains the same ...
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _standardsData;

  @override
  void initState() {
    super.initState();
    _fetchStandardsData();
  }

  Future<void> _fetchStandardsData() async {
    // ... this function does not need to change ...
    final Uri url = Uri.http('localhost:3333', 'codingStandardsFlow');
    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              "data": {'language': widget.language},
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          final responseData = jsonDecode(response.body);
          _standardsData = responseData['response'] ?? responseData;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load standards. Server returned status ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to fetch standards: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (_standardsData != null) {
      return _buildContent(context);
    }
    return const Center(child: Text('No data available.'));
  }

  Widget _buildContent(BuildContext context) {
    // ... The data preparation logic is the same ...
    final summary = _standardsData!["result"]['summary'] as String;
    final bestPractices = (_standardsData!["result"]['bestPractices'] as List<dynamic>).cast<Map<String, dynamic>>();
    final implementationGuide = _standardsData!["result"]['implementationGuide'] as String;

    final buffer = StringBuffer();

    buffer.writeln("## Summary");
    buffer.writeln(summary);

    buffer.writeln("\n## Best Practices");
    for (var practice in bestPractices) {
      buffer.writeln("* **${practice['ruleName']}:** ${practice['description']}");
    }

    buffer.writeln("\n## Implementation Guide");
    buffer.writeln(implementationGuide.replaceAll('\\n', '\n'));

    final markdownContent = buffer.toString();

    // FINAL CORRECTED IMPLEMENTATION:
    // We use the default Markdown() constructor and pass the 'builders' map directly.
    return Markdown(
      data: markdownContent,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(
        Theme.of(context),
      ).copyWith(h2: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      // Pass the builders map directly to the default constructor
      builders: {'pre': CodeBlockBuilder()},
    );
  }
}

class CopyableCodeBlock extends StatefulWidget {
  final String text;

  const CopyableCodeBlock({required this.text, super.key});

  @override
  State<CopyableCodeBlock> createState() => _CopyableCodeBlockState();
}

class _CopyableCodeBlockState extends State<CopyableCodeBlock> {
  bool _hasCopied = false;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      // margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[850] : Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          // The code text content
          Padding(
            // Add extra padding to prevent text from overlapping with the button
            padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                widget.text,
                style: GoogleFonts.sourceCodePro(), // Use a monospace font for code
              ),
            ),
          ),
          // The copy button positioned at the top-right
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              icon: Icon(_hasCopied ? Icons.check_rounded : Icons.copy_rounded, size: 20),
              tooltip: 'Copy Code',
              onPressed: () {
                // Copy the text to the system clipboard
                Clipboard.setData(ClipboardData(text: widget.text));

                // Provide visual feedback to the user
                setState(() {
                  _hasCopied = true;
                });

                // Revert the icon back to 'copy' after 2 seconds
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) {
                    setState(() {
                      _hasCopied = false;
                    });
                  }
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
