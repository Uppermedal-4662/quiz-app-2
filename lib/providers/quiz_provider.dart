import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  
  // Anti-Cheat: Track per-question results in real-time
  List<Map<String, dynamic>?> _sessionResults = [];
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
      await _initSampleDataIfNeeded();
      _classes = await _databaseService.getClasses();
    } catch (e) {
      debugPrint('Error loading classes: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _initSampleDataIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final bool hasRunBefore = prefs.getBool('has_run_v6') ?? false;
    
    if (hasRunBefore) return;

    final existing = await _databaseService.getClasses();
    if (existing.any((c) => c['name'] == 'Sample Math Class')) return;

    // Create Sample Class
    final id = await _databaseService.createClass('Sample Math Class');
    
    // Sample Questions
    final sampleQuestions = [
      {
        'question_text': r'What is $\sqrt{144}$?',
        'options': ['10', '12', '14', '16'],
        'correct_answers': ['12'],
      },
      {
        'question_text': 'Which of these are prime numbers?',
        'options': ['2', '4', '9', '11'],
        'correct_answers': ['2', '11'],
      },
      {
        'question_text': r'Solve: $2x + 5 = 11$. What is $x$?',
        'options': ['2', '3', '4', '6'],
        'correct_answers': ['3'],
      }
    ];


    await _processAndSaveQuestions(id, sampleQuestions);
    await prefs.setBool('has_run_v6', true);
  }

  Future<void> addClass(String name, {String? cloudBankId, String? cloudUpdatedAt}) async {
    try {
      await _databaseService.createClass(name, cloudBankId: cloudBankId, cloudUpdatedAt: cloudUpdatedAt);
      await loadClasses();
    } catch (e) {
      debugPrint('Error adding class: $e');
    }
  }

  Future<void> updateClassSync(int id, String cloudUpdatedAt) async {
    try {
      await _databaseService.updateClassSync(id, cloudUpdatedAt);
      await loadClasses();
    } catch (e) {
      debugPrint('Error updating class sync: $e');
    }
  }

  Future<void> clearQuestionsForClass(int id) async {
    try {
      await _databaseService.clearQuestionsForClass(id);
    } catch (e) {
      debugPrint('Error clearing questions: $e');
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

  Future<void> renameClass(int id, String newName) async {
    try {
      await _databaseService.renameClass(id, newName);
      await loadClasses();
    } catch (e) {
      debugPrint('Error renaming class: $e');
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
      
      List<Map<String, dynamic>> selected;
      if (randomize) {
        selected = _weightedRandomSelect(list, count);
      } else {
        selected = (count == -1 || count > list.length) ? list : list.take(count).toList();
      }

      return selected.map((q) {
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
          'asked_count': q['asked_count'] ?? 0,
          'correct_streak': q['correct_streak'] ?? 0,
        };
      }).toList();
    } catch (e) {
      debugPrint('Error fetching/decrypting questions: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> _weightedRandomSelect(List<Map<String, dynamic>> questions, int count) {
    if (questions.isEmpty) return [];
    if (count == -1) count = questions.length;
    if (count >= questions.length) {
      final list = List<Map<String, dynamic>>.from(questions);
      list.shuffle();
      return list;
    }

    final List<Map<String, dynamic>> pool = List<Map<String, dynamic>>.from(questions);
    final List<Map<String, dynamic>> result = [];

    // Categorize
    final List<Map<String, dynamic>> newQ = pool.where((q) => (q['asked_count'] ?? 0) == 0).toList();
    final List<Map<String, dynamic>> wrongQ = pool.where((q) => (q['asked_count'] ?? 0) > 0 && (q['correct_streak'] ?? 0) < 2).toList();
    final List<Map<String, dynamic>> rightQ = pool.where((q) => (q['correct_streak'] ?? 0) >= 2).toList();

    for (int i = 0; i < count; i++) {
      if (pool.isEmpty) break;

      double r = (DateTime.now().microsecondsSinceEpoch % 1000000) / 1000000.0;
      List<Map<String, dynamic>>? targetList;

      if (newQ.isNotEmpty) {
        if (r < 0.65 && newQ.isNotEmpty) targetList = newQ;
        else if (r < 0.90 && wrongQ.isNotEmpty) targetList = wrongQ;
        else if (rightQ.isNotEmpty) targetList = rightQ;
      } else {
        if (r < 0.60 && wrongQ.isNotEmpty) targetList = wrongQ;
        else if (rightQ.isNotEmpty) targetList = rightQ;
      }

      targetList ??= pool;
      
      if (targetList.isNotEmpty) {
        targetList.shuffle();
        final picked = targetList.removeAt(0);
        result.add(picked);
        pool.removeWhere((q) => q['id'] == picked['id']);
        newQ.removeWhere((q) => q['id'] == picked['id']);
        wrongQ.removeWhere((q) => q['id'] == picked['id']);
        rightQ.removeWhere((q) => q['id'] == picked['id']);
      }
    }

    return result;
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
    _sessionResults = List.filled(questions.length, null); // Reset session state
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
    
    bool correct = _userSelection.length == correctAnswers.length &&
                   _userSelection.every((element) => correctAnswers.contains(element));
    
    if (correct) _score++;

    // Track mastery streak
    _databaseService.updateMastery(currentQ['id'], correct);

    // Persist result in session state
    _sessionResults[_currentIndex] = {
      'question_id': currentQ['id'],
      'user_answers': jsonEncode(_userSelection),
      'is_correct': correct ? 1 : 0,
    };

    notifyListeners();

    int delay = _secondsRemaining <= 0 ? 500 : 1500;
    Future.delayed(Duration(milliseconds: delay), () {
      if (_isQuizActive) nextQuestion();
    });
  }

  void nextQuestion() {
    if (_currentIndex < _currentQuestions.length - 1) {
      _currentIndex++;
      _restoreStateForCurrentIndex();
      if (_timerMode == TimerMode.perQuestion && !_isAnswered) {
        _secondsRemaining = _originalLimit;
      }
      notifyListeners();
    } else {
      finishQuiz();
    }
  }

  void previousQuestion() {
    if (_currentIndex > 0) {
      _currentIndex--;
      _restoreStateForCurrentIndex();
      notifyListeners();
    }
  }

  void skipQuestion() {
    if (!_isQuizActive || _isAnswered) return;
    
    final currentQ = _currentQuestions[_currentIndex];
    _databaseService.updateMastery(currentQ['id'], false);

    _sessionResults[_currentIndex] = {
      'question_id': currentQ['id'],
      'user_answers': jsonEncode([]),
      'is_correct': 0,
    };
    
    nextQuestion();
  }

  void _restoreStateForCurrentIndex() {
    final saved = _sessionResults[_currentIndex];
    if (saved != null) {
      _isAnswered = true;
      _userSelection = List<String>.from(jsonDecode(saved['user_answers']));
    } else {
      _isAnswered = false;
      _userSelection = [];
    }
  }

  Future<void> finishQuiz() async {
    _quizTimer?.cancel();
    if (!_isQuizActive) return;
    _isQuizActive = false;
    
    if (_currentQuestions.isNotEmpty) {
      // 1. Increment asked_count for all questions shown
      final List<int> shownIds = _currentQuestions.take(_currentIndex + 1).map((q) => q['id'] as int).toList();
      await _databaseService.incrementAskedCount(shownIds);

      // 2. Save history using the session results (including skips)
      final historyId = await _databaseService.saveQuizHistory({
        'class_id': _activeClassId,
        'score': _score,
        'total_questions': _currentQuestions.length,
        'time_taken_seconds': _totalTimeSpent,
        'quiz_type': _timerMode.toString(),
        'date_taken': DateTime.now().toIso8601String(),
      });
      
      final validDetails = _sessionResults.where((r) => r != null).cast<Map<String, dynamic>>().toList();
      await _databaseService.saveQuizHistoryDetails(historyId, validDetails);
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
