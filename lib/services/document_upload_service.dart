import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../firebase_options.dart';

/// Tipos de documentos para verificacion de instituciones
enum DocumentType {
  rectorIdCard,
  appointmentAct,
  chamberOfCommerce,
  rut;

  String get displayName {
    switch (this) {
      case DocumentType.rectorIdCard:
        return 'Cedula del Rector';
      case DocumentType.appointmentAct:
        return 'Acta de Posesion';
      case DocumentType.chamberOfCommerce:
        return 'Camara de Comercio';
      case DocumentType.rut:
        return 'RUT';
    }
  }

  String get fileName {
    switch (this) {
      case DocumentType.rectorIdCard:
        return 'cedula_rector';
      case DocumentType.appointmentAct:
        return 'acta_posesion';
      case DocumentType.chamberOfCommerce:
        return 'camara_comercio';
      case DocumentType.rut:
        return 'rut';
    }
  }
}

/// Resultado de seleccion de archivo
class SelectedFile {
  final String name;
  final String? path;
  final Uint8List? bytes;
  final String extension;

  SelectedFile({
    required this.name,
    this.path,
    this.bytes,
    required this.extension,
  });

  bool get isValid => path != null || bytes != null;
}

/// Servicio para manejar carga de documentos a Firebase Storage
class DocumentUploadService {
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(
    app: Firebase.app(),
    bucket: _normalizedBucket,
  );

  static String get _normalizedBucket {
    final raw = (DefaultFirebaseOptions.currentPlatform.storageBucket ?? '')
        .trim();
    if (raw.startsWith('gs://')) {
      return raw;
    }
    return 'gs://$raw';
  }

  /// Extensiones permitidas para documentos
  static const List<String> allowedExtensions = ['pdf', 'jpg', 'jpeg', 'png'];

  /// Tamano maximo de archivo (5 MB)
  static const int maxFileSizeBytes = 5 * 1024 * 1024;

  /// Selecciona un archivo usando file_picker
  Future<SelectedFile?> pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        withData: kIsWeb, // Solo cargar bytes en web
      );

      if (result == null || result.files.isEmpty) {
        return null;
      }

      final file = result.files.first;

      // Validar tamano
      if (file.size > maxFileSizeBytes) {
        throw DocumentUploadException(
          code: 'file-too-large',
          message: 'El archivo excede el tamano maximo de 5 MB.',
        );
      }

      return SelectedFile(
        name: file.name,
        path: file.path,
        bytes: file.bytes,
        extension: file.extension ?? 'pdf',
      );
    } catch (e) {
      if (e is DocumentUploadException) rethrow;
      throw DocumentUploadException(
        code: 'pick-error',
        message: 'Error al seleccionar el archivo.',
      );
    }
  }

  /// Sube un documento a Firebase Storage
  /// Ruta: institutions/{nit}/documents/{documentType}.{extension}
  Future<String> uploadDocument({
    required String nit,
    required DocumentType documentType,
    required SelectedFile file,
    void Function(double progress)? onProgress,
  }) async {
    final auth = FirebaseAuth.instance;
    final currentUser = auth.currentUser;
    final currentUid = currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      throw DocumentUploadException(
        code: 'unauthenticated',
        message:
            'No hay una sesion activa para subir documentos. Inicia sesion y vuelve a intentar.',
      );
    }

    // Fuerza refresco de token para evitar rechazos transitorios al crear cuenta
    // e inmediatamente intentar subir evidencias/documentos.
    await currentUser!.getIdToken(true);

    if (!file.isValid) {
      throw DocumentUploadException(
        code: 'invalid-file',
        message: 'El archivo seleccionado no es valido.',
      );
    }

    final extension = file.extension.trim().toLowerCase();
    if (!allowedExtensions.contains(extension)) {
      throw DocumentUploadException(
        code: 'invalid-extension',
        message:
            'Formato no permitido (${file.extension}). Solo se aceptan PDF, JPG, JPEG o PNG.',
      );
    }

    final fileName = '${documentType.fileName}.$extension';
    final storagePath = 'institutions/$nit/documents/$fileName';
    final ref = _storage.ref().child(storagePath);

    try {
      return await _executeUpload(
        ref: ref,
        file: file,
        extension: extension,
        documentType: documentType,
        onProgress: onProgress,
      );
    } on FirebaseException catch (e) {
      // Reintento de una sola vez si la sesion/token todavia no se propago.
      if (e.code == 'unauthorized' || e.code == 'permission-denied') {
        try {
          await auth.currentUser?.getIdToken(true);
          return await _executeUpload(
            ref: ref,
            file: file,
            extension: extension,
            documentType: documentType,
            onProgress: onProgress,
          );
        } on FirebaseException catch (_) {
          // continua al throw detallado original.
        }
      }
      throw DocumentUploadException(
        code: 'upload-error',
        message:
            'Error al subir el documento (${e.code}). bucket=${_storage.bucket}, ruta=$storagePath, uid=$currentUid. ${e.message ?? ''} Si tienes App Check forzado en Storage, desactiva enforcement en pruebas o configura App Check.',
      );
    }
  }

  /// Sube multiples documentos
  Future<Map<DocumentType, String>> uploadMultipleDocuments({
    required String nit,
    required Map<DocumentType, SelectedFile> files,
    void Function(DocumentType type, double progress)? onProgress,
  }) async {
    final results = <DocumentType, String>{};

    for (final entry in files.entries) {
      final url = await uploadDocument(
        nit: nit,
        documentType: entry.key,
        file: entry.value,
        onProgress: onProgress != null
            ? (progress) => onProgress(entry.key, progress)
            : null,
      );
      results[entry.key] = url;
    }

    return results;
  }

  /// Elimina un documento de Storage
  Future<void> deleteDocument({
    required String nit,
    required DocumentType documentType,
    required String extension,
  }) async {
    final fileName = '${documentType.fileName}.$extension';
    final storagePath = 'institutions/$nit/documents/$fileName';
    final ref = _storage.ref().child(storagePath);

    try {
      await ref.delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') {
        throw DocumentUploadException(
          code: 'delete-error',
          message: 'Error al eliminar el documento.',
        );
      }
    }
  }

  String _getContentType(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }

  Future<String> _executeUpload({
    required Reference ref,
    required SelectedFile file,
    required String extension,
    required DocumentType documentType,
    void Function(double progress)? onProgress,
  }) async {
    UploadTask uploadTask;
    final metadata = SettableMetadata(
      contentType: _getContentType(extension),
      customMetadata: {
        'documentType': documentType.name,
        'originalName': file.name,
        'uploadedAt': DateTime.now().toIso8601String(),
      },
    );

    if (file.bytes != null) {
      uploadTask = ref.putData(file.bytes!, metadata);
    } else if (file.path != null) {
      uploadTask = ref.putFile(File(file.path!), metadata);
    } else {
      throw DocumentUploadException(
        code: 'no-file-data',
        message: 'No se pudo obtener los datos del archivo.',
      );
    }

    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((snapshot) {
        final total = snapshot.totalBytes;
        if (total <= 0) return;
        final progress = snapshot.bytesTransferred / total;
        onProgress(progress);
      });
    }

    await uploadTask;
    return ref.getDownloadURL();
  }
}

/// Excepcion para errores de carga de documentos
class DocumentUploadException implements Exception {
  final String code;
  final String message;

  DocumentUploadException({required this.code, required this.message});

  @override
  String toString() => 'DocumentUploadException: [$code] $message';
}
