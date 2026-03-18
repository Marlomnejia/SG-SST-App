import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import 'capacitaciones_screen.dart';
import 'documents_sst_screen.dart';
import 'login_screen.dart';
import 'my_reports_screen.dart';
import 'profile_screen.dart';
import 'report_event_screen.dart';
import 'action_plans_screen.dart';
import 'inspection_management_screen.dart';
import '../widgets/app_skeleton_box.dart';

class UserDashboardScreen extends StatefulWidget {
  const UserDashboardScreen({super.key});

  @override
  State<UserDashboardScreen> createState() => _UserDashboardScreenState();
}

class _UserDashboardScreenState extends State<UserDashboardScreen> {
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, Future<String?>> _institutionNameFutures =
      <String, Future<String?>>{};
  final Map<String, Future<String?>> _institutionIdFutures =
      <String, Future<String?>>{};
  final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>>
  _reportSummaryStreams =
      <String, Stream<QuerySnapshot<Map<String, dynamic>>>>{};
  final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>>
  _videoTrainingStreams =
      <String, Stream<QuerySnapshot<Map<String, dynamic>>>>{};
  final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>>
  _userActionPlanStreams =
      <String, Stream<QuerySnapshot<Map<String, dynamic>>>>{};
  final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>>
  _userInspectionStreams =
      <String, Stream<QuerySnapshot<Map<String, dynamic>>>>{};
  final Map<String, Future<int>> _pendingTrainingCountFutures =
      <String, Future<int>>{};
  Map<String, dynamic>? _lastUserProfileData;
  String? _lastKnownInstitutionId;
  String? _lastKnownInstitutionName;

