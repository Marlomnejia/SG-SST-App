import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/institution.dart';
import '../models/invitation.dart';
import 'institution_service.dart';
import 'invitation_service.dart';
import 'user_service.dart';
import 'document_upload_service.dart';

/// Excepcion personalizada para errores de autenticacion
class AuthException implements Exception {
  final String code;
  final String message;

  AuthException({required this.code, required this.message});

  @override
  String toString() => 'AuthException: [$code] $message';
}

/// Tipos de proveedores de autenticacion social
enum SocialAuthProvider { google, microsoft }

/// Excepcion generica para usuarios de redes sociales que no estan registrados
/// Contiene los datos del proveedor para completar el registro
class SocialUserNotRegisteredException implements Exception {
  final User user;
  final SocialAuthProvider provider;

  SocialUserNotRegisteredException({
    required this.user,
    required this.provider,
  });

  String get displayName => user.displayName ?? '';
  String get email => user.email ?? '';
  String? get photoUrl => user.photoURL;
  String get uid => user.uid;

  String get providerName {
    switch (provider) {
      case SocialAuthProvider.google:
        return 'Google';
      case SocialAuthProvider.microsoft:
        return 'Microsoft';
    }
  }

  @override
  String toString() =>
      'SocialUserNotRegisteredException: Usuario de $providerName no registrado';
}

/// Mantener compatibilidad con codigo existente
typedef GoogleUserNotRegisteredException = SocialUserNotRegisteredException;

class AuthService {
  static bool socialAuthFlowActive = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final InstitutionService _institutionService = InstitutionService();
  final UserService _userService = UserService();
  final DocumentUploadService _documentService = DocumentUploadService();
  static const Set<String> _allowedRoles = {
    'admin',
    'admin_sst',
    'user',
    'employee',
  };

  Future<bool> _safeNitAlreadyExists(String nit) async {
    try {
      return await _institutionService.isNitRegistered(nit);
    } on FirebaseException catch (e) {
      // En el registro inicial, un usuario sin institucion no puede leer
      // la coleccion institutions por reglas. No bloquear el onboarding.
      if (e.code == 'permission-denied') {
        return false;
      }
      rethrow;
    }
  }

  Future<String?> _resolveRoleFromFirestoreOrClaims(User user) async {
    final firestoreRole = (await _userService.getUserRole(user.uid) ?? '')
        .toString()
        .trim();
    if (_allowedRoles.contains(firestoreRole)) {
      return firestoreRole;
    }

    String claimRole = '';
    try {
      final tokenResult = await user.getIdTokenResult(true);
      claimRole = (tokenResult.claims?['role'] ?? '').toString().trim();
    } catch (_) {}
    if (!_allowedRoles.contains(claimRole)) {
      // En primer login social puede no existir perfil en Firestore todavia.
      // Creamos un perfil base para mantener consistencia con Auth.
      final existingData = await _userService.getUserData(user.uid);
      if (existingData == null) {
        await _userService.createUserProfile(user, role: 'user');
      } else if ((existingData['role'] ?? '').toString().trim().isEmpty) {
        await _userService.updateUserProfile(user.uid, {'role': 'user'});
      }
      return null;
    }

    final existingData = await _userService.getUserData(user.uid);
    if (existingData == null) {
      await _userService.createUserProfile(user, role: claimRole);
    } else if ((existingData['role'] ?? '').toString().trim().isEmpty) {
      await _userService.updateUserProfile(user.uid, {'role': claimRole});
    }

    return claimRole;
  }

