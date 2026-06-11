import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class CloudProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;

  bool get isLoading => _isLoading;

  // --- App Configuration ---

  Future<Map<String, dynamic>> getAppConfig() async {
    final doc = await _firestore.collection('app_config').doc('global').get();
    return doc.data() ?? {};
  }

  Future<void> updateAppConfig(Map<String, dynamic> config) async {
    await _firestore.collection('app_config').doc('global').set(config, SetOptions(merge: true));
  }

  // --- Messaging (Rate Limited) ---

  Future<void> sendMessageToAdmin(String userId, String email, String message) async {
    final userDoc = await _firestore.collection('users').doc(userId).get();
    if (userDoc.data()?['can_message'] == false) {
      throw Exception('Your messaging privileges have been suspended by an administrator.');
    }

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    
    final snapshot = await _firestore.collection('messages')
        .where('sender_uid', isEqualTo: userId)
        .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
        .get();
    
    if (snapshot.docs.length >= 5) {
      throw Exception('Daily message limit reached (5 per day). Please try again tomorrow.');
    }

    await _firestore.collection('messages').add({
      'sender_uid': userId,
      'sender_email': email,
      'message': message,
      'timestamp': FieldValue.serverTimestamp(),
      'reply': null,
    });
  }

  Future<void> replyToMessage(String messageId, String adminEmail, String replyText) async {
    await _firestore.collection('messages').doc(messageId).update({
      'reply': replyText,
      'replied_by': adminEmail,
      'replied_at': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Map<String, dynamic>>> getAdminInbox() async {
    final snapshot = await _firestore.collection('messages')
        .orderBy('timestamp', descending: true)
        .get();
    return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  // --- Super Admin Actions ---

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final snapshot = await _firestore.collection('users').get();
    return snapshot.docs.map((doc) => {'uid': doc.id, ...doc.data()}).toList();
  }

  Future<void> updateUserRole(String uid, String role) async {
    await _firestore.collection('users').doc(uid).update({'role': role});
  }

  Future<void> updateUserPermissions(String uid, List<String> bankIds) async {
    await _firestore.collection('users').doc(uid).update({'accessible_banks': bankIds});
  }

  Future<void> updateUserBanStatus(String uid, {bool? isDisabled, bool? canMessage, bool? canAccessQuizzes, bool? canViewInbox}) async {
    final Map<String, dynamic> updates = {};
    if (isDisabled != null) updates['is_disabled'] = isDisabled;
    if (canMessage != null) updates['can_message'] = canMessage;
    if (canAccessQuizzes != null) updates['can_access_quizzes'] = canAccessQuizzes;
    if (canViewInbox != null) updates['can_view_inbox'] = canViewInbox;
    
    if (updates.isNotEmpty) {
      await _firestore.collection('users').doc(uid).update(updates);
    }
  }

  // --- Admin Actions ---

  Future<String> createQuestionBank(String name, String description, String category, String adminUid) async {
    final docRef = await _firestore.collection('question_banks').add({
      'name': name,
      'description': description,
      'category': category,
      'created_by': adminUid,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> updateQuestionBank(String bankId, Map<String, dynamic> data) async {
    await _firestore.collection('question_banks').doc(bankId).update({
      ...data,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteQuestionBank(String bankId) async {
    // Note: in a real app, we should also delete subcollection cloud_questions
    // but client side SDK requires deleting one by one.
    await _firestore.collection('question_banks').doc(bankId).delete();
  }

  Future<void> uploadQuestionsToCloud(String bankId, List<Map<String, dynamic>> questions) async {
    _isLoading = true;
    notifyListeners();
    try {
      final batch = _firestore.batch();
      final bankRef = _firestore.collection('question_banks').doc(bankId);
      final collection = bankRef.collection('cloud_questions');
      
      for (var q in questions) {
        final docRef = collection.doc();
        batch.set(docRef, {
          'question_text': q['question_text'],
          'options': q['options'],
          'correct_answers': q['correct_answers'],
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      batch.update(bankRef, {'updated_at': FieldValue.serverTimestamp()});
      await batch.commit();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> getMyBanks(String adminUid) async {
    final snapshot = await _firestore.collection('question_banks')
        .where('created_by', isEqualTo: adminUid)
        .get();
    return snapshot.docs.map((doc) => {'bank_id': doc.id, ...doc.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> getCloudQuestions(String bankId) async {
    final snapshot = await _firestore.collection('question_banks')
        .doc(bankId)
        .collection('cloud_questions')
        .orderBy('created_at', descending: true)
        .get();
    return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  Future<void> updateCloudQuestion(String bankId, String questionId, Map<String, dynamic> data) async {
    await _firestore.collection('question_banks')
        .doc(bankId)
        .collection('cloud_questions')
        .doc(questionId)
        .update(data);
    
    // Mark bank as updated
    await _firestore.collection('question_banks').doc(bankId).update({
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteCloudQuestion(String bankId, String questionId) async {
    await _firestore.collection('question_banks')
        .doc(bankId)
        .collection('cloud_questions')
        .doc(questionId)
        .delete();
  }

  // --- User Actions ---

  Future<List<Map<String, dynamic>>> getAccessibleBanks(List<String> bankIds, {String? adminUid}) async {
    final Set<Map<String, dynamic>> banks = {};

    // 1. Get banks by ID list (explicit permissions)
    if (bankIds.isNotEmpty) {
      final chunks = _chunkList(bankIds, 10); // Firestore whereIn limit
      for (var chunk in chunks) {
        final snapshot = await _firestore.collection('question_banks')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        banks.addAll(snapshot.docs.map((doc) => {'bank_id': doc.id, ...doc.data()}));
      }
    }

    // 2. If admin, include their own banks
    if (adminUid != null) {
      final snapshot = await _firestore.collection('question_banks')
          .where('created_by', isEqualTo: adminUid)
          .get();
      banks.addAll(snapshot.docs.map((doc) => {'bank_id': doc.id, ...doc.data()}));
    }

    return banks.toList();
  }

  List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
    List<List<T>> chunks = [];
    for (var i = 0; i < list.length; i += chunkSize) {
      chunks.add(list.sublist(i, i + chunkSize > list.length ? list.length : i + chunkSize));
    }
    return chunks;
  }

  Future<List<Map<String, dynamic>>> downloadBankQuestions(String bankId) async {
    final snapshot = await _firestore.collection('question_banks')
        .doc(bankId)
        .collection('cloud_questions')
        .get();
    return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  // --- General Meta ---
  Future<List<Map<String, dynamic>>> getAllBanks() async {
    final snapshot = await _firestore.collection('question_banks').get();
    return snapshot.docs.map((doc) => {'bank_id': doc.id, ...doc.data()}).toList();
  }
}
