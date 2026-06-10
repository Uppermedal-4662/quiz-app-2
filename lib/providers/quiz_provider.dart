import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/gemini_service.dart';
import '../services/security_service.dart';

enum TimerMode { none, perQuestion, perQuiz, speedRun }

class QuizProvider with ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();
  final GeminiService _geminiService = GeminiService();
  final SecurityService _securityService = SecurityService();

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _classFiles = [];
  bool _isLoading = false;
  String _loadingStatus = "";
  String? _apiKey;
  String _modelName = 'gemini-1.5-flash';
  List<String> _availableModels = [];

  // Quiz Engine State
  List<Map<String, dynamic>> _currentQuestions = [];
  int _currentIndex = 0;
  int _score = 0;
  Timer? _quizTimer;
  int _secondsRemaining = 0;
  int _originalLimit = 0; 
  TimerMode _timerMode = TimerMode.none;
  bool _isQuizActive = false;
  bool _isAnswered = false;
  List<String> _userSelection = [];
  int _totalTimeSpent = 0;
  List<Map<String, dynamic>> _quizResults = []; 
  int _activeClassId = 0;

  List<Map<String, dynamic>> get classes => _classes;
  List<Map<String, dynamic>> get classFiles => _classFiles;
  bool get isLoading => _isLoading;
  String get loadingStatus => _loadingStatus;
  String? get apiKey => _apiKey;
  String get modelName => _modelName;
  List<String> get availableModels => _availableModels;

  // Quiz Getters
  List<Map<String, dynamic>> get currentQuestions => _currentQuestions;
  int get currentIndex => _currentIndex;
  int get score => _score;
  int get secondsRemaining => _secondsRemaining;
  TimerMode get timerMode => _timerMode;
  bool get isQuizActive => _isQuizActive;
  bool get isAnswered => _isAnswered;
  List<String> get userSelection => _userSelection;

  Future<void> loadApiKey() async {
    _apiKey = await _securityService.getApiKey();
    _modelName = await _securityService.getModelName();
    if (_apiKey != null && _apiKey!.isNotEmpty) {
      await fetchAvailableModels();
    }
    notifyListeners();
  }

  Future<void> fetchAvailableModels() async {
    if (_apiKey == null || _apiKey!.isEmpty) return;
    try {
      final models = await _geminiService.listAvailableModels(_apiKey!);
      _availableModels = models;
      if (_availableModels.isNotEmpty && !_availableModels.contains(_modelName)) {
        if (_availableModels.contains('gemini-1.5-flash')) {
          _modelName = 'gemini-1.5-flash';
        } else {
          _modelName = _availableModels.first;
        }
        await _securityService.saveModelName(_modelName);
      }
    } catch (e) {
      debugPrint('Error fetching available models: $e');
    }
    notifyListeners();
  }

  Future<void> saveApiKey(String key) async {
    await _securityService.saveApiKey(key);
    _apiKey = key;
    await fetchAvailableModels();
    notifyListeners();
  }

  Future<void> saveModelName(String model) async {
    await _securityService.saveModelName(model);
    _modelName = model;
    notifyListeners();
  }

  Future<void> loadClasses() async {
    _isLoading = true;
    notifyListeners();
    try {
      _classes = await _databaseService.getClasses();
    } catch (e) {
      debugPrint('Error loading classes: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addClass(String name) async {
    try {
      await _databaseService.createClass(name);
      await loadClasses();
    } catch (e) {
      debugPrint('Error adding class: $e');
    }
  }

  Future<void> removeClass(int id) async {
    try {
      await _databaseService.deleteClass(id);
      await loadClasses();
    } catch (e) {
      debugPrint('Error removing class: $e');
    }
  }

  Future<void> loadClassFiles(int classId) async {
    try {
      _classFiles = await _databaseService.getFilesByClass(classId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading class files: $e');
    }
  }

  Future<List<Map<String, dynamic>>> geminiExtractQuestions(Uint8List pdfBytes, {Function(String)? onProgress}) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API Key is not set.');
    }
    return await _geminiService.extractQuestionsFromPdfChunked(
      pdfBytes, 
      _apiKey!, 
      _modelName,
      onProgress: onProgress ?? (_) {},
    );
  }

  Future<void> uploadPdf(int classId, Uint8List pdfBytes, String filename) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API Key is not set.');
    }
    _isLoading = true;
    _loadingStatus = "Starting extraction...";
    notifyListeners();
    try {
      final questions = await _geminiService.extractQuestionsFromPdfChunked(
        pdfBytes, 
        _apiKey!, 
        _modelName,
        onProgress: (status) {
          _loadingStatus = status;
          notifyListeners();
        }
      );
      _loadingStatus = "Saving questions locally...";
      notifyListeners();
      await _processAndSaveQuestions(classId, questions);
      await _databaseService.addFile(classId, filename);
      await loadClassFiles(classId);
    } catch (e) {
      debugPrint('Error uploading PDF and processing questions: $e');
      rethrow;
    } finally {
      _isLoading = false;
      _loadingStatus = "";
      notifyListeners();
    }
  }

  Future<void> updateQuestion(int questionId, String text, List<String> options, List<String> correctAnswers) async {
    try {
      final encryptedText = _securityService.encryptData(text);
      final encryptedOptions = jsonEncode(options.map((opt) => _securityService.encryptData(opt)).toList());
      final encryptedCorrectAnswers = jsonEncode(correctAnswers.map((ans) => _securityService.encryptData(ans)).toList());

      await _databaseService.updateQuestion(questionId, {
        'question_text': encryptedText,
        'options': encryptedOptions,
        'correct_answers': encryptedCorrectAnswers,
      });
    } catch (e) {
      debugPrint('Error updating question: $e');
      rethrow;
    }
  }

  Future<void> deleteQuestion(int questionId) async {
    try {
      await _databaseService.deleteQuestion(questionId);
    } catch (e) {
      debugPrint('Error deleting question: $e');
      rethrow;
    }
  }

  Future<void> addManualQuestion(int classId, String text, List<String> options, List<String> correctAnswers) async {
    try {
      final encryptedText = _securityService.encryptData(text);
      final encryptedOptions = jsonEncode(options.map((opt) => _securityService.encryptData(opt)).toList());
      final encryptedCorrectAnswers = jsonEncode(correctAnswers.map((ans) => _securityService.encryptData(ans)).toList());

      await _databaseService.addSingleQuestion(classId, {
        'question_text': encryptedText,
        'options': encryptedOptions,
        'correct_answers': encryptedCorrectAnswers,
      });
    } catch (e) {
      debugPrint('Error adding manual question: $e');
      rethrow;
    }
  }

  Future<void> importManualQuestions(int classId, List<Map<String, dynamic>> questions) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _processAndSaveQuestions(classId, questions);
    } catch (e) {
      debugPrint('Error importing manual questions: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _processAndSaveQuestions(int classId, List<Map<String, dynamic>> questions) async {
    final encryptedQuestions = questions.map((q) {
      final String questionText = q['question_text'] as String;
      final List<dynamic> options = q['options'] as List<dynamic>;
      
      List<String> correctAnswersList = [];
      if (q.containsKey('correct_answers')) {
        correctAnswersList = List<String>.from(q['correct_answers']);
      } else if (q.containsKey('correct_answer')) {
        correctAnswersList = [q['correct_answer'].toString()];
      }

      final String encryptedQuestionText = _securityService.encryptData(questionText);
      final String encryptedOptionsJson = jsonEncode(options.map((opt) => _securityService.encryptData(opt.toString())).toList());
      final String encryptedCorrectAnswersJson = jsonEncode(correctAnswersList.map((ans) => _securityService.encryptData(ans)).toList());

      return {
        'question_text': encryptedQuestionText,
        'options': encryptedOptionsJson,
        'correct_answers': encryptedCorrectAnswersJson,
      };
    }).toList();

    await _databaseService.insertQuestions(classId, encryptedQuestions);
  }

  Future<List<Map<String, dynamic>>> getQuestions(int classId, int count, {bool randomize = true}) async {
    try {
      final encryptedQuestions = await _databaseService.getQuestionsByClass(classId);
      List<Map<String, dynamic>> list = List<Map<String, dynamic>>.from(encryptedQuestions);
      if (randomize) list.shuffle();
      final selection = (count == -1 || count > list.length) ? list : list.take(count).toList();

      return selection.map((q) {
        final decryptedText = _securityService.decryptData(q['question_text']);
        final List<dynamic> encryptedOptions = jsonDecode(q['options']);
        final decryptedOptions = encryptedOptions.map((opt) => _securityService.decryptData(opt.toString())).toList();
        List<String> decryptedCorrectAnswers = [];
        if (q['correct_answers'] != null) {
          final List<dynamic> encryptedCorrect = jsonDecode(q['correct_answers']);
          decryptedCorrectAnswers = encryptedCorrect.map((ans) => _securityService.decryptData(ans.toString())).toList();
        } else if (q['correct_answer'] != null) {
          decryptedCorrectAnswers = [_securityService.decryptData(q['correct_answer'])];
        }
        return {
          'id': q['id'],
          'class_id': q['class_id'],
          'question_text': decryptedText,
          'options': decryptedOptions,
          'correct_answers': decryptedCorrectAnswers,
        };
      }).toList();
    } catch (e) {
      debugPrint('Error fetching/decrypting questions: $e');
      return [];
    }
  }

  // Quiz Engine Implementation
  void startQuiz({
    required int classId,
    required List<Map<String, dynamic>> questions,
    required TimerMode mode,
    required int timeLimitSeconds,
  }) {
    _activeClassId = classId;
    _currentQuestions = questions;
    _currentIndex = 0;
    _score = 0;
    _timerMode = mode;
    _secondsRemaining = timeLimitSeconds;
    _originalLimit = timeLimitSeconds;
    _isQuizActive = true;
    _isAnswered = false;
    _userSelection = [];
    _totalTimeSpent = 0;
    _quizResults = [];
    _startTimer();
    notifyListeners();
  }

  void _startTimer() {
    _quizTimer?.cancel();
    if (_timerMode == TimerMode.none) return;
    _quizTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _totalTimeSpent++;
      if (_secondsRemaining > 0) {
        _secondsRemaining--;
      } else {
        if (_timerMode == TimerMode.perQuestion) {
          submitAnswer(); 
        } else {
          finishQuiz();
        }
      }
      notifyListeners();
    });
  }

  void toggleOption(String option) {
    if (_isAnswered) return;
    if (_userSelection.contains(option)) {
      _userSelection.remove(option);
    } else {
      _userSelection.add(option);
    }
    notifyListeners();
  }

  void submitAnswer() {
    if (_isAnswered || !_isQuizActive) return;
    _isAnswered = true;
    final currentQ = _currentQuestions[_currentIndex];
    final List<String> correctAnswers = List<String>.from(currentQ['correct_answers']);
    
    // Check correctness: exact match of sets
    bool correct = _userSelection.length == correctAnswers.length &&
                   _userSelection.every((element) => correctAnswers.contains(element));
    
    if (correct) _score++;

    _quizResults.add({
      'question_id': currentQ['id'],
      'user_answers': jsonEncode(_userSelection),
      'is_correct': correct ? 1 : 0,
    });

    notifyListeners();

    // In perQuestion mode, we want a shorter pause before next
    int delay = _secondsRemaining <= 0 ? 500 : 1500;
    
    Future.delayed(Duration(milliseconds: delay), () {
      if (_isQuizActive) nextQuestion();
    });
  }

  void nextQuestion() {
    if (_currentIndex < _currentQuestions.length - 1) {
      _currentIndex++;
      _isAnswered = false;
      _userSelection = [];
      if (_timerMode == TimerMode.perQuestion) {
        _secondsRemaining = _originalLimit;
      }
      notifyListeners();
    } else {
      if (_timerMode == TimerMode.speedRun) {
        finishQuiz();
      } else {
        finishQuiz();
      }
    }
  }

  Future<void> finishQuiz() async {
    _quizTimer?.cancel();
    if (!_isQuizActive) return;
    _isQuizActive = false;
    if (_currentQuestions.isNotEmpty) {
      final historyId = await _databaseService.saveQuizHistory({
        'class_id': _activeClassId,
        'score': _score,
        'total_questions': _currentQuestions.length,
        'time_taken_seconds': _totalTimeSpent,
        'quiz_type': _timerMode.toString(),
        'date_taken': DateTime.now().toIso8601String(),
      });
      await _databaseService.saveQuizHistoryDetails(historyId, _quizResults);
    }
    notifyListeners();
  }

  void pauseTimer() => _quizTimer?.cancel();
  void resumeTimer() => _startTimer();

  void updateActiveQuestion(Map<String, dynamic> updatedQuestion) {
    int idx = _currentQuestions.indexWhere((q) => q['id'] == updatedQuestion['id']);
    if (idx != -1) {
      _currentQuestions[idx] = {
        ..._currentQuestions[idx],
        ...updatedQuestion,
      };
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    return await _databaseService.getQuizHistory();
  }
}