  Future<User?> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  Future<User?> registerWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await result.user?.sendEmailVerification();
      return result.user;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  /// Registra una nueva institucion junto con su administrador
  /// Orden estricto: 1) Crear usuario Auth, 2) Subir documentos, 3) Crear docs Firestore
  Future<User?> registerInstitutionAdmin({
    required String email,
    required String password,
    required String institutionName,
    required String institutionNit,
    required String institutionDepartment,
    required String institutionCity,
    required String institutionAddress,
    required InstitutionType institutionType,
    required String institutionPhone,
    required String rectorCellPhone,
    required Map<DocumentType, SelectedFile> selectedDocuments,
    String? adminDisplayName,
    void Function(String)? onProgress,
  }) async {
    // Verificar si el NIT ya esta registrado
    final nitExists = await _safeNitAlreadyExists(institutionNit);
    if (nitExists) {
      throw AuthException(
        code: 'nit-already-exists',
        message: 'El NIT ya esta registrado en el sistema.',
      );
    }

    User? user;
    String? institutionId;

    try {
      // PASO 1: Crear usuario en Firebase Auth PRIMERO (esto autentica al usuario)
      onProgress?.call('Creando cuenta...');
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      user = result.user;

      if (user == null) {
        throw AuthException(
          code: 'user-creation-failed',
          message: 'No se pudo crear el usuario.',
        );
      }

      // Actualizar displayName si se proporciono
      if (adminDisplayName != null && adminDisplayName.isNotEmpty) {
        await user.updateDisplayName(adminDisplayName);
      }

      // PASO 2: Subir documentos a Firebase Storage (ahora el usuario esta autenticado)
      final documentUrls = <String, String>{};
      for (final entry in selectedDocuments.entries) {
        onProgress?.call('Subiendo ${entry.key.displayName}...');
        final url = await _documentService.uploadDocument(
          nit: institutionNit,
          documentType: entry.key,
          file: entry.value,
        );
        documentUrls[entry.key.name] = url;
      }

      // PASO 3: Crear la institucion en Firestore
      onProgress?.call('Creando institucion...');
      institutionId = await _institutionService.createInstitution(
        name: institutionName,
        nit: institutionNit,
        department: institutionDepartment,
        city: institutionCity,
        address: institutionAddress,
        type: institutionType,
        institutionPhone: institutionPhone,
        rectorCellPhone: rectorCellPhone,
        email: email,
        documentsUrls: documentUrls,
      );

      // PASO 4: Crear el perfil del administrador en Firestore
      onProgress?.call('Configurando perfil...');
      await _userService.createInstitutionAdminProfile(
        uid: user.uid,
        email: email,
        displayName: adminDisplayName,
        photoUrl: null,
        institutionId: institutionId,
      );

      // PASO 5: Enviar email de verificacion
      await user.sendEmailVerification();

      return user;
    } catch (e) {
      // Rollback: Si algo falla despues de crear el usuario
      if (user != null && institutionId == null) {
        // Si el usuario se creo pero la institucion no, eliminar usuario
        try {
          await user.delete();
        } catch (_) {}
      } else if (institutionId != null) {
        // Si la institucion se creo, marcarla como eliminada
        await _rollbackInstitution(institutionId);
      }
      rethrow;
    }
  }

