
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/user_service.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/user_dashboard_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/super_admin_dashboard_screen.dart';
import 'screens/verification_pending_screen.dart';
import 'screens/verify_email_screen.dart';
import 'services/institution_service.dart';
import 'models/institution.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
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
    ).copyWith(
      secondary: accent,
      primary: seed,
      tertiary: tertiary,
    );
    final ColorScheme darkScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(
      secondary: accent,
      primary: seed,
      tertiary: tertiary,
    );

    return MaterialApp(
      title: 'SST',
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
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
      supportedLocales: const [
        Locale('es', 'CO'),
        Locale('es'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final userService = UserService();
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          // Si el email no está verificado, mostrar pantalla de verificación
          // NO hacer signOut aquí para no interrumpir el proceso de registro
          if (!user.emailVerified) {
            return const VerifyEmailScreen();
          }
          return FutureBuilder<String?>(
            future: userService.getUserRole(user.uid),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              final role = roleSnapshot.data;
              // Super admin del sistema
              if (role == 'admin') {
                return const SuperAdminDashboardScreen();
              }
              if (role == 'admin_sst') {
                // Obtener institución del admin y validar estado
                return FutureBuilder<String?>(
                  future: userService.getUserInstitutionId(user.uid),
                  builder: (context, instIdSnap) {
                    if (instIdSnap.connectionState == ConnectionState.waiting) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final institutionId = instIdSnap.data;
                    if (institutionId == null) {
                      // Sin institución asignada, volver al login
                      FirebaseAuth.instance.signOut();
                      return const LoginScreen();
                    }
                    final institutionService = InstitutionService();
                    return StreamBuilder<Institution?>(
                      stream: institutionService.streamInstitution(institutionId),
                      builder: (context, instSnap) {
                        if (instSnap.connectionState == ConnectionState.waiting) {
                          return const Scaffold(
                            body: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final institution = instSnap.data;
                        if (institution == null) {
                          // Institución no encontrada
                          return VerificationPendingScreen();
                        }
                        if (institution.status == InstitutionStatus.pending) {
                          return VerificationPendingScreen();
                        }
                        if (institution.status == InstitutionStatus.active) {
                          return const AdminDashboardScreen();
                        }
                        // rejected u otros estados => pantalla informativa
                        return VerificationPendingScreen();
                      },
                    );
                  },
                );
              }
              // Usuario normal o empleado
              if (role == 'user' || role == 'employee') {
                return const UserDashboardScreen();
              }
              return const LoginScreen();
            },
          );
        }
        return const LoginScreen();
      },
    );
  }
}
