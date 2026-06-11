import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
    _refresh();
  }

  void _refresh() {
    setState(() {
      _detailsFuture = _fetchDetails();
    });
  }

  Future<List<Map<String, dynamic>>> _fetchDetails() async {
    final db = DatabaseService();
    final rawDetails = await db.getHistoryDetails(widget.historyItem['id']);
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
          'question_data': qData,
          'question_text': decryptedText,
          'options': decryptedOptions,
          'correct_answers': decryptedCorrect,
          'user_answers': jsonDecode(detail['user_answers']),
        });
      }
    }
    return enrichedDetails;
  }

  Future<void> _exportToPdf(List<Map<String, dynamic>> details) async {
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, child: pw.Text("Quiz Review: ${widget.historyItem['class_name']}")),
          pw.Paragraph(text: "Score: ${widget.historyItem['score']} / ${widget.historyItem['total_questions']}"),
          pw.Paragraph(text: "Time Taken: ${widget.historyItem['time_taken_seconds']}s"),
          pw.Paragraph(text: "Date: ${widget.historyItem['date_taken']}"),
          pw.SizedBox(height: 20),
          ...details.map((d) {
            final bool isCorrect = d['is_correct'] == 1;
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("${isCorrect ? '[CORRECT]' : '[WRONG]'} ${d['question_text']}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Bullet(text: "Your Answer: ${d['user_answers'].join(', ')}"),
                pw.Bullet(text: "Correct Answer: ${d['correct_answers'].join(', ')}"),
                pw.SizedBox(height: 10),
              ],
            );
          }),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  void _showEditDialog(Map<String, dynamic> detail) {
    final qData = detail['question_data'];
    final textController = TextEditingController(text: detail['question_text']);
    final List<TextEditingController> optionControllers = [];
    final List<bool> isCorrectList = [];

    final List<dynamic> options = detail['options'];
    final List<dynamic> correctAnswers = detail['correct_answers'];
    for (var opt in options) {
      optionControllers.add(TextEditingController(text: opt.toString()));
      isCorrectList.add(correctAnswers.contains(opt.toString()));
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Question (from History)'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: textController,
                    decoration: const InputDecoration(labelText: 'Question Text', border: OutlineInputBorder()),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Options:', style: TextStyle(fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            optionControllers.add(TextEditingController());
                            isCorrectList.add(false);
                          });
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  ...List.generate(optionControllers.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          Checkbox(
                            value: isCorrectList[index],
                            onChanged: (val) {
                              setState(() {
                                isCorrectList[index] = val!;
                              });
                            },
                          ),
                          Expanded(
                            child: TextField(
                              controller: optionControllers[index],
                              decoration: InputDecoration(
                                labelText: 'Option ${index + 1}',
                                suffixIcon: optionControllers.length > 2
                                    ? IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                        onPressed: () {
                                          setState(() {
                                            optionControllers.removeAt(index);
                                            isCorrectList.removeAt(index);
                                          });
                                        },
                                      )
                                    : null,
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
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final text = textController.text.trim();
                final opts = optionControllers.map((c) => c.text.trim()).toList();
                final List<String> selectedAnswers = [];
                for (int i = 0; i < opts.length; i++) {
                  if (isCorrectList[i]) selectedAnswers.add(opts[i]);
                }

                if (text.isEmpty || opts.any((o) => o.isEmpty) || selectedAnswers.isEmpty) return;

                try {
                  await context.read<QuizProvider>().updateQuestion(qData['id'], text, opts, selectedAnswers);
                  if (mounted) {
                    Navigator.pop(context);
                    _refresh();
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: const Text('Save Fix'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.historyItem['score'];
    final total = widget.historyItem['total_questions'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz Review'),
        actions: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _detailsFuture,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return IconButton(
                  onPressed: () => _exportToPdf(snapshot.data!),
                  icon: const Icon(Icons.picture_as_pdf),
                  tooltip: 'Export to PDF',
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
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
                            }).toList(),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _showEditDialog(d),
                                  icon: const Icon(Icons.edit_note, color: Colors.orange),
                                  label: const Text('Fix Question Error', style: TextStyle(color: Colors.orange)),
                                ),
                              ],
                            ),
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
