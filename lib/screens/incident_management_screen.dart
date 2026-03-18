import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/event_service.dart';
import 'report_details_screen.dart';

class IncidentManagementScreen extends StatefulWidget {
  const IncidentManagementScreen({super.key});

  @override
  State<IncidentManagementScreen> createState() =>
      _IncidentManagementScreenState();
}

class _IncidentManagementScreenState extends State<IncidentManagementScreen> {
  final EventService _eventService = EventService();
  Stream<QuerySnapshot>? _incidentsStream;
  bool _isLoading = true;
  String? _error;
  _IncidentFilter _selectedFilter = _IncidentFilter.open;

  @override
  void initState() {
    super.initState();
    _loadInstitutionAndEvents();
  }

  Future<void> _loadInstitutionAndEvents() async {
    try {
      final institutionId = await _eventService.getCurrentUserInstitutionId();
      if (institutionId == null) {
        setState(() {
          _error = 'No se encontro la institucion del usuario.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _incidentsStream = _eventService.getEventsStream(institutionId);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error al cargar los eventos: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Gestion de incidentes')),
      body: _buildBody(scheme),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: scheme.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = null;
                  });
                  _loadInstitutionAndEvents();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_incidentsStream == null) {
      return const Center(child: Text('No hay stream de eventos.'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _incidentsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: scheme.error),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}', textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 64,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'No hay reportes pendientes.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        }

