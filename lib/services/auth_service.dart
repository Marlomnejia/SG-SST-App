import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/institution.dart';
import '../models/invitation.dart';
import 'institution_service.dart';
import 'invitation_service.dart';
import 'user_service.dart';
import 'document_upload_service.dart';

/// Excepción personalizada para errores de autenticación
class AuthException implements Exception {
  final String code;
  final String message;

  AuthException({required this.code, required this.message});

  @override
  String toString() => 'AuthException: [$code] $message';
}

/// Tipos de proveedores de autenticación social
enum SocialAuthProvider { google, microsoft }

/// Excepción genérica para usuarios de redes sociales que no están registrados
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

/// Mantener compatibilidad con código existente
typedef GoogleUserNotRegisteredException = SocialUserNotRegisteredException;

class AuthService {
  static bool socialAuthFlowActive = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final InstitutionService _institutionService = InstitutionService();
  final UserService _userService = UserService();
  final DocumentUploadService _documentService = DocumentUploadService();

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

  /// Registra una nueva institución junto con su administrador
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
    // Verificar si el NIT ya está registrado
    final nitExists = await _institutionService.isNitRegistered(institutionNit);
    if (nitExists) {
      throw AuthException(
        code: 'nit-already-exists',
        message: 'El NIT ya está registrado en el sistema.',
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

      // Actualizar displayName si se proporcionó
      if (adminDisplayName != null && adminDisplayName.isNotEmpty) {
        await user.updateDisplayName(adminDisplayName);
      }

      // PASO 2: Subir documentos a Firebase Storage (ahora el usuario está autenticado)
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

      // PASO 3: Crear la institución en Firestore
      onProgress?.call('Creando institución...');
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

      // PASO 5: Enviar email de verificación
      await user.sendEmailVerification();

      return user;
    } catch (e) {
      // Rollback: Si algo falla después de crear el usuario
      if (user != null && institutionId == null) {
        // Si el usuario se creó pero la institución no, eliminar usuario
        try {
          await user.delete();
        } catch (_) {}
      } else if (institutionId != null) {
        // Si la institución se creó, marcarla como eliminada
        await _rollbackInstitution(institutionId);
      }
      rethrow;
    }
  }

  /// Registra un usuario que se une mediante código de invitación
  Future<User?> registerWithInviteCode({
    required String email,
    required String password,
    required String inviteCode,
    String? displayName,
  }) async {
    // Verificar que el código de invitación sea válido
    final institution = await _institutionService.getInstitutionByInviteCode(
      inviteCode,
    );
    if (institution == null) {
      throw AuthException(
        code: 'invalid-invite-code',
        message:
            'El código de invitación no es válido o la institución no está activa.',
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

      // Actualizar displayName si se proporcionó
      if (displayName != null && displayName.isNotEmpty) {
        await user.updateDisplayName(displayName);
      }

      // Crear el perfil vinculado a la institución
      await _userService.createUserWithInstitution(
        uid: user.uid,
        email: email,
        displayName: displayName,
        photoUrl: null,
        institutionId: institution.id,
        role: 'user',
      );

      // Enviar email de verificación
      await user.sendEmailVerification();

      return user;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  /// Vincula un usuario existente a una institución mediante código
  Future<void> joinInstitutionWithCode(String uid, String inviteCode) async {
    final institution = await _institutionService.getInstitutionByInviteCode(
      inviteCode,
    );
    if (institution == null) {
      throw AuthException(
        code: 'invalid-invite-code',
        message: 'El código de invitación no es válido.',
      );
    }

    await _userService.linkUserToInstitution(uid, institution.id);
  }

  Future<void> _rollbackInstitution(String institutionId) async {
    try {
      await _institutionService.updateInstitution(institutionId, {
        'isActive': false,
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
        return null; // Usuario canceló el inicio de sesión
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

      // Verificar si el usuario ya existe en Firestore
      final existingRole = await _userService.getUserRole(user.uid);

      if (existingRole == null) {
        // Usuario nuevo de Google - lanzar excepción para onboarding
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

  /// Inicia sesión con Microsoft
  Future<User?> signInWithMicrosoft() async {
    try {
      final microsoftProvider = OAuthProvider('microsoft.com');

      // Configurar scopes opcionales
      microsoftProvider.addScope('email');
      microsoftProvider.addScope('profile');

      // Configurar parámetros opcionales (tenant para organizaciones)
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

      // Verificar si el usuario ya existe en Firestore
      final existingRole = await _userService.getUserRole(user.uid);

      if (existingRole == null) {
        // Usuario nuevo de Microsoft - lanzar excepción para onboarding
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

  /// Completa el registro de un usuario social uniéndolo a una institución (código)
  Future<User?> completeSocialRegistrationWithInviteCode({
    required User socialUser,
    required String inviteCode,
    String? jobTitle,
  }) async {
    // Validar código de invitación
    final institution = await _institutionService.getInstitutionByInviteCode(
      inviteCode,
    );
    if (institution == null) {
      throw AuthException(
        code: 'invalid-invite-code',
        message:
            'El código de invitación no es válido o la institución no está activa.',
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

    // Actualizar jobTitle si se proporcionó
    if (jobTitle != null && jobTitle.isNotEmpty) {
      await _userService.updateUserProfile(socialUser.uid, {
        'jobTitle': jobTitle,
      });
    }

    return socialUser;
  }

  /// Completa el registro de un usuario social usando una invitación por email
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

    // Actualizar jobTitle si se proporcionó
    if (jobTitle != null && jobTitle.isNotEmpty) {
      await _userService.updateUserProfile(socialUser.uid, {
        'jobTitle': jobTitle,
      });
    }

    // Marcar la invitación como aceptada
    await invitationService.acceptInvitation(invitation.id);

    return socialUser;
  }

  /// Registra una nueva institución con un administrador que viene de login social
  /// El usuario social ya está autenticado, solo necesita subir docs y crear Firestore
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
    // Verificar si el NIT ya está registrado
    final nitExists = await _institutionService.isNitRegistered(institutionNit);
    if (nitExists) {
      throw AuthException(
        code: 'nit-already-exists',
        message: 'El NIT ya está registrado en el sistema.',
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

      // PASO 2: Crear la institución en Firestore
      onProgress?.call('Creando institución...');
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

      // Actualizar jobTitle si se proporcionó
      if (jobTitle != null && jobTitle.isNotEmpty) {
        await _userService.updateUserProfile(socialUser.uid, {
          'jobTitle': jobTitle,
        });
      }

      return socialUser;
    } catch (e) {
      // Rollback: Si algo falla después de crear la institución
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
