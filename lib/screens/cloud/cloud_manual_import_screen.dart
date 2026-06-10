import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/cloud_provider.dart';

class CloudManualImportScreen extends StatefulWidget {
  final String bankId;
  final String bankName;

  const CloudManualImportScreen({super.key, required this.bankId, required this.bankName});

  @override
  State<CloudManualImportScreen> createState() => _CloudManualImportScreenState();
}

class _CloudManualImportScreenState extends State<CloudManualImportScreen> {
  final TextEditingController _jsonController = TextEditingController();
  bool _isUploading = false;

  Future<void> _pickJsonFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null) {
      if (result.files.single.bytes != null) {
        setState(() {
          _jsonController.text = utf8.decode(result.files.single.bytes!);
        });
      } else if (result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        setState(() {
          _jsonController.text = content;
        });
      }
    }
  }

  Future<void> _import() async {
    final text = _jsonController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isUploading = true);

    try {
      String cleanedJson = text;
      if (cleanedJson.contains('```')) {
        final start = cleanedJson.indexOf('[');
        final end = cleanedJson.lastIndexOf(']');
        if (start != -1 && end != -1 && end > start) {
          cleanedJson = cleanedJson.substring(start, end + 1);
        }
      }

      final dynamic decoded = jsonDecode(cleanedJson);
      if (decoded is! List) throw Exception('JSON must be an array of objects.');
      
      final List<Map<String, dynamic>> questions = decoded.map((e) => e as Map<String, dynamic>).toList();
      
      // Basic validation
      for (var q in questions) {
        if (!q.containsKey('question_text') || !q.containsKey('options')) {
          throw Exception('Invalid format. Needs question_text and options.');
        }
        // Handle backward compatibility for single correct_answer
        if (!q.containsKey('correct_answers') && !q.containsKey('correct_answer')) {
          throw Exception('Each question needs correct_answers (list).');
        }
      }

      await context.read<CloudProvider>().uploadQuestionsToCloud(widget.bankId, questions);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Successfully imported to cloud!')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Import to ${widget.bankName}')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Paste Question JSON Array',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'Format: [{"question_text": "...", "options": ["A", "B"], "correct_answers": ["A"]}]',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _jsonController,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter JSON here...',
                  fillColor: Color(0xFFF5F5F5),
                  filled: true,
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isUploading ? null : _pickJsonFile,
                    icon: const Icon(Icons.file_upload),
                    label: const Text('Pick JSON File'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isUploading ? null : _import,
                    icon: const Icon(Icons.cloud_done),
                    label: Text(_isUploading ? 'Uploading...' : 'Upload to Cloud'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
