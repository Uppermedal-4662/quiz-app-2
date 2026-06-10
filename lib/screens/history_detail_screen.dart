import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../widgets/latex_text.dart';

class HistoryDetailScreen extends StatefulWidget {
  final Map<String, dynamic> historyItem;

  const HistoryDetailScreen({super.key, required this.historyItem});

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  late Future<List<Map<String, dynamic>>> _detailsFuture;
  final SecurityService _securityService = SecurityService();

  @override
  void initState() {
    super.initState();
    _detailsFuture = _fetchDetails();
  }

  Future<List<Map<String, dynamic>>> _fetchDetails() async {
    final db = DatabaseService();
    final rawDetails = await db.getHistoryDetails(widget.historyItem['id']);
    
    // We need to fetch the question text and options to show them
    // Since history_details only stores IDs and results
    final List<Map<String, dynamic>> enrichedDetails = [];
    
    final allQuestions = await db.getQuestionsByClass(widget.historyItem['class_id']);
    
    for (var detail in rawDetails) {
      final qId = detail['question_id'];
      final qData = allQuestions.firstWhere((q) => q['id'] == qId, orElse: () => {});
      
      if (qData.isNotEmpty) {
        final decryptedText = _securityService.decryptData(qData['question_text']);
        final List<dynamic> encryptedOptions = jsonDecode(qData['options']);
        final decryptedOptions = encryptedOptions.map((opt) => _securityService.decryptData(opt.toString())).toList();
        
        List<String> decryptedCorrect = [];
        if (qData['correct_answers'] != null) {
          final List<dynamic> enc = jsonDecode(qData['correct_answers']);
          decryptedCorrect = enc.map((a) => _securityService.decryptData(a.toString())).toList();
        }

        enrichedDetails.add({
          ...detail,
          'question_text': decryptedText,
          'options': decryptedOptions,
          'correct_answers': decryptedCorrect,
          'user_answers': jsonDecode(detail['user_answers']),
        });
      }
    }
    
    return enrichedDetails;
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.historyItem['score'];
    final total = widget.historyItem['total_questions'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz Review'),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryStat('Score', '$score/$total'),
                _buildSummaryStat('Accuracy', '${((score / total) * 100).toStringAsFixed(0)}%'),
                _buildSummaryStat('Time', '${widget.historyItem['time_taken_seconds']}s'),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _detailsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                
                final details = snapshot.data ?? [];
                
                return ListView.builder(
                  itemCount: details.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final d = details[index];
                    final isCorrect = d['is_correct'] == 1;
                    final List<dynamic> userAns = d['user_answers'];
                    final List<dynamic> correctAns = d['correct_answers'];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: isCorrect ? Colors.green.shade200 : Colors.red.shade200, width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  backgroundColor: isCorrect ? Colors.green : Colors.red,
                                  radius: 12,
                                  child: Icon(isCorrect ? Icons.check : Icons.close, size: 16, color: Colors.white),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: LatexText(
                                    d['question_text'],
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text('Options:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 8),
                            ...(d['options'] as List).map((opt) {
                              final bool wasSelected = userAns.contains(opt);
                              final bool isActuallyCorrect = correctAns.contains(opt);
                              
                              Color? textColor;
                              IconData? icon;
                              if (isActuallyCorrect) {
                                textColor = Colors.green.shade700;
                                icon = Icons.check_circle;
                              } else if (wasSelected && !isActuallyCorrect) {
                                textColor = Colors.red.shade700;
                                icon = Icons.cancel;
                              }

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Icon(icon ?? Icons.circle_outlined, size: 16, color: textColor ?? Colors.grey),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: LatexText(
                                        opt.toString(),
                                        style: TextStyle(
                                          color: textColor,
                                          fontWeight: (wasSelected || isActuallyCorrect) ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
