import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Tipos de documentos para verificación de instituciones
enum DocumentType {
  rectorIdCard,
  appointmentAct,
  chamberOfCommerce,
  rut;

  String get displayName {
    switch (this) {
      case DocumentType.rectorIdCard:
        return 'Cédula del Rector';
      case DocumentType.appointmentAct:
        return 'Acta de Posesión';
      case DocumentType.chamberOfCommerce:
        return 'Cámara de Comercio';
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

/// Resultado de selección de archivo
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
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Extensiones permitidas para documentos
  static const List<String> allowedExtensions = ['pdf', 'jpg', 'jpeg', 'png'];

  /// Tamaño máximo de archivo (5 MB)
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

      // Validar tamaño
      if (file.size > maxFileSizeBytes) {
        throw DocumentUploadException(
          code: 'file-too-large',
          message: 'El archivo excede el tamaño máximo de 5 MB.',
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
    if (!file.isValid) {
      throw DocumentUploadException(
        code: 'invalid-file',
        message: 'El archivo seleccionado no es válido.',
      );
    }

    final fileName = '${documentType.fileName}.${file.extension}';
    final storagePath = 'institutions/$nit/documents/$fileName';
    final ref = _storage.ref().child(storagePath);

    try {
      UploadTask uploadTask;

      if (file.bytes != null) {
        // Web: usar bytes
        uploadTask = ref.putData(
          file.bytes!,
          SettableMetadata(
            contentType: _getContentType(file.extension),
            customMetadata: {
              'documentType': documentType.name,
              'originalName': file.name,
              'uploadedAt': DateTime.now().toIso8601String(),
            },
          ),
        );
      } else if (file.path != null) {
        // Mobile: usar path
        uploadTask = ref.putFile(
          File(file.path!),
          SettableMetadata(
            contentType: _getContentType(file.extension),
            customMetadata: {
              'documentType': documentType.name,
              'originalName': file.name,
              'uploadedAt': DateTime.now().toIso8601String(),
            },
          ),
        );
      } else {
        throw DocumentUploadException(
          code: 'no-file-data',
          message: 'No se pudo obtener los datos del archivo.',
        );
      }

      // Escuchar progreso
      if (onProgress != null) {
        uploadTask.snapshotEvents.listen((snapshot) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          onProgress(progress);
        });
      }

      // Esperar a que termine
      await uploadTask;

      // Obtener URL de descarga
      final downloadUrl = await ref.getDownloadURL();
      return downloadUrl;
    } on FirebaseException catch (e) {
      throw DocumentUploadException(
        code: 'upload-error',
        message: 'Error al subir el documento: ${e.message}',
      );
    }
  }

  /// Sube múltiples documentos
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
}

/// Excepción para errores de carga de documentos
class DocumentUploadException implements Exception {
  final String code;
  final String message;

  DocumentUploadException({required this.code, required this.message});

  @override
  String toString() => 'DocumentUploadException: [$code] $message';
}
