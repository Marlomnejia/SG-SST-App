import 'package:cloud_firestore/cloud_firestore.dart';

class ReportStatusEntry {
  final String status;
  final Timestamp changedAt;
  final String changedBy;
  final String note;

  ReportStatusEntry({
    required this.status,
    required this.changedAt,
    required this.changedBy,
    required this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'status': status,
      'changedAt': changedAt,
      'changedBy': changedBy,
      'note': note,
    };
  }
}

class ReportAttachment {
  final String type;
  final String url;
  final String path;
  final String? thumbUrl;

  ReportAttachment({
    required this.type,
    required this.url,
    required this.path,
    this.thumbUrl,
  });

  Map<String, dynamic> toMap() {
    return {'type': type, 'url': url, 'path': path, 'thumbUrl': thumbUrl};
  }
}

class ReportModel {
  final String id;
  final String caseNumber;
  final String createdBy;
  final String createdByEmail;
  final String institutionId;
  final Timestamp createdAt;
  final Timestamp updatedAt;
  final String eventType;
  final String reportType;
  final String severity;
  final Map<String, dynamic> location;
  final Timestamp datetime;
  final String description;
  final Map<String, dynamic>? gps;
  final Map<String, dynamic> people;
  final List<ReportAttachment> attachments;
  final String status;
  final List<ReportStatusEntry> statusHistory;

  ReportModel({
    required this.id,
    required this.caseNumber,
    required this.createdBy,
    required this.createdByEmail,
    required this.institutionId,
    required this.createdAt,
    required this.updatedAt,
    required this.eventType,
    required this.reportType,
    required this.severity,
    required this.location,
    required this.datetime,
    required this.description,
    this.gps,
    required this.people,
    required this.attachments,
    required this.status,
    required this.statusHistory,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'caseNumber': caseNumber,
      'createdBy': createdBy,
      'createdByEmail': createdByEmail,
      'institutionId': institutionId,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'eventType': eventType,
      'reportType': reportType,
      'severity': severity,
      'location': location,
      'datetime': datetime,
      'description': description,
      'gps': gps,
      'people': people,
      'attachments': attachments.map((e) => e.toMap()).toList(),
      'status': status,
      'statusHistory': statusHistory.map((e) => e.toMap()).toList(),
    };
  }
}