  /// Registra un usuario que se une mediante codigo de invitacion
  Future<User?> registerWithInviteCode({
    required String email,
    required String password,
    required String inviteCode,
    String? displayName,
  }) async {
    // Verificar que el codigo de invitacion sea valido
    final institution = await _institutionService.getInstitutionByInviteCode(
      inviteCode,
    );
    if (institution == null) {
      throw AuthException(
        code: 'invalid-invite-code',
        message:
            'El codigo de invitacion no es valido o la institucion no esta activa.',
      );
    }

    try {
      // Registrar el usuario en Firebase Auth
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = result.user;

      if (user == null) {
        throw AuthException(
          code: 'user-creation-failed',
          message: 'No se pudo crear el usuario.',
        );
      }

      // Actualizar displayName si se proporciono
      if (displayName != null && displayName.isNotEmpty) {
        await user.updateDisplayName(displayName);
      }

      // Crear el perfil vinculado a la institucion
      await _userService.createUserWithInstitution(
        uid: user.uid,
        email: email,
        displayName: displayName,
        photoUrl: null,
        institutionId: institution.id,
        role: 'user',
      );

      // Enviar email de verificacion
      await user.sendEmailVerification();

      return user;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  /// Vincula un usuario existente a una institucion mediante codigo
  Future<void> joinInstitutionWithCode(String uid, String inviteCode) async {
    final institution = await _institutionService.getInstitutionByInviteCode(
      inviteCode,
    );
    if (institution == null) {
      throw AuthException(
        code: 'invalid-invite-code',
        message: 'El codigo de invitacion no es valido.',
      );
    }

    await _userService.linkUserToInstitution(uid, institution.id);
  }

  Future<void> _rollbackInstitution(String institutionId) async {
    try {
      await _institutionService.updateInstitution(institutionId, {
        'isActive': false,
        'status': 'rejected',
        'rejectionReason': 'Registro incompleto o interrumpido',
        'deletedAt': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Silenciar errores de rollback
    }
  }

  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        return null; // Usuario cancelo el inicio de sesion
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential result = await _auth.signInWithCredential(
        credential,
      );
      final user = result.user;

      if (user == null) {
        return null;
      }

      // Verificar rol valido en Firestore o claims (y sincronizar si hace falta)
      final existingRole = await _resolveRoleFromFirestoreOrClaims(user);
      if (existingRole == null) {
        // Usuario nuevo de Google - lanzar excepcion para onboarding
        throw SocialUserNotRegisteredException(
          user: user,
          provider: SocialAuthProvider.google,
        );
      }

      // Usuario existente - login normal
      return user;
    } on SocialUserNotRegisteredException {
      rethrow; // Re-lanzar para que la UI lo maneje
    } on FirebaseAuthException {
      rethrow;
    }
  }

  /// Inicia sesion con Microsoft
  Future<User?> signInWithMicrosoft() async {
    try {
      final microsoftProvider = OAuthProvider('microsoft.com');

      // Configurar scopes opcionales
      microsoftProvider.addScope('email');
      microsoftProvider.addScope('profile');

      // Configurar parametros opcionales (tenant para organizaciones)
      microsoftProvider.setCustomParameters({
        'prompt': 'select_account', // Siempre mostrar selector de cuenta
      });

      final UserCredential result = await _auth.signInWithProvider(
        microsoftProvider,
      );
      final user = result.user;

      if (user == null) {
        return null;
      }

      // Verificar rol valido en Firestore o claims (y sincronizar si hace falta)
      final existingRole = await _resolveRoleFromFirestoreOrClaims(user);
      if (existingRole == null) {
        // Usuario nuevo de Microsoft - lanzar excepcion para onboarding
        throw SocialUserNotRegisteredException(
          user: user,
          provider: SocialAuthProvider.microsoft,
        );
      }

      // Usuario existente - login normal
      return user;
    } on SocialUserNotRegisteredException {
      rethrow; // Re-lanzar para que la UI lo maneje
    } on FirebaseAuthException {
      rethrow;
    }
  }

  /// Completa el registro de un usuario social uniendolo a una institucion (codigo)
  Future<User?> completeSocialRegistrationWithInviteCode({
    required User socialUser,
    required String inviteCode,
    String? jobTitle,
  }) async {
    // Validar codigo de invitacion
    final institution = await _institutionService.getInstitutionByInviteCode(
      inviteCode,
    );
    if (institution == null) {
      throw AuthException(
        code: 'invalid-invite-code',
        message:
            'El codigo de invitacion no es valido o la institucion no esta activa.',
      );
    }

    // Crear perfil en Firestore con los datos del usuario social
    await _userService.createUserWithInstitution(
      uid: socialUser.uid,
      email: socialUser.email ?? '',
      displayName: socialUser.displayName,
      photoUrl: socialUser.photoURL,
      institutionId: institution.id,
      role: 'employee',
    );

    // Actualizar jobTitle si se proporciono
    if (jobTitle != null && jobTitle.isNotEmpty) {
      await _userService.updateUserProfile(socialUser.uid, {
        'jobTitle': jobTitle,
      });
    }

    return socialUser;
  }

  /// Completa el registro de un usuario social usando una invitacion por email
  Future<User?> completeSocialRegistrationWithInvitation({
    required User socialUser,
    required Invitation invitation,
    String? jobTitle,
  }) async {
    final invitationService = InvitationService();

    // Crear perfil en Firestore con los datos del usuario social
    await _userService.createUserWithInstitution(
      uid: socialUser.uid,
      email: socialUser.email ?? '',
      displayName: socialUser.displayName,
      photoUrl: socialUser.photoURL,
      institutionId: invitation.institutionId,
      role: invitation.role,
    );

    // Actualizar jobTitle si se proporciono
    if (jobTitle != null && jobTitle.isNotEmpty) {
      await _userService.updateUserProfile(socialUser.uid, {
        'jobTitle': jobTitle,
      });
    }

    // Marcar la invitacion como aceptada
    await invitationService.acceptInvitation(invitation.id);

    return socialUser;
  }

  /// Registra una nueva institucion con un administrador que viene de login social
  /// El usuario social ya esta autenticado, solo necesita subir docs y crear Firestore
  Future<User?> registerInstitutionAdminWithSocialUser({
    required User socialUser,
    required String institutionName,
    required String institutionNit,
    required String institutionDepartment,
    required String institutionCity,
    required String institutionAddress,
    required InstitutionType institutionType,
    required String institutionPhone,
    required String rectorCellPhone,
    required String email,
    required Map<DocumentType, SelectedFile> selectedDocuments,
    String? jobTitle,
    void Function(String)? onProgress,
  }) async {
    // Verificar si el NIT ya esta registrado
    final nitExists = await _safeNitAlreadyExists(institutionNit);
    if (nitExists) {
      throw AuthException(
        code: 'nit-already-exists',
        message: 'El NIT ya esta registrado en el sistema.',
      );
    }

    String? institutionId;

    try {
      // PASO 1: Subir documentos a Firebase Storage (usuario social ya autenticado)
      final documentUrls = <String, String>{};
      for (final entry in selectedDocuments.entries) {
        onProgress?.call('Subiendo ${entry.key.displayName}...');
        final url = await _documentService.uploadDocument(
          nit: institutionNit,
          documentType: entry.key,
          file: entry.value,
        );
        documentUrls[entry.key.name] = url;
      }

      // PASO 2: Crear la institucion en Firestore
      onProgress?.call('Creando institucion...');
      institutionId = await _institutionService.createInstitution(
        name: institutionName,
        nit: institutionNit,
        department: institutionDepartment,
        city: institutionCity,
        address: institutionAddress,
        type: institutionType,
        institutionPhone: institutionPhone,
        rectorCellPhone: rectorCellPhone,
        email: email,
        documentsUrls: documentUrls,
      );

      // PASO 3: Crear el perfil del administrador en Firestore
      onProgress?.call('Configurando perfil...');
      await _userService.createInstitutionAdminProfile(
        uid: socialUser.uid,
        email: socialUser.email ?? '',
        displayName: socialUser.displayName,
        photoUrl: socialUser.photoURL,
        institutionId: institutionId,
      );

      // Actualizar jobTitle si se proporciono
      if (jobTitle != null && jobTitle.isNotEmpty) {
        await _userService.updateUserProfile(socialUser.uid, {
          'jobTitle': jobTitle,
        });
      }

      return socialUser;
    } catch (e) {
      // Rollback: Si algo falla despues de crear la institucion
      if (institutionId != null) {
        await _rollbackInstitution(institutionId);
      }
      rethrow;
    }
  }

  /// Mantener compatibilidad - alias para completeGoogleRegistrationWithInviteCode
  Future<User?> completeGoogleRegistrationWithInviteCode({
    required User googleUser,
    required String inviteCode,
    String? jobTitle,
  }) {
    return completeSocialRegistrationWithInviteCode(
      socialUser: googleUser,
      inviteCode: inviteCode,
      jobTitle: jobTitle,
    );
  }

  /// Mantener compatibilidad - alias para registerInstitutionAdminWithGoogle
  Future<User?> registerInstitutionAdminWithGoogle({
    required User googleUser,
    required String institutionName,
    required String institutionNit,
    required String institutionDepartment,
    required String institutionCity,
    required String institutionAddress,
    required InstitutionType institutionType,
    required String institutionPhone,
    required String rectorCellPhone,
    required String email,
    required Map<DocumentType, SelectedFile> selectedDocuments,
    String? jobTitle,
    void Function(String)? onProgress,
  }) {
    return registerInstitutionAdminWithSocialUser(
      socialUser: googleUser,
      institutionName: institutionName,
      institutionNit: institutionNit,
      institutionDepartment: institutionDepartment,
      institutionCity: institutionCity,
      institutionAddress: institutionAddress,
      institutionType: institutionType,
      institutionPhone: institutionPhone,
      rectorCellPhone: rectorCellPhone,
      email: email,
      selectedDocuments: selectedDocuments,
      jobTitle: jobTitle,
      onProgress: onProgress,
    );
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException {
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
