import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'incident_detail_screen.dart';
import '../services/event_service.dart';

class IncidentManagementScreen extends StatefulWidget {
  const IncidentManagementScreen({super.key});

  @override
  _IncidentManagementScreenState createState() => _IncidentManagementScreenState();
}

class _IncidentManagementScreenState extends State<IncidentManagementScreen> {
  final EventService _eventService = EventService();
  Stream<QuerySnapshot>? _incidentsStream;
  bool _isLoading = true;
  String? _error;

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
          _error = 'No se encontró la institución del usuario.';
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
      appBar: AppBar(
        title: const Text('Gestión de incidentes'),
      ),
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
                  Text(
                    'Error: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
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

        final incidents = snapshot.data!.docs;

        return ListView.builder(
          itemCount: incidents.length,
          itemBuilder: (context, index) {
            final incident = incidents[index];
            final data = incident.data() as Map<String, dynamic>;

            final String tipo = data['tipo'] ?? 'No especificado';
            final String descripcion = data['descripcion'] ?? 'Sin descripcion';
            final String reportadoPor = data['reportadoPor_email'] ?? 'Anonimo';
            final Timestamp timestamp = data['fechaReporte'] ?? Timestamp.now();
            final String estado = data['estado'] ?? 'desconocido';
            final String lugar = data['lugar'] ?? 'Sin lugar';
            final String categoria = data['categoria'] ?? 'Sin categoria';
            final String severidad = data['severidad'] ?? 'Sin severidad';

            final DateTime fechaReporte = timestamp.toDate();
            final String fechaFormateada =
                DateFormat('dd/MM/yyyy, hh:mm a').format(fechaReporte);

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
                    estado,
                    style: TextStyle(color: _getStatusTextColor(estado, scheme)),
                  ),
                  backgroundColor: _getStatusColor(estado, scheme),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          IncidentDetailScreen(eventDocument: incident),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Color _getStatusColor(String status, ColorScheme scheme) {
    final normalized = status.toLowerCase();
    if (normalized.contains('revisi')) {
      return scheme.tertiary;
    }
    switch (normalized) {
      case 'reportado':
        return scheme.primary;
      case 'resuelto':
      case 'solucionado':
        return scheme.secondary;
      default:
        return scheme.outline;
    }
  }

  Color _getStatusTextColor(String status, ColorScheme scheme) {
    final normalized = status.toLowerCase();
    if (normalized.contains('revisi')) {
      return scheme.onTertiary;
    }
    switch (normalized) {
      case 'reportado':
        return scheme.onPrimary;
      case 'resuelto':
      case 'solucionado':
        return scheme.onSecondary;
      default:
        return scheme.onSurface;
    }
  }

  Widget _buildMetaChip(BuildContext context, String label,
      {bool isSeverity = false}) {
    final scheme = Theme.of(context).colorScheme;
    final String normalized = label.toLowerCase();
    Color backgroundColor = scheme.surfaceContainerHigh;
    Color textColor = scheme.onSurfaceVariant;

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
}
