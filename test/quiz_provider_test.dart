import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/providers/quiz_provider.dart';

void main() {
  group('QuizProvider - Weighted Random Selection', () {
    test('Selects exact number of questions requested', () {
      final List<Map<String, dynamic>> questions = List.generate(20, (i) => {
        'id': i,
        'asked_count': 0,
        'correct_streak': 0,
      });

      final selected = QuizProvider.weightedRandomSelect(questions, 5);
      expect(selected.length, 5);
    });

    test('Returns all questions if count exceeds available', () {
      final List<Map<String, dynamic>> questions = List.generate(5, (i) => {
        'id': i,
        'asked_count': 0,
        'correct_streak': 0,
      });

      final selected = QuizProvider.weightedRandomSelect(questions, 10);
      expect(selected.length, 5);
    });

    test('Returns empty list when given empty list', () {
      final selected = QuizProvider.weightedRandomSelect([], 5);
      expect(selected.isEmpty, true);
    });

    test('Selection pool does not contain duplicates', () {
      final List<Map<String, dynamic>> questions = List.generate(10, (i) => {
        'id': i,
        'asked_count': 0,
        'correct_streak': 0,
      });

      final selected = QuizProvider.weightedRandomSelect(questions, 5);
      final ids = selected.map((q) => q['id']).toSet();
      expect(ids.length, 5);
    });
  });
}
