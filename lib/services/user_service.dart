import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamUserProfile(String uid) {
    return _firestore.collection('users').doc(uid).snapshots();
  }

  Future<String?> getUserRole(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) {
      return null;
    }
    final data = doc.data() as Map<String, dynamic>;
    return data['role'] as String?;
  }

  Future<void> createUserProfile(User user, {String role = 'user'}) async {
    await _firestore.collection('users').doc(user.uid).set({
      'email': user.email,
      'displayName': user.displayName ?? _fallbackName(user.email),
      'photoUrl': user.photoURL,
      'jobTitle': '',
      'institution': '',
      'campus': '',
      'phone': '',
      'notificationsEnabled': true,
      'fcmTokens': [],
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateUserProfile(String uid, Map<String, dynamic> data) async {
    await _firestore.collection('users').doc(uid).set(
      {
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> setNotificationsEnabled(String uid, bool enabled) async {
    await _firestore.collection('users').doc(uid).set(
      {
        'notificationsEnabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> addFcmToken(String uid, String token) async {
    await _firestore.collection('users').doc(uid).set(
      {
        'fcmTokens': FieldValue.arrayUnion([token]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> removeFcmToken(String uid, String token) async {
    await _firestore.collection('users').doc(uid).set(
      {
        'fcmTokens': FieldValue.arrayRemove([token]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  String _fallbackName(String? email) {
    if (email == null || !email.contains('@')) {
      return 'Usuario';
    }
    return email.split('@').first;
  }
}
