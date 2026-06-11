import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/quiz_provider.dart';
import 'history_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<Map<String, dynamic>>> _historyFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _refresh();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  void _refresh() {
    setState(() {
      _historyFuture = context.read<QuizProvider>().getHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz History'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final allHistory = snapshot.data ?? [];
          final history = allHistory.where((item) {
            final className = (item['class_name'] ?? '').toString().toLowerCase();
            return className.contains(_searchQuery);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search classes...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey[100],
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                  ),
                ),
              ),
              if (history.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty ? 'No quiz history found.' : 'No matches for "$_searchQuery"',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: history.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final item = history[index];
                      final date = DateTime.parse(item['date_taken']);
                      final score = item['score'];
                      final total = item['total_questions'];
                      final accuracy = (score / total) * 100;
                      final timeTaken = item['time_taken_seconds'];
                      final type = item['quiz_type'].toString().split('.').last.toUpperCase();

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => HistoryDetailScreen(historyItem: item),
                              ),
                            );
                            _refresh(); // Refresh if edits were made
                          },
                          leading: CircleAvatar(
                            backgroundColor: _getScoreColor(accuracy),
                            foregroundColor: Colors.white,
                            child: Text(score.toString()),
                          ),
                          title: Text(item['class_name'] ?? 'Unknown Class'),
                          subtitle: Text(
                            '${DateFormat('MMM d, yyyy HH:mm').format(date)}\n$type | ${timeTaken}s',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('${accuracy.toStringAsFixed(0)}%', 
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const Text('Accuracy', style: TextStyle(fontSize: 10)),
                                ],
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right, color: Colors.grey),
                            ],
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Color _getScoreColor(double accuracy) {
    if (accuracy >= 80) return Colors.green;
    if (accuracy >= 50) return Colors.orange;
    return Colors.red;
  }
}
