import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'storage_service.dart';
import 'user_service.dart';

class InspectionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserService _userService = UserService();
  final StorageService _storageService = StorageService();

  final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>>
  _inspectionStreams = {};

  static const List<String> editableStatuses = <String>[
    'scheduled',
    'in_progress',
    'completed',
    'completed_with_findings',
    'cancelled',
  ];

  static String normalizeStatus(String raw) {
    final value = raw.trim().toLowerCase().replaceAll(' ', '_');
    if (value.isEmpty) return 'scheduled';
    if (value.contains('progress') || value.contains('curso')) {
      return 'in_progress';
    }
    if (value.contains('find') || value.contains('hallazgo')) {
      return 'completed_with_findings';
    }
    if (value.contains('complet') || value.contains('cerrad')) {
      return 'completed';
    }
    if (value.contains('cancel')) {
      return 'cancelled';
    }
    return value;
  }

  static String statusLabel(String raw) {
    switch (normalizeStatus(raw)) {
      case 'scheduled':
        return 'Programada';
      case 'in_progress':
        return 'En ejecucion';
      case 'completed':
        return 'Completada';
      case 'completed_with_findings':
        return 'Completada con hallazgos';
      case 'cancelled':
        return 'Cancelada';
      default:
        return raw.trim().isEmpty ? 'Programada' : raw.trim();
    }
  }

  Future<CurrentUserData> requireCurrentUserData() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No hay usuario autenticado.');
    }
    final data = await _userService.getCurrentUser();
    if (data == null) {
      throw Exception('No se encontro perfil de usuario.');
    }
    if ((data.institutionId ?? '').trim().isEmpty) {
      throw Exception('Tu cuenta no esta vinculada a una institucion.');
    }
    return data;
  }

  CollectionReference<Map<String, dynamic>> _institutionInspectionsRef(
    String institutionId,
  ) {
    return _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection('inspections');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamInspections({
    required String institutionId,
    required String role,
    required String uid,
  }) {
    final normalizedRole = role.trim();
    final key = '$institutionId::$normalizedRole::$uid';
    return _inspectionStreams.putIfAbsent(key, () {
      Query<Map<String, dynamic>> query = _institutionInspectionsRef(
        institutionId,
      );

      if (normalizedRole != 'admin_sst' && normalizedRole != 'admin') {
        query = query.where('assignedToUid', isEqualTo: uid);
      }

      return query
          .orderBy('scheduledAt', descending: true)
          .snapshots()
          .asBroadcastStream();
    });
  }

  Future<void> createInspection({
    required String institutionId,
    required String title,
    required String description,
    required String inspectionType,
    required String location,
    required DateTime scheduledAt,
    required DateTime dueAt,
    required String assignedToUid,
    required String assignedToName,
    required List<Map<String, dynamic>> checklist,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado.');

    final profile = await _userService.getUserData(user.uid);
    final role = (profile?['role'] ?? '').toString().trim();
    final displayName =
        (profile?['displayName'] ?? profile?['email'] ?? user.email ?? 'Admin')
            .toString()
            .trim();

    if (role != 'admin_sst' && role != 'admin') {
      throw Exception('No tienes permisos para crear inspecciones.');
    }

    if (checklist.isEmpty) {
      throw Exception('Agrega al menos un criterio de inspeccion.');
    }

    final now = Timestamp.now();
    final ref = _institutionInspectionsRef(institutionId).doc();
    final payload = <String, dynamic>{
      'id': ref.id,
      'institutionId': institutionId,
      'title': title.trim(),
      'description': description.trim(),
      'inspectionType': inspectionType.trim(),
      'location': location.trim(),
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'dueAt': Timestamp.fromDate(dueAt),
      'assignedToUid': assignedToUid.trim(),
      'assignedToName': assignedToName.trim(),
      'createdBy': user.uid,
      'createdByName': displayName,
      'createdAt': now,
      'updatedAt': now,
      'status': 'scheduled',
      'checklist': checklist,
      'completion': <String, dynamic>{
        'totalItems': checklist.length,
        'completedItems': 0,
        'failedItems': 0,
        'naItems': 0,
      },
      'result': null,
      'statusHistory': <Map<String, dynamic>>[
        <String, dynamic>{
          'status': 'scheduled',
          'changedAt': now,
          'changedBy': user.uid,
          'note': 'Inspeccion creada',
        },
      ],
    };

    await ref.set(payload);
  }

  Future<void> updateInspection({
    required String institutionId,
    required String inspectionId,
    required String title,
    required String description,
    required String inspectionType,
    required String location,
    required DateTime scheduledAt,
    required DateTime dueAt,
    required String assignedToUid,
    required String assignedToName,
    required List<Map<String, dynamic>> checklist,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado.');

    if (checklist.isEmpty) {
      throw Exception('Agrega al menos un criterio de inspeccion.');
    }

    final ref = _institutionInspectionsRef(institutionId).doc(inspectionId);
    final snap = await ref.get();
    if (!snap.exists) {
      throw Exception('La inspeccion no existe o fue eliminada.');
    }

    final status = normalizeStatus((snap.data()?['status'] ?? '').toString());
    if (status == 'completed' ||
        status == 'completed_with_findings' ||
        status == 'cancelled') {
      throw Exception(
        'No puedes editar una inspeccion completada o cancelada.',
      );
    }

    await ref.update({
      'title': title.trim(),
      'description': description.trim(),
      'inspectionType': inspectionType.trim(),
      'location': location.trim(),
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'dueAt': Timestamp.fromDate(dueAt),
      'assignedToUid': assignedToUid.trim(),
      'assignedToName': assignedToName.trim(),
      'checklist': checklist,
      'completion.totalItems': checklist.length,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> cancelInspection({
    required String institutionId,
    required String inspectionId,
    String note = '',
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado.');

    final now = Timestamp.now();
    await _institutionInspectionsRef(institutionId).doc(inspectionId).update({
      'status': 'cancelled',
      'updatedAt': now,
      'cancelledAt': now,
      'cancelledBy': user.uid,
      'cancellationNote': note.trim().isEmpty ? null : note.trim(),
      'statusHistory': FieldValue.arrayUnion([
        <String, dynamic>{
          'status': 'cancelled',
          'changedAt': now,
          'changedBy': user.uid,
          'note': note.trim().isEmpty ? 'Inspeccion cancelada' : note.trim(),
        },
      ]),
    });
  }

  Future<void> startInspection({
    required String institutionId,
    required String inspectionId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado.');

    final ref = _institutionInspectionsRef(institutionId).doc(inspectionId);
    final snap = await ref.get();
    if (!snap.exists) {
      throw Exception('La inspeccion no existe o fue eliminada.');
    }
    final status = normalizeStatus((snap.data()?['status'] ?? '').toString());
    if (status == 'cancelled' ||
        status == 'completed' ||
        status == 'completed_with_findings') {
      throw Exception('Esta inspeccion no puede cambiarse a en ejecucion.');
    }

    final now = Timestamp.now();
    await ref.update({
      'status': 'in_progress',
      'updatedAt': now,
      'statusHistory': FieldValue.arrayUnion([
        <String, dynamic>{
          'status': 'in_progress',
          'changedAt': now,
          'changedBy': user.uid,
          'note': 'Inspeccion iniciada',
        },
      ]),
    });
  }

  Future<String?> submitInspectionResult({
    required String institutionId,
    required String inspectionId,
    required List<Map<String, dynamic>> itemResults,
    required String generalNote,
    required List<ReportAttachmentInput> evidences,
    void Function(double progress)? onUploadProgress,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado.');

    if (itemResults.isEmpty) {
      throw Exception('Debes completar los criterios de inspeccion.');
    }

    final userData = await _userService.getUserData(user.uid);
    final displayName =
        (userData?['displayName'] ??
                userData?['email'] ??
                user.email ??
                'Usuario')
            .toString()
            .trim();

    List<UploadedAttachment> uploaded = const <UploadedAttachment>[];
    String? uploadWarning;
    if (evidences.isNotEmpty) {
      try {
        uploaded = await _storageService.uploadInspectionAttachments(
          institutionId: institutionId,
          inspectionId: inspectionId,
          attachments: evidences,
          onProgress: onUploadProgress,
        );
      } catch (e) {
        final message = e.toString().replaceAll('\n', ' ').trim();
        uploadWarning = message.length > 280
            ? '${message.substring(0, 280)}...'
            : message;
        onUploadProgress?.call(1);
      }
    }

    int completedItems = 0;
    int failedItems = 0;
    int naItems = 0;

    for (final item in itemResults) {
      final result = (item['result'] ?? '').toString().trim();
      if (result == 'cumple') {
        completedItems += 1;
      } else if (result == 'no_cumple') {
        failedItems += 1;
      } else if (result == 'no_aplica') {
        naItems += 1;
      }
    }

    final now = Timestamp.now();
    final status = failedItems > 0 ? 'completed_with_findings' : 'completed';
    final completedNote = failedItems > 0
        ? 'Inspeccion completada con hallazgos'
        : 'Inspeccion completada sin hallazgos';
    final statusNote = uploadWarning == null
        ? completedNote
        : '$completedNote (evidencias pendientes por error de subida)';

    await _institutionInspectionsRef(institutionId).doc(inspectionId).update({
      'status': status,
      'updatedAt': now,
      'completedAt': now,
      'completion': <String, dynamic>{
        'totalItems': itemResults.length,
        'completedItems': completedItems,
        'failedItems': failedItems,
        'naItems': naItems,
      },
      'result': <String, dynamic>{
        'submittedByUid': user.uid,
        'submittedByName': displayName,
        'submittedAt': now,
        'generalNote': generalNote.trim(),
        'items': itemResults,
        'evidences': uploaded.map((e) => e.toMap()).toList(),
        'evidencesUploadPending': uploadWarning != null,
        'evidencesUploadWarning': uploadWarning,
      },
      'statusHistory': FieldValue.arrayUnion([
        <String, dynamic>{
          'status': status,
          'changedAt': now,
          'changedBy': user.uid,
          'note': statusNote,
        },
      ]),
    });

    return uploadWarning;
  }
}
