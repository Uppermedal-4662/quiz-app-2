import 'package:path/path.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
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
      version: 3,
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
        created_at TEXT
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
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');
    await _createFilesTable(db);
    await _createHistoryTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createFilesTable(db);
    }
    if (oldVersion < 3) {
      await _createHistoryTables(db);
      await _upgradeToV3(db);
    }
  }

  Future<void> _createFilesTable(Database db) async {
    await db.execute('''
      CREATE TABLE files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER,
        filename TEXT,
        created_at TEXT,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createHistoryTables(Database db) async {
    await db.execute('''
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
    await db.execute('''
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

  Future<void> _upgradeToV3(Database db) async {
    // Add correct_answers column if it doesn't exist
    try {
      await db.execute('ALTER TABLE questions ADD COLUMN correct_answers TEXT');
    } catch (e) {
      // Column might already exist if onCreate was called for v3
    }

    // Migrate existing correct_answer to correct_answers JSON array
    final List<Map<String, dynamic>> questions = await db.query('questions');
    final security = SecurityService();
    
    for (var q in questions) {
      if (q['correct_answer'] != null && q['correct_answers'] == null) {
        try {
          final decrypted = security.decryptData(q['correct_answer']);
          final jsonArray = jsonEncode([decrypted]);
          final encrypted = security.encryptData(jsonArray);
          
          await db.update(
            'questions',
            {'correct_answers': encrypted},
            where: 'id = ?',
            whereArgs: [q['id']],
          );
        } catch (e) {
          print('Error migrating question ${q['id']}: $e');
        }
      }
    }
  }

  // Classes methods
  Future<int> createClass(String name) async {
    final db = await database;
    return await db.insert('classes', {
      'name': name,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getClasses() async {
    final db = await database;
    return await db.query('classes', orderBy: 'created_at DESC');
  }

  Future<void> deleteClass(int id) async {
    final db = await database;
    await db.delete('classes', where: 'id = ?', whereArgs: [id]);
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

  // Questions methods
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
    // Join with classes to get class name
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
}
