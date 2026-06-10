import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';
import '../widgets/latex_text.dart';
import 'package:intl/intl.dart';

class ContentManagementScreen extends StatefulWidget {
  final int classId;
  final String className;

  const ContentManagementScreen({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<ContentManagementScreen> createState() => _ContentManagementScreenState();
}

class _ContentManagementScreenState extends State<ContentManagementScreen> {
  late Future<List<Map<String, dynamic>>> _questionsFuture;

  @override
  void initState() {
    super.initState();
    _refreshQuestions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<QuizProvider>().loadClassFiles(widget.classId);
    });
  }

  void _refreshQuestions() {
    setState(() {
      _questionsFuture = context.read<QuizProvider>().getQuestions(widget.classId, -1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Manage ${widget.className}'),
          actions: [
            IconButton(
              icon: const Icon(Icons.key),
              onPressed: () => _showAnswerKeyDialog(),
              tooltip: 'Answer Key',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.question_answer), text: 'Questions'),
              Tab(icon: Icon(Icons.picture_as_pdf), text: 'Files'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildQuestionsTab(),
            _buildFilesTab(),
          ],
        ),
        floatingActionButton: Builder(
          builder: (context) {
            final tabController = DefaultTabController.of(context);
            return AnimatedBuilder(
              animation: tabController,
              builder: (context, child) {
                return tabController.index == 0
                    ? FloatingActionButton.extended(
                        onPressed: () => _showEditQuestionDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Question'),
                      )
                    : const SizedBox.shrink();
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildQuestionsTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _questionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final questions = snapshot.data ?? [];

        if (questions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.question_mark, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No questions found.', style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: questions.length,
          itemBuilder: (context, index) {
            final q = questions[index];
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ExpansionTile(
                title: LatexText(
                  q['question_text'],
                ),
                subtitle: Text('Answers: ${(q['correct_answers'] as List).join(', ')}'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Options:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ...(q['options'] as List<dynamic>).map((opt) {
                          final bool isCorrect = (q['correct_answers'] as List).contains(opt.toString());
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Icon(
                                  isCorrect ? Icons.check_circle : Icons.circle_outlined,
                                  size: 16,
                                  color: isCorrect ? Colors.green : Colors.grey,
                                ),
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
                              onPressed: () => _showEditQuestionDialog(question: q),
                              icon: const Icon(Icons.edit),
                              label: const Text('Edit'),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () => _confirmDeleteQuestion(q['id']),
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
        );
      },
    );
  }

  Widget _buildFilesTab() {
    return Consumer<QuizProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final files = provider.classFiles;

        if (files.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.file_copy_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No PDFs uploaded yet.', style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: files.length,
          itemBuilder: (context, index) {
            final file = files[index];
            final DateTime uploadedAt = DateTime.parse(file['created_at']);
            return Card(
              child: ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: Text(file['filename']),
                subtitle: Text('Uploaded on ${DateFormat('MMM d, yyyy HH:mm').format(uploadedAt)}'),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditQuestionDialog({Map<String, dynamic>? question}) {
    final bool isEditing = question != null;
    final textController = TextEditingController(text: question?['question_text'] ?? '');
    
    // Dynamic options
    final List<TextEditingController> optionControllers = [];
    final List<bool> isCorrectList = [];

    if (isEditing) {
      final List<dynamic> options = question['options'];
      final List<dynamic> correctAnswers = question['correct_answers'];
      for (var opt in options) {
        optionControllers.add(TextEditingController(text: opt.toString()));
        isCorrectList.add(correctAnswers.contains(opt.toString()));
      }
    } else {
      // Default 4 options for new question
      for (int i = 0; i < 4; i++) {
        optionControllers.add(TextEditingController());
        isCorrectList.add(false);
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isEditing ? 'Edit Question' : 'Add Question'),
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
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final text = textController.text.trim();
                final options = optionControllers.map((c) => c.text.trim()).toList();
                final List<String> selectedAnswers = [];
                for (int i = 0; i < options.length; i++) {
                  if (isCorrectList[i]) selectedAnswers.add(options[i]);
                }
                
                if (text.isEmpty || options.any((o) => o.isEmpty) || selectedAnswers.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all fields and select at least one correct answer')),
                  );
                  return;
                }

                final provider = context.read<QuizProvider>();
                try {
                  if (isEditing) {
                    await provider.updateQuestion(question['id'], text, options, selectedAnswers);
                  } else {
                    await provider.addManualQuestion(widget.classId, text, options, selectedAnswers);
                  }
                  if (mounted) {
                    Navigator.pop(context);
                    _refreshQuestions();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: Text(isEditing ? 'Update' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteQuestion(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Question'),
        content: const Text('Are you sure you want to delete this question?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await context.read<QuizProvider>().deleteQuestion(id);
                if (mounted) {
                  Navigator.pop(context);
                  _refreshQuestions();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAnswerKeyDialog() async {
    final questions = await context.read<QuizProvider>().getQuestions(widget.classId, -1);
    
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${widget.className} - Answer Key'),
        content: SizedBox(
          width: double.maxFinite,
          child: questions.isEmpty
              ? const Text('No questions found.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: questions.length,
                  itemBuilder: (context, index) {
                    final q = questions[index];
                    return ListTile(
                      leading: CircleAvatar(child: Text('${index + 1}')),
                      title: LatexText(q['question_text']),
                      subtitle: Text(
                        'Correct Answers: ${(q['correct_answers'] as List).join(', ')}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
