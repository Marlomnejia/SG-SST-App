import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'firebase_options.dart';
import 'models/institution.dart';
import 'screens/action_plans_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/capacitaciones_screen.dart';
import 'screens/documents_admin_screen.dart';
import 'screens/documents_sst_screen.dart';
import 'screens/incident_management_screen.dart';
import 'screens/inspection_management_screen.dart';
import 'screens/login_screen.dart';
import 'screens/my_reports_screen.dart';
import 'screens/super_admin_dashboard_screen.dart';
import 'screens/super_admin_institutions_screen.dart';
import 'screens/training_admin_screen.dart';
import 'screens/user_dashboard_screen.dart';
import 'screens/verification_pending_screen.dart';
import 'screens/verify_email_screen.dart';
import 'services/auth_service.dart';
import 'services/device_settings_service.dart';
import 'services/institution_service.dart';
import 'services/notification_service.dart';
import 'services/user_service.dart';

final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final NotificationService _notificationService = NotificationService();
final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
const AndroidNotificationChannel _defaultNotificationChannel =
    AndroidNotificationChannel(
      'sst_alerts',
      'Alertas SG-SST',
      description: 'Notificaciones de eventos, capacitaciones y planes SG-SST',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
final Set<String> _notificationInitInProgress = <String>{};
Map<String, dynamic>? _pendingNotificationData;
String? _pendingNotificationKey;
String? _lastHandledNotificationKey;
bool _notificationNavigationInProgress = false;

String _messageNavigationKey(RemoteMessage message) {
  final raw = <String>[
    message.messageId ?? '',
    message.sentTime?.millisecondsSinceEpoch.toString() ?? '',
    message.data['type']?.toString() ?? '',
    message.data['trainingId']?.toString() ?? '',
    message.data['reportId']?.toString() ?? '',
  ];
  return raw.join('|');
}

Future<Widget?> _resolveNotificationDestination(
  Map<String, dynamic> data,
) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;

  final userDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .get();
  if (!userDoc.exists) return null;

  final userData = userDoc.data() ?? const <String, dynamic>{};
  final role = (userData['role'] ?? '').toString().trim().toLowerCase();
  final type = (data['type'] ?? '').toString().trim().toLowerCase();

  final isSuperAdmin = role == 'admin';
  final isAdminSst = role == 'admin_sst';
  final isUser = role == 'user' || role == 'employee';

  if (type == 'institution_pending' || type == 'institution_approved') {
    if (isSuperAdmin) {
      return const SuperAdminInstitutionsScreen();
    }
    return null;
  }

  if (type.startsWith('training_')) {
    if (isAdminSst) return const AdminTrainingScreen();
    if (isUser) return const CapacitacionesScreen();
    if (isSuperAdmin) return const SuperAdminDashboardScreen();
    return null;
  }

  if (type == 'document_published') {
    if (isAdminSst || isSuperAdmin) return const AdminDocumentsScreen();
    if (isUser) return const DocumentsSstScreen();
    return null;
  }

  if (type.startsWith('action_plan_')) {
    if (isAdminSst || isUser) return const ActionPlansScreen();
    if (isSuperAdmin) return const SuperAdminDashboardScreen();
    return null;
  }

  if (type.startsWith('inspection_')) {
    if (isAdminSst || isUser) return const InspectionManagementScreen();
    if (isSuperAdmin) return const SuperAdminDashboardScreen();
    return null;
  }

  if (type == 'report_status_changed') {
    if (isUser) return const MyReportsScreen();
    if (isAdminSst) return const IncidentManagementScreen();
    if (isSuperAdmin) return const SuperAdminDashboardScreen();
    return null;
  }

  if (type == 'event_created' || type == 'critical_event_created') {
    if (isAdminSst) return const IncidentManagementScreen();
    if (isSuperAdmin) return const SuperAdminDashboardScreen();
    if (isUser) return const UserDashboardScreen();
    return null;
  }

  return null;
}

Future<void> _tryProcessPendingNotificationNavigation() async {
  if (_notificationNavigationInProgress) return;
  final data = _pendingNotificationData;
  final key = _pendingNotificationKey;
  if (data == null || key == null) return;
  if (_lastHandledNotificationKey == key) return;

  _notificationNavigationInProgress = true;
  try {
    final destination = await _resolveNotificationDestination(data);
    if (destination == null) {
      return;
    }

    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;

    _pendingNotificationData = null;
    _pendingNotificationKey = null;
    _lastHandledNotificationKey = key;

    navigator.push(MaterialPageRoute(builder: (_) => destination));
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[FCM][navigate] error: $e');
    }
  } finally {
    _notificationNavigationInProgress = false;
  }
}

