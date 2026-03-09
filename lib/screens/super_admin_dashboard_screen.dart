import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/institution.dart';
import '../services/auth_service.dart';
import '../services/institution_service.dart';
import 'documents_admin_screen.dart';
import 'institution_review_screen.dart';
import 'super_admin_institutions_screen.dart';
import '../widgets/notification_permission_banner.dart';

/// Panel de Super Administrador para aprobaciones y gestion global.
class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  State<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  final InstitutionService _institutionService = InstitutionService();
  final AuthService _authService = AuthService();
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

  Future<void> _signOut() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Centro de control',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Super admin',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesion',
            onPressed: _signOut,
          ),
        ],
      ),
      body: StreamBuilder<List<Institution>>(
        stream: _institutionService.streamAllInstitutions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: scheme.error),
                    const SizedBox(height: 12),
                    Text(
                      'No se pudo cargar el panel',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final institutions = snapshot.data ?? const <Institution>[];
          final pending = institutions
              .where((item) => item.status == InstitutionStatus.pending)
              .toList();
          final activeCount = institutions
              .where((item) => item.status == InstitutionStatus.active)
              .length;
          final rejectedCount = institutions
              .where((item) => item.status == InstitutionStatus.rejected)
              .length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const NotificationPermissionBanner(),
              _buildHeaderCard(
                theme,
                pendingCount: pending.length,
                totalCount: institutions.length,
                activeCount: activeCount,
              ),
              const SizedBox(height: 20),
              _buildSectionHeader(
                context,
                title: 'Resumen global',
                subtitle:
                    'Vista general del sistema. Usa la gestión central para revisar instituciones.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _SummaryCard(
                    label: 'Pendientes',
                    value: pending.length.toString(),
                    icon: Icons.pending_actions_outlined,
                    color: scheme.primary,
                  ),
                  _SummaryCard(
                    label: 'Activas',
                    value: activeCount.toString(),
                    icon: Icons.verified_outlined,
                    color: Colors.green,
                  ),
                  _SummaryCard(
                    label: 'Rechazadas',
                    value: rejectedCount.toString(),
                    icon: Icons.block_outlined,
                    color: scheme.error,
                  ),
                  _SummaryCard(
                    label: 'Total',
                    value: institutions.length.toString(),
                    icon: Icons.account_balance_outlined,
                    color: scheme.secondary,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildSectionHeader(
                context,
                title: 'Accesos globales',
                subtitle: 'Herramientas centrales del sistema',
              ),
              const SizedBox(height: 12),
              _ActionCard(
                icon: Icons.account_balance_outlined,
                title: 'Gestionar instituciones',
                subtitle:
                    'Consulta, filtra y revisa el estado completo de cada institución',
                color: scheme.primary,
                badgeLabel: 'Principal',
                onTap: _openInstitutionsList,
              ),
              const SizedBox(height: 12),
              _ActionCard(
                icon: Icons.library_books_outlined,
                title: 'Documentos globales SST',
                subtitle:
                    'Gestiona la normativa común para todas las instituciones',
                color: scheme.secondary,
                badgeLabel: 'Clave',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AdminDocumentsScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              _buildSectionHeader(
                context,
                title: 'Instituciones pendientes',
                subtitle: pending.isEmpty
                    ? 'No hay solicitudes por revisar en este momento'
                    : 'Solicitudes que requieren decision del super admin',
              ),
              const SizedBox(height: 12),
              if (pending.isEmpty)
                _buildPendingEmptyState(theme)
              else
                ...pending.map(
                  (institution) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _InstitutionCard(
                      institution: institution,
                      onTap: () => _openReview(institution),
                      dateFormat: _dateFormat,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              _buildSectionHeader(
                context,
                title: 'Últimas instituciones registradas',
                subtitle: 'Acceso rapido a los registros mas recientes',
              ),
              const SizedBox(height: 12),
              if (institutions.isEmpty)
                _buildNoInstitutionsState(theme)
              else
                ...institutions
                    .take(5)
                    .map(
                      (institution) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _InstitutionOverviewCard(
                          institution: institution,
                          dateFormat: _dateFormat,
                          onTap: () => _openReview(institution),
                        ),
                      ),
                    ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard(
    ThemeData theme, {
    required int pendingCount,
    required int totalCount,
    required int activeCount,
  }) {
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.admin_panel_settings_outlined,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Control global SG-SST',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  pendingCount == 0
                      ? 'No hay solicitudes pendientes. Puedes gestionar documentos globales.'
                      : 'Tienes $pendingCount solicitud(es) pendiente(s) de revisión.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _headerPill(
                      label: '$pendingCount pendientes',
                      icon: Icons.pending_actions_outlined,
                    ),
                    _headerPill(
                      label: '$activeCount activas',
                      icon: Icons.verified_outlined,
                    ),
                    _headerPill(
                      label: '$totalCount en total',
                      icon: Icons.account_balance_outlined,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }

  Widget _headerPill({required String label, required IconData icon}) {
    return Builder(
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingEmptyState(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 40,
            color: Colors.green.withValues(alpha: 0.85),
          ),
          const SizedBox(height: 12),
          Text(
            'No hay instituciones pendientes',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Todas las solicitudes han sido procesadas. Mientras tanto, puedes gestionar la normativa global.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminDocumentsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.library_books_outlined),
            label: const Text('Abrir documentos globales'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoInstitutionsState(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.domain_disabled_outlined, size: 40, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            'Aún no hay instituciones registradas',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _openReview(Institution institution) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InstitutionReviewScreen(institution: institution),
      ),
    );
  }

  void _openInstitutionsList({InstitutionStatus? initialFilter}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            SuperAdminInstitutionsScreen(initialFilter: initialFilter),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
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
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
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
              child: Icon(icon, color: color, size: 20),
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

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final String? badgeLabel;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.badgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (badgeLabel != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              badgeLabel!,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: color,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstitutionCard extends StatelessWidget {
  final Institution institution;
  final VoidCallback onTap;
  final DateFormat dateFormat;

  const _InstitutionCard({
    required this.institution,
    required this.onTap,
    required this.dateFormat,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final createdDate = institution.createdAt?.toDate();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.business,
                      color: scheme.onPrimaryContainer,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          institution.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'NIT: ${institution.nit}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusChip(context, institution.status),
                  _metaChip(
                    context,
                    Icons.location_on_outlined,
                    '${institution.city}, ${institution.department}',
                  ),
                  if (createdDate != null)
                    _metaChip(
                      context,
                      Icons.schedule,
                      dateFormat.format(createdDate),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstitutionOverviewCard extends StatelessWidget {
  final Institution institution;
  final DateFormat dateFormat;
  final VoidCallback onTap;

  const _InstitutionOverviewCard({
    required this.institution,
    required this.dateFormat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final createdDate = institution.createdAt?.toDate();

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.account_balance_outlined,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      institution.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      createdDate != null
                          ? 'Registro: ${dateFormat.format(createdDate)}'
                          : 'Registro sin fecha',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusChip(context, institution.status),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _metaChip(BuildContext context, IconData icon, String label) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    ),
  );
}

Widget _statusChip(BuildContext context, InstitutionStatus status) {
  final scheme = Theme.of(context).colorScheme;
  final Color color;
  final String label;

  switch (status) {
    case InstitutionStatus.active:
      color = Colors.green;
      label = 'Activa';
      break;
    case InstitutionStatus.rejected:
      color = scheme.error;
      label = 'Rechazada';
      break;
    case InstitutionStatus.pending:
      color = scheme.primary;
      label = 'Pendiente';
      break;
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.28)),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
