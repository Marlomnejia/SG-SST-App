import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../services/event_service.dart';
import '../services/storage_service.dart';
import '../services/user_service.dart';
import '../widgets/app_meta_chip.dart';
import 'create_action_plan_screen.dart';
import 'full_screen_image_screen.dart';

class ReportDetailsScreen extends StatefulWidget {
  final String documentId;

  const ReportDetailsScreen({super.key, required this.documentId});

  @override
  State<ReportDetailsScreen> createState() => _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends State<ReportDetailsScreen> {
  final _eventService = EventService();
  final _userService = UserService();
  final _dateFormat = DateFormat('dd/MM/yyyy, hh:mm a');
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _reportStream;
  late final Future<DocumentSnapshot<Map<String, dynamic>>> _legacyFuture;

  String? _role;
  bool _retryingAttachments = false;
  bool _updatingStatus = false;
  double _retryProgress = 0;

  bool get _canManageStatus => _role == 'admin' || _role == 'admin_sst';

  @override
  void initState() {
    super.initState();
    _reportStream = FirebaseFirestore.instance
        .collection('reports')
        .doc(widget.documentId)
        .snapshots();
    _legacyFuture = FirebaseFirestore.instance
        .collection('eventos')
        .doc(widget.documentId)
        .get();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final role = await _userService.getUserRole(uid);
    if (mounted) setState(() => _role = role);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }

  String _formatDate(dynamic value) {
    final date = _asDate(value);
    return date == null ? 'No disponible' : _dateFormat.format(date);
  }

  DateTime? _reportCreatedDate(Map<String, dynamic> data) {
    return _asDate(
      data['createdAt'] ?? data['fechaReporte'] ?? data['datetime'],
    );
  }

  DateTime? _reportUpdatedDate(Map<String, dynamic> data) {
    final direct = _asDate(data['updatedAt']);
    if (direct != null) return direct;
    final history = _historyEntries(data);
    DateTime? latest;
    for (final entry in history) {
      final candidate = entry['changedAt'] as DateTime?;
      if (candidate == null) continue;
      if (latest == null || candidate.isAfter(latest)) {
        latest = candidate;
      }
    }
    return latest ?? _reportCreatedDate(data);
  }

  DateTime? _reportClosedDate(Map<String, dynamic> data) {
    final direct = _asDate(data['closedAt'] ?? data['fechaCierre']);
    if (direct != null) return direct;
    final history = _historyEntries(data);
    DateTime? latestClosed;
    for (final entry in history) {
      final status = (entry['status'] ?? '').toString();
      if (_normalizeStatus(status) != 'cerrado') continue;
      final candidate = entry['changedAt'] as DateTime?;
      if (candidate == null) continue;
      if (latestClosed == null || candidate.isAfter(latestClosed)) {
        latestClosed = candidate;
      }
    }
    if (latestClosed != null) return latestClosed;
    final currentStatus = (data['status'] ?? data['estado'] ?? '').toString();
    if (_normalizeStatus(currentStatus) == 'cerrado') {
      return _reportUpdatedDate(data);
    }
    return null;
  }

  String _normalizeStatus(String raw) {
    final status = raw.trim().toLowerCase();
    if (status.contains('revisi')) return 'en_revision';
    if (status.contains('proceso')) return 'en_proceso';
    if (status.contains('solucion') ||
        status.contains('resuelto') ||
        status.contains('cerrad')) {
      return 'cerrado';
    }
    if (status.contains('rechaz')) return 'rechazado';
    if (status.contains('report')) return 'reportado';
    return status.replaceAll(' ', '_');
  }

  ({String label, IconData icon}) _statusMeta(String raw) {
    switch (_normalizeStatus(raw)) {
      case 'reportado':
        return (label: 'Reportado', icon: Icons.assignment_turned_in_outlined);
      case 'en_revision':
        return (label: 'En revision', icon: Icons.search_outlined);
      case 'en_proceso':
        return (label: 'En proceso', icon: Icons.build_outlined);
      case 'cerrado':
        return (label: 'Cerrado', icon: Icons.check_circle_outline);
      case 'rechazado':
        return (label: 'Rechazado', icon: Icons.cancel_outlined);
      default:
        final clean = raw.trim().replaceAll('_', ' ');
        final label = clean.isEmpty ? 'Estado desconocido' : clean;
        return (label: label, icon: Icons.info_outline);
    }
  }

  Color _statusChipBackground(String raw, ColorScheme scheme) {
    switch (_normalizeStatus(raw)) {
      case 'en_revision':
        return scheme.primaryContainer;
      case 'en_proceso':
        return scheme.tertiaryContainer;
      case 'cerrado':
        return scheme.secondaryContainer;
      case 'rechazado':
        return scheme.errorContainer;
      case 'reportado':
      default:
        return scheme.surfaceContainerHighest;
    }
  }

  Color _statusChipForeground(String raw, ColorScheme scheme) {
    switch (_normalizeStatus(raw)) {
      case 'en_revision':
        return scheme.onPrimaryContainer;
      case 'en_proceso':
        return scheme.onTertiaryContainer;
      case 'cerrado':
        return scheme.onSecondaryContainer;
      case 'rechazado':
        return scheme.onErrorContainer;
      case 'reportado':
      default:
        return scheme.onSurfaceVariant;
    }
  }

  List<String> _attachmentUrls(Map<String, dynamic> data, String type) {
    final urls = <String>[];
    final attachments = data['attachments'];
    if (attachments is List) {
      for (final item in attachments) {
        if (item is! Map) continue;
        if ((item['type'] ?? '').toString() != type) continue;
        final url = (item['url'] ?? '').toString().trim();
        if (url.isNotEmpty) urls.add(url);
      }
    }
    if (urls.isNotEmpty) return urls;
    final legacy = data[type == 'video' ? 'videoUrls' : 'fotoUrls'];
    if (legacy is List) {
      return legacy
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return urls;
  }

  String _resolvePlace(Map<String, dynamic> data) {
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

  String _resolveGps(Map<String, dynamic> data) {
    final legacyAddress = (data['direccionGps'] ?? '').toString().trim();
    if (legacyAddress.isNotEmpty) return legacyAddress;
    final legacyGps = data['ubicacionGps'];
    if (legacyGps is GeoPoint) {
      return 'Lat: ${legacyGps.latitude.toStringAsFixed(5)}, Lng: ${legacyGps.longitude.toStringAsFixed(5)}';
    }
    for (final key in ['location', 'gps']) {
      final source = data[key];
      final gps = key == 'location' && source is Map<String, dynamic>
          ? source['gps']
          : source;
      if (gps is! Map<String, dynamic>) continue;
      final address = (gps['address'] ?? '').toString().trim();
      if (address.isNotEmpty) return address;
      final lat = gps['lat'];
      final lng = gps['lng'];
      if (lat is num && lng is num) {
        return 'Lat: ${lat.toStringAsFixed(5)}, Lng: ${lng.toStringAsFixed(5)}';
      }
    }
    return 'No capturada';
  }

  DateTime? _planDueDate(Map<String, dynamic> data) {
    return _asDate(
      data['dueDate'] ?? data['fechaLimite'] ?? data['targetDate'],
    );
  }

  String _planStatusLabel(String raw) {
    final value = raw.trim().toLowerCase().replaceAll(' ', '_');
    if (value.contains('curso')) return 'En curso';
    if (value.contains('ejecut')) return 'Ejecutado';
    if (value.contains('verif')) return 'Verificado';
    if (value.contains('cerr')) return 'Cerrado';
    if (value.contains('venc')) return 'Vencido';
    return 'Pendiente';
  }

  ({Color bg, Color fg}) _planStatusColors(String raw, ColorScheme scheme) {
    final value = raw.trim().toLowerCase().replaceAll(' ', '_');
    if (value.contains('cerr') || value.contains('verif')) {
      return (bg: scheme.secondaryContainer, fg: scheme.onSecondaryContainer);
    }
    if (value.contains('ejecut')) {
      return (bg: scheme.tertiaryContainer, fg: scheme.onTertiaryContainer);
    }
    if (value.contains('curso')) {
      return (bg: scheme.primaryContainer, fg: scheme.onPrimaryContainer);
    }
    if (value.contains('venc')) {
      return (bg: scheme.errorContainer, fg: scheme.onErrorContainer);
    }
    return (bg: scheme.surfaceContainerHighest, fg: scheme.onSurfaceVariant);
  }

  Future<void> _openCreateActionPlan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CreateActionPlanScreen(eventId: widget.documentId),
      ),
    );
  }

