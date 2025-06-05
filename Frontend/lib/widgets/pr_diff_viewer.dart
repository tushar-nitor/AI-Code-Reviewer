// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/material.dart';

// This widget displays a Git diff with expandable sections for files and their content.
class GitDiffWidget extends StatefulWidget {
  final String prDiff;

  const GitDiffWidget({super.key, required this.prDiff});

  @override
  _GitDiffWidgetState createState() => _GitDiffWidgetState();
}

class _GitDiffWidgetState extends State<GitDiffWidget> {
  late List<DiffFile> _parsedFiles;

  @override
  void initState() {
    super.initState();
    _parsedFiles = _parseDiff(widget.prDiff);
  }

  // Parses the raw Git diff string into a list of DiffFile objects.
  List<DiffFile> _parseDiff(String diffText) {
    final lines = diffText.split('\n');
    final List<DiffFile> files = [];
    DiffFile? currentFile;
    bool inHunk = false; // To track if we are inside a diff hunk

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.startsWith('diff --git')) {
        inHunk = false; // Reset hunk state
        String? fileName;
        final diffParts = line.split(' ');
        if (diffParts.length >= 3) {
          String tempFileName = diffParts.last.replaceFirst('b/', '');
          if (tempFileName == diffParts.last) {
            tempFileName = diffParts[2].replaceFirst('a/', '');
          }
          if (tempFileName != '/dev/null') {
            fileName = tempFileName;
          }
        }

        currentFile = null;
        if (fileName != null) {
          currentFile = DiffFile(fileName: fileName, lines: []);
          files.add(currentFile);
        }
      } else if (currentFile != null && (line.startsWith('--- a/') || line.startsWith('+++ b/'))) {
        // We can ignore these lines as the filename is usually captured from 'diff --git'
        // or from the '+++ b/' line if the file was new.
        // If currentFile's fileName is still generic/placeholder and we find a better one here:
        if (currentFile.fileName == 'Unknown File' && line.startsWith('+++ b/')) {
          currentFile.fileName = line.substring(6); // Get path after '+++ b/'
        }
      } else if (currentFile != null && line.startsWith('@@')) {
        inHunk = true;
      } else if (currentFile != null && inHunk) {
        if (line.startsWith('+')) {
          currentFile.lines.add(DiffLine(text: line.substring(1), type: DiffLineType.added));
        } else if (line.startsWith('-')) {
          currentFile.lines.add(DiffLine(text: line.substring(1), type: DiffLineType.deleted));
        } else if (line.startsWith(' ')) {
          currentFile.lines.add(DiffLine(text: line.substring(1), type: DiffLineType.unchanged));
        } else {
          currentFile.lines.add(DiffLine(text: line, type: DiffLineType.unchanged));
        }
      }
    }
    return files;
  }

  @override
  Widget build(BuildContext context) {
    if (_parsedFiles.isEmpty) {
      return const Center(child: Text('No diff to display or diff is invalid.'));
    }

    return Container(
      // margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        border: Border.all(width: .2),
        borderRadius: BorderRadius.circular(10),
        color: Colors.white,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent, // Removes the top/bottom divider line
        ),
        child: ExpansionTile(
          title: Text(
            'Files Changed (${_parsedFiles.length})',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).colorScheme.onSurface),
          ),
          initiallyExpanded: true, // You can control initial expansion
          children: [
            // Use a ListView.builder here if you want scrolling for the file list itself
            // However, if the parent is a SingleChildScrollView, a Column is fine.
            Column(
              children: _parsedFiles.map((file) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: Container(
                    // Inner card for each file
                    decoration: BoxDecoration(
                      border: Border.all(width: .2),
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.white,
                    ),
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        dividerColor: Colors.transparent, // Removes the top/bottom divider line
                      ),
                      child: ExpansionTile(
                        title: Text(
                          file.fileName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        childrenPadding: const EdgeInsets.all(8.0),
                        children: [
                          // Column to display the diff lines for this file
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: file.lines.map((diffLine) {
                              Color textColor;
                              Color backgroundColor = Colors.transparent;
                              String prefix = '';

                              switch (diffLine.type) {
                                case DiffLineType.added:
                                  textColor = Colors.green.shade800;
                                  backgroundColor = Colors.green.shade50;
                                  prefix = '+';
                                  break;
                                case DiffLineType.deleted:
                                  textColor = Colors.red.shade800;
                                  backgroundColor = Colors.red.shade50;
                                  prefix = '-';
                                  break;
                                case DiffLineType.unchanged:
                                  textColor = Colors.black87;
                                  backgroundColor = Colors.white;
                                  prefix = ' ';
                                  break;
                              }

                              return Container(
                                color: backgroundColor,
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                                child: Text(
                                  '$prefix${diffLine.text}',
                                  style: TextStyle(color: textColor, fontFamily: 'monospace', fontSize: 13),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// Data models (keep these in the same file for DartPad or separate them in a real project)
enum DiffLineType { added, deleted, unchanged }

class DiffLine {
  final String text;
  final DiffLineType type;

  DiffLine({required this.text, required this.type});
}

class DiffFile {
  String fileName; // Changed to non-final to allow updates in parsing
  final List<DiffLine> lines;

  DiffFile({required this.fileName, required this.lines});
}
