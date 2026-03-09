import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../models/report_model.dart';
import 'storage_service.dart';
import 'user_service.dart';

class ReportSubmissionResult {
  final String reportId;
  final String caseNumber;
  final bool attachmentsPending;

  ReportSubmissionResult({
    required this.reportId,
    required this.caseNumber,
    this.attachmentsPending = false,
  });
}

class EventService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final StorageService _storageService = StorageService();
  final UserService _userService = UserService();
  static const List<String> manageableStatuses = <String>[
    'reportado',
    'en_revision',
    'en_proceso',
    'cerrado',
    'rechazado',
  ];

  static const Set<String> _closedStatuses = <String>{'cerrado'};

  static String canonicalStatus(String raw) {
    final normalized = raw.trim().toLowerCase().replaceAll(' ', '_');
    if (normalized.isEmpty) return '';
    if (normalized.contains('revisi')) return 'en_revision';
    if (normalized.contains('proceso')) return 'en_proceso';
    if (normalized.contains('solucion')) return 'cerrado';
    if (normalized.contains('cerrad')) return 'cerrado';
    if (normalized.contains('rechaz')) return 'rechazado';
    if (normalized.contains('report')) return 'reportado';
    return normalized;
  }

  static String statusLabel(String raw) {
    switch (canonicalStatus(raw)) {
      case 'reportado':
        return 'Reportado';
      case 'en_revision':
        return 'En revisión';
      case 'en_proceso':
        return 'En proceso';
      case 'cerrado':
        return 'Cerrado';
      case 'rechazado':
        return 'Rechazado';
      default:
        final value = raw.trim();
        return value.isEmpty ? 'Reportado' : value;
    }
  }

  /// Obtiene el stream de eventos filtrados por institución
  /// Requerido para cumplir con las reglas de seguridad de Firestore
  Stream<QuerySnapshot> getEventsStream(String institutionId) {
    return _firestore
        .collection('eventos')
        .where('institutionId', isEqualTo: institutionId)
        .orderBy('fechaReporte', descending: true)
        .snapshots();
  }

  /// Obtiene eventos de una institución (Future)
  Future<QuerySnapshot> getEvents(String institutionId) {
    return _firestore
        .collection('eventos')
        .where('institutionId', isEqualTo: institutionId)
        .orderBy('fechaReporte', descending: true)
        .get();
  }

  /// Obtiene el institutionId del usuario actual
  Future<String?> getCurrentUserInstitutionId() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return await _userService.getUserInstitutionId(user.uid);
  }

  Future<List<String>> getRecentPlaceSuggestionsForCurrentInstitution() async {
    final user = _auth.currentUser;
    if (user == null) return [];
    final institutionId = await _userService.getUserInstitutionId(user.uid);
    if (institutionId == null) return [];

    final snapshot = await _firestore
        .collection('reports')
        .where('institutionId', isEqualTo: institutionId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();

    final uniquePlaces = <String, String>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final location = data['location'] as Map<String, dynamic>?;
      final placeName = (location?['placeName'] ?? '').toString().trim();
      final normalized = (location?['placeNormalized'] ?? '').toString().trim();
      if (placeName.isEmpty || normalized.isEmpty) continue;
      uniquePlaces.putIfAbsent(normalized, () => placeName);
      if (uniquePlaces.length >= 10) break;
    }
    return uniquePlaces.values.take(10).toList();
  }

  Future<void> addEvent(
    String tipo,
    String descripcion,
    List<XFile> images, {
    List<XFile> videos = const [],
    String? location,
    String? category,
    String? severity,
    DateTime? eventDateTime,
    double? latitude,
    double? longitude,
    String? gpsAddress,
  }) async {
    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('No hay un usuario autenticado.');
      }

      // Obtener institutionId del usuario actual
      final institutionId = await _userService.getUserInstitutionId(
        currentUser.uid,
      );
      if (institutionId == null) {
        throw Exception('El usuario no pertenece a ninguna institución.');
      }

      // Step 1: Create the document with institutionId for security rules
      final Map<String, dynamic> data = {
        'tipo': tipo,
        'descripcion': descripcion,
        'fechaReporte': Timestamp.now(),
        'estado': 'reportado',
        'reportadoPor_uid': currentUser.uid,
        'reportadoPor_email': currentUser.email,
        'institutionId': institutionId, // Requerido para reglas de seguridad
        'lugar': location,
        'categoria': category,
        'severidad': severity,
        'fotoUrls': [], // Initialize as an empty list
        'videoUrls': [], // Initialize as an empty list
      };

      if (eventDateTime != null) {
        data['fechaEvento'] = Timestamp.fromDate(eventDateTime);
      }

      if (latitude != null && longitude != null) {
        data['ubicacionGps'] = GeoPoint(latitude, longitude);
      }
      if (gpsAddress != null && gpsAddress.trim().isNotEmpty) {
        data['direccionGps'] = gpsAddress.trim();
      }

      DocumentReference docRef = await _firestore
          .collection('eventos')
          .add(data);

      // Step 2: Upload photos if there are any
      if (images.isNotEmpty) {
        // Call the storage service
        List<String> downloadUrls = await _storageService.uploadEventImages(
          images,
          docRef.id,
        );

        // Step 3: Update the document with the photo URLs
        await docRef.update({'fotoUrls': downloadUrls});
      }
      if (videos.isNotEmpty) {
        List<String> downloadUrls = await _storageService.uploadEventVideos(
          videos,
          docRef.id,
        );
        await docRef.update({'videoUrls': downloadUrls});
      }
    } on FirebaseException catch (e) {
      // Re-throw the exception to be handled by the UI
      throw Exception('Error al guardar el evento: ${e.message}');
    }
  }

  Future<ReportSubmissionResult> submitStructuredReport({
    required String eventType,
    required String reportType,
    required String severity,
    required Map<String, dynamic> location,
    required DateTime eventDateTime,
    required String description,
    required Map<String, dynamic> people,
    double? latitude,
    double? longitude,
    String? gpsAddress,
    required List<ReportAttachmentInput> attachments,
    void Function(double progress)? onUploadProgress,
  }) async {
    final User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('No hay un usuario autenticado.');
    }

    final institutionId = await _userService.getUserInstitutionId(
      currentUser.uid,
    );
    if (institutionId == null) {
      throw Exception('El usuario no pertenece a ninguna institución.');
    }

    final reportRef = _firestore.collection('reports').doc();
    final caseNumber = await _nextCaseNumber();
    final resolvedEventType = _resolveEventTypeForReportType(
      reportType: reportType,
      currentEventType: eventType,
    );
    final normalizedLocation = _normalizeLocation(
      location: location,
      latitude: latitude,
      longitude: longitude,
      gpsAddress: gpsAddress,
    );

    final statusEntry = ReportStatusEntry(
      status: 'reportado',
      changedAt: Timestamp.now(),
      changedBy: currentUser.uid,
      note: 'Reporte creado por usuario',
    );

    final report = ReportModel(
      id: reportRef.id,
      caseNumber: caseNumber,
      createdBy: currentUser.uid,
      createdByEmail: currentUser.email ?? '',
      institutionId: institutionId,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
      eventType: resolvedEventType,
      reportType: reportType,
      severity: severity,
      location: normalizedLocation,
      datetime: Timestamp.fromDate(eventDateTime),
      description: description,
      gps: (latitude != null && longitude != null)
          ? {
              'lat': latitude,
              'lng': longitude,
              if (gpsAddress != null && gpsAddress.trim().isNotEmpty)
                'address': gpsAddress.trim(),
            }
          : null,
      people: people,
      attachments: const [],
      status: 'reportado',
      statusHistory: [statusEntry],
    );

    await reportRef.set(report.toMap());
    await reportRef.update({
      'attachmentsPending': attachments.isNotEmpty,
      'pendingAttachments': attachments
          .map((e) => <String, dynamic>{'path': e.file.path, 'type': e.type})
          .toList(),
    });

    final legacyEventRef = _firestore.collection('eventos').doc(reportRef.id);
    await legacyEventRef.set({
      'tipo': resolvedEventType,
      'descripcion': description,
      'fechaReporte': Timestamp.now(),
      'fechaEvento': Timestamp.fromDate(eventDateTime),
      'estado': 'reportado',
      'reportadoPor_uid': currentUser.uid,
      'reportadoPor_email': currentUser.email,
      'institutionId': institutionId,
      'lugar': _legacyLocationLabel(normalizedLocation),
      'categoria': reportType,
      'severidad': severity,
      'fotoUrls': const <String>[],
      'videoUrls': const <String>[],
      if (latitude != null && longitude != null)
        'ubicacionGps': GeoPoint(latitude, longitude),
      if (gpsAddress != null && gpsAddress.trim().isNotEmpty)
        'direccionGps': gpsAddress.trim(),
      'reportId': reportRef.id,
      'caseNumber': caseNumber,
      'location': normalizedLocation,
      'people': people,
      'adjuntosPendientes': attachments.isNotEmpty,
    });

    List<UploadedAttachment> uploadedAttachments = const [];
    bool attachmentsPending = false;
    if (attachments.isNotEmpty) {
      try {
        uploadedAttachments = await _storageService.uploadReportAttachments(
          attachments,
          reportRef.id,
          onProgress: onUploadProgress,
        );
      } catch (_) {
        attachmentsPending = true;
        final pendingEntry = ReportStatusEntry(
          status: 'reportado',
          changedAt: Timestamp.now(),
          changedBy: currentUser.uid,
          note: 'Adjuntos pendientes',
        );
        await reportRef.update({
          'updatedAt': Timestamp.now(),
          'attachmentsPending': true,
          'statusHistory': FieldValue.arrayUnion([pendingEntry.toMap()]),
        });
        await legacyEventRef.update({'adjuntosPendientes': true});
      }
    }

    if (uploadedAttachments.isNotEmpty) {
      await reportRef.update({
        'attachments': uploadedAttachments.map((e) => e.toMap()).toList(),
        'updatedAt': Timestamp.now(),
        'attachmentsPending': false,
        'pendingAttachments': const <Map<String, dynamic>>[],
      });
      await legacyEventRef.update({
        'fotoUrls': uploadedAttachments
            .where((a) => a.type == 'image')
            .map((e) => e.url)
            .toList(),
        'videoUrls': uploadedAttachments
            .where((a) => a.type == 'video')
            .map((e) => e.url)
            .toList(),
        'adjuntosPendientes': false,
      });
    }

    return ReportSubmissionResult(
      reportId: reportRef.id,
      caseNumber: caseNumber,
      attachmentsPending: attachmentsPending,
    );
  }

  Future<bool> retryPendingAttachments({
    required String reportId,
    required List<ReportAttachmentInput> attachments,
    void Function(double progress)? onUploadProgress,
  }) async {
    if (attachments.isEmpty) {
      await _firestore.collection('reports').doc(reportId).update({
        'attachmentsPending': false,
        'updatedAt': Timestamp.now(),
        'pendingAttachments': const <Map<String, dynamic>>[],
      });
      await _firestore.collection('eventos').doc(reportId).set({
        'adjuntosPendientes': false,
      }, SetOptions(merge: true));
      onUploadProgress?.call(1);
      return true;
    }

    final currentUser = _auth.currentUser;
    final uploadedAttachments = await _storageService.uploadReportAttachments(
      attachments,
      reportId,
      onProgress: onUploadProgress,
    );

    await _firestore.collection('reports').doc(reportId).update({
      'attachments': uploadedAttachments.map((e) => e.toMap()).toList(),
      'updatedAt': Timestamp.now(),
      'attachmentsPending': false,
      'pendingAttachments': const <Map<String, dynamic>>[],
      if (currentUser != null)
        'statusHistory': FieldValue.arrayUnion([
          ReportStatusEntry(
            status: 'reportado',
            changedAt: Timestamp.now(),
            changedBy: currentUser.uid,
            note: 'Adjuntos sincronizados',
          ).toMap(),
        ]),
    });

    await _firestore.collection('eventos').doc(reportId).set({
      'fotoUrls': uploadedAttachments
          .where((a) => a.type == 'image')
          .map((e) => e.url)
          .toList(),
      'videoUrls': uploadedAttachments
          .where((a) => a.type == 'video')
          .map((e) => e.url)
          .toList(),
      'adjuntosPendientes': false,
    }, SetOptions(merge: true));

    return true;
  }

  Future<void> updateReportStatus({
    required String reportId,
    required String status,
    String? note,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('No hay un usuario autenticado.');
    }

    final normalizedStatus = canonicalStatus(status);
    if (normalizedStatus.isEmpty) {
      throw Exception('Debes seleccionar un estado.');
    }

    final now = Timestamp.now();
    final statusEntry = ReportStatusEntry(
      status: normalizedStatus,
      changedAt: now,
      changedBy: currentUser.uid,
      note: (note ?? '').trim(),
    );
    final isClosed = _closedStatuses.contains(normalizedStatus);

    final reportRef = _firestore.collection('reports').doc(reportId);
    final reportSnap = await reportRef.get();
    if (reportSnap.exists) {
      await reportRef.set({
        'status': normalizedStatus,
        'updatedAt': now,
        'closedAt': isClosed ? now : FieldValue.delete(),
        'statusHistory': FieldValue.arrayUnion([statusEntry.toMap()]),
      }, SetOptions(merge: true));
    }

    await _firestore.collection('eventos').doc(reportId).set({
      'estado': normalizedStatus,
      'fechaCierre': isClosed ? now : FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  Future<String> _nextCaseNumber() async {
    final counterRef = _firestore.collection('system').doc('counters');
    final number = await _firestore.runTransaction<int>((transaction) async {
      final snap = await transaction.get(counterRef);
      final current = (snap.data()?['reportCounter'] as int?) ?? 0;
      final next = current + 1;
      transaction.set(counterRef, {
        'reportCounter': next,
      }, SetOptions(merge: true));
      return next;
    });
    return 'SGSST-${number.toString().padLeft(6, '0')}';
  }

  String _legacyLocationLabel(Map<String, dynamic> location) {
    final placeName = (location['placeName'] ?? '').toString().trim();
    final reference = (location['reference'] ?? '').toString().trim();
    if (placeName.isEmpty) return 'No especificado';
    if (reference.isEmpty) return placeName;
    return '$placeName / $reference';
  }

  Map<String, dynamic> _normalizeLocation({
    required Map<String, dynamic> location,
    double? latitude,
    double? longitude,
    String? gpsAddress,
  }) {
    final placeName = (location['placeName'] ?? '')
        .toString()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    final placeNormalized = placeName.toLowerCase();
    final referenceRaw = (location['reference'] ?? '')
        .toString()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');

    return {
      'placeName': placeName,
      'placeNormalized': placeNormalized,
      'reference': referenceRaw.isEmpty ? null : referenceRaw,
      'gps': (latitude != null && longitude != null)
          ? {
              'lat': latitude,
              'lng': longitude,
              if (gpsAddress != null && gpsAddress.trim().isNotEmpty)
                'address': gpsAddress.trim(),
            }
          : null,
    };
  }

  String _resolveEventTypeForReportType({
    required String reportType,
    required String currentEventType,
  }) {
    switch (reportType) {
      case 'Accidente con lesion':
      case 'Accidente con lesión':
      case 'Emergencia / evento grave':
        return 'Accidente';
      case 'Condicion insegura':
      case 'Condición insegura':
      case 'Acto inseguro':
      case 'Incidente (casi accidente)':
      case 'Riesgo psicosocial':
        return 'Incidente';
      default:
        return currentEventType;
    }
  }
}