Future<void> _queueNotificationNavigation(RemoteMessage message) async {
  if (message.data.isEmpty) return;
  _pendingNotificationData = Map<String, dynamic>.from(message.data);
  _pendingNotificationKey = _messageNavigationKey(message);
  await _tryProcessPendingNotificationNavigation();
}

Future<void> _initLocalNotifications() async {
  if (kIsWeb) return;
  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  await _localNotificationsPlugin.initialize(settings);
  final androidPlugin = _localNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  await androidPlugin?.createNotificationChannel(_defaultNotificationChannel);
}

Future<void> _showForegroundSystemNotification(RemoteMessage message) async {
  if (kIsWeb) return;
  final notification = message.notification;
  if (notification == null) return;
  final title = notification.title ?? 'Notificacion';
  final body = notification.body ?? '';
  final androidDetails = AndroidNotificationDetails(
    _defaultNotificationChannel.id,
    _defaultNotificationChannel.name,
    channelDescription: _defaultNotificationChannel.description,
    importance: Importance.max,
    priority: Priority.max,
    icon: '@mipmap/ic_launcher',
    playSound: true,
    enableVibration: true,
    ticker: 'sg-sst-alert',
    styleInformation: body.isEmpty ? null : BigTextStyleInformation(body),
  );
  await _localNotificationsPlugin.show(
    message.messageId?.hashCode ??
        DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
    title,
    body.isEmpty ? null : body,
    NotificationDetails(android: androidDetails),
    payload: message.data['type'],
  );
}

Future<void> _syncNotificationTopicsForRole(String role) async {
  final messaging = FirebaseMessaging.instance;
  final normalizedRole = role.trim().toLowerCase();

  try {
    if (normalizedRole == 'admin') {
      await messaging.subscribeToTopic('role_admin');
      if (kDebugMode) {
        debugPrint('[FCM] Suscrito a topic role_admin');
      }
    } else {
      await messaging.unsubscribeFromTopic('role_admin');
      if (kDebugMode) {
        debugPrint('[FCM] Desuscrito de topic role_admin');
      }
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[FCM] Error sincronizando topic role_admin: $e');
    }
  }
}

Future<void> _ensureNotificationRegistration(User user) async {
  if (_notificationInitInProgress.contains(user.uid)) {
    return;
  }
  _notificationInitInProgress.add(user.uid);
  try {
    final userService = UserService();
    final userData = await userService.getUserData(user.uid);
    final role = (userData?['role'] ?? '').toString().trim();
    if (userData == null || role.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[FCM] Perfil incompleto o sin rol para uid=${user.uid}. Se omite registro de token.',
        );
      }
      return;
    }
    await _syncNotificationTopicsForRole(role);
    bool enabled = (userData['notificationsEnabled'] ?? true) == true;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    final osGranted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    // Asegura consistencia: este flujo exige notificaciones activas.
    if (!enabled) {
      await userService.setNotificationsEnabled(user.uid, true);
      enabled = true;
      if (kDebugMode) {
        debugPrint(
          '[FCM] Auto-recuperacion notificationsEnabled=true para uid=${user.uid}',
        );
      }
    }

    // Si el SDK ya expone token valido, sincronizalo de inmediato.
    final preDiagnostic = await _notificationService.getDiagnostic();
    final preToken = (preDiagnostic.currentToken ?? '').trim();
    final preAuthorized =
        preDiagnostic.authorizationStatus == AuthorizationStatus.authorized ||
        preDiagnostic.authorizationStatus == AuthorizationStatus.provisional;
    if (preAuthorized && preToken.isNotEmpty) {
      await userService.addFcmToken(user.uid, preToken);
      if (kDebugMode) {
        debugPrint('[FCM] Token previo sincronizado uid=${user.uid}');
      }
    }

    if (!osGranted && kDebugMode) {
      debugPrint(
        '[FCM] Permiso del sistema no concedido para uid=${user.uid}. Solicitando permiso.',
      );
    }
    final ok = await _notificationService.enableForUser(user.uid);
    if (kDebugMode) {
      debugPrint('[FCM] Registro token uid=${user.uid} ok=$ok');
    }
    if (ok) {
      return;
    }

    // Reintento corto: algunos dispositivos tardan en exponer el token tras
    // conceder permiso por primera vez.
    final diagnostic = await _notificationService.getDiagnostic();
    final canRetry =
        diagnostic.authorizationStatus == AuthorizationStatus.authorized ||
        diagnostic.authorizationStatus == AuthorizationStatus.provisional;
    if (!canRetry) return;

    final existingToken = diagnostic.currentToken?.trim() ?? '';
    if (existingToken.isNotEmpty) {
      await userService.addFcmToken(user.uid, existingToken);
      if (kDebugMode) {
        debugPrint(
          '[FCM] Token recuperado desde diagnostico para uid=${user.uid}',
        );
      }
      return;
    }

    await Future<void>.delayed(const Duration(seconds: 2));
    final retryOk = await _notificationService.enableForUser(user.uid);
    if (kDebugMode) {
      debugPrint('[FCM] Reintento token uid=${user.uid} ok=$retryOk');
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[FCM] Error registrando token para uid=${user.uid}: $e');
    }
  } finally {
    _notificationInitInProgress.remove(user.uid);
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
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    await _showForegroundSystemNotification(message);
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    if (kDebugMode) {
      debugPrint(
        '[FCM][opened] messageId=${message.messageId} data=${message.data}',
      );
    }
    await _queueNotificationNavigation(message);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _initLocalNotifications();
  await FirebaseMessaging.instance.setAutoInitEnabled(true);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  _setupForegroundNotificationHandlers();
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (kDebugMode && initialMessage != null) {
    debugPrint(
      '[FCM][initial] messageId=${initialMessage.messageId} data=${initialMessage.data}',
    );
  }
  if (initialMessage != null) {
    await _queueNotificationNavigation(initialMessage);
  }
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
      navigatorKey: appNavigatorKey,
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
      home: const _AppNotificationSetupGate(),
    );
  }
}

