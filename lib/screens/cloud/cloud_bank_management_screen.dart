import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/cloud_provider.dart';
import '../../widgets/latex_text.dart';

class CloudBankManagementScreen extends StatefulWidget {
  final String bankId;
  final String bankName;

  const CloudBankManagementScreen({
    super.key,
    required this.bankId,
    required this.bankName,
  });

  @override
  State<CloudBankManagementScreen> createState() => _CloudBankManagementScreenState();
}

class _CloudBankManagementScreenState extends State<CloudBankManagementScreen> {
  late Future<List<Map<String, dynamic>>> _questionsFuture;
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
      _questionsFuture = context.read<CloudProvider>().getCloudQuestions(widget.bankId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit ${widget.bankName}'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _questionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));

          final allQuestions = snapshot.data ?? [];
          final questions = allQuestions.where((q) {
            final text = (q['question_text'] ?? '').toString().toLowerCase();
            return text.contains(_searchQuery);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search cloud questions...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                ),
              ),
              Expanded(
                child: questions.isEmpty
                  ? const Center(child: Text('No matching questions found.'))
                  : ListView.builder(
                      itemCount: questions.length,
                      padding: const EdgeInsets.all(8),
                      itemBuilder: (context, index) {
                        final q = questions[index];
                        final List<dynamic> options = q['options'] ?? [];
                        final List<dynamic> correct = q['correct_answers'] ?? [];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ExpansionTile(
                            title: LatexText(q['question_text'] ?? ''),
                            subtitle: Text('Answers: ${correct.join(', ')}'),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Options:', style: TextStyle(fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    ...options.map((opt) {
                                      bool isCorrect = correct.contains(opt);
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Row(
                                          children: [
                                            Icon(isCorrect ? Icons.check_circle : Icons.circle_outlined, 
                                                 size: 16, color: isCorrect ? Colors.green : Colors.grey),
                                            const SizedBox(width: 8),
                                            Expanded(child: LatexText(opt.toString())),
                                          ],
                                        ),
                                      );
                                    }),
                                    const Divider(height: 24),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () => _showEditDialog(q),
                                          icon: const Icon(Icons.edit),
                                          label: const Text('Edit'),
                                        ),
                                        const SizedBox(width: 8),
                                        TextButton.icon(
                                          onPressed: () => _confirmDelete(q['id']),
                                          icon: const Icon(Icons.delete, color: Colors.red),
                                          label: const Text('Delete', style: TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
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

  void _showEditDialog(Map<String, dynamic> question) {
    final textController = TextEditingController(text: question['question_text']);
    final List<TextEditingController> optionControllers = [];
    final List<bool> isCorrectList = [];

    final List<dynamic> options = question['options'];
    final List<dynamic> correctAnswers = question['correct_answers'] ?? [];
    
    for (var opt in options) {
      optionControllers.add(TextEditingController(text: opt.toString()));
      isCorrectList.add(correctAnswers.contains(opt.toString()));
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Cloud Question'),
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
                          setDialogState(() {
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
                            onChanged: (val) => setDialogState(() => isCorrectList[index] = val!),
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
                                          setDialogState(() {
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
                  await context.read<CloudProvider>().updateCloudQuestion(widget.bankId, question['id'], {
                    'question_text': text,
                    'options': opts,
                    'correct_answers': selectedAnswers,
                  });
                  if (mounted) {
                    Navigator.pop(context);
                    _refresh();
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(String questionId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Cloud Question?'),
        content: const Text('This action cannot be undone and will remove the question from the cloud store.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await context.read<CloudProvider>().deleteCloudQuestion(widget.bankId, questionId);
              if (mounted) {
                Navigator.pop(context);
                _refresh();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
