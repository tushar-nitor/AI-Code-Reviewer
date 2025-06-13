// widgets/diff_viewer.dart

import 'package:flutter/material.dart';

class DiffViewer extends StatelessWidget {
  final String diffText;

  const DiffViewer({super.key, required this.diffText});

  @override
  Widget build(BuildContext context) {
    final lines = diffText.split('\n');

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(10.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines.map((line) => _buildDiffLine(line)).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildDiffLine(String line) {
    Color backgroundColor;
    Color textColor = Colors.black87;
    String prefix;

    if (line.startsWith('+')) {
      backgroundColor = Colors.green.withOpacity(0.15);
      textColor = Colors.green.shade900;
      prefix = '+ ';
    } else if (line.startsWith('-')) {
      backgroundColor = Colors.red.withOpacity(0.15);
      textColor = Colors.red.shade900;
      prefix = '- ';
    } else if (line.startsWith('@@') || line.startsWith('---') || line.startsWith('+++')) {
      return const SizedBox.shrink();
    } else {
      backgroundColor = Colors.transparent;
      prefix = '  ';
    }

    final displayLine = line.isNotEmpty ? line.substring(1) : '';

    return Container(
      color: backgroundColor,
      width: 2000,
      child: SelectableText.rich(
        TextSpan(
          children: [
            TextSpan(
              text: prefix,
              style: TextStyle(fontFamily: 'SourceCodePro', fontSize: 12, color: textColor.withOpacity(0.7)),
            ),
            TextSpan(
              text: displayLine,
              style: TextStyle(fontFamily: 'SourceCodePro', fontSize: 12, color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}
