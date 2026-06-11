import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

class GeminiService {
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  // Robust Model Rotation List
  static const List<String> _modelRotation = [
    'gemini-1.5-flash',
    'gemini-1.5-pro',
    'gemini-1.0-pro',
  ];

  Future<List<String>> listAvailableModels(String apiKey) async {
    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> models = data['models'] ?? [];
        return models
            .where((model) {
              final List<dynamic> methods = model['supportedGenerationMethods'] ?? [];
              return methods.contains('generateContent');
            })
            .map((model) => model['name'] as String)
            .toList();
      } else {
        throw Exception('Failed to list models');
      }
    } catch (e) {
      throw Exception('Error fetching models: $e');
    }
  }

  /// NEW: Robust extraction with auto-model switching and per-section processing
  Future<List<Map<String, dynamic>>> extractQuestionsFromPdfChunked(
    Uint8List pdfBytes,
    String apiKey,
    String modelName, {
    required Function(String) onProgress,
    Uint8List? answerKeyBytes,
    bool aiSolve = false,
  }) async {
    final List<Map<String, dynamic>> allQuestions = [];
    
    // We break the process into 5 granular sections for better reliability (simulating per-page)
    const int sections = 5;
    
    for (int i = 1; i <= sections; i++) {
      int retryCount = 0;
      bool success = false;
      String currentModel = modelName;

      while (retryCount < 5 && !success) {
        try {
          onProgress("Processing Section $i of $sections (Attempt ${retryCount + 1})...");
          
          final model = GenerativeModel(
            model: currentModel,
            apiKey: apiKey,
            generationConfig: GenerationConfig(responseMimeType: 'application/json'),
          );

          String sectionContext = _getSectionPrompt(i, sections);
          String scenarioPrompt = _getScenarioPrompt(answerKeyBytes != null, aiSolve);

          List<Part> contentParts = [
            DataPart('application/pdf', pdfBytes),
          ];

          if (answerKeyBytes != null) {
            contentParts.add(TextPart("Answer Key Document:"));
            contentParts.add(DataPart('application/pdf', answerKeyBytes));
          }

          final fullPrompt = '''
$scenarioPrompt
$sectionContext

STRICT JSON COMPLIANCE:
1. Return ONLY a valid JSON array of objects.
2. Escape double quotes (") as \\" inside text.
3. Use LaTeX for math (wrap in \$).
4. 'question_text', 'options' (list), 'correct_answers' (list).

Return ONLY the array.
''';

          contentParts.insert(0, TextPart(fullPrompt));
          final response = await model.generateContent([Content.multi(contentParts)]);
          final responseText = response.text;

          if (responseText != null && responseText.isNotEmpty) {
            final List<Map<String, dynamic>> chunkQuestions = _parseJson(responseText);
            
            // Deduplicate and merge
            for (var q in chunkQuestions) {
              if (q.containsKey('question_text') && q.containsKey('options')) {
                if (!allQuestions.any((existing) => 
                    existing['question_text'].trim().toLowerCase() == q['question_text'].trim().toLowerCase())) {
                  allQuestions.add(q);
                }
              }
            }
            success = true;
          } else {
            throw Exception("Empty response from AI");
          }
        } catch (e) {
          retryCount++;
          if (retryCount < 5) {
            // AUTO MODEL SWITCHING
            // If flash fails, try pro, etc.
            int nextModelIndex = (retryCount) % _modelRotation.length;
            currentModel = _modelRotation[nextModelIndex];
            onProgress("Demand spike or error detected. Switching to $currentModel...");
            await Future.delayed(Duration(seconds: 2 * retryCount)); // Exponential backoff
          } else {
            onProgress("Critical: AI services are currently overwhelmed. Showing partial results.");
          }
        }
      }
    }

    if (allQuestions.isEmpty) {
      throw Exception('Failed to extract questions after 5 attempts. The model might be under high demand.');
    }

    return allQuestions;
  }

  String _getSectionPrompt(int index, int total) {
    if (total == 1) return "Extract ALL questions from the document.";
    
    double startPct = ((index - 1) / total) * 100;
    double endPct = (index / total) * 100;
    
    return "Focus your extraction strictly on the content located between ${startPct.toInt()}% and ${endPct.toInt()}% of the document's total length. Ensure you do not skip questions in this specific range.";
  }

  String _getScenarioPrompt(bool hasAnswerKey, bool aiSolve) {
    if (hasAnswerKey) {
      return "Extract questions from the first document and find their correct answers in the second Answer Key document.";
    } else if (aiSolve) {
      return "Extract questions from the document and solve them using your internal knowledge to determine the correct answers.";
    } else {
      return "Extract questions and their corresponding correct answers provided within the document itself.";
    }
  }

  List<Map<String, dynamic>> _parseJson(String text) {
    String cleaned = text.trim();
    try {
      if (cleaned.contains('```')) {
        final start = cleaned.indexOf('[');
        final end = cleaned.lastIndexOf(']');
        if (start != -1 && end != -1 && end > start) {
          cleaned = cleaned.substring(start, end + 1);
        }
      }
      return (jsonDecode(cleaned) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      // Recovery logic
      final start = cleaned.indexOf('[');
      final end = cleaned.lastIndexOf(']');
      if (start != -1 && end != -1 && end > start) {
        try {
          return (jsonDecode(cleaned.substring(start, end + 1)) as List).cast<Map<String, dynamic>>();
        } catch (_) {}
      }
      return [];
    }
  }

  /// Backward compatibility
  Future<List<Map<String, dynamic>>> extractQuestionsFromPdf(
    Uint8List pdfBytes,
    String apiKey,
    String modelName, {
    Uint8List? answerKeyBytes,
    bool aiSolve = false,
  }) async {
    return await extractQuestionsFromPdfChunked(
      pdfBytes, 
      apiKey, 
      modelName, 
      onProgress: (_) {},
      answerKeyBytes: answerKeyBytes,
      aiSolve: aiSolve
    );
  }
}
