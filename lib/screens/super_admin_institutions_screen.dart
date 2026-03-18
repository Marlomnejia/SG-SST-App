import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/institution.dart';
import '../services/institution_service.dart';
import 'institution_review_screen.dart';

class SuperAdminInstitutionsScreen extends StatefulWidget {
  final InstitutionStatus? initialFilter;

  const SuperAdminInstitutionsScreen({super.key, this.initialFilter});

  @override
  State<SuperAdminInstitutionsScreen> createState() =>
      _SuperAdminInstitutionsScreenState();
}

class _SuperAdminInstitutionsScreenState
    extends State<SuperAdminInstitutionsScreen> {
  final InstitutionService _institutionService = InstitutionService();
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

  InstitutionStatus? _selectedFilter;

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.initialFilter;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Instituciones registradas')),
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
                      'No se pudo cargar la lista',
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
          final filtered = _applyFilter(institutions);
          final pendingCount = institutions
              .where(
                (institution) =>
                    institution.status == InstitutionStatus.pending,
              )
              .length;
          final activeCount = institutions
              .where(
                (institution) => institution.status == InstitutionStatus.active,
              )
              .length;
          final suspendedCount = institutions
              .where(
                (institution) =>
                    institution.status == InstitutionStatus.suspended,
              )
              .length;
          final rejectedCount = institutions
              .where(
                (institution) =>
                    institution.status == InstitutionStatus.rejected,
              )
              .length;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _OverviewBanner(
                  selectedFilter: _selectedFilter,
                  totalCount: institutions.length,
                  pendingCount: pendingCount,
                  activeCount: activeCount,
                  suspendedCount: suspendedCount,
                  rejectedCount: rejectedCount,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FilterChip(
                        label: 'Todas',
                        selected: _selectedFilter == null,
                        onTap: () => setState(() => _selectedFilter = null),
                      ),
                      _FilterChip(
                        label: 'Pendientes',
                        selected: _selectedFilter == InstitutionStatus.pending,
                        onTap: () => setState(
                          () => _selectedFilter = InstitutionStatus.pending,
                        ),
                      ),
                      _FilterChip(
                        label: 'Activas',
                        selected: _selectedFilter == InstitutionStatus.active,
                        onTap: () => setState(
                          () => _selectedFilter = InstitutionStatus.active,
                        ),
                      ),
                      _FilterChip(
                        label: 'Suspendidas',
                        selected:
                            _selectedFilter == InstitutionStatus.suspended,
                        onTap: () => setState(
                          () => _selectedFilter = InstitutionStatus.suspended,
                        ),
                      ),
                      _FilterChip(
                        label: 'Rechazadas',
                        selected: _selectedFilter == InstitutionStatus.rejected,
                        onTap: () => setState(
                          () => _selectedFilter = InstitutionStatus.rejected,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Text(
                      '${filtered.length} resultado(s) visibles',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? _EmptyState(
                        title: _selectedFilter == null
                            ? 'Aún no hay instituciones registradas'
                            : 'No hay instituciones para este filtro',
                        subtitle: _selectedFilter == null
                            ? 'Cuando se registren instituciones aparecerán aquí para su revisión.'
                            : 'Prueba con otro estado para revisar más instituciones.',
                        actionLabel: _selectedFilter != null
                            ? 'Mostrar todas'
                            : null,
                        onAction: _selectedFilter != null
                            ? () => setState(() => _selectedFilter = null)
                            : null,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final institution = filtered[index];
                          return _InstitutionListCard(
                            institution: institution,
                            dateFormat: _dateFormat,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => InstitutionReviewScreen(
                                  institution: institution,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Institution> _applyFilter(List<Institution> institutions) {
    if (_selectedFilter == null) {
      return institutions;
    }

    return institutions
        .where((institution) => institution.status == _selectedFilter)
        .toList();
  }
}

class _InstitutionListCard extends StatelessWidget {
  final Institution institution;
  final DateFormat dateFormat;
  final VoidCallback onTap;

  const _InstitutionListCard({
    required this.institution,
    required this.dateFormat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final createdDate = institution.createdAt?.toDate();

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.account_balance_outlined,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      institution.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'NIT: ${institution.nit}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatusChip(status: institution.status),
                        _InfoChip(
                          icon: Icons.place_outlined,
                          label:
                              '${institution.city}, ${institution.department}',
                        ),
                        if (createdDate != null)
                          _InfoChip(
                            icon: Icons.schedule,
                            label: dateFormat.format(createdDate),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: scheme.primaryContainer,
      checkmarkColor: scheme.onPrimaryContainer,
      labelStyle: TextStyle(
        color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: scheme.surface,
      showCheckmark: false,
    );
  }
}

class _OverviewBanner extends StatelessWidget {
  final InstitutionStatus? selectedFilter;
  final int totalCount;
  final int pendingCount;
  final int activeCount;
  final int suspendedCount;
  final int rejectedCount;

  const _OverviewBanner({
    required this.selectedFilter,
    required this.totalCount,
    required this.pendingCount,
    required this.activeCount,
    required this.suspendedCount,
    required this.rejectedCount,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filterLabel = switch (selectedFilter) {
      InstitutionStatus.pending => 'Pendientes',
      InstitutionStatus.active => 'Activas',
      InstitutionStatus.suspended => 'Suspendidas',
      InstitutionStatus.rejected => 'Rechazadas',
      null => 'Todas',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.18),
            scheme.secondary.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vista de instituciones',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Filtro actual: $filterLabel',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _BannerPill(
                label: '$totalCount total',
                icon: Icons.account_balance_outlined,
              ),
              _BannerPill(
                label: '$pendingCount pendientes',
                icon: Icons.pending_actions_outlined,
              ),
              _BannerPill(
                label: '$activeCount activas',
                icon: Icons.verified_outlined,
              ),
              _BannerPill(
                label: '$suspendedCount suspendidas',
                icon: Icons.pause_circle_outline,
              ),
              _BannerPill(
                label: '$rejectedCount rechazadas',
                icon: Icons.block_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BannerPill extends StatelessWidget {
  final String label;
  final IconData icon;

  const _BannerPill({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final InstitutionStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late final Color color;
    late final String label;

    switch (status) {
      case InstitutionStatus.pending:
        color = scheme.primary;
        label = 'Pendiente';
        break;
      case InstitutionStatus.active:
        color = Colors.green;
        label = 'Activa';
        break;
      case InstitutionStatus.suspended:
        color = Colors.orange.shade700;
        label = 'Suspendida';
        break;
      case InstitutionStatus.rejected:
        color = scheme.error;
        label = 'Rechazada';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
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
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
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
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.domain_disabled_outlined,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
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
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