class _AppNotificationSetupGate extends StatefulWidget {
  const _AppNotificationSetupGate();

  @override
  State<_AppNotificationSetupGate> createState() =>
      _AppNotificationSetupGateState();
}

class _AppNotificationSetupGateState extends State<_AppNotificationSetupGate> {
  static const String _markerName = '.notification_setup_v2';

  final DeviceSettingsService _deviceSettingsService = DeviceSettingsService();

  bool _loading = true;
  bool _needsSetup = true;
  bool _granted = false;
  bool _requesting = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<File> _markerFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_markerName');
  }

  Future<bool> _hasMarker() async {
    try {
      final file = await _markerFile();
      return file.exists();
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveMarker() async {
    final file = await _markerFile();
    await file.writeAsString(DateTime.now().toIso8601String(), flush: true);
  }

  Future<void> _bootstrap() async {
    final hasMarker = await _hasMarker();
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    if (!mounted) return;
    setState(() {
      _granted = granted;
      _needsSetup = !hasMarker || !granted;
      _loading = false;
    });
  }

  Future<void> _requestPermission() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!mounted) return;
      setState(() => _granted = granted);
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Debes habilitar notificaciones.')),
        );
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _continue() async {
    if (!_granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Habilita notificaciones para continuar.'),
        ),
      );
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _saveMarker();
      if (!mounted) return;
      setState(() => _needsSetup = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_needsSetup) {
      return const AuthWrapper();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Configurar permisos')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.notifications_active_outlined,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Activa notificaciones para continuar',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Se usan para alertas y novedades del SG-SST.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _requesting ? null : _requestPermission,
                        icon: _requesting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: const Text('Habilitar notificaciones'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await _deviceSettingsService
                              .openNotificationSettings();
                        },
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Abrir ajustes de notificaciones'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () async {
                          await _deviceSettingsService.openAutoStartSettings();
                        },
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('Autoencendido en segundo plano'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () async {
                          await _deviceSettingsService.openAppSettings();
                        },
                        icon: const Icon(Icons.battery_alert_outlined),
                        label: const Text('Ajustes de bateria y segundo plano'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _continue,
                        child: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Continuar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  final UserService _userService = UserService();
  final InstitutionService _institutionService = InstitutionService();
  late final Stream<User?> _authStateStream;
  final Set<String> _profileBootstrapInProgress = <String>{};

  String? _cachedInstitutionStreamId;
  Stream<Institution?>? _cachedInstitutionStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authStateStream = FirebaseAuth.instance
        .authStateChanges()
        .asBroadcastStream();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _ensureNotificationRegistration(user);
    _tryProcessPendingNotificationNavigation();
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
    _notificationInitInProgress.clear();
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
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _ensureNotificationRegistration(user);
                _tryProcessPendingNotificationNavigation();
              });
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
