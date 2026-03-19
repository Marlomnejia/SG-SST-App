import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/sst_document_model.dart';
import 'user_service.dart';

class SstDocumentService {
  static const int maxPdfSizeBytes = 10 * 1024 * 1024;
  static const Duration _uploadTimeout = Duration(seconds: 60);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final UserService _userService = UserService();
  final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>>
  _documentStreams = {};
  final Map<String, Stream<DocumentSnapshot<Map<String, dynamic>>>>
  _readStatusStreams = {};
  final Map<String, Stream<int>> _readCountStreams = {};

  Future<PlatformFile?> pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final file = result.files.first;
    _validatePdfFile(file);
    return file;
  }

  Future<String> requireInstitutionId() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No hay usuario autenticado.');
    }
    final institutionId = await _userService.getUserInstitutionId(user.uid);
    if (institutionId == null || institutionId.trim().isEmpty) {
      throw Exception('Usuario sin institucion asignada.');
    }
    return institutionId;
  }

  CollectionReference<Map<String, dynamic>> _documentsRef(
    String institutionId,
  ) {
    return _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection('documents');
  }

  CollectionReference<Map<String, dynamic>> _globalDocumentsRef() {
    return _firestore.collection('global_documents');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamDocumentsForAdmin({
    int limit = 100,
    bool isGlobal = false,
  }) {
    final userKey = _auth.currentUser?.uid ?? 'guest';
    final cacheKey = 'admin:$userKey:$isGlobal:$limit';
    if (_documentStreams.containsKey(cacheKey)) {
      return _documentStreams[cacheKey]!;
    }

    late final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
    if (isGlobal) {
      stream = _globalDocumentsRef()
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .asBroadcastStream();
    } else {
      stream = Stream.fromFuture(requireInstitutionId())
          .asyncExpand(
            (institutionId) => _documentsRef(
              institutionId,
            ).orderBy('createdAt', descending: true).limit(limit).snapshots(),
          )
          .asBroadcastStream();
    }
    _documentStreams[cacheKey] = stream;
    return stream;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamPublishedDocumentsForUser({
    int limit = 100,
  }) {
    return streamPublishedInstitutionDocuments(limit: limit);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>
  streamPublishedInstitutionDocuments({int limit = 100}) {
    final userKey = _auth.currentUser?.uid ?? 'guest';
    final cacheKey = 'published-inst:$userKey:$limit';
    if (_documentStreams.containsKey(cacheKey)) {
      return _documentStreams[cacheKey]!;
    }
    final stream = Stream.fromFuture(requireInstitutionId())
        .asyncExpand(
          (institutionId) => _documentsRef(
            institutionId,
          ).where('isPublished', isEqualTo: true).limit(limit).snapshots(),
        )
        .asBroadcastStream();
    _documentStreams[cacheKey] = stream;
    return stream;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamPublishedGlobalDocuments({
    int limit = 100,
  }) {
    final cacheKey = 'published-global:$limit';
    return _documentStreams.putIfAbsent(
      cacheKey,
      () => _globalDocumentsRef()
          .where('isPublished', isEqualTo: true)
          .limit(limit)
          .snapshots()
          .asBroadcastStream(),
    );
  }

  Future<DocumentReference<Map<String, dynamic>>> createDocument({
    required String title,
    required String description,
    required SstDocumentCategory category,
    required PlatformFile file,
    required bool isPublished,
    required bool isRequired,
    bool isGlobal = false,
    void Function(double progress)? onProgress,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado.');
    _validateRequiredText(title, 'titulo');
    _validateRequiredText(description, 'descripcion');
    _validatePdfFile(file);

    final String? institutionId = isGlobal
        ? null
        : await requireInstitutionId();
    final docRef = isGlobal
        ? _globalDocumentsRef().doc()
        : _documentsRef(institutionId!).doc();
    final storagePath = _buildStoragePath(
      institutionId: institutionId,
      documentId: docRef.id,
      originalFileName: file.name,
      isGlobal: isGlobal,
    );

    final fileUrl = await _uploadPdf(
      file: file,
      storagePath: storagePath,
      onProgress: onProgress,
    );

    final payload = SstDocumentModel(
      id: docRef.id,
      title: title.trim(),
      description: description.trim(),
      category: category.firestoreValue,
      fileUrl: fileUrl,
      fileName: file.name,
      fileSizeKb: (file.size / 1024).ceil(),
      isPublished: isPublished,
      isRequired: isRequired,
      createdAt: null,
      publishedAt: null,
      uploadedBy: user.uid,
      storagePath: storagePath,
    ).toMap();
    if (isPublished) {
      payload['publishedAt'] = FieldValue.serverTimestamp();
    }

    await docRef.set(payload);
    return docRef;
  }

  Future<void> updateDocument({
    required String documentId,
    required String title,
    required String description,
    required SstDocumentCategory category,
    required bool isPublished,
    required bool isRequired,
    bool isGlobal = false,
    PlatformFile? replacementFile,
    void Function(double progress)? onProgress,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado.');
    _validateRequiredText(title, 'titulo');
    _validateRequiredText(description, 'descripcion');

    final String? institutionId = isGlobal
        ? null
        : await requireInstitutionId();
    final docRef = isGlobal
        ? _globalDocumentsRef().doc(documentId)
        : _documentsRef(institutionId!).doc(documentId);
    final currentDoc = await docRef.get();
    if (!currentDoc.exists) {
      throw Exception('El documento no existe.');
    }

    final updates = <String, dynamic>{
      'title': title.trim(),
      'description': description.trim(),
      'category': category.firestoreValue,
      'isPublished': isPublished,
      'isRequired': isRequired,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final currentData = currentDoc.data() ?? const <String, dynamic>{};
    final existingPublishedAt = currentData['publishedAt'];
    if (isPublished && existingPublishedAt == null) {
      updates['publishedAt'] = FieldValue.serverTimestamp();
    }

    if (replacementFile != null) {
      _validatePdfFile(replacementFile);
      final oldPath = (currentDoc.data()?['storagePath'] ?? '').toString();
      final newStoragePath = _buildStoragePath(
        institutionId: institutionId,
        documentId: documentId,
        originalFileName: replacementFile.name,
        isGlobal: isGlobal,
      );
      final fileUrl = await _uploadPdf(
        file: replacementFile,
        storagePath: newStoragePath,
        onProgress: onProgress,
      );

      updates.addAll({
        'fileUrl': fileUrl,
        'fileName': replacementFile.name,
        'fileSizeKb': (replacementFile.size / 1024).ceil(),
        'storagePath': newStoragePath,
      });

      if (oldPath.isNotEmpty && oldPath != newStoragePath) {
        await _deleteStoragePathSilently(oldPath);
      }
    }

    await docRef.update(updates);
  }

  Future<void> setDocumentPublished({
    required String documentId,
    required bool isPublished,
    bool isGlobal = false,
  }) async {
    final docRef = isGlobal
        ? _globalDocumentsRef().doc(documentId)
        : _documentsRef(await requireInstitutionId()).doc(documentId);
    final currentDoc = await docRef.get();
    final currentData = currentDoc.data() ?? const <String, dynamic>{};
    final updates = <String, dynamic>{
      'isPublished': isPublished,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (isPublished && currentData['publishedAt'] == null) {
      updates['publishedAt'] = FieldValue.serverTimestamp();
    }
    await docRef.update(updates);
  }

  Future<void> deleteDocument(
    String documentId, {
    bool isGlobal = false,
  }) async {
    final docRef = isGlobal
        ? _globalDocumentsRef().doc(documentId)
        : _documentsRef(await requireInstitutionId()).doc(documentId);
    final snap = await docRef.get();
    if (!snap.exists) return;

    final storagePath = (snap.data()?['storagePath'] ?? '').toString();
    if (storagePath.isNotEmpty) {
      await _deleteStoragePathSilently(storagePath);
    }
    await docRef.delete();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamMyReadStatus(
    String documentId, {
    required bool isGlobal,
  }) {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    final cacheKey = 'read:${user.uid}:$isGlobal:$documentId';
    if (_readStatusStreams.containsKey(cacheKey)) {
      return _readStatusStreams[cacheKey]!;
    }
    late final Stream<DocumentSnapshot<Map<String, dynamic>>> stream;
    if (isGlobal) {
      stream = _globalDocumentsRef()
          .doc(documentId)
          .collection('reads')
          .doc(user.uid)
          .snapshots()
          .asBroadcastStream();
    } else {
      stream = Stream.fromFuture(requireInstitutionId())
          .asyncExpand(
            (institutionId) => _documentsRef(
              institutionId,
            ).doc(documentId).collection('reads').doc(user.uid).snapshots(),
          )
          .asBroadcastStream();
    }
    _readStatusStreams[cacheKey] = stream;
    return stream;
  }

  Future<void> markAsRead(String documentId, {required bool isGlobal}) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado.');
    final docRef = isGlobal
        ? _globalDocumentsRef().doc(documentId)
        : _documentsRef(await requireInstitutionId()).doc(documentId);
    await docRef.collection('reads').doc(user.uid).set({
      'read': true,
      'readAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<int> streamReadCount(String documentId, {required bool isGlobal}) {
    final userKey = _auth.currentUser?.uid ?? 'guest';
    final cacheKey = 'count:$userKey:$isGlobal:$documentId';
    if (_readCountStreams.containsKey(cacheKey)) {
      return _readCountStreams[cacheKey]!;
    }
    late final Stream<int> stream;
    if (isGlobal) {
      stream = _globalDocumentsRef()
          .doc(documentId)
          .collection('reads')
          .where('read', isEqualTo: true)
          .snapshots()
          .map((snapshot) => snapshot.size)
          .asBroadcastStream();
    } else {
      stream = Stream.fromFuture(requireInstitutionId())
          .asyncExpand(
            (institutionId) => _documentsRef(institutionId)
                .doc(documentId)
                .collection('reads')
                .where('read', isEqualTo: true)
                .snapshots(),
          )
          .map((snapshot) => snapshot.size)
          .asBroadcastStream();
    }
    _readCountStreams[cacheKey] = stream;
    return stream;
  }

  Future<int> getReadDocumentCountForUser({
    required String userId,
    String? institutionId,
  }) async {
    Future<int> countReadsForDocs(
      QuerySnapshot<Map<String, dynamic>> docsSnapshot,
    ) async {
      if (docsSnapshot.docs.isEmpty) {
        return 0;
      }

      final checks = docsSnapshot.docs.map((doc) async {
        final readDoc = await doc.reference
            .collection('reads')
            .doc(userId)
            .get();
        return (readDoc.data()?['read'] as bool?) == true ? 1 : 0;
      });

      final results = await Future.wait(checks);
      return results.fold<int>(0, (total, item) => total + item);
    }

    final normalizedInstitutionId = institutionId?.trim();
    var total = 0;

    if (normalizedInstitutionId != null && normalizedInstitutionId.isNotEmpty) {
      final institutionDocs = await _documentsRef(
        normalizedInstitutionId,
      ).get();
      total += await countReadsForDocs(institutionDocs);
    }

    final globalDocs = await _globalDocumentsRef().get();
    total += await countReadsForDocs(globalDocs);

    return total;
  }

  Future<String> _uploadPdf({
    required PlatformFile file,
    required String storagePath,
    void Function(double progress)? onProgress,
  }) async {
    final ref = _storage.ref().child(storagePath);
    late UploadTask task;
    StreamSubscription<TaskSnapshot>? progressSubscription;

    if (kIsWeb) {
      if (file.bytes == null) {
        throw Exception('No se pudo leer el PDF seleccionado.');
      }
      task = ref.putData(
        file.bytes!,
        SettableMetadata(
          contentType: 'application/pdf',
          customMetadata: {
            'originalName': file.name,
            'uploadedAt': DateTime.now().toIso8601String(),
          },
        ),
      );
    } else {
      final filePath = file.path;
      if (filePath == null || filePath.trim().isEmpty) {
        throw Exception('No se pudo leer el archivo local.');
      }
      task = ref.putFile(
        File(filePath),
        SettableMetadata(
          contentType: 'application/pdf',
          customMetadata: {
            'originalName': file.name,
            'uploadedAt': DateTime.now().toIso8601String(),
          },
        ),
      );
    }

    if (onProgress != null) {
      progressSubscription = task.snapshotEvents.listen((snapshot) {
        final total = snapshot.totalBytes;
        if (total <= 0) {
          onProgress(0);
          return;
        }
        onProgress(snapshot.bytesTransferred / total);
      });
    }
    try {
      await task.timeout(_uploadTimeout);
      onProgress?.call(1);
      return await ref.getDownloadURL().timeout(_uploadTimeout);
    } on FirebaseException catch (e) {
      throw Exception(
        'Error de Storage (${e.code}): ${e.message ?? 'No se pudo subir el PDF.'}',
      );
    } on TimeoutException {
      try {
        await task.cancel().timeout(const Duration(seconds: 5));
      } catch (_) {}
      throw Exception(
        'La subida del PDF excedio el tiempo limite. Verifica la conexion e intenta nuevamente.',
      );
    } finally {
      await progressSubscription?.cancel();
    }
  }

  String _buildStoragePath({
    String? institutionId,
    required String documentId,
    required String originalFileName,
    bool isGlobal = false,
  }) {
    final safeName = _safeFileName(originalFileName);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    if (isGlobal) {
      return 'global_sst_documents/$documentId/${stamp}_$safeName';
    }
    return 'institutions/$institutionId/sst_documents/$documentId/${stamp}_$safeName';
  }

  String _safeFileName(String name) {
    return name.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  void _validateRequiredText(String value, String field) {
    if (value.trim().isEmpty) {
      throw Exception('El campo $field es obligatorio.');
    }
  }

  void _validatePdfFile(PlatformFile file) {
    final extension = (file.extension ?? '').toLowerCase();
    final lowerName = file.name.toLowerCase();
    final isPdf = extension == 'pdf' || lowerName.endsWith('.pdf');
    if (!isPdf) {
      throw Exception('Solo se permiten archivos PDF.');
    }
    if (file.size <= 0) {
      throw Exception('El archivo seleccionado esta vacio.');
    }
    if (file.size > maxPdfSizeBytes) {
      throw Exception('El PDF supera el maximo de 10 MB.');
    }
  }

  Future<void> _deleteStoragePathSilently(String path) async {
    try {
      await _storage.ref().child(path).delete();
    } catch (_) {
      // Ignorar errores para evitar bloquear flujos de edicion/eliminacion.
    }
  }
}