  Future<void> _copyCaseNumber(String caseNumber) async {
    await Clipboard.setData(ClipboardData(text: caseNumber));
    _showMessage('Copiado');
  }

  Future<void> _changeStatus(String currentStatus) async {
    String selected =
        EventService.manageableStatuses.contains(
          _normalizeStatus(currentStatus),
        )
        ? _normalizeStatus(currentStatus)
        : EventService.manageableStatuses.first;
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cambiar estado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: const InputDecoration(
                  labelText: 'Nuevo estado',
                  border: OutlineInputBorder(),
                ),
                items: EventService.manageableStatuses
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(_statusMeta(status).label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => selected = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    final note = noteController.text;
    noteController.dispose();
    if (confirmed != true) return;
    setState(() => _updatingStatus = true);
    try {
      await _eventService.updateReportStatus(
        reportId: widget.documentId,
        status: selected,
        note: note,
      );
      _showMessage('Estado actualizado correctamente.');
    } catch (e) {
      _showMessage('No se pudo actualizar el estado: $e');
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  Future<void> _retryPendingAttachments(Map<String, dynamic> data) async {
    final raw = data['pendingAttachments'];
    if (raw is! List || raw.isEmpty) {
      _showMessage('No hay adjuntos locales disponibles para reintentar.');
      return;
    }
    final attachments = <ReportAttachmentInput>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final path = (item['path'] ?? '').toString().trim();
      if (path.isEmpty) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      attachments.add(
        ReportAttachmentInput(
          file: XFile(path),
          type: (item['type'] ?? 'image').toString(),
        ),
      );
    }
    if (attachments.isEmpty) {
      _showMessage('No se encontraron archivos para reintentar la subida.');
      return;
    }
    setState(() {
      _retryingAttachments = true;
      _retryProgress = 0;
    });
    try {
      await _eventService.retryPendingAttachments(
        reportId: widget.documentId,
        attachments: attachments,
        onUploadProgress: (progress) {
          if (mounted) setState(() => _retryProgress = progress);
        },
      );
      _showMessage('Adjuntos sincronizados correctamente.');
    } catch (e) {
      _showMessage('No se pudo completar el reintento: $e');
    } finally {
      if (mounted) {
        setState(() {
          _retryingAttachments = false;
          _retryProgress = 0;
        });
      }
    }
  }

  List<Map<String, dynamic>> _historyEntries(Map<String, dynamic> data) {
    final entries = <Map<String, dynamic>>[];
    final raw = data['statusHistory'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        entries.add({
          'status':
              (item['status'] ??
                      data['status'] ??
                      data['estado'] ??
                      'reportado')
                  .toString(),
          'changedAt': _asDate(item['changedAt']),
          'note': (item['note'] ?? '').toString(),
        });
      }
    }
    entries.sort((a, b) {
      final left =
          (a['changedAt'] as DateTime?) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final right =
          (b['changedAt'] as DateTime?) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return left.compareTo(right);
    });
    if (entries.isNotEmpty) return entries;
    return [
      {
        'status': (data['status'] ?? data['estado'] ?? 'reportado').toString(),
        'changedAt': _asDate(
          data['createdAt'] ?? data['fechaReporte'] ?? data['datetime'],
        ),
        'note': '',
        'fallback': true,
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del reporte')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _reportStream,
        builder: (context, reportSnapshot) {
          if (reportSnapshot.connectionState == ConnectionState.waiting &&
              !reportSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: _legacyFuture,
            builder: (context, legacySnapshot) {
              final reportData = reportSnapshot.data?.data();
              final legacyData = legacySnapshot.data?.data();
              if (reportData == null && legacyData == null) {
                if (legacySnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                return const Center(child: Text('No se encontro el reporte.'));
              }
              final data = <String, dynamic>{
                if (legacyData != null) ...legacyData,
                if (reportData != null) ...reportData,
              };
              final currentStatus =
                  (data['status'] ?? data['estado'] ?? 'reportado').toString();
              final statusMeta = _statusMeta(currentStatus);
              final history = _historyEntries(data);
              final caseNumber = (data['caseNumber'] ?? '').toString().trim();
              final reportedAt = _reportCreatedDate(data);
              final updatedAt = _reportUpdatedDate(data);
              final closedAt = _reportClosedDate(data);
              final imageUrls = _attachmentUrls(data, 'image');
              final videoUrls = _attachmentUrls(data, 'video');
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  caseNumber.isEmpty
                                      ? 'Caso sin numero'
                                      : caseNumber,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (caseNumber.isNotEmpty)
                                IconButton(
                                  onPressed: () => _copyCaseNumber(caseNumber),
                                  icon: const Icon(Icons.copy_outlined),
                                ),
                            ],
                          ),
                          Text(
                            _formatDate(reportedAt),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              AppMetaChip(
                                icon: statusMeta.icon,
                                label: statusMeta.label,
                                background: _statusChipBackground(
                                  currentStatus,
                                  scheme,
                                ),
                                foreground: _statusChipForeground(
                                  currentStatus,
                                  scheme,
                                ),
                              ),
                              AppMetaChip(
                                icon:
                                    (data['eventType'] ?? data['tipo'] ?? '')
                                            .toString()
                                            .trim()
                                            .toLowerCase() ==
                                        'accidente'
                                    ? Icons.health_and_safety_outlined
                                    : Icons.warning_amber_outlined,
                                label:
                                    (data['eventType'] ??
                                            data['tipo'] ??
                                            'No especificado')
                                        .toString(),
                              ),
                              AppMetaChip(
                                icon: Icons.flag_outlined,
                                label:
                                    (data['severity'] ??
                                            data['severidad'] ??
                                            'No especificada')
                                        .toString(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              AppMetaChip(
                                icon: Icons.event_available_outlined,
                                label: 'Reportado: ${_formatDate(reportedAt)}',
                              ),
                              if (updatedAt != null &&
                                  (reportedAt == null ||
                                      updatedAt.isAfter(
                                        reportedAt.add(
                                          const Duration(minutes: 1),
                                        ),
                                      )))
                                AppMetaChip(
                                  icon: Icons.update_outlined,
                                  label:
                                      'Actualizado: ${_formatDate(updatedAt)}',
                                ),
                              if (closedAt != null)
                                AppMetaChip(
                                  icon: Icons.task_alt_outlined,
                                  label: 'Cerrado: ${_formatDate(closedAt)}',
                                  background: scheme.secondaryContainer,
                                  foreground: scheme.onSecondaryContainer,
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            (data['reportType'] ??
                                    data['categoria'] ??
                                    'No especificado')
                                .toString(),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          if (_canManageStatus && reportData != null) ...[
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                onPressed: _updatingStatus
                                    ? null
                                    : () => _changeStatus(currentStatus),
                                icon: const Icon(Icons.sync_alt_outlined),
                                label: const Text('Cambiar estado'),
                              ),
                            ),
                          ],
                          if (_updatingStatus) ...[
                            const SizedBox(height: 8),
                            const LinearProgressIndicator(),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_canManageStatus) ...[
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Planes de accion asociados',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed: _openCreateActionPlan,
                                  icon: const Icon(Icons.playlist_add_outlined),
                                  label: const Text('Crear plan'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: FirebaseFirestore.instance
                                  .collection('planesDeAccion')
                                  .where(
                                    'eventoId',
                                    isEqualTo: widget.documentId,
                                  )
                                  .snapshots(),
                              builder: (context, plansSnapshot) {
                                if (plansSnapshot.connectionState ==
                                        ConnectionState.waiting &&
                                    !plansSnapshot.hasData) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: LinearProgressIndicator(
                                      minHeight: 2,
                                    ),
                                  );
                                }
                                final docs =
                                    plansSnapshot.data?.docs ??
                                    const <
                                      QueryDocumentSnapshot<
                                        Map<String, dynamic>
                                      >
                                    >[];
                                if (docs.isEmpty) {
                                  return Text(
                                    'No hay planes de accion para este caso.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  );
                                }
                                final ordered = [...docs]
                                  ..sort((a, b) {
                                    final left = _planDueDate(a.data());
                                    final right = _planDueDate(b.data());
                                    if (left == null && right == null) return 0;
                                    if (left == null) return 1;
                                    if (right == null) return -1;
                                    return left.compareTo(right);
                                  });
                                return Column(
                                  children: ordered.map((doc) {
                                    final plan = doc.data();
                                    final title =
                                        (plan['title'] ??
                                                plan['titulo'] ??
                                                'Plan sin titulo')
                                            .toString();
                                    final responsible =
                                        (plan['responsibleName'] ??
                                                plan['assignedToName'] ??
                                                'Sin responsable')
                                            .toString();
                                    final dueDate = _planDueDate(plan);
                                    final statusLabel = _planStatusLabel(
                                      (plan['status'] ?? plan['estado'] ?? '')
                                          .toString(),
                                    );
                                    final statusColors = _planStatusColors(
                                      (plan['status'] ?? plan['estado'] ?? '')
                                          .toString(),
                                      scheme,
                                    );
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: scheme.outlineVariant,
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  title,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyLarge
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Responsable: $responsible',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                                if (dueDate != null)
                                                  Text(
                                                    'Fecha limite: ${_dateFormat.format(dueDate)}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: scheme
                                                              .onSurfaceVariant,
                                                        ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          AppMetaChip(
                                            icon: Icons.assignment_turned_in,
                                            label: statusLabel,
                                            background: statusColors.bg,
                                            foreground: statusColors.fg,
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (reportData != null &&
                      data['attachmentsPending'] == true) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Adjuntos pendientes. Reintenta la subida.',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSecondaryContainer,
                                ),
                          ),
                          const SizedBox(height: 10),
                          if (_retryingAttachments) ...[
                            LinearProgressIndicator(value: _retryProgress),
                            const SizedBox(height: 6),
                            Text(
                              'Subiendo adjuntos: ${(_retryProgress * 100).toStringAsFixed(0)}%',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: scheme.onSecondaryContainer,
                                  ),
                            ),
                          ] else
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.tonalIcon(
                                onPressed: () => _retryPendingAttachments(data),
                                icon: const Icon(Icons.cloud_upload_outlined),
                                label: const Text('Reintentar adjuntos'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Seguimiento del caso',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          for (int index = 0; index < history.length; index++)
                            _TimelineRow(
                              data: history[index],
                              isLast: index == history.length - 1,
                              isActive: index == history.length - 1,
                              dateFormat: _dateFormat,
                              statusMeta: _statusMeta,
                            ),
                          if ((history.first['fallback'] ?? false) == true)
                            Text(
                              'No hay historial adicional. Este reporte fue registrado correctamente.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Informacion del reporte',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          _InfoRow(
                            label: 'Descripcion',
                            value:
                                (data['description'] ??
                                        data['descripcion'] ??
                                        'Sin descripcion')
                                    .toString(),
                          ),
                          _InfoRow(
                            label: 'Lugar / area',
                            value: _resolvePlace(data),
                          ),
                          _InfoRow(
                            label: 'Fecha del evento',
                            value: _formatDate(
                              data['datetime'] ?? data['fechaEvento'],
                            ),
                          ),
                          _InfoRow(
                            label: 'Fecha de reporte',
                            value: _formatDate(reportedAt),
                          ),
                          _InfoRow(
                            label: 'Ultima actualizacion',
                            value: _formatDate(updatedAt),
                          ),
                          if (closedAt != null)
                            _InfoRow(
                              label: 'Fecha de cierre',
                              value: _formatDate(closedAt),
                            ),
                          _InfoRow(
                            label: 'Ubicacion GPS',
                            value: _resolveGps(data),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (imageUrls.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Imagenes',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 6,
                                    mainAxisSpacing: 6,
                                  ),
                              itemCount: imageUrls.length,
                              itemBuilder: (context, index) => GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => FullScreenImageScreen(
                                      imageUrl: imageUrls[index],
                                    ),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    imageUrls[index],
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (videoUrls.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Videos',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 220,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: videoUrls.length,
                                itemBuilder: (context, index) => Padding(
                                  padding: EdgeInsets.only(
                                    right: index == videoUrls.length - 1
                                        ? 0
                                        : 12,
                                  ),
                                  child: _NetworkVideoCard(
                                    url: videoUrls[index],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
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
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isLast;
  final bool isActive;
  final DateFormat dateFormat;
  final ({String label, IconData icon}) Function(String) statusMeta;

  const _TimelineRow({
    required this.data,
    required this.isLast,
    required this.isActive,
    required this.dateFormat,
    required this.statusMeta,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = statusMeta((data['status'] ?? 'reportado').toString());
    final changedAt = data['changedAt'] as DateTime?;
    final note = (data['note'] ?? '').toString().trim();
    return IntrinsicHeight(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  Container(
                    width: isActive ? 18 : 14,
                    height: isActive ? 18 : 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Icon(
                      meta.icon,
                      size: isActive ? 10 : 8,
                      color: isActive
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: scheme.outlineVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isActive
                      ? scheme.primaryContainer.withValues(alpha: 0.28)
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isActive ? scheme.primary : scheme.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      changedAt == null
                          ? 'Fecha no disponible'
                          : dateFormat.format(changedAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        note,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
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
  VideoPlayerController? _previewController;
  bool _previewReady = false;
  bool _previewError = false;

  @override
  void initState() {
    super.initState();
    _initPreviewController();
  }

  @override
  void didUpdateWidget(covariant _NetworkVideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _disposePreviewController();
      _initPreviewController();
    }
  }

  void _initPreviewController() {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      setState(() {
        _previewError = true;
      });
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
    _previewController = controller;
    controller.setLooping(false);
    controller
        .initialize()
        .then((_) {
          if (!mounted || _previewController != controller) return;
          controller.pause();
          setState(() {
            _previewReady = true;
            _previewError = false;
          });
        })
        .catchError((_) {
          if (!mounted || _previewController != controller) return;
          setState(() {
            _previewReady = false;
            _previewError = true;
          });
        });
  }

  void _disposePreviewController() {
    _previewController?.dispose();
    _previewController = null;
    _previewReady = false;
    _previewError = false;
  }

  @override
  void dispose() {
    _disposePreviewController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 240,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _FullScreenVideoScreen(url: widget.url),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 128,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: scheme.surface,
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_previewReady && _previewController != null)
                      FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: _previewController!.value.size.width <= 0
                              ? 16
                              : _previewController!.value.size.width,
                          height: _previewController!.value.size.height <= 0
                              ? 9
                              : _previewController!.value.size.height,
                          child: VideoPlayer(_previewController!),
                        ),
                      )
                    else
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withValues(alpha: 0.18),
                              Colors.black.withValues(alpha: 0.32),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.26),
                      ),
                    ),
                    Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        size: 52,
                        color: Colors.white.withValues(alpha: 0.94),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _previewError
                              ? 'Vista previa no disponible'
                              : 'Toca para reproducir',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Video de evidencia',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Toca para abrir en pantalla completa.',
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

class _FullScreenVideoScreen extends StatefulWidget {
  final String url;

  const _FullScreenVideoScreen({required this.url});

  @override
  State<_FullScreenVideoScreen> createState() => _FullScreenVideoScreenState();
}

class _FullScreenVideoScreenState extends State<_FullScreenVideoScreen> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _loadError = false;
  bool _showPlayer = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.setLooping(true);
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {
            _ready = true;
          });
        })
        .catchError((_) {
          if (!mounted) return;
          setState(() {
            _loadError = true;
          });
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _togglePlayPause() {
    setState(() {
      if (!_showPlayer) {
        _showPlayer = true;
      }
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    });
  }

  Widget _buildPoster(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_circle_fill_rounded,
                size: 72,
                color: Colors.white.withValues(alpha: 0.92),
              ),
              const SizedBox(height: 10),
              Text(
                'Reproducir video',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video de evidencia'),
        actions: [
          IconButton(
            tooltip: 'Abrir externamente',
            onPressed: _openExternal,
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: Center(
        child: _loadError
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: scheme.error, size: 48),
                    const SizedBox(height: 10),
                    Text(
                      'No se pudo cargar el video en la app.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _openExternal,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Abrir externamente'),
                    ),
                  ],
                ),
              )
            : !_ready
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _showPlayer
                        ? Stack(
                            alignment: Alignment.center,
                            children: [
                              AspectRatio(
                                aspectRatio: _controller.value.aspectRatio == 0
                                    ? 16 / 9
                                    : _controller.value.aspectRatio,
                                child: VideoPlayer(_controller),
                              ),
                              IconButton(
                                iconSize: 64,
                                icon: Icon(
                                  _controller.value.isPlaying
                                      ? Icons.pause_circle_filled
                                      : Icons.play_circle_fill,
                                ),
                                color: Colors.white,
                                onPressed: _togglePlayPause,
                              ),
                            ],
                          )
                        : InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _togglePlayPause,
                            child: _buildPoster(context),
                          ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _openExternal,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Abrir externamente'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
