import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'models/institution.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/super_admin_dashboard_screen.dart';
import 'screens/user_dashboard_screen.dart';
import 'screens/verification_pending_screen.dart';
import 'screens/verify_email_screen.dart';
import 'services/auth_service.dart';
import 'services/institution_service.dart';
import 'services/notification_service.dart';
import 'services/user_service.dart';

final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final NotificationService _notificationService = NotificationService();
final Set<String> _notificationInitUsers = <String>{};

Future<void> _ensureNotificationRegistration(User user) async {
  if (_notificationInitUsers.contains(user.uid)) return;
  try {
    final userData = await UserService().getUserData(user.uid);
    final role = (userData?['role'] ?? '').toString().trim();
    if (userData == null || role.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[FCM] Perfil incompleto o sin rol para uid=${user.uid}. Se omite registro de token.',
        );
      }
      return;
    }
    _notificationInitUsers.add(user.uid);
    final enabled = (userData['notificationsEnabled'] ?? true) == true;
    if (!enabled) {
      if (kDebugMode) {
        debugPrint('[FCM] Notificaciones desactivadas para uid=${user.uid}');
      }
      return;
    }
    final ok = await _notificationService.enableForUser(user.uid);
    if (kDebugMode) {
      debugPrint('[FCM] Registro token uid=${user.uid} ok=$ok');
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[FCM] Error registrando token para uid=${user.uid}: $e');
    }
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kDebugMode) {
    debugPrint(
      '[FCM][background] messageId=${message.messageId} data=${message.data}',
    );
  }
}

void _setupForegroundNotificationHandlers() {
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    final title = notification.title ?? 'Notificacion';
    final body = notification.body ?? '';
    appScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(body.isEmpty ? title : '$title\n$body'),
        duration: const Duration(seconds: 4),
      ),
    );
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    final title = notification.title ?? 'Notificacion';
    final body = notification.body ?? '';
    appScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(body.isEmpty ? title : '$title\n$body'),
        duration: const Duration(seconds: 4),
      ),
    );
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  _setupForegroundNotificationHandlers();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const Color seed = Color(0xFF2F6E3A);
    const Color accent = Color(0xFFF0B429);
    const Color tertiary = Color(0xFF1F6F8B);
    final ColorScheme lightScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: const Color(0xFFF2F5F8),
    ).copyWith(secondary: accent, primary: seed, tertiary: tertiary);
    final ColorScheme darkScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(secondary: accent, primary: seed, tertiary: tertiary);

    return MaterialApp(
      title: 'SST',
      scaffoldMessengerKey: appScaffoldMessengerKey,
      theme: ThemeData(
        colorScheme: lightScheme,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        scaffoldBackgroundColor: lightScheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: lightScheme.primary,
          foregroundColor: lightScheme.onPrimary,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: lightScheme.surface,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: lightScheme.primary,
            foregroundColor: lightScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: darkScheme,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        scaffoldBackgroundColor: darkScheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: darkScheme.surface,
          foregroundColor: darkScheme.onSurface,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: darkScheme.surface,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: darkScheme.primary,
            foregroundColor: darkScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      themeMode: ThemeMode.system,
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final UserService _userService = UserService();
  final InstitutionService _institutionService = InstitutionService();
  late final Stream<User?> _authStateStream;
  final Set<String> _profileBootstrapInProgress = <String>{};

  String? _cachedInstitutionStreamId;
  Stream<Institution?>? _cachedInstitutionStream;

  @override
  void initState() {
    super.initState();
    _authStateStream = FirebaseAuth.instance
        .authStateChanges()
        .asBroadcastStream();
  }

  Stream<Institution?> _institutionStreamFor(String institutionId) {
    if (_cachedInstitutionStreamId != institutionId ||
        _cachedInstitutionStream == null) {
      _cachedInstitutionStreamId = institutionId;
      _cachedInstitutionStream = _institutionService.streamInstitution(
        institutionId,
      );
    }
    return _cachedInstitutionStream!;
  }

  void _resetAuthWrapperCaches() {
    _cachedInstitutionStreamId = null;
    _cachedInstitutionStream = null;
    _profileBootstrapInProgress.clear();
  }

  Future<String> _resolveInitialRole(User user) async {
    const allowedRoles = <String>{'admin', 'admin_sst', 'user', 'employee'};
    try {
      final tokenResult = await user.getIdTokenResult();
      final claimRole = (tokenResult.claims?['role'] ?? '').toString().trim();
      if (allowedRoles.contains(claimRole)) {
        return claimRole;
      }
    } catch (_) {}
    return 'user';
  }

  Future<void> _ensureUserProfileDocument(User user) async {
    if (_profileBootstrapInProgress.contains(user.uid)) return;
    _profileBootstrapInProgress.add(user.uid);
    try {
      final existing = await _userService.getUserData(user.uid);
      if (existing == null) {
        final role = await _resolveInitialRole(user);
        await _userService.createUserProfile(user, role: role);
        return;
      }

      final role = (existing['role'] ?? '').toString().trim();
      if (role.isEmpty) {
        final resolvedRole = await _resolveInitialRole(user);
        await _userService.updateUserProfile(user.uid, {'role': resolvedRole});
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[AuthWrapper] No se pudo sincronizar users/${user.uid}: $e',
        );
      }
    } finally {
      _profileBootstrapInProgress.remove(user.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStateStream,
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        if (AuthService.socialAuthFlowActive) {
          return const LoginScreen();
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          if (!user.emailVerified) {
            return const VerifyEmailScreen();
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _ensureNotificationRegistration(user);
          });
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _userService.streamUserProfile(user.uid),
            builder: (context, userSnap) {
              if (userSnap.connectionState == ConnectionState.waiting &&
                  !userSnap.hasData) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              final userDoc = userSnap.data;
              if (userDoc == null || !userDoc.exists) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _ensureUserProfileDocument(user);
                });
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              final userData = userDoc.data() ?? const <String, dynamic>{};
              final role = (userData['role'] ?? '').toString().trim();
              if (role.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _ensureUserProfileDocument(user);
                });
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (role == 'admin') {
                return const SuperAdminDashboardScreen();
              }
              if (role == 'admin_sst') {
                final institutionId = (userData['institutionId'] ?? '')
                    .toString()
                    .trim();
                if (institutionId.isEmpty) {
                  // Evita cerrar sesion automaticamente durante flujos de
                  // bootstrap/registro para no invalidar operaciones en curso
                  // (ej. carga de documentos en Storage).
                  return const LoginScreen();
                }
                return StreamBuilder<Institution?>(
                  stream: _institutionStreamFor(institutionId),
                  builder: (context, instSnap) {
                    if (instSnap.connectionState == ConnectionState.waiting &&
                        !instSnap.hasData) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final institution = instSnap.data;
                    if (institution == null) {
                      return VerificationPendingScreen();
                    }
                    if (institution.status == InstitutionStatus.pending) {
                      return VerificationPendingScreen();
                    }
                    if (institution.status == InstitutionStatus.active) {
                      return const AdminDashboardScreen();
                    }
                    return VerificationPendingScreen();
                  },
                );
              }
              if (role == 'user' || role == 'employee') {
                final institutionId = (userData['institutionId'] ?? '')
                    .toString()
                    .trim();
                if (institutionId.isEmpty) {
                  // Evita cerrar sesion automaticamente durante flujos de
                  // bootstrap/registro para no invalidar operaciones en curso.
                  return const LoginScreen();
                }
                return const UserDashboardScreen();
              }
              return const LoginScreen();
            },
          );
        }
        _resetAuthWrapperCaches();
        return const LoginScreen();
      },
    );
  }
}
