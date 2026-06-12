import 'package:path/path.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'security_service.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    
    String path = join(await getDatabasesPath(), 'quiz_app.db');
    return await openDatabase(
      path,
      version: 6,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE classes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        created_at TEXT,
        cloud_bank_id TEXT,
        cloud_updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE questions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER,
        question_text TEXT,
        options TEXT,
        correct_answer TEXT,
        correct_answers TEXT,
        asked_count INTEGER DEFAULT 0,
        correct_streak INTEGER DEFAULT 0,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');
    await _createFilesTable(db);
    await _createHistoryTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await db.transaction((txn) async {
      if (oldVersion < 2) {
        await _createFilesTable(txn);
      }
      if (oldVersion < 3) {
        await _createHistoryTables(txn);
        await _upgradeToV3(txn);
      }
      if (oldVersion < 4) {
        try {
          await txn.execute('ALTER TABLE questions ADD COLUMN asked_count INTEGER DEFAULT 0');
        } catch (e) {
          debugPrint('Migration Error (v4): $e');
        }
      }
      if (oldVersion < 5) {
        try {
          await txn.execute('ALTER TABLE classes ADD COLUMN cloud_bank_id TEXT');
          await txn.execute('ALTER TABLE classes ADD COLUMN cloud_updated_at TEXT');
        } catch (e) {
          debugPrint('Migration Error (v5): $e');
        }
      }
      if (oldVersion < 6) {
        try {
          await txn.execute('ALTER TABLE questions ADD COLUMN correct_streak INTEGER DEFAULT 0');
        } catch (e) {
          debugPrint('Migration Error (v6): $e');
        }
      }
    });
  }

  // Helper for v3 upgrade inside transaction
  Future<void> _upgradeToV3(dynamic txnOrDb) async {
    try {
      await txnOrDb.execute('ALTER TABLE questions ADD COLUMN correct_answers TEXT');
    } catch (e) {
      debugPrint('Column already exists or migration error: $e');
    }

    final List<Map<String, dynamic>> questions = await txnOrDb.query('questions');
    final security = SecurityService();
    
    for (var q in questions) {
      if (q['correct_answer'] != null && q['correct_answers'] == null) {
        try {
          final decrypted = security.decryptData(q['correct_answer']);
          final jsonArray = jsonEncode([decrypted]);
          final encrypted = security.encryptData(jsonArray);
          
          await txnOrDb.update(
            'questions',
            {'correct_answers': encrypted},
            where: 'id = ?',
            whereArgs: [q['id']],
          );
        } catch (e) {
          debugPrint('Error migrating question ${q['id']}: $e');
        }
      }
    }
  }

  Future<void> _createFilesTable(dynamic txnOrDb) async {
    await txnOrDb.execute('''
      CREATE TABLE files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER,
        filename TEXT,
        created_at TEXT,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createHistoryTables(dynamic txnOrDb) async {
    await txnOrDb.execute('''
      CREATE TABLE quiz_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER,
        score INTEGER,
        total_questions INTEGER,
        time_taken_seconds INTEGER,
        quiz_type TEXT,
        date_taken TEXT,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');
    await txnOrDb.execute('''
      CREATE TABLE quiz_history_details (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        history_id INTEGER,
        question_id INTEGER,
        user_answers TEXT,
        is_correct INTEGER,
        FOREIGN KEY (history_id) REFERENCES quiz_history (id) ON DELETE CASCADE
      )
    ''');
  }

  // Classes methods
  Future<int> createClass(String name, {String? cloudBankId, String? cloudUpdatedAt}) async {
    final db = await database;
    return await db.insert('classes', {
      'name': name,
      'created_at': DateTime.now().toIso8601String(),
      'cloud_bank_id': cloudBankId,
      'cloud_updated_at': cloudUpdatedAt,
    });
  }

  Future<void> updateClassSync(int id, String cloudUpdatedAt) async {
    final db = await database;
    await db.update('classes', {'cloud_updated_at': cloudUpdatedAt}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getClasses() async {
    final db = await database;
    return await db.query('classes', orderBy: 'created_at DESC');
  }

  Future<void> deleteClass(int id) async {
    final db = await database;
    await db.delete('classes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> renameClass(int id, String newName) async {
    final db = await database;
    await db.update('classes', {'name': newName}, where: 'id = ?', whereArgs: [id]);
  }

  // Questions methods
  Future<void> clearQuestionsForClass(int classId) async {
    final db = await database;
    await db.delete('questions', where: 'class_id = ?', whereArgs: [classId]);
  }

  Future<void> insertQuestions(int classId, List<Map<String, dynamic>> questions) async {
    final db = await database;
    final batch = db.batch();
    for (var question in questions) {
      batch.insert('questions', {
        'class_id': classId,
        'question_text': question['question_text'],
        'options': question['options'],
        'correct_answers': question['correct_answers'] ?? question['correct_answer'],
      });
    }
    await batch.commit(noResult: true);
  }

  Future<int> addSingleQuestion(int classId, Map<String, dynamic> question) async {
    final db = await database;
    return await db.insert('questions', {
      'class_id': classId,
      'question_text': question['question_text'],
      'options': question['options'],
      'correct_answers': question['correct_answers'] ?? question['correct_answer'],
    });
  }

  Future<List<Map<String, dynamic>>> getQuestionsByClass(int classId) async {
    final db = await database;
    return await db.query('questions', where: 'class_id = ?', whereArgs: [classId]);
  }

  Future<void> updateQuestion(int id, Map<String, dynamic> data) async {
    final db = await database;
    await db.update('questions', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteQuestion(int id) async {
    final db = await database;
    await db.delete('questions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateMastery(int questionId, bool correct) async {
    final db = await database;
    if (correct) {
      await db.rawUpdate(
        'UPDATE questions SET correct_streak = correct_streak + 1 WHERE id = ?',
        [questionId],
      );
    } else {
      await db.rawUpdate(
        'UPDATE questions SET correct_streak = 0 WHERE id = ?',
        [questionId],
      );
    }
  }

  Future<void> incrementAskedCount(List<int> questionIds) async {
    final db = await database;
    await db.transaction((txn) async {
      for (var id in questionIds) {
        await txn.rawUpdate('UPDATE questions SET asked_count = asked_count + 1 WHERE id = ?', [id]);
      }
    });
  }

  // History methods
  Future<int> saveQuizHistory(Map<String, dynamic> history) async {
    final db = await database;
    return await db.insert('quiz_history', history);
  }

  Future<void> saveQuizHistoryDetails(int historyId, List<Map<String, dynamic>> details) async {
    final db = await database;
    final batch = db.batch();
    for (var detail in details) {
      batch.insert('quiz_history_details', {
        ...detail,
        'history_id': historyId,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getQuizHistory() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT h.*, c.name as class_name
      FROM quiz_history h
      JOIN classes c ON h.class_id = c.id
      ORDER BY h.date_taken DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getHistoryDetails(int historyId) async {
    final db = await database;
    return await db.query('quiz_history_details', where: 'history_id = ?', whereArgs: [historyId]);
  }

  // Files methods
  Future<int> addFile(int classId, String filename) async {
    final db = await database;
    return await db.insert('files', {
      'class_id': classId,
      'filename': filename,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getFilesByClass(int classId) async {
    final db = await database;
    return await db.query('files', where: 'class_id = ?', whereArgs: [classId], orderBy: 'created_at DESC');
  }
}
