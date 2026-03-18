import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, Stream<DocumentSnapshot<Map<String, dynamic>>>>
  _profileStreams = {};
  final Map<String, Stream<QuerySnapshot>> _institutionUserStreams = {};

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamUserProfile(String uid) {
    return _profileStreams.putIfAbsent(
      uid,
      () => _firestore
          .collection('users')
          .doc(uid)
          .snapshots()
          .asBroadcastStream(),
    );
  }

  Future<String?> getUserRole(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) {
      return null;
    }
    final data = doc.data() as Map<String, dynamic>;
    return data['role'] as String?;
  }

  Future<String?> getUserInstitutionId(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) {
      return null;
    }
    final data = doc.data() as Map<String, dynamic>;
    return data['institutionId'] as String?;
  }

  Future<Map<String, dynamic>?> getUserData(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) {
      return null;
    }
    return doc.data();
  }

  /// Crea perfil de usuario estandar (sin institucion asignada inicialmente)
  Future<void> createUserProfile(User user, {String role = 'user'}) async {
    await _firestore.collection('users').doc(user.uid).set({
      'email': user.email,
      'displayName': user.displayName ?? _fallbackName(user.email),
      'photoUrl': user.photoURL,
      'jobTitle': '',
      'institutionId': null, // Referencia a institutions collection
      'campus': '',
      'phone': '',
      'notificationsEnabled': true,
      'fcmTokens': [],
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Crea perfil de administrador de institucion
  Future<void> createInstitutionAdminProfile({
    required String uid,
    required String email,
    required String? displayName,
    required String? photoUrl,
    required String institutionId,
  }) async {
    await _firestore.collection('users').doc(uid).set({
      'email': email,
      'displayName': displayName ?? _fallbackName(email),
      'photoUrl': photoUrl,
      'jobTitle': 'Administrador SG-SST',
      'institutionId': institutionId,
      'campus': '',
      'phone': '',
      'notificationsEnabled': true,
      'fcmTokens': [],
      'role': 'admin_sst', // Nuevo rol para admin de institucion
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Crea perfil de usuario vinculado a una institucion
  Future<void> createUserWithInstitution({
    required String uid,
    required String email,
    required String? displayName,
    required String? photoUrl,
    required String institutionId,
    String role = 'user',
  }) async {
    await _firestore.collection('users').doc(uid).set({
      'email': email,
      'displayName': displayName ?? _fallbackName(email),
      'photoUrl': photoUrl,
      'jobTitle': '',
      'institutionId': institutionId,
      'campus': '',
      'phone': '',
      'notificationsEnabled': true,
      'fcmTokens': [],
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Vincula un usuario existente a una institucion mediante codigo de invitacion
  Future<void> linkUserToInstitution(String uid, String institutionId) async {
    await _firestore.collection('users').doc(uid).update({
      'institutionId': institutionId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateUserProfile(String uid, Map<String, dynamic> data) async {
    await _firestore.collection('users').doc(uid).set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateUserRole(String uid, String role) async {
    await _firestore.collection('users').doc(uid).set({
      'role': role,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> unlinkUserFromInstitution(
    String uid, {
    bool demoteFromInstitutionAdmin = false,
  }) async {
    final payload = <String, dynamic>{
      'institutionId': null,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (demoteFromInstitutionAdmin) {
      payload['role'] = 'user';
    }
    await _firestore
        .collection('users')
        .doc(uid)
        .set(payload, SetOptions(merge: true));
  }

  Future<void> setNotificationsEnabled(String uid, bool enabled) async {
    await _firestore.collection('users').doc(uid).set({
      'notificationsEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> addFcmToken(String uid, String token) async {
    await _firestore.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeFcmToken(String uid, String token) async {
    await _firestore.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayRemove([token]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Obtiene usuarios de una institucion especifica
  Stream<QuerySnapshot> streamUsersByInstitution(String institutionId) {
    return _institutionUserStreams.putIfAbsent(
      institutionId,
      () => _firestore
          .collection('users')
          .where('institutionId', isEqualTo: institutionId)
          .snapshots()
          .asBroadcastStream(),
    );
  }

  Future<int> getUserReportCount(String uid, {String? institutionId}) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('reports')
        .where('createdBy', isEqualTo: uid);

    final normalizedInstitutionId = institutionId?.trim();
    if (normalizedInstitutionId != null && normalizedInstitutionId.isNotEmpty) {
      query = query.where('institutionId', isEqualTo: normalizedInstitutionId);
    }

    final snapshot = await query.count().get();
    return snapshot.count ?? 0;
  }

  /// Verifica si el usuario tiene una institucion asignada
  Future<bool> hasInstitution(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return false;
    final data = doc.data() as Map<String, dynamic>;
    final institutionId = data['institutionId'];
    return institutionId != null && institutionId.toString().isNotEmpty;
  }

  String _fallbackName(String? email) {
    if (email == null || !email.contains('@')) {
      return 'Usuario';
    }
    return email.split('@').first;
  }

  /// Obtiene los datos del usuario actual autenticado
  Future<CurrentUserData?> getCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final data = await getUserData(user.uid);
    if (data == null) return null;

    return CurrentUserData(
      uid: user.uid,
      email: user.email ?? '',
      displayName: data['displayName'] as String?,
      photoUrl: data['photoUrl'] as String?,
      institutionId: data['institutionId'] as String?,
      role: data['role'] as String?,
    );
  }

  /// Obtiene el nombre de una institucion por su ID
  Future<String?> getInstitutionName(String institutionId) async {
    try {
      final doc = await _firestore
          .collection('institutions')
          .doc(institutionId)
          .get();
      if (!doc.exists) return null;
      final data = doc.data();
      return data?['name'] as String?;
    } catch (e) {
      return null;
    }
  }
}

/// Datos del usuario actual
class CurrentUserData {
  final String uid;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final String? institutionId;
  final String? role;

  CurrentUserData({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.institutionId,
    this.role,
  });
}
