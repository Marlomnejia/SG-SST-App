import 'package:cloud_firestore/cloud_firestore.dart';

class TrainingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<QuerySnapshot> streamPublishedTrainings() {
    return _firestore
        .collection('trainings')
        .where('published', isEqualTo: true)
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> streamAllTrainings() {
    return _firestore
        .collection('trainings')
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  Future<void> createTraining(Map<String, dynamic> data) async {
    await _firestore.collection('trainings').add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateTraining(String id, Map<String, dynamic> data) async {
    await _firestore.collection('trainings').doc(id).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> assignTraining({
    required String trainingId,
    required String target,
    DateTime? dueDate,
    bool autoReassign = false,
  }) async {
    await _firestore.collection('assignments').add({
      'trainingId': trainingId,
      'target': target,
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate) : null,
      'autoReassign': autoReassign,
      'archived': false,
      'assignedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> streamAssignmentsForUser(String uid) {
    return _firestore
        .collection('assignments')
        .where('target', whereIn: ['all', uid])
        .snapshots();
  }

  Stream<QuerySnapshot> streamAttemptsForUser(String uid) {
    return _firestore
        .collection('trainingAttempts')
        .where('userId', isEqualTo: uid)
        .snapshots();
  }

  Stream<QuerySnapshot> streamCertificatesForUser(String uid) {
    return _firestore
        .collection('certificates')
        .where('userId', isEqualTo: uid)
        .snapshots();
  }

  Future<int> countAttempts(String trainingId, String uid) async {
    final snapshot = await _firestore
        .collection('trainingAttempts')
        .where('trainingId', isEqualTo: trainingId)
        .where('userId', isEqualTo: uid)
        .get();
    return snapshot.docs.length;
  }

  Future<void> saveAttempt({
    required String trainingId,
    required String uid,
    required int score,
    required bool passed,
    required int totalQuestions,
    String? trainingVersion,
  }) async {
    await _firestore.collection('trainingAttempts').add({
      'trainingId': trainingId,
      'userId': uid,
      'score': score,
      'totalQuestions': totalQuestions,
      'passed': passed,
      'version': trainingVersion,
      'startedAt': FieldValue.serverTimestamp(),
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> issueCertificate({
    required String trainingId,
    required String uid,
    required int score,
    String? trainingVersion,
  }) async {
    await _firestore.collection('certificates').add({
      'trainingId': trainingId,
      'userId': uid,
      'score': score,
      'version': trainingVersion,
      'issuedAt': FieldValue.serverTimestamp(),
    });
  }
}
