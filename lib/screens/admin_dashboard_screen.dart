import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'incident_management_screen.dart';
import 'training_admin_screen.dart';
import 'documents_admin_screen.dart';
import 'invite_employee_screen.dart';
import 'institution_users_screen.dart';
import 'report_generation_screen.dart';
import 'action_plans_screen.dart';
import 'inspection_management_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  Future<void> _confirmLogout(BuildContext context) async {
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
      await AuthService().signOut();
      if (!context.mounted) {
        return;
      }
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
    final Color background = scheme.surface;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('Panel administrativo'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesion',
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
      body: FutureBuilder<_AdminDashboardContext?>(
        future: _loadAdminContext(),
        builder: (context, contextSnap) {
          final adminContext = contextSnap.data;
          return _buildDashboardContent(
            context,
            adminContext: adminContext,
            loadingContext:
                contextSnap.connectionState == ConnectionState.waiting &&
                !contextSnap.hasData,
          );
        },
      ),
    );
  }

  Future<void> _copyInstitutionCode(BuildContext context, String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: trimmed));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Codigo copiado: $trimmed')));
  }

  Widget _buildHeaderCard(
    BuildContext context,
    ThemeData theme,
    Color primary,
    Color accent,
    _AdminDashboardContext? adminContext,
  ) {
    final institutionName = adminContext?.institutionName.trim() ?? '';
    final inviteCode = adminContext?.inviteCode.trim() ?? '';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.admin_panel_settings_outlined,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Administracion SG-SST',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.school_outlined,
                        size: 14,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          institutionName.isEmpty
                              ? 'Institucion no asignada'
                              : institutionName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (inviteCode.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _copyInstitutionCode(context, inviteCode),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.key_outlined,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Codigo: $inviteCode',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.copy_outlined,
                              size: 14,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Admin',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<_AdminDashboardContext?> _loadAdminContext() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final data = userDoc.data() ?? <String, dynamic>{};
    final institutionId = (data['institutionId'] ?? '').toString().trim();
    if (institutionId.isEmpty) return null;
    final institutionDoc = await _firestore
        .collection('institutions')
        .doc(institutionId)
        .get();
    final institutionData = institutionDoc.data() ?? <String, dynamic>{};
    return _AdminDashboardContext(
      institutionId: institutionId,
      institutionName: (institutionData['name'] ?? '').toString(),
      inviteCode: (institutionData['inviteCode'] ?? '').toString(),
    );
  }

  Widget _buildDashboardContent(
    BuildContext context, {
    required _AdminDashboardContext? adminContext,
    required bool loadingContext,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Color primary = scheme.primary;
    final Color accent = scheme.secondary;

    final incidentsStream = adminContext == null
        ? null
        : _firestore
              .collection('eventos')
              .where('institutionId', isEqualTo: adminContext.institutionId)
              .snapshots()
              .asBroadcastStream();

    final inspectionsStream = adminContext == null
        ? null
        : _firestore
              .collection('institutions')
              .doc(adminContext.institutionId)
              .collection('inspections')
              .snapshots()
              .asBroadcastStream();

    final trainingsStream = adminContext == null
        ? null
        : _firestore
              .collection('institutions')
              .doc(adminContext.institutionId)
              .collection('trainings')
              .snapshots()
              .asBroadcastStream();

    final plansStream = adminContext == null
        ? null
        : _firestore
              .collection('planesDeAccion')
              .where('institutionId', isEqualTo: adminContext.institutionId)
              .snapshots()
              .asBroadcastStream();

    final invitationsStream = adminContext == null
        ? null
        : _firestore
              .collection('invitations')
              .where('institutionId', isEqualTo: adminContext.institutionId)
              .snapshots()
              .asBroadcastStream();

    final documentsStream = adminContext == null
        ? null
        : _firestore
              .collection('institutions')
              .doc(adminContext.institutionId)
              .collection('documents')
              .snapshots()
              .asBroadcastStream();

    Widget incidentsTile = _buildManagementTile(
      context,
      icon: Icons.assignment_late,
      title: 'Incidentes',
      subtitle: 'Revisar y gestionar reportes',
      color: primary,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const IncidentManagementScreen(),
          ),
        );
      },
    );
    if (incidentsStream != null) {
      incidentsTile = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: incidentsStream,
        builder: (context, snapshot) {
          final pendingCount = snapshot.hasData
              ? _countOpenIncidents(
                  snapshot.data?.docs ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                )
              : null;
          return _buildManagementTile(
            context,
            icon: Icons.assignment_late,
            title: 'Incidentes',
            subtitle: 'Revisar y gestionar reportes',
            color: primary,
            pendingCount: pendingCount,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const IncidentManagementScreen(),
                ),
              );
            },
          );
        },
      );
    }

    Widget inspectionsTile = _buildManagementTile(
      context,
      icon: Icons.checklist,
      title: 'Inspecciones',
      subtitle: 'Crear y asignar inspecciones',
      color: accent,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const InspectionManagementScreen(),
          ),
        );
      },
    );
    if (inspectionsStream != null) {
      inspectionsTile = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: inspectionsStream,
        builder: (context, snapshot) {
          final pendingCount = snapshot.hasData
              ? _countOpenInspections(
                  snapshot.data?.docs ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                )
              : null;
          return _buildManagementTile(
            context,
            icon: Icons.checklist,
            title: 'Inspecciones',
            subtitle: 'Crear y asignar inspecciones',
            color: accent,
            pendingCount: pendingCount,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const InspectionManagementScreen(),
                ),
              );
            },
          );
        },
      );
    }

    Widget trainingsTile = _buildManagementTile(
      context,
      icon: Icons.school,
      title: 'Capacitaciones',
      subtitle: 'Gestion de contenidos',
      color: scheme.tertiary,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AdminTrainingScreen()),
        );
      },
    );
    if (trainingsStream != null) {
      trainingsTile = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: trainingsStream,
        builder: (context, snapshot) {
          final pendingCount = snapshot.hasData
              ? _countTrainingDrafts(
                  snapshot.data?.docs ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                )
              : null;
          return _buildManagementTile(
            context,
            icon: Icons.school,
            title: 'Capacitaciones',
            subtitle: 'Gestion de contenidos',
            color: scheme.tertiary,
            pendingCount: pendingCount,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminTrainingScreen(),
                ),
              );
            },
          );
        },
      );
    }

    Widget plansTile = _buildManagementTile(
      context,
      icon: Icons.event_available,
      title: 'Planes de accion',
      subtitle: 'Seguimiento y validacion de tareas',
      color: scheme.secondaryContainer,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ActionPlansScreen()),
        );
      },
    );
    if (plansStream != null) {
      plansTile = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: plansStream,
        builder: (context, snapshot) {
          final pendingCount = snapshot.hasData
              ? _countPendingValidationPlans(
                  snapshot.data?.docs ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                )
              : null;
          return _buildManagementTile(
            context,
            icon: Icons.event_available,
            title: 'Planes de accion',
            subtitle: 'Seguimiento y validacion de tareas',
            color: scheme.secondaryContainer,
            pendingCount: pendingCount,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ActionPlansScreen(),
                ),
              );
            },
          );
        },
      );
    }

    Widget invitationsTile = _buildManagementTile(
      context,
      icon: Icons.person_add_alt_1,
      title: 'Invitar Empleados',
      subtitle: 'Enviar invitaciones por correo',
      color: scheme.secondary,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const InviteEmployeeScreen()),
        );
      },
    );
    if (invitationsStream != null) {
      invitationsTile = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: invitationsStream,
        builder: (context, snapshot) {
          final pendingCount = snapshot.hasData
              ? _countPendingInvitations(
                  snapshot.data?.docs ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                )
              : null;
          return _buildManagementTile(
            context,
            icon: Icons.person_add_alt_1,
            title: 'Invitar Empleados',
            subtitle: 'Enviar invitaciones por correo',
            color: scheme.secondary,
            pendingCount: pendingCount,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const InviteEmployeeScreen(),
                ),
              );
            },
          );
        },
      );
    }

    Widget documentsTile = _buildManagementTile(
      context,
      icon: Icons.picture_as_pdf_outlined,
      title: 'Documentos SST',
      subtitle: 'Normativa y formatos',
      color: scheme.secondary,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AdminDocumentsScreen()),
        );
      },
    );
    if (documentsStream != null) {
      documentsTile = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: documentsStream,
        builder: (context, snapshot) {
          final pendingCount = snapshot.hasData
              ? _countUnpublishedDocuments(
                  snapshot.data?.docs ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                )
              : null;
          return _buildManagementTile(
            context,
            icon: Icons.picture_as_pdf_outlined,
            title: 'Documentos SST',
            subtitle: 'Normativa y formatos',
            color: scheme.secondary,
            pendingCount: pendingCount,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminDocumentsScreen(),
                ),
              );
            },
          );
        },
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildHeaderCard(context, theme, primary, accent, adminContext),
        if (loadingContext) ...[
          const SizedBox(height: 20),
          const LinearProgressIndicator(minHeight: 2),
        ],
        const SizedBox(height: 20),
        _buildSectionTitle(context, 'Gestion principal'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final int columns = width > 900 ? 3 : 2;
            const double spacing = 12.0;
            final double itemWidth =
                (width - (columns - 1) * spacing) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                SizedBox(width: itemWidth, child: incidentsTile),
                SizedBox(width: itemWidth, child: inspectionsTile),
                SizedBox(width: itemWidth, child: trainingsTile),
                SizedBox(
                  width: itemWidth,
                  child: _buildManagementTile(
                    context,
                    icon: Icons.bar_chart,
                    title: 'Reportes',
                    subtitle: 'Exportar datos para auditorias',
                    color: scheme.primaryContainer,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ReportGenerationScreen(),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(width: itemWidth, child: plansTile),
                SizedBox(width: itemWidth, child: invitationsTile),
                SizedBox(width: itemWidth, child: documentsTile),
                SizedBox(
                  width: itemWidth,
                  child: _buildManagementTile(
                    context,
                    icon: Icons.groups_2_outlined,
                    title: 'Usuarios',
                    subtitle: 'Ver usuarios de la institucion',
                    color: scheme.tertiary,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const InstitutionUsersScreen(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  Widget _buildManagementTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    int? pendingCount,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      height: 40,
                      width: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color),
                    ),
                    const Spacer(),
                    if (pendingCount != null && pendingCount > 0)
                      _buildPendingBadge(
                        context,
                        count: pendingCount,
                        color: color,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingBadge(
    BuildContext context, {
    required int count,
    required Color color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isActive = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive
            ? scheme.errorContainer
            : scheme.surfaceContainerHighest.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isActive
              ? scheme.error.withValues(alpha: 0.45)
              : scheme.outlineVariant,
        ),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: isActive ? scheme.onErrorContainer : color,
        ),
      ),
    );
  }

  int _countOpenIncidents(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) {
      final status = _normalizeIncidentStatus(
        (doc.data()['estado'] ?? doc.data()['status'] ?? '').toString(),
      );
      return status != 'cerrado' && status != 'rechazado';
    }).length;
  }

  String _normalizeIncidentStatus(String raw) {
    final value = raw.trim().toLowerCase().replaceAll(' ', '_');
    if (value.contains('revisi')) return 'en_revision';
    if (value.contains('proceso')) return 'en_proceso';
    if (value.contains('solucion')) return 'cerrado';
    if (value.contains('cerrad')) return 'cerrado';
    if (value.contains('rechaz')) return 'rechazado';
    if (value.contains('report')) return 'reportado';
    return value;
  }

  int _countOpenInspections(
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

  int _countTrainingDrafts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) {
      final status = (doc.data()['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      return status == 'draft' || status.isEmpty;
    }).length;
  }

  int _countPendingValidationPlans(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) {
      final status = _normalizePlanStatus(
        (doc.data()['status'] ?? doc.data()['estado'] ?? '').toString(),
      );
      return status == 'ejecutado';
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

  int _countPendingInvitations(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) {
      final status = (doc.data()['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      return status == 'pending';
    }).length;
  }

  int _countUnpublishedDocuments(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) => doc.data()['isPublished'] != true).length;
  }
}

class TrainingManagementScreen extends StatelessWidget {
  const TrainingManagementScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const AdminTrainingScreen();
  }
}

class _AdminDashboardContext {
  final String institutionId;
  final String institutionName;
  final String inviteCode;

  const _AdminDashboardContext({
    required this.institutionId,
    required this.institutionName,
    required this.inviteCode,
  });
}

class ReportGenerationScreen extends StatelessWidget {
  const ReportGenerationScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const SgSstReportGenerationScreen();
  }
}