        final incidents = snapshot.data!.docs.toList();
        incidents.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aStatus = _statusPriority(_normalizedStatus(aData));
          final bStatus = _statusPriority(_normalizedStatus(bData));
          if (_selectedFilter == _IncidentFilter.all && aStatus != bStatus) {
            return aStatus.compareTo(bStatus);
          }
          return _reportDate(bData).compareTo(_reportDate(aData));
        });

        final filteredIncidents = incidents.where((incident) {
          final data = incident.data() as Map<String, dynamic>;
          return _matchesFilter(_normalizedStatus(data));
        }).toList();

        final openCount = incidents.where((incident) {
          final data = incident.data() as Map<String, dynamic>;
          return _isOpenStatus(_normalizedStatus(data));
        }).length;
        final closedCount = incidents.length - openCount;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _IncidentFilter.values
                          .map(
                            (filter) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(_filterLabel(filter)),
                                selected: _selectedFilter == filter,
                                onSelected: (_) {
                                  setState(() => _selectedFilter = filter);
                                },
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _summaryLabel(
                      filter: _selectedFilter,
                      visibleCount: filteredIncidents.length,
                      openCount: openCount,
                      closedCount: closedCount,
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filteredIncidents.isEmpty
                  ? _buildFilteredEmptyState(context, scheme)
                  : _selectedFilter == _IncidentFilter.all
                  ? _buildSectionedList(context, scheme, filteredIncidents)
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: filteredIncidents.length,
                      itemBuilder: (context, index) => _buildIncidentCard(
                        context,
                        scheme,
                        filteredIncidents[index],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionedList(
    BuildContext context,
    ColorScheme scheme,
    List<QueryDocumentSnapshot<Object?>> incidents,
  ) {
    final openItems = incidents.where((incident) {
      final data = incident.data() as Map<String, dynamic>;
      return _isOpenStatus(_normalizedStatus(data));
    }).toList();
    final closedItems = incidents.where((incident) {
      final data = incident.data() as Map<String, dynamic>;
      return !_isOpenStatus(_normalizedStatus(data));
    }).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (openItems.isNotEmpty) ...[
          _buildSectionHeader(context, 'Casos abiertos', openItems.length),
          ...openItems.map(
            (incident) => _buildIncidentCard(context, scheme, incident),
          ),
        ],
        if (closedItems.isNotEmpty) ...[
          _buildSectionHeader(
            context,
            'Cerrados y rechazados',
            closedItems.length,
          ),
          ...closedItems.map(
            (incident) => _buildIncidentCard(context, scheme, incident),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, int count) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              '$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredEmptyState(BuildContext context, ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.filter_alt_off_outlined,
              size: 48,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.65),
            ),
            const SizedBox(height: 12),
            Text(
              'No hay incidentes para este filtro.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Prueba con otra vista para revisar mas casos.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentCard(
    BuildContext context,
    ColorScheme scheme,
    QueryDocumentSnapshot<Object?> incident,
  ) {
    final data = incident.data() as Map<String, dynamic>;

    final tipo = (data['eventType'] ?? data['tipo'] ?? 'No especificado')
        .toString();
    final descripcion =
        (data['descripcion'] ?? data['description'] ?? 'Sin descripcion')
            .toString();
    final reportadoPor =
        (data['reportadoPor_email'] ?? data['createdByEmail'] ?? 'Anonimo')
            .toString();
    final estado = _normalizedStatus(data);
    final lugar = _resolveLugar(data);
    final categoria =
        (data['reportType'] ?? data['categoria'] ?? 'Sin categoria').toString();
    final severidad = (data['severity'] ?? data['severidad'] ?? 'Sin severidad')
        .toString();
    final fechaFormateada = DateFormat(
      'dd/MM/yyyy, hh:mm a',
    ).format(_reportDate(data));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: scheme.surfaceContainerHighest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: ListTile(
        leading: Icon(
          tipo == 'Accidente' ? Icons.warning : Icons.report_problem,
          color: tipo == 'Accidente' ? scheme.error : scheme.tertiary,
        ),
        title: Text(descripcion, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$reportadoPor - $fechaFormateada'),
            Text(lugar),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildMetaChip(context, categoria),
                _buildMetaChip(context, severidad, isSeverity: true),
              ],
            ),
          ],
        ),
        trailing: Chip(
          label: Text(
            EventService.statusLabel(estado),
            style: TextStyle(color: _getStatusTextColor(estado, scheme)),
          ),
          backgroundColor: _getStatusColor(estado, scheme),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  ReportDetailsScreen(documentId: incident.id),
            ),
          );
        },
      ),
    );
  }

  Color _getStatusColor(String status, ColorScheme scheme) {
    switch (EventService.canonicalStatus(status)) {
      case 'reportado':
        return scheme.primary;
      case 'en_revision':
        return scheme.tertiary;
      case 'en_proceso':
        return scheme.secondary;
      case 'cerrado':
        return scheme.secondaryContainer;
      case 'rechazado':
        return scheme.errorContainer;
      default:
        return scheme.outline;
    }
  }

  Color _getStatusTextColor(String status, ColorScheme scheme) {
    switch (EventService.canonicalStatus(status)) {
      case 'reportado':
        return scheme.onPrimary;
      case 'en_revision':
        return scheme.onTertiary;
      case 'en_proceso':
        return scheme.onSecondary;
      case 'cerrado':
        return scheme.onSecondaryContainer;
      case 'rechazado':
        return scheme.onErrorContainer;
      default:
        return scheme.onSurface;
    }
  }

  Widget _buildMetaChip(
    BuildContext context,
    String label, {
    bool isSeverity = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final normalized = label.toLowerCase();
    var backgroundColor = scheme.surfaceContainerHigh;
    var textColor = scheme.onSurfaceVariant;

    if (isSeverity) {
      if (normalized.contains('leve')) {
        backgroundColor = scheme.secondaryContainer;
        textColor = scheme.onSecondaryContainer;
      } else if (normalized.contains('moderada')) {
        backgroundColor = scheme.tertiaryContainer;
        textColor = scheme.onTertiaryContainer;
      } else if (normalized.contains('grave')) {
        backgroundColor = scheme.errorContainer;
        textColor = scheme.onErrorContainer;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _resolveLugar(Map<String, dynamic> data) {
    final location = data['location'];
    if (location is Map<String, dynamic>) {
      final place = (location['placeName'] ?? '').toString().trim();
      final reference = (location['reference'] ?? '').toString().trim();
      if (place.isNotEmpty && reference.isNotEmpty) {
        return '$place / $reference';
      }
      if (place.isNotEmpty) {
        return place;
      }
    }
    return (data['lugar'] ?? 'Sin lugar').toString();
  }

  String _normalizedStatus(Map<String, dynamic> data) {
    return EventService.canonicalStatus(
      (data['status'] ?? data['estado'] ?? 'reportado').toString(),
    );
  }

  DateTime _reportDate(Map<String, dynamic> data) {
    final fechaReporte = data['fechaReporte'];
    if (fechaReporte is Timestamp) return fechaReporte.toDate();
    final createdAt = data['createdAt'];
    if (createdAt is Timestamp) return createdAt.toDate();
    final dateTime = data['datetime'];
    if (dateTime is Timestamp) return dateTime.toDate();
    return DateTime.now();
  }

  bool _isOpenStatus(String status) {
    switch (status) {
      case 'reportado':
      case 'en_revision':
      case 'en_proceso':
        return true;
      default:
        return false;
    }
  }

  int _statusPriority(String status) {
    if (_isOpenStatus(status)) return 0;
    if (status == 'cerrado') return 1;
    if (status == 'rechazado') return 2;
    return 3;
  }

  bool _matchesFilter(String status) {
    switch (_selectedFilter) {
      case _IncidentFilter.all:
        return true;
      case _IncidentFilter.open:
        return _isOpenStatus(status);
      case _IncidentFilter.inReview:
        return status == 'en_revision';
      case _IncidentFilter.inProgress:
        return status == 'en_proceso';
      case _IncidentFilter.closed:
        return status == 'cerrado';
      case _IncidentFilter.rejected:
        return status == 'rechazado';
    }
  }

  String _filterLabel(_IncidentFilter filter) {
    switch (filter) {
      case _IncidentFilter.all:
        return 'Todos';
      case _IncidentFilter.open:
        return 'Abiertos';
      case _IncidentFilter.inReview:
        return 'En revision';
      case _IncidentFilter.inProgress:
        return 'En proceso';
      case _IncidentFilter.closed:
        return 'Cerrados';
      case _IncidentFilter.rejected:
        return 'Rechazados';
    }
  }

  String _summaryLabel({
    required _IncidentFilter filter,
    required int visibleCount,
    required int openCount,
    required int closedCount,
  }) {
    switch (filter) {
      case _IncidentFilter.all:
        return '$visibleCount casos en total. $openCount abiertos y $closedCount cerrados o rechazados.';
      case _IncidentFilter.open:
        return '$visibleCount casos abiertos, ordenados por fecha mas reciente.';
      default:
        return '$visibleCount casos en la vista actual.';
    }
  }
}

enum _IncidentFilter { open, all, inReview, inProgress, closed, rejected }
