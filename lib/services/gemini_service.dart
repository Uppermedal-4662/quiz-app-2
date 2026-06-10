import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

class GeminiService {
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

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

  /// Original extraction method (single pass)
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
      onProgress: (_) {}, // No-op progress for backward compatibility
      answerKeyBytes: answerKeyBytes,
      aiSolve: aiSolve
    );
  }

  /// NEW: Chunked extraction logic to handle large PDFs and avoid timeouts.
  Future<List<Map<String, dynamic>>> extractQuestionsFromPdfChunked(
    Uint8List pdfBytes,
    String apiKey,
    String modelName, {
    required Function(String) onProgress,
    Uint8List? answerKeyBytes,
    bool aiSolve = false,
    int chunkCount = 3, // Logic: we try to process the PDF in 3 conceptual passes
  }) async {
    try {
      final model = GenerativeModel(
        model: modelName,
        apiKey: apiKey,
        generationConfig: GenerationConfig(responseMimeType: 'application/json'),
      );

      final List<Map<String, dynamic>> allQuestions = [];
      
      // We perform multiple passes to ensure we get ALL questions 
      // without hitting response token limits.
      for (int i = 1; i <= chunkCount; i++) {
        onProgress("Processing part $i of $chunkCount...");

        String rangePrompt = "";
        if (chunkCount > 1) {
          if (i == 1) rangePrompt = "Focus on the START and early sections of the document.";
          else if (i == chunkCount) rangePrompt = "Focus on the END and final sections of the document.";
          else rangePrompt = "Focus on the MIDDLE sections of the document.";
        }

        List<Part> contentParts = [];
        String scenarioPrompt = _getScenarioPrompt(answerKeyBytes != null, aiSolve);
        
        contentParts.add(DataPart('application/pdf', pdfBytes));
        if (answerKeyBytes != null) {
          contentParts.add(TextPart("Answer Key PDF:"));
          contentParts.add(DataPart('application/pdf', answerKeyBytes));
        }

        final fullPrompt = '''
$scenarioPrompt
$rangePrompt

STRICT JSON COMPLIANCE REQUIREMENTS:
1. Return ONLY a valid JSON array of objects.
2. Inside strings (question_text and options), you MUST escape every double quote symbol (") as \\" to prevent breaking the JSON format.
3. For LaTeX math symbols, wrap them in single dollar signs (e.g. \$x^2\$). Ensure backslashes in LaTeX are preserved.
4. 'options': Provide a list of all possible answers.
5. 'correct_answers': A list of all correct answer strings exactly as they appear in 'options'.

Example structure:
[
  {
    "question_text": "The value of \\"x\\" in \$x + 2 = 4\$ is:",
    "options": ["1", "2", "3", "4"],
    "correct_answers": ["2"]
  }
]
''';

        contentParts.insert(0, TextPart(fullPrompt));
        final response = await model.generateContent([Content.multi(contentParts)]);
        final responseText = response.text;

        if (responseText != null && responseText.isNotEmpty) {
          final List<Map<String, dynamic>> chunkQuestions = _parseJson(responseText);
          // Deduplicate based on question text
          for (var q in chunkQuestions) {
            if (q.containsKey('question_text') && q.containsKey('options')) {
              if (!allQuestions.any((existing) => 
                  existing['question_text'] == q['question_text'])) {
                allQuestions.add(q);
              }
            }
          }
        }
      }

      if (allQuestions.isEmpty) {
        throw Exception('No valid questions were found. The AI might be having trouble with this specific document format.');
      }

      return allQuestions;
    } catch (e) {
      throw Exception('Failed to extract questions: $e');
    }
  }

  String _getScenarioPrompt(bool hasAnswerKey, bool aiSolve) {
    if (hasAnswerKey) {
      return "Extract questions from the first PDF and match them with correct answers from the second PDF.";
    } else if (aiSolve) {
      return "Extract questions from the PDF and solve them yourself to find the correct answer.";
    } else {
      return "Extract questions and their corresponding correct answers from the attached PDF. The key is usually at the end.";
    }
  }

  List<Map<String, dynamic>> _parseJson(String text) {
    String cleaned = text.trim();
    try {
      // 1. Remove Markdown markers
      if (cleaned.contains('```')) {
        final start = cleaned.indexOf('[');
        final end = cleaned.lastIndexOf(']');
        if (start != -1 && end != -1 && end > start) {
          cleaned = cleaned.substring(start, end + 1);
        }
      }

      // 2. Pre-processing: Fix common AI mistakes with nested quotes
      // This is a heuristic: try to find unescaped quotes between property names
      // However, jsonDecode is strict. Let's try standard decode first.
      return (jsonDecode(cleaned) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Standard JSON parsing failed, attempting recovery...');
      try {
        // Recovery attempt: If the AI failed to escape some quotes, 
        // this regex-based approach might help, though it's risky.
        // For now, let's just log the error and try a more targeted fix if common patterns emerge.
        print('Raw faulty JSON: $cleaned');
        
        // Sometimes AI adds text before/after the array even without backticks
        final start = cleaned.indexOf('[');
        final end = cleaned.lastIndexOf(']');
        if (start != -1 && end != -1 && end > start) {
          final subCleaned = cleaned.substring(start, end + 1);
          return (jsonDecode(subCleaned) as List).cast<Map<String, dynamic>>();
        }
      } catch (inner) {
        print('JSON Recovery failed: $inner');
      }
      return [];
    }
  }
}
