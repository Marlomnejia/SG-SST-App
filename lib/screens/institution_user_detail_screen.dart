import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/sst_document_service.dart';
import '../services/training_service.dart';
import '../services/user_service.dart';

class InstitutionUserDetailScreen extends StatefulWidget {
  final String userId;
  final String institutionId;
  final String? institutionName;

  const InstitutionUserDetailScreen({
    super.key,
    required this.userId,
    required this.institutionId,
    this.institutionName,
  });

  @override
  State<InstitutionUserDetailScreen> createState() =>
      _InstitutionUserDetailScreenState();
}

class _InstitutionUserDetailScreenState
    extends State<InstitutionUserDetailScreen> {
  final UserService _userService = UserService();
  final TrainingService _trainingService = TrainingService();
  final SstDocumentService _documentService = SstDocumentService();
  final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
  late final Future<CurrentUserData?> _viewerFuture;

  @override
  void initState() {
    super.initState();
    _viewerFuture = _userService.getCurrentUser();
  }

  Future<_UserDetailMetrics> _loadMetrics(String institutionId) async {
    final results = await Future.wait<dynamic>([
      _userService.getUserReportCount(
        widget.userId,
        institutionId: institutionId,
      ),
      _trainingService.getCompletedTrainingCountForUser(
        institutionId: institutionId,
        userId: widget.userId,
      ),
      _documentService.getReadDocumentCountForUser(
        userId: widget.userId,
        institutionId: institutionId,
      ),
      _userService.getInstitutionName(institutionId),
    ]);

    return _UserDetailMetrics(
      reportCount: results[0] as int,
      completedTrainingCount: results[1] as int,
      readDocumentCount: results[2] as int,
      institutionName: widget.institutionName?.trim().isNotEmpty == true
          ? widget.institutionName!.trim()
          : ((results[3] as String?) ?? 'Institución no disponible'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del usuario')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userService.streamUserProfile(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _CenteredMessage(
              icon: Icons.error_outline,
              title: 'No se pudo cargar el usuario',
              subtitle: snapshot.error.toString(),
              color: scheme.error,
            );
          }

          final profile = snapshot.data?.data();
          if (profile == null) {
            return const _CenteredMessage(
              icon: Icons.person_off_outlined,
              title: 'Usuario no disponible',
              subtitle:
                  'Este perfil ya no existe o no se puede consultar en este momento.',
            );
          }

          final displayName = (profile['displayName'] ?? 'Usuario sin nombre')
              .toString();
          final email = (profile['email'] ?? 'Sin correo').toString();
          final role = (profile['role'] ?? 'user').toString();
          final jobTitle = (profile['jobTitle'] ?? '').toString();
          final photoUrl = (profile['photoUrl'] ?? '').toString();
          final notificationsEnabled =
              (profile['notificationsEnabled'] as bool?) ?? true;
          final registeredTokens = List<String>.from(
            profile['fcmTokens'] ?? const [],
          );
          final tokenCount = registeredTokens.length;
          final notificationReady = notificationsEnabled && tokenCount > 0;
          final createdAt = profile['createdAt'] as Timestamp?;
          final currentInstitutionId =
              (profile['institutionId'] ?? widget.institutionId)
                  .toString()
                  .trim();

          return FutureBuilder<_UserDetailMetrics>(
            future: _loadMetrics(currentInstitutionId),
            builder: (context, metricsSnap) {
              final metrics = metricsSnap.data;

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundImage: photoUrl.isNotEmpty
                              ? NetworkImage(photoUrl)
                              : null,
                          child: photoUrl.isEmpty
                              ? Text(
                                  displayName.isNotEmpty
                                      ? displayName.characters.first
                                            .toUpperCase()
                                      : 'U',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                email,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              if (jobTitle.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  jobTitle,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _InfoChip(
                                    icon: Icons.badge_outlined,
                                    label: _roleLabel(role),
                                    highlighted:
                                        role == 'admin_sst' || role == 'admin',
                                  ),
                                  _InfoChip(
                                    icon: notificationsEnabled
                                        ? Icons.notifications_active_outlined
                                        : Icons.notifications_off_outlined,
                                    label: notificationsEnabled
                                        ? 'Notificaciones activas'
                                        : 'Notificaciones desactivadas',
                                  ),
                                  _InfoChip(
                                    icon: Icons.key_outlined,
                                    label: 'Tokens: $tokenCount',
                                    highlighted: tokenCount > 0,
                                  ),
                                  _InfoChip(
                                    icon: notificationReady
                                        ? Icons.verified_outlined
                                        : Icons.warning_amber_outlined,
                                    label: notificationReady
                                        ? 'Listo para alertas'
                                        : 'Pendiente de configuracion',
                                    highlighted: notificationReady,
                                  ),
                                  _InfoChip(
                                    icon: Icons.event_outlined,
                                    label: createdAt != null
                                        ? 'Registro ${_dateTimeFormat.format(createdAt.toDate())}'
                                        : 'Sin fecha de registro',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Resumen del usuario',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (metricsSnap.connectionState == ConnectionState.waiting &&
                      metrics == null)
                    const Center(child: CircularProgressIndicator())
                  else if (metricsSnap.hasError)
                    _CenteredMessage(
                      icon: Icons.analytics_outlined,
                      title: 'No se pudieron cargar las metricas',
                      subtitle: metricsSnap.error.toString(),
                      color: scheme.error,
                    )
                  else if (metrics != null) ...[
                    _SummaryGrid(metrics: metrics),
                    const SizedBox(height: 20),
                    FutureBuilder<CurrentUserData?>(
                      future: _viewerFuture,
                      builder: (context, viewerSnap) {
                        final viewer = viewerSnap.data;
                        final canManageUser =
                            viewer?.role == 'admin' &&
                            viewer?.uid != widget.userId;

                        if (!canManageUser) {
                          return const SizedBox.shrink();
                        }

                        return Column(
                          children: [
                            _SectionCard(
                              title: 'Acciones de administración',
                              icon: Icons.admin_panel_settings_outlined,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (role == 'admin_sst')
                                    OutlinedButton.icon(
                                      onPressed: () => _changeRole(
                                        displayName: displayName,
                                        role: role,
                                      ),
                                      icon: const Icon(Icons.person_outline),
                                      label: const Text('Cambiar a Usuario'),
                                    )
                                  else
                                    FilledButton.tonalIcon(
                                      onPressed: () => _changeRole(
                                        displayName: displayName,
                                        role: role,
                                      ),
                                      icon: const Icon(
                                        Icons.verified_user_outlined,
                                      ),
                                      label: const Text(
                                        'Asignar como Admin SST',
                                      ),
                                    ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: () => _unlinkUser(
                                      displayName: displayName,
                                      role: role,
                                    ),
                                    icon: const Icon(Icons.link_off_outlined),
                                    label: const Text(
                                      'Desvincular de la institución',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: scheme.error,
                                      side: BorderSide(color: scheme.error),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        );
                      },
                    ),
                    _SectionCard(
                      title: 'Contexto',
                      icon: Icons.account_balance_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DetailRow(
                            label: 'Institución',
                            value: metrics.institutionName,
                          ),
                          _DetailRow(
                            label: 'Rol actual',
                            value: _roleLabel(role),
                          ),
                          _DetailRow(
                            label: 'Estado de notificaciones',
                            value: notificationsEnabled
                                ? 'Activadas'
                                : 'Desactivadas',
                          ),
                          _DetailRow(
                            label: 'Tokens registrados',
                            value: tokenCount.toString(),
                          ),
                          _DetailRow(
                            label: 'Diagnostico backend',
                            value: notificationReady
                                ? 'Listo para recibir alertas'
                                : 'Pendiente de configuracion',
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Super admin';
      case 'admin_sst':
        return 'Admin SST';
      default:
        return 'Usuario';
    }
  }

  Future<void> _changeRole({
    required String displayName,
    required String role,
  }) async {
    final makeAdminSst = role != 'admin_sst';
    final confirmed = await _showConfirmationDialog(
      title: makeAdminSst ? 'Asignar rol' : 'Cambiar rol',
      content: makeAdminSst
          ? 'Se asignará a $displayName como Admin SST de esta institución.'
          : 'Se cambiará el rol de $displayName a Usuario dentro de la institución.',
      confirmLabel: makeAdminSst ? 'Asignar' : 'Cambiar',
    );
    if (!confirmed) {
      return;
    }

    await _runUserMutation(
      successMessage: makeAdminSst
          ? '$displayName ahora es Admin SST.'
          : '$displayName ahora tiene rol Usuario.',
      operation: () => _userService.updateUserRole(
        widget.userId,
        makeAdminSst ? 'admin_sst' : 'user',
      ),
    );
  }

  Future<void> _unlinkUser({
    required String displayName,
    required String role,
  }) async {
    final confirmed = await _showConfirmationDialog(
      title: 'Desvincular usuario',
      content:
          'Se quitará a $displayName de esta institución. Si es Admin SST, volverá a rol Usuario.',
      confirmLabel: 'Desvincular',
      isDestructive: true,
    );
    if (!confirmed) {
      return;
    }

    await _runUserMutation(
      successMessage: '$displayName fue desvinculado de la institución.',
      popAfterSuccess: true,
      operation: () => _userService.unlinkUserFromInstitution(
        widget.userId,
        demoteFromInstitutionAdmin: role == 'admin_sst',
      ),
    );
  }

  Future<void> _runUserMutation({
    required Future<void> Function() operation,
    required String successMessage,
    bool popAfterSuccess = false,
  }) async {
    try {
      await operation();
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));

      if (popAfterSuccess) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo actualizar el usuario: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<bool> _showConfirmationDialog({
    required String title,
    required String content,
    required String confirmLabel,
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: isDestructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    return result == true;
  }
}

class _UserDetailMetrics {
  final int reportCount;
  final int completedTrainingCount;
  final int readDocumentCount;
  final String institutionName;

  const _UserDetailMetrics({
    required this.reportCount,
    required this.completedTrainingCount,
    required this.readDocumentCount,
    required this.institutionName,
  });
}

class _SummaryGrid extends StatelessWidget {
  final _UserDetailMetrics metrics;

  const _SummaryGrid({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetricCard(
          label: 'Reportes',
          value: metrics.reportCount.toString(),
          icon: Icons.assignment_outlined,
          color: scheme.primary,
        ),
        _MetricCard(
          label: 'Capacitaciones',
          value: metrics.completedTrainingCount.toString(),
          icon: Icons.school_outlined,
          color: scheme.secondary,
        ),
        _MetricCard(
          label: 'Documentos leidos',
          value: metrics.readDocumentCount.toString(),
          icon: Icons.library_books_outlined,
          color: Colors.teal,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 164,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlighted;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final backgroundColor = highlighted
        ? scheme.primaryContainer.withValues(alpha: 0.7)
        : scheme.surfaceContainerHighest;
    final foregroundColor = highlighted
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foregroundColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? color;

  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = color ?? scheme.onSurfaceVariant;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: iconColor),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
