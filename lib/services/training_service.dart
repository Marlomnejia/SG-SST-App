import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/training_module_model.dart';
import 'user_service.dart';

class TrainingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserService _userService = UserService();
  final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>>
  _trainingStreams = {};
  final Map<String, Stream<DocumentSnapshot<Map<String, dynamic>>>>
  _trainingDocStreams = {};
  final Map<String, Stream<QuerySnapshot>> _legacyStreams = {};

  Stream<QuerySnapshot> streamPublishedTrainings() {
    return _legacyStreams.putIfAbsent(
      'publishedTrainings',
      () => _firestore
          .collection('trainings')
          .where('published', isEqualTo: true)
          .orderBy('updatedAt', descending: true)
          .snapshots()
          .asBroadcastStream(),
    );
  }

  Stream<QuerySnapshot> streamAllTrainings() {
    return _legacyStreams.putIfAbsent(
      'allTrainings',
      () => _firestore
          .collection('trainings')
          .orderBy('updatedAt', descending: true)
          .snapshots()
          .asBroadcastStream(),
    );
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
    return _legacyStreams.putIfAbsent(
      'assignments:$uid',
      () => _firestore
          .collection('assignments')
          .where('target', whereIn: ['all', uid])
          .snapshots()
          .asBroadcastStream(),
    );
  }

  Stream<QuerySnapshot> streamAttemptsForUser(String uid) {
    return _legacyStreams.putIfAbsent(
      'attempts:$uid',
      () => _firestore
          .collection('trainingAttempts')
          .where('userId', isEqualTo: uid)
          .snapshots()
          .asBroadcastStream(),
    );
  }

  Stream<QuerySnapshot> streamCertificatesForUser(String uid) {
    return _legacyStreams.putIfAbsent(
      'certificates:$uid',
      () => _firestore
          .collection('certificates')
          .where('userId', isEqualTo: uid)
          .snapshots()
          .asBroadcastStream(),
    );
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

  Future<String> _requireInstitutionId() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No hay usuario autenticado.');
    }
    final institutionId = await _userService.getUserInstitutionId(user.uid);
    if (institutionId == null || institutionId.isEmpty) {
      throw Exception('Usuario sin institucion.');
    }
    return institutionId;
  }

  CollectionReference<Map<String, dynamic>> _institutionTrainingsRef(
    String institutionId,
  ) {
    return _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection('trainings');
  }

  Future<void> createInstitutionTraining(TrainingModuleModel model) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado.');
    final institutionId = await _requireInstitutionId();
    final payload = model.toMap();
    payload['createdBy'] = user.uid;
    await _institutionTrainingsRef(institutionId).add(payload);
  }

  Future<void> updateInstitutionTraining(
    String trainingId,
    Map<String, dynamic> data,
  ) async {
    final institutionId = await _requireInstitutionId();
    await _institutionTrainingsRef(institutionId).doc(trainingId).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> cancelInstitutionTraining(String trainingId) async {
    await updateInstitutionTraining(trainingId, {'status': 'cancelled'});
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>
  streamInstitutionTrainingsForAdmin() {
    final userKey = _auth.currentUser?.uid ?? 'guest';
    final cacheKey = 'adminTrainings:$userKey';
    if (_trainingStreams.containsKey(cacheKey)) {
      return _trainingStreams[cacheKey]!;
    }
    final stream = Stream.fromFuture(_requireInstitutionId())
        .asyncExpand(
          (institutionId) => _institutionTrainingsRef(
            institutionId,
          ).orderBy('createdAt', descending: true).snapshots(),
        )
        .asBroadcastStream();
    _trainingStreams[cacheKey] = stream;
    return stream;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>
  streamPublishedScheduledForUser() {
    final userKey = _auth.currentUser?.uid ?? 'guest';
    final cacheKey = 'scheduled:$userKey';
    if (_trainingStreams.containsKey(cacheKey)) {
      return _trainingStreams[cacheKey]!;
    }
    final stream = Stream.fromFuture(_requireInstitutionId())
        .asyncExpand(
          (institutionId) => _institutionTrainingsRef(institutionId)
              .where('type', isEqualTo: TrainingType.scheduled.name)
              .where('status', isEqualTo: TrainingStatus.published.name)
              .orderBy('createdAt', descending: true)
              .snapshots(),
        )
        .asBroadcastStream();
    _trainingStreams[cacheKey] = stream;
    return stream;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamPublishedVideoForUser() {
    final userKey = _auth.currentUser?.uid ?? 'guest';
    final cacheKey = 'video:$userKey';
    if (_trainingStreams.containsKey(cacheKey)) {
      return _trainingStreams[cacheKey]!;
    }
    final stream = Stream.fromFuture(_requireInstitutionId())
        .asyncExpand(
          (institutionId) => _institutionTrainingsRef(institutionId)
              .where('type', isEqualTo: TrainingType.video.name)
              .where('status', isEqualTo: TrainingStatus.published.name)
              .orderBy('createdAt', descending: true)
              .snapshots(),
        )
        .asBroadcastStream();
    _trainingStreams[cacheKey] = stream;
    return stream;
  }

  Future<void> saveRsvp({
    required String trainingId,
    required String response,
    String? comment,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado.');
    final institutionId = await _requireInstitutionId();
    final responseRef = _institutionTrainingsRef(
      institutionId,
    ).doc(trainingId).collection('responses').doc(user.uid);
    final existing = await responseRef.get();
    final existingData = existing.data();
    if (existing.exists &&
        (existingData?['response'] ?? '').toString().trim().isNotEmpty) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'already-exists',
        message:
            'Ya registraste tu confirmacion. Si necesitas cambiarla, contacta al responsable.',
      );
    }

    final userProfile = await _firestore
        .collection('users')
        .doc(user.uid)
        .get();
    final userProfileData = userProfile.data() ?? const <String, dynamic>{};
    await responseRef.set({
      'userId': user.uid,
      'userName':
          (userProfileData['displayName'] ??
                  userProfileData['name'] ??
                  user.displayName ??
                  '')
              .toString()
              .trim(),
      'userEmail': (userProfileData['email'] ?? user.email ?? '')
          .toString()
          .trim(),
      'response': response,
      'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamMyRsvp(
    String trainingId,
  ) {
    final user = _auth.currentUser;
    if (user == null) {
      return const Stream.empty();
    }
    final cacheKey = 'rsvp:${user.uid}:$trainingId';
    if (_trainingDocStreams.containsKey(cacheKey)) {
      return _trainingDocStreams[cacheKey]!;
    }
    final stream = Stream.fromFuture(_requireInstitutionId())
        .asyncExpand(
          (institutionId) => _institutionTrainingsRef(
            institutionId,
          ).doc(trainingId).collection('responses').doc(user.uid).snapshots(),
        )
        .asBroadcastStream();
    _trainingDocStreams[cacheKey] = stream;
    return stream;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamResponsesForTraining(
    String trainingId,
  ) {
    final userKey = _auth.currentUser?.uid ?? 'guest';
    final cacheKey = 'responses:$userKey:$trainingId';
    if (_trainingStreams.containsKey(cacheKey)) {
      return _trainingStreams[cacheKey]!;
    }
    final stream = Stream.fromFuture(_requireInstitutionId())
        .asyncExpand(
          (institutionId) => _institutionTrainingsRef(institutionId)
              .doc(trainingId)
              .collection('responses')
              .orderBy('respondedAt', descending: true)
              .snapshots(),
        )
        .asBroadcastStream();
    _trainingStreams[cacheKey] = stream;
    return stream;
  }

  Future<void> markAttendance({
    required String trainingId,
    required String userId,
    required bool attended,
  }) async {
    final admin = _auth.currentUser;
    if (admin == null) throw Exception('No hay usuario autenticado.');
    final institutionId = await _requireInstitutionId();
    await _institutionTrainingsRef(
      institutionId,
    ).doc(trainingId).collection('attendance').doc(userId).set({
      'userId': userId,
      'attended': attended,
      'markedAt': FieldValue.serverTimestamp(),
      'markedBy': admin.uid,
    }, SetOptions(merge: true));
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamMyAttendance(
    String trainingId,
  ) {
    final user = _auth.currentUser;
    if (user == null) {
      return const Stream.empty();
    }
    final cacheKey = 'attendance:${user.uid}:$trainingId';
    if (_trainingDocStreams.containsKey(cacheKey)) {
      return _trainingDocStreams[cacheKey]!;
    }
    final stream = Stream.fromFuture(_requireInstitutionId())
        .asyncExpand(
          (institutionId) => _institutionTrainingsRef(
            institutionId,
          ).doc(trainingId).collection('attendance').doc(user.uid).snapshots(),
        )
        .asBroadcastStream();
    _trainingDocStreams[cacheKey] = stream;
    return stream;
  }

  Future<void> markVideoWatched(String trainingId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado.');
    final institutionId = await _requireInstitutionId();
    if (kDebugMode) {
      debugPrint(
        '[TrainingService][markVideoWatched] uid=${user.uid} institutionId=$institutionId trainingId=$trainingId',
      );
      debugPrint(
        '[TrainingService][markVideoWatched] path=institutions/$institutionId/trainings/$trainingId/progress/${user.uid}',
      );
    }
    await _institutionTrainingsRef(
      institutionId,
    ).doc(trainingId).collection('progress').doc(user.uid).set({
      'userId': user.uid,
      'watched': true,
      'watchedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamMyVideoProgress(
    String trainingId,
  ) {
    final user = _auth.currentUser;
    if (user == null) {
      return const Stream.empty();
    }
    final cacheKey = 'progress:${user.uid}:$trainingId';
    if (_trainingDocStreams.containsKey(cacheKey)) {
      return _trainingDocStreams[cacheKey]!;
    }
    final stream = Stream.fromFuture(_requireInstitutionId())
        .asyncExpand(
          (institutionId) => _institutionTrainingsRef(
            institutionId,
          ).doc(trainingId).collection('progress').doc(user.uid).snapshots(),
        )
        .asBroadcastStream();
    _trainingDocStreams[cacheKey] = stream;
    return stream;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  getTrainingDocsByIds(List<String> trainingIds) async {
    if (trainingIds.isEmpty) return [];
    final institutionId = await _requireInstitutionId();
    final uniqueIds = trainingIds.toSet().toList();
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    const chunkSize = 10;
    for (int i = 0; i < uniqueIds.length; i += chunkSize) {
      final chunk = uniqueIds.sublist(
        i,
        i + chunkSize > uniqueIds.length ? uniqueIds.length : i + chunkSize,
      );
      final snapshot = await _institutionTrainingsRef(
        institutionId,
      ).where(FieldPath.documentId, whereIn: chunk).get();
      docs.addAll(snapshot.docs);
    }
    return docs;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>
  streamMyResponsesCollectionGroup() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    return _trainingStreams.putIfAbsent(
      'groupResponses:${user.uid}',
      () => _firestore
          .collectionGroup('responses')
          .where('userId', isEqualTo: user.uid)
          .orderBy('respondedAt', descending: true)
          .snapshots()
          .asBroadcastStream(),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>
  streamMyAttendanceCollectionGroup() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    return _trainingStreams.putIfAbsent(
      'groupAttendance:${user.uid}',
      () => _firestore
          .collectionGroup('attendance')
          .where('userId', isEqualTo: user.uid)
          .orderBy('markedAt', descending: true)
          .snapshots()
          .asBroadcastStream(),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>
  streamMyProgressCollectionGroup() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    return _trainingStreams.putIfAbsent(
      'groupProgress:${user.uid}',
      () => _firestore
          .collectionGroup('progress')
          .where('userId', isEqualTo: user.uid)
          .orderBy('watchedAt', descending: true)
          .snapshots()
          .asBroadcastStream(),
    );
  }

  Future<int> getCompletedTrainingCountForUser({
    required String institutionId,
    required String userId,
  }) async {
    final trainingsSnapshot = await _institutionTrainingsRef(
      institutionId,
    ).get();
    if (trainingsSnapshot.docs.isEmpty) {
      return 0;
    }

    final completionChecks = trainingsSnapshot.docs.map((doc) async {
      final data = doc.data();
      final type = (data['type'] ?? '').toString();

      if (type == TrainingType.video.name) {
        final progressDoc = await doc.reference
            .collection('progress')
            .doc(userId)
            .get();
        return (progressDoc.data()?['watched'] as bool?) == true ? 1 : 0;
      }

      if (type == TrainingType.scheduled.name) {
        final attendanceDoc = await doc.reference
            .collection('attendance')
            .doc(userId)
            .get();
        return (attendanceDoc.data()?['attended'] as bool?) == true ? 1 : 0;
      }

      return 0;
    });

    final counts = await Future.wait(completionChecks);
    return counts.fold<int>(0, (total, item) => total + item);
  }
}
