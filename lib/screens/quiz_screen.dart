import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:confetti/confetti.dart';
import 'package:vibration/vibration.dart';
import '../providers/quiz_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/latex_text.dart';

enum QuizScreenState { config, playing, summary }

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  QuizScreenState _uiState = QuizScreenState.config;
  late ConfettiController _confettiController;
  
  // Config state
  int? _selectedClassId;
  final TextEditingController _countController = TextEditingController(text: '10');
  final TextEditingController _minController = TextEditingController(text: '0');
  final TextEditingController _secController = TextEditingController(text: '30');
  TimerMode _selectedTimerMode = TimerMode.none;
  bool _randomize = true;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<QuizProvider>(context, listen: false).loadClasses();
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  void _onStartQuiz() async {
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a class first')));
      return;
    }

    final int questionCount = int.tryParse(_countController.text) ?? 10;
    final int mins = int.tryParse(_minController.text) ?? 0;
    final int secs = int.tryParse(_secController.text) ?? 0;
    final int totalSeconds = (mins * 60) + secs;

    if (totalSeconds <= 0 && _selectedTimerMode != TimerMode.none) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please set a valid time limit')));
      return;
    }

    final provider = context.read<QuizProvider>();
    final fetchCount = _selectedTimerMode == TimerMode.speedRun ? -1 : questionCount;
    final questions = await provider.getQuestions(_selectedClassId!, fetchCount, randomize: _randomize);

    if (questions.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No questions found for this class')));
      return;
    }

    provider.startQuiz(
      classId: _selectedClassId!,
      questions: questions,
      mode: _selectedTimerMode,
      timeLimitSeconds: totalSeconds,
    );

    setState(() {
      _uiState = QuizScreenState.playing;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz AI'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (_uiState == QuizScreenState.playing) {
              _showExitConfirmation();
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Stack(
        children: [
          _buildBody(),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [Colors.green, Colors.blue, Colors.pink, Colors.orange, Colors.purple],
            ),
          ),
        ],
      ),
    );
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Quiz?'),
        content: const Text('Your progress will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              context.read<QuizProvider>().finishQuiz();
              Navigator.pop(context); 
              Navigator.pop(context); 
            },
            child: const Text('Exit', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_uiState) {
      case QuizScreenState.config:
        return _buildConfig();
      case QuizScreenState.playing:
        return _buildQuiz();
      case QuizScreenState.summary:
        return _buildSummary();
    }
  }

  Widget _buildConfig() {
    return Consumer<QuizProvider>(
      builder: (context, provider, child) {
        bool isSpeedrun = _selectedTimerMode == TimerMode.speedRun;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('1. Choose Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              DropdownButton<int>(
                value: _selectedClassId,
                hint: const Text('Select Class'),
                isExpanded: true,
                items: provider.classes.map((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['name']))).toList(),
                onChanged: (val) => setState(() => _selectedClassId = val),
              ),
              const SizedBox(height: 24),
              if (!isSpeedrun) ...[
                const Text('2. Number of Questions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _countController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'e.g. 20'),
                ),
                const SizedBox(height: 16),
              ],
              CheckboxListTile(
                title: const Text('Randomize Question Order'),
                value: _randomize,
                onChanged: (v) => setState(() => _randomize = v!),
              ),
              const SizedBox(height: 24),
              const Text('3. Timer Mode', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ...TimerMode.values.map((mode) => RadioListTile<TimerMode>(
                title: Text(mode.toString().split('.').last.toUpperCase()),
                subtitle: Text(_getTimerDescription(mode)),
                value: mode,
                groupValue: _selectedTimerMode,
                onChanged: (v) => setState(() => _selectedTimerMode = v!),
              )),
              if (_selectedTimerMode != TimerMode.none) ...[
                const SizedBox(height: 24),
                Text(isSpeedrun ? '4. Total Speedrun Time' : '4. Time Limit', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _minController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Minutes', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _secController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Seconds', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: _onStartQuiz,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16), backgroundColor: Colors.blue, foregroundColor: Colors.white),
                child: const Text('START QUIZ', style: TextStyle(fontSize: 18, letterSpacing: 1.2)),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getTimerDescription(TimerMode mode) {
    switch (mode) {
      case TimerMode.none: return 'Relaxed mode, no pressure.';
      case TimerMode.perQuestion: return 'Fixed time for each question.';
      case TimerMode.perQuiz: return 'Fixed total time for the entire quiz.';
      case TimerMode.speedRun: return 'Answer as many as you can before time runs out!';
    }
  }

  Widget _buildQuiz() {
    final settings = context.read<SettingsProvider>();
    return Consumer<QuizProvider>(
      builder: (context, provider, child) {
        if (!provider.isQuizActive) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() => _uiState = QuizScreenState.summary);
            if (settings.enableGamification && provider.score / provider.currentQuestions.length >= 0.8) {
              _confettiController.play();
            }
          });
          return const Center(child: CircularProgressIndicator());
        }

        final question = provider.currentQuestions[provider.currentIndex];
        final options = List<String>.from(question['options']);
        final correctAnswers = List<String>.from(question['correct_answers']);
        final isMulti = correctAnswers.length > 1;

        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.enter): () {
              if (provider.isAnswered) {
                provider.nextQuestion();
              } else if (provider.userSelection.isNotEmpty) {
                _submitAnswer(provider, settings);
              }
            },
            const SingleActivator(LogicalKeyboardKey.backspace): () {
              if (provider.currentIndex > 0) provider.previousQuestion();
            },
            ...Map.fromIterable(
              Iterable.generate(options.length),
              key: (i) {
                final digits = [
                  LogicalKeyboardKey.digit1,
                  LogicalKeyboardKey.digit2,
                  LogicalKeyboardKey.digit3,
                  LogicalKeyboardKey.digit4,
                  LogicalKeyboardKey.digit5,
                  LogicalKeyboardKey.digit6,
                  LogicalKeyboardKey.digit7,
                  LogicalKeyboardKey.digit8,
                  LogicalKeyboardKey.digit9,
                ];
                return SingleActivator(digits[i % digits.length]);
              },
              value: (i) => () {
                if (!provider.isAnswered) {
                  provider.toggleOption(options[i]);
                  if (settings.enableHaptics) Vibration.vibrate(duration: 50);
                }
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Column(
              children: [
                LinearProgressIndicator(value: (provider.currentIndex + 1) / provider.currentQuestions.length),
                // ... rest of the original Column children ...
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Q ${provider.currentIndex + 1}/${provider.currentQuestions.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (provider.timerMode != TimerMode.none)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: provider.secondsRemaining < 10 ? Colors.red.shade100 : Colors.blue.shade100, borderRadius: BorderRadius.circular(12)),
                          child: Text('${provider.secondsRemaining}s', style: TextStyle(fontWeight: FontWeight.bold, color: provider.secondsRemaining < 10 ? Colors.red : Colors.blue.shade900)),
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit_note, color: Colors.orange),
                        tooltip: 'Fix Question Error',
                        onPressed: () {
                          provider.pauseTimer();
                          _showInQuizEditDialog(question);
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LatexText(question['question_text'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                        if (isMulti) const Padding(padding: EdgeInsets.only(top: 8), child: Text('(Select all correct options)', style: TextStyle(color: Colors.grey, fontSize: 12))),
                        const SizedBox(height: 32),
                        ...options.map((option) {
                          bool isSelected = provider.userSelection.contains(option);
                          bool isCorrect = correctAnswers.contains(option);
                          Color? tileColor;
                          
                          if (provider.isAnswered) {
                            if (isCorrect) tileColor = Colors.green.shade100;
                            else if (isSelected) tileColor = Colors.red.shade100;
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: InkWell(
                              onTap: provider.isAnswered ? null : () {
                                provider.toggleOption(option);
                                if (settings.enableHaptics) Vibration.vibrate(duration: 50);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: tileColor ?? (isSelected ? Colors.blue.shade50 : Colors.white),
                                  border: Border.all(color: isSelected ? Colors.blue : Colors.grey.shade300, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    isMulti 
                                      ? Icon(isSelected ? Icons.check_box : Icons.check_box_outline_blank, color: isSelected ? Colors.blue : Colors.grey)
                                      : Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off, color: isSelected ? Colors.blue : Colors.grey),
                                    const SizedBox(width: 12),
                                    Expanded(child: LatexText(option, style: const TextStyle(fontSize: 16), showTTS: false)),
                                    if (provider.isAnswered && isCorrect) const Icon(Icons.check_circle, color: Colors.green),
                                    if (provider.isAnswered && !isCorrect && isSelected) const Icon(Icons.cancel, color: Colors.red),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                  child: Row(
                    children: [
                      if (provider.currentIndex > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => provider.previousQuestion(),
                            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
                            child: const Text('PREVIOUS'),
                          ),
                        ),
                      if (provider.currentIndex > 0) const SizedBox(width: 8),
                      if (provider.timerMode != TimerMode.speedRun && !provider.isAnswered)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => provider.skipQuestion(),
                            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 56), foregroundColor: Colors.orange),
                            child: const Text('SKIP'),
                          ),
                        ),
                      if (provider.timerMode != TimerMode.speedRun && !provider.isAnswered) const SizedBox(width: 8),
                      if (provider.isAnswered)
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () => provider.nextQuestion(),
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('NEXT'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 56),
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        )
                      else
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: provider.userSelection.isEmpty ? null : () => _submitAnswer(provider, settings),
                            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56), backgroundColor: Colors.blue, foregroundColor: Colors.white),
                            child: const Text('SUBMIT ANSWER', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _submitAnswer(QuizProvider provider, SettingsProvider settings) {
    provider.submitAnswer();
    if (settings.enableHaptics) {
      final currentQ = provider.currentQuestions[provider.currentIndex];
      final List<String> correctAnswers = List<String>.from(currentQ['correct_answers']);
      bool correct = provider.userSelection.length == correctAnswers.length &&
                      provider.userSelection.every((element) => correctAnswers.contains(element));
      if (correct) {
        Vibration.vibrate(duration: 100);
      } else {
        Vibration.vibrate(pattern: [0, 50, 50, 50]);
      }
    }
  }

  void _showInQuizEditDialog(Map<String, dynamic> question) {
    final textController = TextEditingController(text: question['question_text']);
    final List<TextEditingController> optionControllers = [];
    final List<bool> isCorrectList = [];

    final List<dynamic> options = question['options'];
    final List<dynamic> correctAnswers = question['correct_answers'];
    for (var opt in options) {
      optionControllers.add(TextEditingController(text: opt.toString()));
      isCorrectList.add(correctAnswers.contains(opt.toString()));
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Question (In-Quiz)'),
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
              onPressed: () {
                context.read<QuizProvider>().resumeTimer();
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final text = textController.text.trim();
                final opts = optionControllers.map((c) => c.text.trim()).toList();
                final List<String> selectedAnswers = [];
                for (int i = 0; i < opts.length; i++) {
                  if (isCorrectList[i]) selectedAnswers.add(opts[i]);
                }

                if (text.isEmpty || opts.any((o) => o.isEmpty) || selectedAnswers.isEmpty) {
                  return; 
                }

                final provider = context.read<QuizProvider>();
                try {
                  await provider.updateQuestion(question['id'], text, opts, selectedAnswers);
                  provider.updateActiveQuestion({
                    'id': question['id'],
                    'question_text': text,
                    'options': opts,
                    'correct_answers': selectedAnswers,
                  });
                  if (mounted) {
                    provider.resumeTimer();
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('Update & Resume'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final provider = context.read<QuizProvider>();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.stars, size: 100, color: Colors.amber),
            const SizedBox(height: 24),
            const Text('Quiz Completed!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 48),
            _buildStatRow('Score', '${provider.score} / ${provider.currentQuestions.length}'),
            const Divider(),
            _buildStatRow('Accuracy', '${((provider.score / provider.currentQuestions.length) * 100).toStringAsFixed(1)}%'),
            const Divider(),
            _buildStatRow('Timer Mode', provider.timerMode.toString().split('.').last.toUpperCase()),
            const SizedBox(height: 64),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(minimumSize: const Size(200, 50)),
              child: const Text('RETURN HOME'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 18, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
