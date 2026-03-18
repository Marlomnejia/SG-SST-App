import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/institution.dart';

class InstitutionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Map<String, Stream<Institution?>> _institutionStreams = {};
  Stream<List<Institution>>? _pendingInstitutionsStream;
  Stream<List<Institution>>? _allInstitutionsStream;

  static const String _collection = 'institutions';
  static const String _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const int _codeLength = 6;

  /// Genera un código de invitación único de 6 caracteres
  String _generateInviteCode() {
    final random = Random.secure();
    return List.generate(
      _codeLength,
      (_) => _chars[random.nextInt(_chars.length)],
    ).join();
  }

  /// Genera un código de invitación.
  /// Nota: se evita la consulta previa por reglas de lectura en registro inicial.
  /// El espacio de códigos (32^6) hace la colisión extremadamente improbable.
  Future<String> generateUniqueInviteCode() async {
    return _generateInviteCode();
  }

  /// Crea una nueva institución y retorna su ID
  /// Acepta los nuevos campos: type, phones, email, documentsUrls, department, city
  Future<String> createInstitution({
    required String name,
    required String nit,
    required String department,
    required String city,
    required String address,
    required InstitutionType type,
    required String institutionPhone,
    required String rectorCellPhone,
    required String email,
    required Map<String, String> documentsUrls,
  }) async {
    final inviteCode = await generateUniqueInviteCode();

    final docRef = await _firestore.collection(_collection).add({
      'name': name,
      'nit': nit,
      'department': department,
      'city': city,
      'address': address,
      'type': type.name,
      'institutionPhone': institutionPhone,
      'rectorCellPhone': rectorCellPhone,
      'email': email,
      'documentsUrls': documentsUrls,
      'inviteCode': inviteCode,
      // Estado inicial 'pending' hasta verificación legal
      'status': 'pending',
      // Compatibilidad: marcar isActive=false mientras está pendiente
      'isActive': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return docRef.id;
  }

  /// Obtiene una institución por su ID
  Future<Institution?> getInstitutionById(String id) async {
    final doc = await _firestore.collection(_collection).doc(id).get();
    if (!doc.exists) {
      return null;
    }
    return Institution.fromFirestore(doc);
  }

  /// Obtiene una institución por su código de invitación
  Future<Institution?> getInstitutionByInviteCode(String code) async {
    final snapshot = await _firestore
        .collection(_collection)
        .where('inviteCode', isEqualTo: code.toUpperCase().trim())
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    return Institution.fromFirestore(snapshot.docs.first);
  }

  /// Actualiza los datos de una institución
  Future<void> updateInstitution(String id, Map<String, dynamic> data) async {
    await _firestore.collection(_collection).doc(id).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Regenera el código de invitación de una institución
  Future<String> regenerateInviteCode(String institutionId) async {
    final newCode = await generateUniqueInviteCode();
    await _firestore.collection(_collection).doc(institutionId).update({
      'inviteCode': newCode,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return newCode;
  }

  /// Stream de una institución específica
  Stream<Institution?> streamInstitution(String id) {
    return _institutionStreams.putIfAbsent(
      id,
      () => _firestore.collection(_collection).doc(id).snapshots().map((doc) {
        if (!doc.exists) return null;
        return Institution.fromFirestore(doc);
      }).asBroadcastStream(),
    );
  }

  /// Verifica si un NIT ya está registrado
  Future<bool> isNitRegistered(String nit) async {
    final snapshot = await _firestore
        .collection(_collection)
        .where('nit', isEqualTo: nit.trim())
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  /// Valida un código de invitación y retorna los datos de la institución
  /// Lanza [InviteCodeException] si el código es inválido o la institución no está activa
  Future<InstitutionValidationResult> validateInviteCode(String code) async {
    final normalizedCode = code.toUpperCase().trim();

    if (normalizedCode.length != _codeLength) {
      throw InviteCodeException(
        code: 'invalid-format',
        message: 'El código debe tener $_codeLength caracteres.',
      );
    }

    final snapshot = await _firestore
        .collection(_collection)
        .where('inviteCode', isEqualTo: normalizedCode)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      throw InviteCodeException(
        code: 'code-not-found',
        message: 'El código de invitación no existe.',
      );
    }

    final doc = snapshot.docs.first;
    final data = doc.data();

    if ((data['status'] ?? 'pending') != 'active') {
      throw InviteCodeException(
        code: 'institution-inactive',
        message: 'La institución no está activa.',
      );
    }

    return InstitutionValidationResult(
      institutionId: doc.id,
      institutionName: data['name'] ?? '',
      nit: data['nit'] ?? '',
    );
  }

  /// Obtiene el conteo de usuarios de una institución
  Future<int> getUserCount(String institutionId) async {
    final snapshot = await _firestore
        .collection('users')
        .where('institutionId', isEqualTo: institutionId)
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  /// Stream de instituciones pendientes de aprobación (para super admin)
  Stream<List<Institution>> streamPendingInstitutions() {
    return _pendingInstitutionsStream ??= _firestore
        .collection(_collection)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Institution.fromFirestore(doc))
              .toList(),
        )
        .asBroadcastStream();
  }

  /// Stream de todas las instituciones registradas (para super admin)
  Stream<List<Institution>> streamAllInstitutions() {
    return _allInstitutionsStream ??= _firestore
        .collection(_collection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Institution.fromFirestore(doc))
              .toList(),
        )
        .asBroadcastStream();
  }

  /// Aprueba una institución (cambia status a 'active')
  Future<_InstitutionActor> _resolveActor() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return const _InstitutionActor(uid: 'system', role: 'system');
    }

    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final role = (userDoc.data()?['role'] ?? '').toString().trim();
      return _InstitutionActor(uid: uid, role: role.isEmpty ? 'unknown' : role);
    } catch (_) {
      return _InstitutionActor(uid: uid, role: 'unknown');
    }
  }

  Map<String, dynamic> _auditEntry({
    required String status,
    required _InstitutionActor actor,
    String? note,
  }) {
    return <String, dynamic>{
      'status': status,
      'changedAt': Timestamp.now(),
      'changedBy': actor.uid,
      'changedByRole': actor.role,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };
  }

  Future<void> approveInstitution(String institutionId) async {
    final actor = await _resolveActor();
    await _firestore.collection(_collection).doc(institutionId).update({
      'status': 'active',
      'isActive': true,
      'rejectionReason': FieldValue.delete(),
      'suspensionReason': FieldValue.delete(),
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': actor.uid,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': actor.uid,
      'reviewedByRole': actor.role,
      'statusHistory': FieldValue.arrayUnion([
        _auditEntry(status: 'active', actor: actor),
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Rechaza una institución (cambia status a 'rejected')
  Future<void> rejectInstitution(String institutionId, {String? reason}) async {
    final actor = await _resolveActor();
    final cleanReason = reason?.trim();
    await _firestore.collection(_collection).doc(institutionId).update({
      'status': 'rejected',
      'isActive': false,
      'rejectionReason': (cleanReason == null || cleanReason.isEmpty)
          ? FieldValue.delete()
          : cleanReason,
      'suspensionReason': FieldValue.delete(),
      'rejectedAt': FieldValue.serverTimestamp(),
      'rejectedBy': actor.uid,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': actor.uid,
      'reviewedByRole': actor.role,
      'statusHistory': FieldValue.arrayUnion([
        _auditEntry(status: 'rejected', actor: actor, note: cleanReason),
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> suspendInstitution(
    String institutionId, {
    String? reason,
  }) async {
    final actor = await _resolveActor();
    final cleanReason = reason?.trim();
    await _firestore.collection(_collection).doc(institutionId).update({
      'status': 'suspended',
      'isActive': false,
      'suspensionReason': (cleanReason == null || cleanReason.isEmpty)
          ? FieldValue.delete()
          : cleanReason,
      'suspendedAt': FieldValue.serverTimestamp(),
      'suspendedBy': actor.uid,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': actor.uid,
      'reviewedByRole': actor.role,
      'statusHistory': FieldValue.arrayUnion([
        _auditEntry(status: 'suspended', actor: actor, note: cleanReason),
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> reactivateInstitution(String institutionId) async {
    final actor = await _resolveActor();
    await _firestore.collection(_collection).doc(institutionId).update({
      'status': 'active',
      'isActive': true,
      'suspensionReason': FieldValue.delete(),
      'reactivatedAt': FieldValue.serverTimestamp(),
      'reactivatedBy': actor.uid,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': actor.uid,
      'reviewedByRole': actor.role,
      'statusHistory': FieldValue.arrayUnion([
        _auditEntry(status: 'active', actor: actor, note: 'reactivated'),
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

class _InstitutionActor {
  final String uid;
  final String role;

  const _InstitutionActor({required this.uid, required this.role});
}

/// Resultado de validación de código de invitación
class InstitutionValidationResult {
  final String institutionId;
  final String institutionName;
  final String nit;

  InstitutionValidationResult({
    required this.institutionId,
    required this.institutionName,
    required this.nit,
  });
}

/// Excepción para errores de código de invitación
class InviteCodeException implements Exception {
  final String code;
  final String message;

  InviteCodeException({required this.code, required this.message});

  @override
  String toString() => 'InviteCodeException: [$code] $message';
}
