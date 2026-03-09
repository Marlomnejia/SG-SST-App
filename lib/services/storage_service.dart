import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class ReportAttachmentInput {
  final XFile file;
  final String type;

  ReportAttachmentInput({required this.file, required this.type});
}

class UploadedAttachment {
  final String type;
  final String url;
  final String path;
  final String? thumbUrl;

  UploadedAttachment({
    required this.type,
    required this.url,
    required this.path,
    this.thumbUrl,
  });

  Map<String, dynamic> toMap() {
    return {'type': type, 'url': url, 'path': path, 'thumbUrl': thumbUrl};
  }
}

class StorageService {
  Future<List<String>> uploadEventImages(
    List<XFile> images,
    String eventId,
  ) async {
    List<String> downloadUrls = [];
    try {
      for (var image in images) {
        String fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
        Reference ref = FirebaseStorage.instance.ref().child(
          'eventos/$eventId/$fileName',
        );
        UploadTask uploadTask = ref.putFile(File(image.path));
        TaskSnapshot snapshot = await uploadTask;
        String downloadUrl = await snapshot.ref.getDownloadURL();
        downloadUrls.add(downloadUrl);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error uploading images: $e');
    }
    return downloadUrls;
  }

  Future<List<String>> uploadEventVideos(
    List<XFile> videos,
    String eventId,
  ) async {
    List<String> downloadUrls = [];
    try {
      for (var video in videos) {
        String fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${video.name}';
        Reference ref = FirebaseStorage.instance.ref().child(
          'eventos/$eventId/videos/$fileName',
        );
        UploadTask uploadTask = ref.putFile(File(video.path));
        TaskSnapshot snapshot = await uploadTask;
        String downloadUrl = await snapshot.ref.getDownloadURL();
        downloadUrls.add(downloadUrl);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error uploading videos: $e');
    }
    return downloadUrls;
  }

  Future<List<UploadedAttachment>> uploadReportAttachments(
    List<ReportAttachmentInput> attachments,
    String reportId, {
    void Function(double progress)? onProgress,
  }) async {
    return _uploadAttachmentsToBasePath(
      attachments,
      'reports/$reportId',
      onProgress: onProgress,
    );
  }

  Future<List<UploadedAttachment>> uploadActionPlanExecutionAttachments(
    List<ReportAttachmentInput> attachments,
    String planId, {
    void Function(double progress)? onProgress,
  }) async {
    return _uploadAttachmentsToBasePath(
      attachments,
      'action_plans/$planId',
      onProgress: onProgress,
    );
  }

  Future<List<UploadedAttachment>> uploadActionPlanValidationAttachments(
    List<ReportAttachmentInput> attachments,
    String planId, {
    void Function(double progress)? onProgress,
  }) async {
    return _uploadAttachmentsToBasePath(
      attachments,
      'action_plans/$planId/validation',
      onProgress: onProgress,
    );
  }

  Future<List<UploadedAttachment>> _uploadAttachmentsToBasePath(
    List<ReportAttachmentInput> attachments,
    String basePath, {
    void Function(double progress)? onProgress,
  }) async {
    final uploaded = <UploadedAttachment>[];
    final total = attachments.length;
    if (total == 0) {
      onProgress?.call(1);
      return uploaded;
    }

    for (int index = 0; index < attachments.length; index++) {
      final attachment = attachments[index];
      final extension = _extensionFromName(attachment.file.name);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${attachment.file.name}';
      final folder = attachment.type == 'video' ? 'videos' : 'images';
      final storagePath = '$basePath/$folder/$fileName';
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      final task = ref.putFile(
        File(attachment.file.path),
        SettableMetadata(contentType: _contentType(extension, attachment.type)),
      );

      task.snapshotEvents.listen((snapshot) {
        final fileProgress = snapshot.totalBytes > 0
            ? snapshot.bytesTransferred / snapshot.totalBytes
            : 0;
        onProgress?.call((index + fileProgress) / total);
      });

      final result = await task;
      final url = await result.ref.getDownloadURL();
      uploaded.add(
        UploadedAttachment(
          type: attachment.type,
          url: url,
          path: storagePath,
          thumbUrl: null,
        ),
      );
      onProgress?.call((index + 1) / total);
    }
    return uploaded;
  }

  String _extensionFromName(String name) {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == name.length - 1) {
      return '';
    }
    return name.substring(dotIndex + 1).toLowerCase();
  }

  String _contentType(String extension, String type) {
    if (type == 'video') {
      return 'video/mp4';
    }
    switch (extension) {
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
