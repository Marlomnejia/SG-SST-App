import 'package:cloud_firestore/cloud_firestore.dart';

/// Estados de una invitación
enum InvitationStatus {
  pending,
  accepted,
  cancelled;

  String get displayName {
    switch (this) {
      case InvitationStatus.pending:
        return 'Pendiente';
      case InvitationStatus.accepted:
        return 'Aceptada';
      case InvitationStatus.cancelled:
        return 'Cancelada';
    }
  }

  static InvitationStatus fromString(String? value) {
    switch (value) {
      case 'pending':
        return InvitationStatus.pending;
      case 'accepted':
        return InvitationStatus.accepted;
      case 'cancelled':
        return InvitationStatus.cancelled;
      default:
        return InvitationStatus.pending;
    }
  }
}

/// Modelo de invitación para registro de empleados
class Invitation {
  final String id;
  final String email;
  final String institutionId;
  final String role;
  final InvitationStatus status;
  final DateTime createdAt;
  final String? createdBy;
  final String? institutionName;
  final DateTime? acceptedAt;

  Invitation({
    required this.id,
    required this.email,
    required this.institutionId,
    required this.role,
    required this.status,
    required this.createdAt,
    this.createdBy,
    this.institutionName,
    this.acceptedAt,
  });

  factory Invitation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Invitation(
      id: doc.id,
      email: data['email'] ?? '',
      institutionId: data['institutionId'] ?? '',
      role: data['role'] ?? 'employee',
      status: InvitationStatus.fromString(data['status']),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'],
      institutionName: data['institutionName'],
      acceptedAt: (data['acceptedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email.toLowerCase().trim(),
      'institutionId': institutionId,
      'role': role,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      if (createdBy != null) 'createdBy': createdBy,
      if (institutionName != null) 'institutionName': institutionName,
      if (acceptedAt != null) 'acceptedAt': Timestamp.fromDate(acceptedAt!),
    };
  }

  Invitation copyWith({
    String? id,
    String? email,
    String? institutionId,
    String? role,
    InvitationStatus? status,
    DateTime? createdAt,
    String? createdBy,
    String? institutionName,
    DateTime? acceptedAt,
  }) {
    return Invitation(
      id: id ?? this.id,
      email: email ?? this.email,
      institutionId: institutionId ?? this.institutionId,
      role: role ?? this.role,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      institutionName: institutionName ?? this.institutionName,
      acceptedAt: acceptedAt ?? this.acceptedAt,
    );
  }
}