  Route<T> _userRoute<T>(Widget child) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, page) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curved);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(position: slide, child: page),
        );
      },
    );
  }

  Future<void> _confirmLogout() async {
    final bool? shouldLogout = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar cierre de sesion'),
          content: const Text('Estas seguro de que quieres cerrar sesion?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: const Text('Confirmar'),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      await _authService.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Color primary = scheme.primary;
    final Color softSurface = scheme.surface;
    final Color softBorder = scheme.outlineVariant;
    final Color background = scheme.surface;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('Panel personal'),
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesion',
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primary.withValues(alpha: 0.08),
                  scheme.tertiary.withValues(alpha: 0.06),
                  scheme.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: -70,
            right: -40,
            child: _buildGlowCircle(scheme.primary, 140),
          ),
          Positioned(
            bottom: -90,
            left: -40,
            child: _buildGlowCircle(scheme.secondary, 180),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildInstitutionInfoStrip(theme),
                const SizedBox(height: 12),
                _buildHeroCard(theme, primary),
                const SizedBox(height: 24),
                _buildSectionTitle(
                  context,
                  'Accesos principales',
                  subtitle:
                      'Tus herramientas frecuentes para reportar y hacer seguimiento.',
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    const double spacing = 14.0;
                    int columns;
                    if (width > 900) {
                      columns = 3;
                    } else {
                      final twoColumnWidth = (width - spacing) / 2;
                      columns = twoColumnWidth < 170 ? 1 : 2;
                    }
                    final double itemWidth =
                        (width - (columns - 1) * spacing) / columns;

                    return _buildMainActionsGrid(
                      context,
                      itemWidth: itemWidth,
                      spacing: spacing,
                      primary: primary,
                      softSurface: softSurface,
                      softBorder: softBorder,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(ThemeData theme, Color primary) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary.withValues(alpha: 0.9),
            theme.colorScheme.tertiary.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_buildHeroUserRow(theme)],
        ),
      ),
    );
  }

  Widget _buildInstitutionInfoStrip(ThemeData theme) {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<String?>(
      initialData: _lastKnownInstitutionId,
      future: _getInstitutionIdCached(user.uid),
      builder: (context, institutionIdSnap) {
        final institutionId = (institutionIdSnap.data ?? '').trim();
        if (institutionId.isNotEmpty) {
          _lastKnownInstitutionId = institutionId;
        }
        if (institutionId.isEmpty) {
          return const SizedBox.shrink();
        }

        return FutureBuilder<String?>(
          initialData: _lastKnownInstitutionName,
          future: _getInstitutionNameCached(institutionId),
          builder: (context, institutionNameSnap) {
            final institutionName = institutionNameSnap.data?.trim();
            if (institutionName != null && institutionName.isNotEmpty) {
              _lastKnownInstitutionName = institutionName;
            }
            if (institutionName == null || institutionName.isEmpty) {
              return const SizedBox.shrink();
            }

            final scheme = theme.colorScheme;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Container(
                    height: 34,
                    width: 34,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.school_outlined,
                      color: scheme.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Institucion actual',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          institutionName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSectionTitle(
    BuildContext context,
    String title, {
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        if (subtitle != null && subtitle.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMainActionsGrid(
    BuildContext context, {
    required double itemWidth,
    required double spacing,
    required Color primary,
    required Color softSurface,
    required Color softBorder,
  }) {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return _buildMainActionsWrap(
        context,
        itemWidth: itemWidth,
        spacing: spacing,
        primary: primary,
        softSurface: softSurface,
        softBorder: softBorder,
      );
    }

    return FutureBuilder<String?>(
      initialData: _lastKnownInstitutionId,
      future: _getInstitutionIdCached(user.uid),
      builder: (context, snapshot) {
        final institutionId = (snapshot.data ?? '').trim();
        if (institutionId.isNotEmpty) {
          _lastKnownInstitutionId = institutionId;
        }
        return _buildMainActionsWrap(
          context,
          itemWidth: itemWidth,
          spacing: spacing,
          primary: primary,
          softSurface: softSurface,
          softBorder: softBorder,
          uid: user.uid,
          institutionId: institutionId.isEmpty ? null : institutionId,
        );
      },
    );
  }

  Widget _buildMainActionsWrap(
    BuildContext context, {
    required double itemWidth,
    required double spacing,
    required Color primary,
    required Color softSurface,
    required Color softBorder,
    String? uid,
    String? institutionId,
  }) {
    final scheme = Theme.of(context).colorScheme;

    Widget reportsCard = _buildActionCard(
      context,
      icon: Icons.assignment_turned_in_outlined,
      title: 'Mis reportes',
      subtitle: 'Seguimiento personal',
      color: scheme.tertiary,
      backgroundColor: softSurface,
      borderColor: softBorder,
      onTap: () {
        Navigator.of(context).push(_userRoute(const MyReportsScreen()));
      },
    );

    if (uid != null && institutionId != null) {
      reportsCard = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getReportSummaryStream(institutionId: institutionId, uid: uid),
        builder: (context, snapshot) {
          final docs =
              snapshot.data?.docs ??
              const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final pendingCount = snapshot.hasData
              ? _countActiveReports(docs)
              : null;
          return _buildActionCard(
            context,
            icon: Icons.assignment_turned_in_outlined,
            title: 'Mis reportes',
            subtitle: 'Seguimiento personal',
            color: scheme.tertiary,
            backgroundColor: softSurface,
            borderColor: softBorder,
            pendingCount: pendingCount,
            onTap: () {
              Navigator.of(context).push(_userRoute(const MyReportsScreen()));
            },
          );
        },
      );
    }

    Widget trainingsCard = _buildActionCard(
      context,
      icon: Icons.school_outlined,
      title: 'Capacitaciones',
      subtitle: 'Gestion personal',
      color: scheme.primary,
      backgroundColor: softSurface,
      borderColor: softBorder,
      onTap: () {
        Navigator.of(context).push(_userRoute(const CapacitacionesScreen()));
      },
    );

    if (uid != null && institutionId != null) {
      trainingsCard = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getPublishedVideoTrainingsStream(institutionId: institutionId),
        builder: (context, trainingsSnap) {
          if (!trainingsSnap.hasData) {
            return _buildActionCard(
              context,
              icon: Icons.school_outlined,
              title: 'Capacitaciones',
              subtitle: 'Gestion personal',
              color: scheme.primary,
              backgroundColor: softSurface,
              borderColor: softBorder,
              onTap: () {
                Navigator.of(
                  context,
                ).push(_userRoute(const CapacitacionesScreen()));
              },
            );
          }
          final videoDocs =
              trainingsSnap.data?.docs ??
              const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          return FutureBuilder<int>(
            future: _getPendingTrainingCountFuture(
              uid: uid,
              videoDocs: videoDocs,
            ),
            builder: (context, pendingSnap) {
              final pendingCount = pendingSnap.data;
              return _buildActionCard(
                context,
                icon: Icons.school_outlined,
                title: 'Capacitaciones',
                subtitle: 'Gestion personal',
                color: scheme.primary,
                backgroundColor: softSurface,
                borderColor: softBorder,
                pendingCount: pendingCount,
                onTap: () {
                  Navigator.of(
                    context,
                  ).push(_userRoute(const CapacitacionesScreen()));
                },
              );
            },
          );
        },
      );
    }

    Widget plansCard = _buildActionCard(
      context,
      icon: Icons.event_available_outlined,
      title: 'Mis planes',
      subtitle: 'Acciones asignadas',
      color: scheme.secondary,
      backgroundColor: softSurface,
      borderColor: softBorder,
      onTap: () {
        Navigator.of(context).push(_userRoute(const ActionPlansScreen()));
      },
    );

    if (uid != null) {
      plansCard = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getUserActionPlansStream(uid: uid),
        builder: (context, snapshot) {
          final pendingCount = snapshot.hasData
              ? _countPendingAssignedPlans(
                  snapshot.data?.docs ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                  institutionId: institutionId,
                )
              : null;
          return _buildActionCard(
            context,
            icon: Icons.event_available_outlined,
            title: 'Mis planes',
            subtitle: 'Acciones asignadas',
            color: scheme.secondary,
            backgroundColor: softSurface,
            borderColor: softBorder,
            pendingCount: pendingCount,
            onTap: () {
              Navigator.of(context).push(_userRoute(const ActionPlansScreen()));
            },
          );
        },
      );
    }

    Widget inspectionsCard = _buildActionCard(
      context,
      icon: Icons.fact_check_outlined,
      title: 'Inspecciones',
      subtitle: 'Checklist asignados',
      color: scheme.tertiary,
      backgroundColor: softSurface,
      borderColor: softBorder,
      onTap: () {
        Navigator.of(
          context,
        ).push(_userRoute(const InspectionManagementScreen()));
      },
    );

    if (uid != null && institutionId != null) {
      inspectionsCard = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getUserInspectionsStream(
          institutionId: institutionId,
          uid: uid,
        ),
        builder: (context, snapshot) {
          final pendingCount = snapshot.hasData
              ? _countPendingInspections(
                  snapshot.data?.docs ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                )
              : null;
          return _buildActionCard(
            context,
            icon: Icons.fact_check_outlined,
            title: 'Inspecciones',
            subtitle: 'Checklist asignados',
            color: scheme.tertiary,
            backgroundColor: softSurface,
            borderColor: softBorder,
            pendingCount: pendingCount,
            onTap: () {
              Navigator.of(
                context,
              ).push(_userRoute(const InspectionManagementScreen()));
            },
          );
        },
      );
    }

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        SizedBox(
          width: itemWidth,
          child: _buildActionCard(
            context,
            icon: Icons.add_circle_outline,
            title: 'Reportar evento',
            subtitle: 'Incidente o accidente',
            color: primary,
            backgroundColor: softSurface,
            borderColor: softBorder,
            isPrimary: true,
            onTap: () {
              Navigator.of(context).push(_userRoute(const ReportEventScreen()));
            },
          ),
        ),
        SizedBox(width: itemWidth, child: trainingsCard),
        SizedBox(
          width: itemWidth,
          child: _buildActionCard(
            context,
            icon: Icons.picture_as_pdf_outlined,
            title: 'Documentos SST',
            subtitle: 'Normativa y manuales',
            color: scheme.secondary,
            backgroundColor: softSurface,
            borderColor: softBorder,
            onTap: () {
              Navigator.of(
                context,
              ).push(_userRoute(const DocumentsSstScreen()));
            },
          ),
        ),
        SizedBox(width: itemWidth, child: reportsCard),
        SizedBox(
          width: itemWidth,
          child: _buildActionCard(
            context,
            icon: Icons.person_outline,
            title: 'Perfil',
            subtitle: 'Configuracion de cuenta',
            color: scheme.primary,
            backgroundColor: softSurface,
            borderColor: softBorder,
            onTap: () {
              Navigator.of(context).push(_userRoute(const ProfileScreen()));
            },
          ),
        ),
        SizedBox(width: itemWidth, child: plansCard),
        SizedBox(width: itemWidth, child: inspectionsCard),
      ],
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color backgroundColor,
    required Color borderColor,
    required VoidCallback onTap,
    bool isPrimary = false,
    int? pendingCount,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final borderRadius = BorderRadius.circular(22);
    return Material(
      color: backgroundColor,
      borderRadius: borderRadius,
      elevation: 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(
            color: borderColor.withValues(alpha: isPrimary ? 0.95 : 0.82),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: borderRadius,
          splashColor: color.withValues(alpha: 0.14),
          highlightColor: color.withValues(alpha: 0.08),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 158),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 40,
                        width: 40,
                        decoration: BoxDecoration(
                          color: color.withValues(
                            alpha: isPrimary ? 0.2 : 0.12,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: color, size: 22),
                      ),
                      const Spacer(),
                      if (pendingCount != null && pendingCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: pendingCount > 0
                                ? scheme.errorContainer
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: pendingCount > 0
                                  ? scheme.error.withValues(alpha: 0.45)
                                  : scheme.outlineVariant,
                            ),
                          ),
                          child: Text(
                            pendingCount > 99 ? '99+' : '$pendingCount',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: pendingCount > 0
                                  ? scheme.onErrorContainer
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _countActiveReports(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) {
      final data = doc.data();
      final status = (data['estado'] ?? data['status'] ?? '').toString();
      return !_isClosedReportStatus(status);
    }).length;
  }

  bool _isClosedReportStatus(String rawStatus) {
    final status = _normalizeStatus(rawStatus);
    return status.contains('solucion') ||
        status.contains('resuelt') ||
        status.contains('cerrad') ||
        status.contains('finaliz') ||
        status == 'closed' ||
        status == 'resolved' ||
        status == 'done';
  }

  String _normalizeStatus(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _getReportSummaryStream({
    required String institutionId,
    required String uid,
  }) {
    final key = '$institutionId::$uid';
    return _reportSummaryStreams.putIfAbsent(
      key,
      () => _firestore
          .collection('eventos')
          .where('institutionId', isEqualTo: institutionId)
          .where('reportadoPor_uid', isEqualTo: uid)
          .snapshots()
          .asBroadcastStream(),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>
  _getPublishedVideoTrainingsStream({required String institutionId}) {
    return _videoTrainingStreams.putIfAbsent(
      institutionId,
      () => _firestore
          .collection('institutions')
          .doc(institutionId)
          .collection('trainings')
          .where('type', isEqualTo: 'video')
          .where('status', isEqualTo: 'published')
          .snapshots()
          .asBroadcastStream(),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _getUserActionPlansStream({
    required String uid,
  }) {
    return _userActionPlanStreams.putIfAbsent(
      uid,
      () => _firestore
          .collection('planesDeAccion')
          .where('responsibleUid', isEqualTo: uid)
          .snapshots()
          .asBroadcastStream(),
    );
  }

  int _countPendingAssignedPlans(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    String? institutionId,
  }) {
    return docs.where((doc) {
      final data = doc.data();
      final planInstitutionId = (data['institutionId'] ?? '').toString().trim();
      if (institutionId != null &&
          institutionId.isNotEmpty &&
          planInstitutionId.isNotEmpty &&
          planInstitutionId != institutionId) {
        return false;
      }
      final status = _normalizePlanStatus(
        (data['status'] ?? data['estado'] ?? '').toString(),
      );
      return status == 'pendiente' || status == 'en_curso';
    }).length;
  }

  String _normalizePlanStatus(String raw) {
    final normalized = raw.trim().toLowerCase().replaceAll(' ', '_');
    if (normalized.contains('curso')) return 'en_curso';
    if (normalized.contains('ejecut')) return 'ejecutado';
    if (normalized.contains('verif')) return 'verificado';
    if (normalized.contains('cerr')) return 'cerrado';
    return 'pendiente';
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _getUserInspectionsStream({
    required String institutionId,
    required String uid,
  }) {
    final key = '$institutionId::$uid';
    return _userInspectionStreams.putIfAbsent(
      key,
      () => _firestore
          .collection('institutions')
          .doc(institutionId)
          .collection('inspections')
          .where('assignedToUid', isEqualTo: uid)
          .snapshots()
          .asBroadcastStream(),
    );
  }

  int _countPendingInspections(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) {
      final status = _normalizeInspectionStatus(
        (doc.data()['status'] ?? '').toString(),
      );
      return status == 'scheduled' || status == 'in_progress';
    }).length;
  }

  String _normalizeInspectionStatus(String raw) {
    final value = raw.trim().toLowerCase().replaceAll(' ', '_');
    if (value.contains('progress') || value.contains('curso')) {
      return 'in_progress';
    }
    if (value.contains('find') || value.contains('hallazgo')) {
      return 'completed_with_findings';
    }
    if (value.contains('complet') || value.contains('cerrad')) {
      return 'completed';
    }
    if (value.contains('cancel')) {
      return 'cancelled';
    }
    return value.isEmpty ? 'scheduled' : value;
  }

  Future<int> _getPendingTrainingCountFuture({
    required String uid,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> videoDocs,
  }) {
    final ids = videoDocs.map((doc) => doc.id).toList()..sort();
    final key = '$uid::${ids.join(',')}';
    return _pendingTrainingCountFutures.putIfAbsent(
      key,
      () => _countPendingTrainingDocs(uid: uid, videoDocs: videoDocs),
    );
  }

  Future<int> _countPendingTrainingDocs({
    required String uid,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> videoDocs,
  }) async {
    if (videoDocs.isEmpty) return 0;
    final snapshots = await Future.wait(
      videoDocs.map(
        (doc) => doc.reference.collection('progress').doc(uid).get(),
      ),
    );
    final watched = snapshots.where((snap) {
      final data = snap.data();
      return data != null && data['watched'] == true;
    }).length;
    return (videoDocs.length - watched).clamp(0, videoDocs.length);
  }

  Widget _buildGlowCircle(Color color, double size) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.18),
      ),
    );
  }

  Widget _buildHeroUserRow(ThemeData theme) {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return _buildHeroUserContent(theme, user, null);
    }

    return StreamBuilder(
      stream: _userService.streamUserProfile(user.uid),
      builder: (context, snapshot) {
        final liveData = snapshot.data?.data();
        if (liveData != null) {
          _lastUserProfileData = Map<String, dynamic>.from(liveData);
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData &&
            _lastUserProfileData == null) {
          return _buildHeroUserSkeleton();
        }
        final data = liveData ?? _lastUserProfileData;
        return _buildHeroUserContent(theme, user, data);
      },
    );
  }

  Widget _buildHeroUserSkeleton() {
    return Row(
      children: [
        const AppSkeletonBox(
          height: 44,
          width: 44,
          borderRadius: BorderRadius.all(Radius.circular(22)),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeletonBox(
                height: 12,
                width: 90,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              SizedBox(height: 8),
              AppSkeletonBox(
                height: 16,
                width: 176,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              SizedBox(height: 8),
              AppSkeletonBox(
                height: 12,
                width: 140,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        AppSkeletonBox(
          height: 16,
          width: 72,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ],
    );
  }

  Widget _buildHeroUserContent(
    ThemeData theme,
    User? user,
    Map<String, dynamic>? data,
  ) {
    final displayName = _resolveDisplayName(data: data, user: user);
    final photoUrl = _resolvePhotoUrl(data: data, user: user);
    final roleLabel = _resolveRoleLabel(data);
    final greeting = _greetingForHour(DateTime.now().hour);
    final initials = _initialsFrom(displayName);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).push(_userRoute(const ProfileScreen()));
      },
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Colors.white24,
              backgroundImage: photoUrl == null || photoUrl.isEmpty
                  ? null
                  : NetworkImage(photoUrl),
              child: photoUrl == null || photoUrl.isEmpty
                  ? Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting,',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (roleLabel != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        roleLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              'Ver perfil',
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }

  String _greetingForHour(int hour) {
    if (hour < 12) {
      return 'Buenos dias';
    }
    if (hour < 18) {
      return 'Buenas tardes';
    }
    return 'Buenas noches';
  }

  String _resolveDisplayName({Map<String, dynamic>? data, User? user}) {
    final dataName = data?['displayName'] as String?;
    if (dataName != null && dataName.trim().isNotEmpty) {
      return dataName.trim();
    }
    final authName = user?.displayName;
    if (authName != null && authName.trim().isNotEmpty) {
      return authName.trim();
    }
    final email = user?.email;
    if (email != null && email.contains('@')) {
      return email.split('@').first;
    }
    return 'Usuario';
  }

  String? _resolvePhotoUrl({Map<String, dynamic>? data, User? user}) {
    final dataUrl = data?['photoUrl'] as String?;
    if (dataUrl != null && dataUrl.trim().isNotEmpty) {
      return dataUrl.trim();
    }
    final authUrl = user?.photoURL;
    if (authUrl != null && authUrl.trim().isNotEmpty) {
      return authUrl.trim();
    }
    return null;
  }

  String? _resolveRoleLabel(Map<String, dynamic>? data) {
    final role = (data?['role'] as String?)?.trim();
    if (role == null || role.isEmpty) {
      return null;
    }
    switch (role) {
      case 'admin_sst':
        return 'Admin SST';
      case 'admin':
        return 'Super Admin';
      default:
        return 'Usuario';
    }
  }

  Future<String?> _getInstitutionNameCached(String institutionId) {
    return _institutionNameFutures.putIfAbsent(
      institutionId,
      () => _userService.getInstitutionName(institutionId),
    );
  }

  Future<String?> _getInstitutionIdCached(String uid) {
    return _institutionIdFutures.putIfAbsent(
      uid,
      () => _userService.getUserInstitutionId(uid),
    );
  }

  String _initialsFrom(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.map((p) => p[0]).take(2).join();
    if (letters.isEmpty) {
      return 'U';
    }
    return letters.toUpperCase();
  }
}
