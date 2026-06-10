import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';
import '../widgets/latex_text.dart';

class ManualImportScreen extends StatefulWidget {
  final int classId;
  final String className;

  const ManualImportScreen({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<ManualImportScreen> createState() => _ManualImportScreenState();
}

class _ManualImportScreenState extends State<ManualImportScreen> {
  final TextEditingController _jsonController = TextEditingController();
  bool _isValidating = false;

  final String aiPrompt = r'''
Extract all multiple-choice questions from the content. 
STRICT JSON REQUIREMENTS:
1. Return ONLY a valid JSON array of objects.
2. Inside strings, you MUST escape every double quote symbol (") as \" to prevent breaking the JSON format.
3. For LaTeX math symbols, wrap them in single dollar signs (e.g. $x^2$).
4. 'question_text': The text of the question.
5. 'options': A list of all possible answers.
6. 'correct_answers': A list of all correct answer strings exactly as they appear in 'options'.

Example format:
[
  {
    "question_text": "Which of these are \"prime\" numbers?",
    "options": ["1", "2", "3", "4"],
    "correct_answers": ["2", "3"]
  }
]
''';

  void _copyPrompt() {
    Clipboard.setData(ClipboardData(text: aiPrompt));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Prompt copied to clipboard')),
    );
  }

  Future<void> _importQuestions() async {
    final input = _jsonController.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste the JSON output first')),
      );
      return;
    }

    setState(() {
      _isValidating = true;
    });

    try {
      // Basic JSON validation
      String cleanedJson = input;
      if (cleanedJson.contains('```')) {
        final start = cleanedJson.indexOf('[');
        final end = cleanedJson.lastIndexOf(']');
        if (start != -1 && end != -1 && end > start) {
          cleanedJson = cleanedJson.substring(start, end + 1);
        }
      }

      final decoded = jsonDecode(cleanedJson);
      if (decoded is! List) {
        throw Exception('JSON must be an array of question objects.');
      }

      final questions = decoded.map((e) => e as Map<String, dynamic>).toList();
      
      // Validate structure of each question
      for (var q in questions) {
        bool hasCorrect = q.containsKey('correct_answers') || q.containsKey('correct_answer');
        if (!q.containsKey('question_text') ||
            !q.containsKey('options') ||
            !hasCorrect) {
          throw Exception('Each question must have question_text, options, and correct_answers.');
        }
        if (q['options'] is! List) {
          throw Exception('Options must be a list of strings.');
        }
      }

      final provider = Provider.of<QuizProvider>(context, listen: false);
      await provider.importManualQuestions(widget.classId, questions);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully imported ${questions.length} questions')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error validating JSON: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isValidating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Manual Import: ${widget.className}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'AI Prompt',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: _copyPrompt,
                          tooltip: 'Copy Prompt',
                        ),
                      ],
                    ),
                    const Text(
                      'Copy this prompt to use with ChatGPT, Claude, or another AI to generate the correct JSON format.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const Divider(),
                    LatexText(
                      aiPrompt,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Paste JSON Output',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _jsonController,
              maxLines: 15,
              decoration: const InputDecoration(
                hintText: '[{"question_text": "...", "options": [...], "correct_answer": "..."}]',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isValidating ? null : _importQuestions,
              icon: _isValidating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download),
              label: const Text('Import Questions'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
