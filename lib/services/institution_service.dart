import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/institution.dart';

class InstitutionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

  /// Verifica si un código de invitación ya existe
  Future<bool> _isCodeUnique(String code) async {
    final snapshot = await _firestore
        .collection(_collection)
        .where('inviteCode', isEqualTo: code)
        .limit(1)
        .get();
    return snapshot.docs.isEmpty;
  }

  /// Genera un código único verificando que no exista en la base de datos
  Future<String> generateUniqueInviteCode() async {
    String code;
    bool isUnique;
    int attempts = 0;
    const maxAttempts = 10;

    do {
      code = _generateInviteCode();
      isUnique = await _isCodeUnique(code);
      attempts++;
    } while (!isUnique && attempts < maxAttempts);

    if (!isUnique) {
      throw Exception(
          'No se pudo generar un código único después de $maxAttempts intentos');
    }

    return code;
  }

  /// Crea una nueva institución y retorna su ID
  /// Acepta los nuevos campos: type, phones, email, documentsUrls
  Future<String> createInstitution({
    required String name,
    required String nit,
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
    return _firestore.collection(_collection).doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Institution.fromFirestore(doc);
    });
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
