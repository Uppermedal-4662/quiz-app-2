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

  @override
  void initState() {
    super.initState();
    _historyFuture = context.read<QuizProvider>().getHistory();
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
          final history = snapshot.data ?? [];
          if (history.isEmpty) {
            return const Center(child: Text('No quiz history found. Go take a quiz!'));
          }

          return ListView.builder(
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
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HistoryDetailScreen(historyItem: item),
                      ),
                    );
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
