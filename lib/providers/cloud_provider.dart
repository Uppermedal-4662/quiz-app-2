import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class CloudProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;

  bool get isLoading => _isLoading;

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

  // --- Admin Actions ---

  Future<String> createQuestionBank(String name, String description, String adminUid) async {
    final docRef = await _firestore.collection('question_banks').add({
      'name': name,
      'description': description,
      'created_by': adminUid,
      'created_at': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> uploadQuestionsToCloud(String bankId, List<Map<String, dynamic>> questions) async {
    _isLoading = true;
    notifyListeners();
    try {
      final batch = _firestore.batch();
      final collection = _firestore.collection('question_banks').doc(bankId).collection('cloud_questions');
      
      for (var q in questions) {
        final docRef = collection.doc();
        batch.set(docRef, {
          'question_text': q['question_text'],
          'options': q['options'],
          'correct_answers': q['correct_answers'],
          'created_at': FieldValue.serverTimestamp(),
        });
      }
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

  // --- User Actions ---

  Future<List<Map<String, dynamic>>> getAccessibleBanks(List<String> bankIds) async {
    if (bankIds.isEmpty) return [];
    
    // Firestore 'whereIn' supports up to 30 items. For simplicity here:
    final snapshot = await _firestore.collection('question_banks')
        .where(FieldPath.documentId, whereIn: bankIds)
        .get();
    return snapshot.docs.map((doc) => {'bank_id': doc.id, ...doc.data()}).toList();
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
