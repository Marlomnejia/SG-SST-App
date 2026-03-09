import 'package:cloud_firestore/cloud_firestore.dart';

enum TrainingType { scheduled, video }

enum TrainingStatus { published, draft, cancelled }

class ScheduledTrainingData {
  final Timestamp startAt;
  final Timestamp endAt;
  final String mode;
  final String? place;
  final String? meetUrl;
  final int? capacity;
  final bool requireRsvp;

  ScheduledTrainingData({
    required this.startAt,
    required this.endAt,
    required this.mode,
    this.place,
    this.meetUrl,
    this.capacity,
    required this.requireRsvp,
  });

  Map<String, dynamic> toMap() {
    return {
      'startAt': startAt,
      'endAt': endAt,
      'mode': mode,
      'place': place,
      'meetUrl': meetUrl,
      'capacity': capacity,
      'requireRsvp': requireRsvp,
    };
  }
}

class VideoTrainingData {
  final String youtubeUrl;
  final int? durationMinutes;

  VideoTrainingData({required this.youtubeUrl, this.durationMinutes});

  Map<String, dynamic> toMap() {
    return {'youtubeUrl': youtubeUrl, 'durationMinutes': durationMinutes};
  }
}

class TrainingModuleModel {
  final String type;
  final String title;
  final String description;
  final String topic;
  final String createdBy;
  final String status;
  final Timestamp? createdAt;
  final Object? publishedAt;
  final ScheduledTrainingData? scheduled;
  final VideoTrainingData? video;

  TrainingModuleModel({
    required this.type,
    required this.title,
    required this.description,
    required this.topic,
    required this.createdBy,
    required this.status,
    this.createdAt,
    this.publishedAt,
    this.scheduled,
    this.video,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'title': title,
      'description': description,
      'topic': topic,
      'createdBy': createdBy,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'status': status,
      if (publishedAt != null)
        'publishedAt': publishedAt
      else if (status == TrainingStatus.published.name)
        'publishedAt': FieldValue.serverTimestamp(),
      if (scheduled != null) 'scheduled': scheduled!.toMap(),
      if (video != null) 'video': video!.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
