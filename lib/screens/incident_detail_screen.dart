import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import '../services/event_service.dart';
import '../widgets/app_meta_chip.dart';
import 'full_screen_image_screen.dart';
import 'create_action_plan_screen.dart';
import 'report_details_screen.dart';

class IncidentDetailScreen extends StatefulWidget {
  final DocumentSnapshot eventDocument;

  const IncidentDetailScreen({super.key, required this.eventDocument});

  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen> {
  final EventService _eventService = EventService();
  String? _selectedStatus;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final currentStatus = EventService.canonicalStatus(
      (widget.eventDocument['estado'] ?? '').toString(),
    );
    _selectedStatus = EventService.manageableStatuses.contains(currentStatus)
        ? currentStatus
        : EventService.manageableStatuses.first;
  }

  Future<void> _updateStatus() async {
    final currentStatus = EventService.canonicalStatus(
      (widget.eventDocument['estado'] ?? '').toString(),
    );
    if (_selectedStatus == null || _selectedStatus == currentStatus) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _eventService.updateReportStatus(
        reportId: widget.eventDocument.id,
        status: _selectedStatus!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Estado actualizado correctamente')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar el estado: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showUpdatePlanStatusDialog(DocumentSnapshot planDoc) {
    final planData = planDoc.data() as Map<String, dynamic>;
    final currentStatus =
        (planData['status'] ?? planData['estado'] ?? 'pendiente').toString();
    final verificationController = TextEditingController(
      text: (planData['verificationNote'] ?? '').toString(),
    );
    final closureEvidenceController = TextEditingController(
      text: (planData['closureEvidence'] ?? '').toString(),
    );
    String verificationStatus = (planData['verificationStatus'] ?? 'pendiente')
        .toString();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        String? newStatus = currentStatus;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Actualizar estado del plan'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: newStatus,
                      decoration: const InputDecoration(
                        labelText: 'Estado del plan',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'pendiente',
                          child: Text('Pendiente'),
                        ),
                        DropdownMenuItem(
                          value: 'en_curso',
                          child: Text('En curso'),
                        ),
                        DropdownMenuItem(
                          value: 'ejecutado',
                          child: Text('Ejecutado'),
                        ),
                        DropdownMenuItem(
                          value: 'verificado',
                          child: Text('Verificado'),
                        ),
                        DropdownMenuItem(
                          value: 'cerrado',
                          child: Text('Cerrado'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            newStatus = value;
                          });
                        }
                      },
                    ),
                    if (newStatus == 'verificado' ||
                        newStatus == 'cerrado') ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: verificationStatus,
                        decoration: const InputDecoration(
                          labelText: 'Resultado de verificacion',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'pendiente',
                            child: Text('Pendiente'),
                          ),
                          DropdownMenuItem(
                            value: 'efectiva',
                            child: Text('Efectiva'),
                          ),
                          DropdownMenuItem(
                            value: 'requiere_ajuste',
                            child: Text('Requiere ajuste'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => verificationStatus = value);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: closureEvidenceController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Evidencia de cierre',
                          hintText: 'Ej: acta, foto, soporte o nota breve',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: verificationController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Nota de verificacion',
                          hintText: 'Resume como se verifico la eficacia',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    verificationController.dispose();
                    closureEvidenceController.dispose();
                    Navigator.pop(context);
                  },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final trimmedEvidence = closureEvidenceController.text
                        .trim();
                    final trimmedVerification = verificationController.text
                        .trim();
                    final requiresClosureFields =
                        newStatus == 'verificado' || newStatus == 'cerrado';
                    if (requiresClosureFields &&
                        trimmedEvidence.isEmpty &&
                        trimmedVerification.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Agrega evidencia de cierre o una nota de verificacion.',
                          ),
                        ),
                      );
                      return;
                    }

                    if (newStatus != null && newStatus != currentStatus ||
                        requiresClosureFields) {
                      final payload = <String, dynamic>{
                        'status': newStatus,
                        'estado': newStatus,
                        'updatedAt': FieldValue.serverTimestamp(),
                        'verificationStatus': requiresClosureFields
                            ? verificationStatus
                            : 'pendiente',
                        'verificationNote': trimmedVerification.isEmpty
                            ? null
                            : trimmedVerification,
                        'closureEvidence': trimmedEvidence.isEmpty
                            ? null
                            : trimmedEvidence,
                      };
                      if (newStatus == 'cerrado') {
                        payload['closedAt'] = FieldValue.serverTimestamp();
                        payload['closedBy'] =
                            FirebaseAuth.instance.currentUser?.uid;
                      }
                      await planDoc.reference.update(payload);
                    }
                    verificationController.dispose();
                    closureEvidenceController.dispose();
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                  child: const Text('Actualizar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = widget.eventDocument.data() as Map<String, dynamic>;

    final String tipo = (data['eventType'] ?? data['tipo'] ?? 'No especificado')
        .toString();
    final String descripcion = data['descripcion'] ?? 'Sin descripcion';
    final String reportadoPor = data['reportadoPor_email'] ?? 'Anonimo';
    final Timestamp timestamp = data['fechaReporte'] ?? Timestamp.now();
    final List<dynamic> fotoUrls = data['fotoUrls'] ?? [];
    final List<dynamic> videoUrls = data['videoUrls'] ?? [];
    final String categoria =
        (data['reportType'] ?? data['categoria'] ?? 'No especificada')
            .toString();
    final String severidad =
        (data['severity'] ?? data['severidad'] ?? 'No especificada').toString();
    final String lugar = _resolveLugar(data);
    final Timestamp? fechaEvento = data['fechaEvento'] as Timestamp?;
    final GeoPoint? ubicacionGps = data['ubicacionGps'] as GeoPoint?;
    final String? direccionGps = data['direccionGps'] as String?;

    final DateTime fechaReporte = timestamp.toDate();
    final String fechaFormateada = DateFormat(
      'dd/MM/yyyy, hh:mm a',
    ).format(fechaReporte);

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del reporte')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppMetaChip(
              icon: tipo == 'Accidente'
                  ? Icons.health_and_safety_outlined
                  : Icons.warning_amber_outlined,
              label: tipo.toUpperCase(),
              background: tipo == 'Accidente' ? scheme.error : scheme.tertiary,
              foreground: tipo == 'Accidente'
                  ? scheme.onError
                  : scheme.onTertiary,
              fontWeight: FontWeight.w700,
            ),
            const SizedBox(height: 16.0),
            Text(descripcion, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16.0),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReportDetailsScreen(
                        documentId: widget.eventDocument.id,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.timeline_outlined),
                label: const Text('Ver seguimiento del caso'),
              ),
            ),
            const SizedBox(height: 8.0),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Reportado por'),
              subtitle: Text(reportadoPor),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Fecha del reporte'),
              subtitle: Text(fechaFormateada),
            ),
            if (fechaEvento != null)
              ListTile(
                leading: const Icon(Icons.event),
                title: const Text('Fecha del evento'),
                subtitle: Text(
                  DateFormat(
                    'dd/MM/yyyy, hh:mm a',
                  ).format(fechaEvento.toDate()),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: const Text('Lugar / area'),
              subtitle: Text(lugar),
            ),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Categoria'),
              subtitle: Text(categoria),
            ),
            ListTile(
              leading: const Icon(Icons.warning_amber_outlined),
              title: const Text('Severidad'),
              subtitle: Text(severidad),
            ),
            if (ubicacionGps != null ||
                (direccionGps != null && direccionGps.isNotEmpty) ||
                _hasLocationGpsMap(data))
              ListTile(
                leading: const Icon(Icons.my_location),
                title: const Text('Ubicacion GPS'),
                subtitle: Text(
                  _resolveGpsText(data, ubicacionGps, direccionGps),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Estado actual'),
              subtitle: Text(widget.eventDocument['estado'] ?? 'desconocido'),
            ),
            const Divider(),
            const SizedBox(height: 16.0),
            if (fotoUrls.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fotos adjuntas:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8.0),
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: fotoUrls.length,
                      itemBuilder: (context, index) {
                        final url = fotoUrls[index] as String;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      FullScreenImageScreen(imageUrl: url),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8.0),
                              child: Image.network(
                                url,
                                fit: BoxFit.cover,
                                width: 150,
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    },
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(Icons.error);
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24.0),
                ],
              ),
            if (videoUrls.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Videos adjuntos:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8.0),
                  SizedBox(
                    height: 220,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: videoUrls.length,
                      itemBuilder: (context, index) {
                        final url = videoUrls[index] as String;
                        return Padding(
                          padding: const EdgeInsets.only(right: 12.0),
                          child: _NetworkVideoCard(url: url),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24.0),
                ],
              ),
            DropdownButtonFormField<String>(
              initialValue: _selectedStatus,
              decoration: const InputDecoration(
                labelText: 'Actualizar estado',
                border: OutlineInputBorder(),
              ),
              items: EventService.manageableStatuses
                  .map(
                    (status) => DropdownMenuItem(
                      value: status,
                      child: Text(EventService.statusLabel(status)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedStatus = value;
                  });
                }
              },
            ),
            const SizedBox(height: 24.0),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _updateStatus,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                ),
                child: _isSaving
                    ? SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Text('Guardar cambios'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CreateActionPlanScreen(
                        eventId: widget.eventDocument.id,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                ),
                child: const Text('Crear plan de accion'),
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 10),
            Text(
              'Planes de accion asociados:',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('planesDeAccion')
                  .where('eventoId', isEqualTo: widget.eventDocument.id)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('No hay planes de accion para este evento.'),
                  );
                }

                final planDocs = [...snapshot.data!.docs]
                  ..sort((a, b) {
                    final aData = a.data() as Map<String, dynamic>;
                    final bData = b.data() as Map<String, dynamic>;
                    final aDue = _planDueDate(aData);
                    final bDue = _planDueDate(bData);
                    if (aDue == null && bDue == null) return 0;
                    if (aDue == null) return 1;
                    if (bDue == null) return -1;
                    return aDue.compareTo(bDue);
                  });

                final pendingPlans = <DocumentSnapshot>[];
                final inProgressPlans = <DocumentSnapshot>[];
                final completedPlans = <DocumentSnapshot>[];

                for (final planDoc in planDocs) {
                  final planData = planDoc.data() as Map<String, dynamic>;
                  final derivedStatus = _derivedPlanStatus(planData);
                  if (derivedStatus == 'pendiente') {
                    pendingPlans.add(planDoc);
                  } else if (derivedStatus == 'en_curso' ||
                      derivedStatus == 'vencido') {
                    inProgressPlans.add(planDoc);
                  } else {
                    completedPlans.add(planDoc);
                  }
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildActionPlanSection(
                      context,
                      title: 'Pendientes',
                      subtitle: 'Acciones creadas que aun no han iniciado.',
                      plans: pendingPlans,
                    ),
                    _buildActionPlanSection(
                      context,
                      title: 'En seguimiento',
                      subtitle:
                          'Incluye acciones en curso y planes vencidos que requieren atencion.',
                      plans: inProgressPlans,
                    ),
                    _buildActionPlanSection(
                      context,
                      title: 'Verificados y cerrados',
                      subtitle:
                          'Acciones finalizadas con cierre o validacion registrada.',
                      plans: completedPlans,
                    ),
                  ],
                );
              },
            ),
          ],
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
      if (place.isNotEmpty) return place;
    }
    return (data['lugar'] ?? 'No especificado').toString();
  }

  bool _hasLocationGpsMap(Map<String, dynamic> data) {
    final location = data['location'];
    if (location is! Map<String, dynamic>) return false;
    final gps = location['gps'];
    if (gps is! Map<String, dynamic>) return false;
    final lat = gps['lat'];
    final lng = gps['lng'];
    return lat is num && lng is num;
  }

  String _resolveGpsText(
    Map<String, dynamic> data,
    GeoPoint? ubicacionGps,
    String? direccionGps,
  ) {
    if (direccionGps != null && direccionGps.isNotEmpty) {
      return direccionGps;
    }
    if (ubicacionGps != null) {
      return 'Lat: ${ubicacionGps.latitude.toStringAsFixed(5)}, Lng: ${ubicacionGps.longitude.toStringAsFixed(5)}';
    }
    final location = data['location'];
    if (location is Map<String, dynamic>) {
      final gps = location['gps'];
      if (gps is Map<String, dynamic>) {
        final address = (gps['address'] ?? '').toString().trim();
        if (address.isNotEmpty) return address;
        final lat = gps['lat'];
        final lng = gps['lng'];
        if (lat is num && lng is num) {
          return 'Lat: ${lat.toStringAsFixed(5)}, Lng: ${lng.toStringAsFixed(5)}';
        }
      }
    }
    return 'No capturada';
  }

  String _formatPlanValue(String raw) {
    final normalized = raw.trim().replaceAll('_', ' ');
    if (normalized.isEmpty) return 'No definido';
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  Color _planStatusColor(String rawStatus, ColorScheme scheme) {
    switch (rawStatus.trim().toLowerCase()) {
      case 'cerrado':
        return scheme.secondaryContainer;
      case 'verificado':
        return scheme.primaryContainer;
      case 'vencido':
        return scheme.errorContainer;
      case 'en_curso':
        return scheme.tertiaryContainer;
      case 'ejecutado':
        return scheme.secondaryContainer;
      case 'realizado':
        return scheme.secondaryContainer;
      case 'pendiente':
      default:
        return scheme.surfaceContainerHighest;
    }
  }

  Color _planStatusTextColor(String rawStatus, ColorScheme scheme) {
    switch (rawStatus.trim().toLowerCase()) {
      case 'cerrado':
        return scheme.onSecondaryContainer;
      case 'verificado':
        return scheme.onPrimaryContainer;
      case 'vencido':
        return scheme.onErrorContainer;
      case 'en_curso':
        return scheme.onTertiaryContainer;
      case 'ejecutado':
        return scheme.onSecondaryContainer;
      case 'realizado':
        return scheme.onSecondaryContainer;
      case 'pendiente':
      default:
        return scheme.onSurfaceVariant;
    }
  }

  IconData _planStatusIcon(String rawStatus) {
    switch (rawStatus.trim().toLowerCase()) {
      case 'cerrado':
      case 'realizado':
        return Icons.task_alt_outlined;
      case 'verificado':
        return Icons.verified_outlined;
      case 'vencido':
        return Icons.warning_amber_outlined;
      case 'en_curso':
        return Icons.sync_outlined;
      case 'ejecutado':
        return Icons.task_alt_outlined;
      case 'pendiente':
      default:
        return Icons.schedule_outlined;
    }
  }

  bool _isClosedPlanStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'cerrado' ||
        normalized == 'verificado' ||
        normalized == 'realizado';
  }

  DateTime? _planStartDate(Map<String, dynamic> data) {
    final start = data['startDate'] ?? data['fechaInicio'];
    if (start is Timestamp) {
      return start.toDate();
    }
    return null;
  }

  DateTime? _planDueDate(Map<String, dynamic> data) {
    final due = data['dueDate'] ?? data['fechaLimite'];
    if (due is Timestamp) {
      return due.toDate();
    }
    return null;
  }

  String _derivedPlanStatus(Map<String, dynamic> data) {
    final raw = (data['status'] ?? data['estado'] ?? 'pendiente').toString();
    final normalized = raw.trim().toLowerCase();
    if (_isClosedPlanStatus(normalized)) {
      return normalized;
    }
    final dueDate = _planDueDate(data);
    if (dueDate != null &&
        dueDate.isBefore(DateTime.now()) &&
        (normalized == 'pendiente' || normalized == 'en_curso')) {
      return 'vencido';
    }
    return normalized;
  }

  Widget _buildActionPlanCard(DocumentSnapshot planDoc, ColorScheme scheme) {
    final planData = planDoc.data() as Map<String, dynamic>;
    final estado = _derivedPlanStatus(planData);
    final actionType = (planData['actionType'] ?? planData['tipoAccion'] ?? '')
        .toString();
    final priority = (planData['priority'] ?? planData['prioridad'] ?? '')
        .toString();
    final verificationStatus = (planData['verificationStatus'] ?? '')
        .toString()
        .trim();
    final verificationNote = (planData['verificationNote'] ?? '')
        .toString()
        .trim();
    final executionNote = (planData['executionNote'] ?? '').toString().trim();
    final executionEvidence = (planData['executionEvidence'] ?? '')
        .toString()
        .trim();
    final executionAttachmentCount =
        (planData['executionAttachments'] is Iterable)
        ? (planData['executionAttachments'] as Iterable).length
        : 0;
    final closureEvidence = (planData['closureEvidence'] ?? '')
        .toString()
        .trim();
    final closureAttachmentCount = (planData['closureAttachments'] is Iterable)
        ? (planData['closureAttachments'] as Iterable).length
        : 0;
    final startDate = _planStartDate(planData);
    final dueDate = _planDueDate(planData);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: ListTile(
        title: Text(
          (planData['title'] ?? planData['descripcion'] ?? 'Sin descripcion')
              .toString(),
        ),
        subtitle: Text(
          'Responsable de la accion: ${planData['responsibleName'] ?? planData['asignadoA'] ?? 'N/A'}\n'
          '${actionType.isEmpty ? '' : 'Tipo: ${_formatPlanValue(actionType)} - '}${priority.isEmpty ? '' : 'Prioridad: ${_formatPlanValue(priority)}\n'}'
          '${startDate != null ? 'Inicio: ${DateFormat('dd/MM/yyyy').format(startDate)}\n' : ''}'
          'Limite: ${dueDate != null ? DateFormat('dd/MM/yyyy').format(dueDate) : 'No especificada'}'
          '${executionNote.isNotEmpty ? '\nAvance: $executionNote' : ''}'
          '${executionEvidence.isNotEmpty ? '\nSoporte del responsable: $executionEvidence' : ''}'
          '${executionAttachmentCount > 0 ? '\nEvidencias adjuntas: $executionAttachmentCount' : ''}'
          '${verificationStatus.isNotEmpty && verificationStatus != 'pendiente' ? '\nVerificacion: ${_formatPlanValue(verificationStatus)}' : ''}'
          '${verificationNote.isNotEmpty ? '\nNota: $verificationNote' : ''}'
          '${closureEvidence.isNotEmpty ? '\nEvidencia: $closureEvidence' : ''}'
          '${closureAttachmentCount > 0 ? '\nSoportes de validacion: $closureAttachmentCount' : ''}',
        ),
        trailing: AppMetaChip(
          icon: _planStatusIcon(estado),
          label: _formatPlanValue(estado),
          background: _planStatusColor(estado, scheme),
          foreground: _planStatusTextColor(estado, scheme),
        ),
        onTap: () => _showUpdatePlanStatusDialog(planDoc),
      ),
    );
  }

  Widget _buildActionPlanSection(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<DocumentSnapshot> plans,
  }) {
    if (plans.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          ...plans.map((planDoc) => _buildActionPlanCard(planDoc, scheme)),
        ],
      ),
    );
  }
}

class _NetworkVideoCard extends StatefulWidget {
  final String url;

  const _NetworkVideoCard({required this.url});

  @override
  State<_NetworkVideoCard> createState() => _NetworkVideoCardState();
}

class _NetworkVideoCardState extends State<_NetworkVideoCard> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.setLooping(true);
    _controller.setVolume(0);
    _controller.initialize().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: _controller.value.isInitialized
                  ? _controller.value.aspectRatio
                  : 16 / 9,
              child: _controller.value.isInitialized
                  ? VideoPlayer(_controller)
                  : Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
            ),
            IconButton(
              icon: Icon(
                _controller.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
                size: 52,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  if (_controller.value.isPlaying) {
                    _controller.pause();
                  } else {
                    _controller.play();
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
