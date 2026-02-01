import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipos de institución
enum InstitutionType {
  public,
  private;

  String get displayName {
    switch (this) {
      case InstitutionType.public:
        return 'Pública';
      case InstitutionType.private:
        return 'Privada';
    }
  }

  static InstitutionType fromString(String? value) {
    switch (value) {
      case 'public':
        return InstitutionType.public;
      case 'private':
        return InstitutionType.private;
      default:
        return InstitutionType.private;
    }
  }
}

/// Estados de verificación de institución
enum InstitutionStatus {
  pending,
  active,
  rejected;

  String get displayName {
    switch (this) {
      case InstitutionStatus.pending:
        return 'Pendiente de verificación';
      case InstitutionStatus.active:
        return 'Activa';
      case InstitutionStatus.rejected:
        return 'Rechazada';
    }
  }

  static InstitutionStatus fromString(String? value) {
    switch (value) {
      case 'pending':
        return InstitutionStatus.pending;
      case 'active':
        return InstitutionStatus.active;
      case 'rejected':
        return InstitutionStatus.rejected;
      default:
        return InstitutionStatus.pending;
    }
  }
}

/// URLs de documentos requeridos para verificación
class InstitutionDocuments {
  /// Cédula del rector (obligatorio para todos)
  final String? rectorIdCard;

  /// Acta de posesión (solo instituciones públicas)
  final String? appointmentAct;

  /// Cámara de comercio (solo instituciones privadas)
  final String? chamberOfCommerce;

  /// RUT (solo instituciones privadas)
  final String? rut;

  InstitutionDocuments({
    this.rectorIdCard,
    this.appointmentAct,
    this.chamberOfCommerce,
    this.rut,
  });

  factory InstitutionDocuments.fromMap(Map<String, dynamic>? data) {
    if (data == null) return InstitutionDocuments();
    return InstitutionDocuments(
      rectorIdCard: data['rectorIdCard'] as String?,
      appointmentAct: data['appointmentAct'] as String?,
      chamberOfCommerce: data['chamberOfCommerce'] as String?,
      rut: data['rut'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (rectorIdCard != null) 'rectorIdCard': rectorIdCard,
      if (appointmentAct != null) 'appointmentAct': appointmentAct,
      if (chamberOfCommerce != null) 'chamberOfCommerce': chamberOfCommerce,
      if (rut != null) 'rut': rut,
    };
  }

  InstitutionDocuments copyWith({
    String? rectorIdCard,
    String? appointmentAct,
    String? chamberOfCommerce,
    String? rut,
  }) {
    return InstitutionDocuments(
      rectorIdCard: rectorIdCard ?? this.rectorIdCard,
      appointmentAct: appointmentAct ?? this.appointmentAct,
      chamberOfCommerce: chamberOfCommerce ?? this.chamberOfCommerce,
      rut: rut ?? this.rut,
    );
  }

  /// Verifica si todos los documentos requeridos están presentes según el tipo
  bool isComplete(InstitutionType type) {
    if (rectorIdCard == null || rectorIdCard!.isEmpty) return false;

    if (type == InstitutionType.public) {
      return appointmentAct != null && appointmentAct!.isNotEmpty;
    } else {
      return (chamberOfCommerce != null && chamberOfCommerce!.isNotEmpty) &&
          (rut != null && rut!.isNotEmpty);
    }
  }
}

class Institution {
  final String id;
  final String name;
  final String nit;
  final String address;

  /// Tipo de institución: pública o privada
  final InstitutionType type;

  /// Estado de verificación: pending, active, rejected
  final InstitutionStatus status;

  /// Teléfono fijo de la institución
  final String institutionPhone;

  /// Celular del rector
  final String rectorCellPhone;

  /// Email de contacto (preferiblemente institucional)
  final String email;

  /// URLs de documentos para verificación
  final InstitutionDocuments documents;

  /// Código de invitación para empleados (solo activo cuando status == active)
  final String inviteCode;

  /// Compatibilidad con versiones anteriores
  final bool isActive;

  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  /// Mensaje de rechazo (si aplica)
  final String? rejectionReason;

  Institution({
    required this.id,
    required this.name,
    required this.nit,
    required this.address,
    this.type = InstitutionType.private,
    this.status = InstitutionStatus.pending,
    this.institutionPhone = '',
    this.rectorCellPhone = '',
    this.email = '',
    InstitutionDocuments? documents,
    this.inviteCode = '',
    this.isActive = false,
    this.createdAt,
    this.updatedAt,
    this.rejectionReason,
  }) : documents = documents ?? InstitutionDocuments();

  factory Institution.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Institution(
      id: doc.id,
      name: data['name'] ?? '',
      nit: data['nit'] ?? '',
      address: data['address'] ?? '',
      type: InstitutionType.fromString(data['type'] as String?),
      status: InstitutionStatus.fromString(data['status'] as String?),
      institutionPhone: data['institutionPhone'] ?? data['phone'] ?? '',
      rectorCellPhone: data['rectorCellPhone'] ?? '',
      email: data['email'] ?? '',
      documents: InstitutionDocuments.fromMap(
          data['documentsUrls'] as Map<String, dynamic>?),
      inviteCode: data['inviteCode'] ?? '',
      isActive: data['isActive'] ?? false,
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
      rejectionReason: data['rejectionReason'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'nit': nit,
      'address': address,
      'type': type.name,
      'status': status.name,
      'institutionPhone': institutionPhone,
      'rectorCellPhone': rectorCellPhone,
      'email': email,
      'documentsUrls': documents.toMap(),
      'inviteCode': inviteCode,
      'isActive': isActive,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
    };
  }

  Institution copyWith({
    String? id,
    String? name,
    String? nit,
    String? address,
    InstitutionType? type,
    InstitutionStatus? status,
    String? institutionPhone,
    String? rectorCellPhone,
    String? email,
    InstitutionDocuments? documents,
    String? inviteCode,
    bool? isActive,
    Timestamp? createdAt,
    Timestamp? updatedAt,
    String? rejectionReason,
  }) {
    return Institution(
      id: id ?? this.id,
      name: name ?? this.name,
      nit: nit ?? this.nit,
      address: address ?? this.address,
      type: type ?? this.type,
      status: status ?? this.status,
      institutionPhone: institutionPhone ?? this.institutionPhone,
      rectorCellPhone: rectorCellPhone ?? this.rectorCellPhone,
      email: email ?? this.email,
      documents: documents ?? this.documents,
      inviteCode: inviteCode ?? this.inviteCode,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }

  /// Verifica si la institución tiene todos los documentos requeridos
  bool get hasRequiredDocuments => documents.isComplete(type);

  /// Nombre legible del tipo
  String get typeName => type.displayName;

  /// Nombre legible del estado
  String get statusName => status.displayName;
}
