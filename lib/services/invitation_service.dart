import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/invitation.dart';

/// Excepciones específicas del servicio de invitaciones
class InvitationException implements Exception {
  final String code;
  final String message;

  InvitationException({required this.code, required this.message});

  @override
  String toString() => message;
}

/// Servicio para manejar invitaciones de empleados
class InvitationService {
  final _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _invitationsRef =>
      _firestore.collection('invitations');

  /// Crea una nueva invitación para un empleado
  Future<Invitation> createInvitation({
    required String email,
    required String institutionId,
    required String institutionName,
    required String createdBy,
    String role = 'employee',
  }) async {
    final normalizedEmail = email.toLowerCase().trim();

    // Verificar si ya existe una invitación pendiente para este email
    final existing = await _invitationsRef
        .where('email', isEqualTo: normalizedEmail)
        .where('institutionId', isEqualTo: institutionId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      throw InvitationException(
        code: 'invitation-exists',
        message: 'Ya existe una invitación pendiente para este correo.',
      );
    }

    final invitation = Invitation(
      id: '',
      email: normalizedEmail,
      institutionId: institutionId,
      role: role,
      status: InvitationStatus.pending,
      createdAt: DateTime.now(),
      createdBy: createdBy,
      institutionName: institutionName,
    );

    final docRef = await _invitationsRef.add(invitation.toMap());

    return invitation.copyWith(id: docRef.id);
  }

  /// Busca una invitación pendiente por email
  Future<Invitation?> findPendingInvitationByEmail(String email) async {
    final normalizedEmail = email.toLowerCase().trim();

    final querySnapshot = await _invitationsRef
        .where('email', isEqualTo: normalizedEmail)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (querySnapshot.docs.isEmpty) {
      return null;
    }

    return Invitation.fromFirestore(querySnapshot.docs.first);
  }

  /// Marca una invitación como aceptada
  Future<void> acceptInvitation(String invitationId) async {
    await _invitationsRef.doc(invitationId).update({
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Cancela una invitación
  Future<void> cancelInvitation(String invitationId) async {
    await _invitationsRef.doc(invitationId).update({
      'status': 'cancelled',
    });
  }

  /// Elimina una invitación
  Future<void> deleteInvitation(String invitationId) async {
    await _invitationsRef.doc(invitationId).delete();
  }

  /// Obtiene todas las invitaciones de una institución
  Stream<List<Invitation>> getInstitutionInvitationsStream(
      String institutionId) {
    return _invitationsRef
        .where('institutionId', isEqualTo: institutionId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Invitation.fromFirestore(doc)).toList());
  }

  /// Obtiene invitaciones pendientes de una institución
  Future<List<Invitation>> getPendingInvitations(String institutionId) async {
    final querySnapshot = await _invitationsRef
        .where('institutionId', isEqualTo: institutionId)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .get();

    return querySnapshot.docs
        .map((doc) => Invitation.fromFirestore(doc))
        .toList();
  }
}
