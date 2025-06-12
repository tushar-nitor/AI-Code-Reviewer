// lib/pr_charts_widget.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

class PRChartsWidget extends StatefulWidget {
  final List<Map<String, dynamic>> suggestions;

  const PRChartsWidget({super.key, required this.suggestions});

  @override
  State<PRChartsWidget> createState() => _PRChartsWidgetState();
}

class _PRChartsWidgetState extends State<PRChartsWidget> {
  late Map<String, int> _issueTypeCounts;
  late Map<String, int> _commentsPerFile;
  late Map<String, int> _severityCounts;
  late List<MapEntry<String, int>> _sortedTopFiles; // Holds top files for the bar chart
  int? touchedIndex; // For pie chart touch interaction

  @override
  void initState() {
    super.initState();
    _analyzeSuggestions(widget.suggestions);
  }

  @override
  void didUpdateWidget(covariant PRChartsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.suggestions != oldWidget.suggestions) {
      _analyzeSuggestions(widget.suggestions);
    }
  }

  void _analyzeSuggestions(List<Map<String, dynamic>> suggestions) {
    _issueTypeCounts = {};
    _commentsPerFile = {};
    _severityCounts = {};
    _sortedTopFiles = [];

    for (var suggestion in suggestions) {
      // Analyze Issue Type
      final type = (suggestion['type'] as String?) ?? 'OTHER';
      _issueTypeCounts[type] = (_issueTypeCounts[type] ?? 0) + 1;

      // Analyze Comments Per File
      final fileName = (suggestion['fileName'] as String?) ?? 'UNKNOWN_FILE';
      _commentsPerFile[fileName] = (_commentsPerFile[fileName] ?? 0) + 1;

      // Analyze Severity
      final severity = (suggestion['severity'] as String?) ?? 'UNKNOWN';
      _severityCounts[severity] = (_severityCounts[severity] ?? 0) + 1;
    }

    // Filter and Sort files for Bar Chart: Only show files with count >= 2
    if (_commentsPerFile.isNotEmpty) {
      final filteredFiles = _commentsPerFile.entries.where((entry) => entry.value >= 2).toList();
      filteredFiles.sort((a, b) => b.value.compareTo(a.value)); // Sort by comment count
      _sortedTopFiles = filteredFiles.take(5).toList(); // Take top 5 after filtering
    }
  }

  // --- CHART DATA PREPARATION METHODS ---

  List<PieChartSectionData> _getIssueTypePieChartSections(BuildContext context) {
    final Map<String, Color> typeColors = {
      'SECURITY': Colors.red.shade700,
      'PERFORMANCE': Colors.deepOrange.shade500,
      'READABILITY': Colors.blue.shade600,
      'BUG': Colors.purple.shade600,
      'STYLE': Colors.green.shade600,
      'BEST_PRACTICE': Colors.teal.shade500,
      'TYPO': Colors.brown.shade400,
      'OTHER': Colors.grey.shade500,
    };

    if (_issueTypeCounts.isEmpty) {
      return [
        PieChartSectionData(
          color: Colors.grey.shade200,
          value: 1,
          title: 'No issue types',
          radius: 80,
          titleStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ];
    }

    double total = _issueTypeCounts.values.fold(0, (sum, count) => sum + count);
    final List<PieChartSectionData> sections = [];
    int index = 0;

    _issueTypeCounts.entries.forEach((entry) {
      final isTouched = index == touchedIndex;
      final double radius = isTouched ? 90.0 : 80.0;
      final double percentage = (entry.value / total) * 100;

      // Badge widget for labels outside the chart
      final badge = _ChartBadge(
        '${entry.key}',
        value: percentage,
        borderColor: typeColors[entry.key],
        textColor: Theme.of(context).textTheme.bodyLarge?.color,
      );

      sections.add(
        PieChartSectionData(
          color: typeColors[entry.key] ?? Colors.black,
          value: entry.value.toDouble(),
          title: '', // We use the badge widget instead of the title
          radius: radius,
          badgeWidget: percentage < 4 ? null : badge, // Hide badge for small sections
          badgePositionPercentageOffset: 1.2,
        ),
      );
      index++;
    });
    return sections;
  }

  List<PieChartSectionData> _getSeverityPieChartSections(BuildContext context) {
    final Map<String, Color> severityColors = {
      'CRITICAL': Colors.red.shade900,
      'HIGH': Colors.red.shade600,
      'MEDIUM': Colors.orange.shade600,
      'LOW': Colors.yellow.shade600,
      'INFO': Colors.green.shade600,
      'UNKNOWN': Colors.grey.shade400,
    };

    if (_severityCounts.isEmpty || (_severityCounts.length == 1 && _severityCounts.containsKey('UNKNOWN'))) {
      return [
        PieChartSectionData(
          color: Colors.grey.shade200,
          value: 1,
          title: 'No severity data',
          radius: 70,
          titleStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ];
    }

    double total = _severityCounts.values.fold(0, (sum, count) => sum + count);
    final List<PieChartSectionData> sections = [];
    int index = 0;

    _severityCounts.entries.forEach((entry) {
      final isTouched = index == touchedIndex;
      final double radius = isTouched ? 80.0 : 70.0;
      final double percentage = (entry.value / total) * 100;

      final badge = _ChartBadge(
        '${entry.key}',
        value: percentage,
        borderColor: severityColors[entry.key],
        textColor: Theme.of(context).textTheme.bodyLarge?.color,
      );

      sections.add(
        PieChartSectionData(
          color: severityColors[entry.key] ?? Colors.black,
          value: entry.value.toDouble(),
          title: '', // Use badge widget instead
          radius: radius,
          badgeWidget: percentage < 4 ? null : badge, // Hide badge for small sections
          badgePositionPercentageOffset: 1.15,
        ),
      );
      index++;
    });

    return sections;
  }

  List<BarChartGroupData> _getCommentsPerFileBarGroups() {
    if (_sortedTopFiles.isEmpty) return [];

    return _sortedTopFiles.asMap().entries.map((entry) {
      final index = entry.key;
      final fileEntry = entry.value;
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: fileEntry.value.toDouble(),
            color: Colors.blueAccent,
            width: 16,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
        showingTooltipIndicators: [],
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.suggestions.isEmpty) {
      return const Center(child: Text('No suggestions to chart.'));
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    const double breakpoint = 700.0;
    final bool useRowLayout = screenWidth > breakpoint;

    // --- Build Chart Widgets ---
    Widget issueTypeChartWidget = _issueTypeCounts.isNotEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Issue Type Distribution', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              SizedBox(
                height: 320, // Increased height for labels
                width: useRowLayout ? screenWidth * 0.45 : double.infinity,
                child: PieChart(
                  PieChartData(
                    sections: _getIssueTypePieChartSections(context),
                    sectionsSpace: 2,
                    centerSpaceRadius: 40, // Make it a donut chart
                    pieTouchData: PieTouchData(
                      touchCallback: (FlTouchEvent event, pieTouchResponse) {
                        setState(() {
                          if (!event.isInterestedForInteractions ||
                              pieTouchResponse == null ||
                              pieTouchResponse.touchedSection == null) {
                            touchedIndex = -1;
                            return;
                          }
                          touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                        });
                      },
                    ),
                  ),
                ),
              ),
            ],
          )
        : const SizedBox.shrink();

    Widget commentsPerFileChartWidget = _sortedTopFiles.isNotEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Top Files by Comments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              SizedBox(
                height: 320, // Consistent height
                width: useRowLayout ? screenWidth * 0.45 : double.infinity,
                child: BarChart(
                  BarChartData(
                    barGroups: _getCommentsPerFileBarGroups(),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final int intValue = value.toInt();
                            if (intValue < 0 || intValue >= _sortedTopFiles.length) {
                              return const Text('');
                            }
                            final fileName = _sortedTopFiles[intValue].key;
                            final shortFileName = fileName.split('/').last;
                            return SideTitleWidget(
                              meta: meta,
                              space: 4,
                              child: Text(
                                shortFileName.length > 15 ? '${shortFileName.substring(0, 12)}...' : shortFileName,
                                style: const TextStyle(fontSize: 9),
                              ),
                            );
                          },
                          reservedSize: 32,
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final filePath = _sortedTopFiles[group.x.toInt()].key;
                          return BarTooltipItem(
                            '${filePath.split('/').last}\n${rod.toY.toInt()} comments',
                            const TextStyle(color: Colors.white, fontSize: 10),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          )
        : const SizedBox.shrink();

    Widget severityChartWidget =
        _severityCounts.isNotEmpty && !(_severityCounts.length == 1 && _severityCounts.containsKey('UNKNOWN'))
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Issue Severity Distribution', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              SizedBox(
                height: 320, // Increased height for labels
                child: PieChart(
                  PieChartData(
                    sections: _getSeverityPieChartSections(context),
                    sectionsSpace: 2,
                    centerSpaceRadius: 60,
                    pieTouchData: PieTouchData(
                      touchCallback: (FlTouchEvent event, pieTouchResponse) {
                        setState(() {
                          if (!event.isInterestedForInteractions ||
                              pieTouchResponse == null ||
                              pieTouchResponse.touchedSection == null) {
                            touchedIndex = -1;
                            return;
                          }
                          touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                        });
                      },
                    ),
                  ),
                ),
              ),
            ],
          )
        : const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(width: 1, color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (useRowLayout && issueTypeChartWidget is! SizedBox && commentsPerFileChartWidget is! SizedBox)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: issueTypeChartWidget),
                const SizedBox(width: 30),
                Expanded(child: commentsPerFileChartWidget),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                issueTypeChartWidget,
                if (issueTypeChartWidget is! SizedBox && commentsPerFileChartWidget is! SizedBox)
                  const SizedBox(height: 30),
                commentsPerFileChartWidget,
              ],
            ),
          if (severityChartWidget is! SizedBox) ...[
            if ((issueTypeChartWidget is! SizedBox || commentsPerFileChartWidget is! SizedBox))
              const SizedBox(height: 30),
            severityChartWidget,
          ],
        ],
      ),
    );
  }
}

/// A custom widget for pie chart badges to prevent clutter.
class _ChartBadge extends StatelessWidget {
  const _ChartBadge(this.label, {required this.value, this.borderColor, this.textColor});

  final String label;
  final double value;
  final Color? borderColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(0.8),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor ?? Colors.grey, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 3, offset: const Offset(1, 1))],
      ),
      child: Text(
        '$label (${value.toStringAsFixed(0)}%)',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor ?? Colors.black),
      ),
    );
  }
}
