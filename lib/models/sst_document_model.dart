import 'package:cloud_firestore/cloud_firestore.dart';

enum SstDocumentCategory {
  normativa,
  procedimiento,
  manual,
  formato;

  String get firestoreValue {
    switch (this) {
      case SstDocumentCategory.normativa:
        return 'Normativa';
      case SstDocumentCategory.procedimiento:
        return 'Procedimiento';
      case SstDocumentCategory.manual:
        return 'Manual';
      case SstDocumentCategory.formato:
        return 'Formato';
    }
  }

  String get label => firestoreValue;

  static SstDocumentCategory fromValue(String value) {
    final normalized = value.trim().toLowerCase();
    for (final category in SstDocumentCategory.values) {
      if (category.firestoreValue.toLowerCase() == normalized) {
        return category;
      }
    }
    return SstDocumentCategory.normativa;
  }
}

class SstDocumentModel {
  final String id;
  final String title;
  final String description;
  final String category;
  final String fileUrl;
  final String fileName;
  final int fileSizeKb;
  final bool isPublished;
  final bool isRequired;
  final Timestamp? createdAt;
  final Timestamp? publishedAt;
  final String uploadedBy;
  final String? storagePath;

  const SstDocumentModel({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.fileUrl,
    required this.fileName,
    required this.fileSizeKb,
    required this.isPublished,
    required this.isRequired,
    required this.createdAt,
    required this.publishedAt,
    required this.uploadedBy,
    this.storagePath,
  });

  factory SstDocumentModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return SstDocumentModel(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      category: (data['category'] ?? 'Normativa').toString(),
      fileUrl: (data['fileUrl'] ?? '').toString(),
      fileName: (data['fileName'] ?? '').toString(),
      fileSizeKb: _toInt(data['fileSizeKb']),
      isPublished: data['isPublished'] == true,
      isRequired: data['isRequired'] == true,
      createdAt: data['createdAt'] as Timestamp?,
      publishedAt: data['publishedAt'] as Timestamp?,
      uploadedBy: (data['uploadedBy'] ?? '').toString(),
      storagePath: (data['storagePath'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title.trim(),
      'description': description.trim(),
      'category': category,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'fileSizeKb': fileSizeKb,
      'isPublished': isPublished,
      'isRequired': isRequired,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      if (publishedAt != null) 'publishedAt': publishedAt,
      'uploadedBy': uploadedBy,
      'updatedAt': FieldValue.serverTimestamp(),
      if (storagePath != null && storagePath!.isNotEmpty)
        'storagePath': storagePath,
    };
  }

  SstDocumentModel copyWith({
    String? id,
    String? title,
    String? description,
    String? category,
    String? fileUrl,
    String? fileName,
    int? fileSizeKb,
    bool? isPublished,
    bool? isRequired,
    Timestamp? createdAt,
    Timestamp? publishedAt,
    String? uploadedBy,
    String? storagePath,
  }) {
    return SstDocumentModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      fileUrl: fileUrl ?? this.fileUrl,
      fileName: fileName ?? this.fileName,
      fileSizeKb: fileSizeKb ?? this.fileSizeKb,
      isPublished: isPublished ?? this.isPublished,
      isRequired: isRequired ?? this.isRequired,
      createdAt: createdAt ?? this.createdAt,
      publishedAt: publishedAt ?? this.publishedAt,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      storagePath: storagePath ?? this.storagePath,
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return 0;
  }
}
