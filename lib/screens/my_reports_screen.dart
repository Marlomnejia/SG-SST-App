import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'report_details_screen.dart';
import '../services/user_service.dart';
import '../widgets/app_meta_chip.dart';

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  final UserService _userService = UserService();
  final Map<String, Future<DocumentSnapshot<Map<String, dynamic>>>>
  _reportPreviewFutures = {};
  Stream<QuerySnapshot<Map<String, dynamic>>>? _reportsStream;
  String? _userId;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUserReports();
  }

  Future<void> _loadUserReports() async {
    try {
      _userId = FirebaseAuth.instance.currentUser?.uid;
      if (_userId == null) {
        setState(() {
          _error = 'No se pudo identificar al usuario.';
          _isLoading = false;
        });
        return;
      }

      // Obtener institutionId del usuario para cumplir con reglas de seguridad
      final institutionId = await _userService.getUserInstitutionId(_userId!);

      // Consulta con ambos filtros para cumplir con las reglas de Firestore
      if (institutionId != null) {
        _reportsStream = FirebaseFirestore.instance
            .collection('eventos')
            .where('institutionId', isEqualTo: institutionId)
            .where('reportadoPor_uid', isEqualTo: _userId)
            .orderBy('fechaReporte', descending: true)
            .snapshots();
      } else {
        _reportsStream = FirebaseFirestore.instance
            .collection('eventos')
            .where('reportadoPor_uid', isEqualTo: _userId)
            .orderBy('fechaReporte', descending: true)
            .snapshots();
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error al cargar los reportes: $e';
        _isLoading = false;
      });
    }
  }

  Color _getStatusColor(String status, ColorScheme scheme) {
    final normalized = _normalizeStatus(status);
    switch (normalized) {
      case 'en_revision':
        return scheme.primaryContainer;
      case 'cerrado':
        return scheme.secondaryContainer;
      case 'en_proceso':
        return scheme.tertiaryContainer;
      case 'rechazado':
        return scheme.errorContainer;
      case 'reportado':
      default:
        return scheme.surfaceContainerHighest;
    }
  }

  Color _getStatusTextColor(String status, ColorScheme scheme) {
    final normalized = _normalizeStatus(status);
    switch (normalized) {
      case 'en_revision':
        return scheme.onPrimaryContainer;
      case 'cerrado':
        return scheme.onSecondaryContainer;
      case 'en_proceso':
        return scheme.onTertiaryContainer;
      case 'rechazado':
        return scheme.onErrorContainer;
      case 'reportado':
      default:
        return scheme.onSurfaceVariant;
    }
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

  String _friendlyStatus(String raw) {
    switch (_normalizeStatus(raw)) {
      case 'en_revision':
        return 'En revisión';
      case 'en_proceso':
        return 'En proceso';
      case 'cerrado':
        return 'Cerrado';
      case 'rechazado':
        return 'Rechazado';
      case 'reportado':
        return 'Reportado';
      default:
        final clean = raw.trim().replaceAll('_', ' ');
        return clean.isEmpty ? 'Desconocido' : clean;
    }
  }

  IconData _statusIcon(String raw) {
    switch (_normalizeStatus(raw)) {
      case 'en_revision':
        return Icons.search_outlined;
      case 'en_proceso':
        return Icons.build_outlined;
      case 'cerrado':
        return Icons.check_circle_outline;
      case 'rechazado':
        return Icons.cancel_outlined;
      case 'reportado':
      default:
        return Icons.assignment_turned_in_outlined;
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _getStructuredPreview(
    String reportId,
  ) {
    return _reportPreviewFutures.putIfAbsent(
      reportId,
      () =>
          FirebaseFirestore.instance.collection('reports').doc(reportId).get(),
    );
  }

  String _previewText(
    Map<String, dynamic> legacyData,
    Map<String, dynamic>? structuredData,
  ) {
    if (structuredData != null) {
      final rawHistory = structuredData['statusHistory'];
      if (rawHistory is List && rawHistory.isNotEmpty) {
        Map<String, dynamic>? latest;
        DateTime? latestDate;
        for (final item in rawHistory) {
          if (item is! Map) continue;
          final changedAt = item['changedAt'];
          final date = changedAt is Timestamp ? changedAt.toDate() : null;
          if (latest == null) {
            latest = item.map((key, value) => MapEntry(key.toString(), value));
            latestDate = date;
            continue;
          }
          final fallbackDate = DateTime.fromMillisecondsSinceEpoch(0);
          final currentDate = latestDate ?? fallbackDate;
          final candidateDate = date ?? fallbackDate;
          if (candidateDate.isAfter(currentDate)) {
            latest = item.map((key, value) => MapEntry(key.toString(), value));
            latestDate = date;
          }
        }
        if (latest != null) {
          final note = (latest['note'] ?? '').toString().trim();
          if (note.isNotEmpty) {
            return note;
          }
          final when = latestDate != null
              ? DateFormat('dd/MM/yyyy, hh:mm a').format(latestDate)
              : null;
          final label = _friendlyStatus((latest['status'] ?? '').toString());
          if (when != null) {
            return '$label · $when';
          }
          if (label.isNotEmpty) {
            return 'Último estado: $label';
          }
        }
      }
    }
    return 'Toca para ver el seguimiento del caso';
  }

  DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }

  DateTime? _reportCreatedDate(
    Map<String, dynamic> legacyData,
    Map<String, dynamic>? structuredData,
  ) {
    return _asDate(
      structuredData?['createdAt'] ??
          legacyData['fechaReporte'] ??
          structuredData?['datetime'],
    );
  }

  DateTime? _reportUpdatedDate(
    Map<String, dynamic> legacyData,
    Map<String, dynamic>? structuredData,
  ) {
    final direct = _asDate(structuredData?['updatedAt']);
    if (direct != null) return direct;
    final rawHistory = structuredData?['statusHistory'];
    if (rawHistory is List) {
      DateTime? latest;
      for (final item in rawHistory) {
        if (item is! Map) continue;
        final candidate = _asDate(item['changedAt']);
        if (candidate == null) continue;
        if (latest == null || candidate.isAfter(latest)) {
          latest = candidate;
        }
      }
      if (latest != null) return latest;
    }
    return _reportCreatedDate(legacyData, structuredData);
  }

  DateTime? _reportClosedDate(
    Map<String, dynamic> legacyData,
    Map<String, dynamic>? structuredData,
  ) {
    final direct = _asDate(
      structuredData?['closedAt'] ?? legacyData['fechaCierre'],
    );
    if (direct != null) return direct;
    final rawHistory = structuredData?['statusHistory'];
    if (rawHistory is List) {
      DateTime? latestClosed;
      for (final item in rawHistory) {
        if (item is! Map) continue;
        final status = (item['status'] ?? '').toString();
        if (_normalizeStatus(status) != 'cerrado') continue;
        final candidate = _asDate(item['changedAt']);
        if (candidate == null) continue;
        if (latestClosed == null || candidate.isAfter(latestClosed)) {
          latestClosed = candidate;
        }
      }
      if (latestClosed != null) return latestClosed;
    }
    final currentStatus =
        (structuredData?['status'] ?? legacyData['estado'] ?? '').toString();
    if (_normalizeStatus(currentStatus) == 'cerrado') {
      return _reportUpdatedDate(legacyData, structuredData);
    }
    return null;
  }

  String _formatMetaDate(DateTime? value) {
    if (value == null) return 'No disponible';
    return DateFormat('dd/MM/yyyy, hh:mm a').format(value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Mis reportes enviados')),
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
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = null;
                  });
                  _loadUserReports();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_reportsStream == null) {
      return const Center(child: Text('No se pudieron cargar los reportes.'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _reportsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: ${snapshot.error}'),
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
                  'Aún no has enviado reportes.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        }

        final reports = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: reports.length,
          itemBuilder: (context, index) {
            final report = reports[index];
            final data = report.data();
            final tipo = (data['eventType'] ?? data['tipo'] ?? 'Incidente')
                .toString();
            final descripcion = (data['descripcion'] ?? 'Sin descripción')
                .toString();
            final estado = (data['estado'] ?? 'Desconocido').toString();
            final caseNumber = (data['caseNumber'] ?? '').toString();
            final lugar = _resolvePlace(data);

            return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: _getStructuredPreview(report.id),
              builder: (context, previewSnapshot) {
                final structuredData = previewSnapshot.data?.data();
                final displayStatus = (structuredData?['status'] ?? estado)
                    .toString();
                final attachmentsPending =
                    structuredData?['attachmentsPending'] == true;
                final previewText = _previewText(data, structuredData);
                final createdDate = _reportCreatedDate(data, structuredData);
                final updatedDate = _reportUpdatedDate(data, structuredData);
                final closedDate = _reportClosedDate(data, structuredData);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ReportDetailsScreen(documentId: report.id),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 48,
                                width: 48,
                                decoration: BoxDecoration(
                                  color: tipo == 'Accidente'
                                      ? scheme.errorContainer.withValues(
                                          alpha: 0.7,
                                        )
                                      : scheme.tertiaryContainer,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  tipo == 'Accidente'
                                      ? Icons.health_and_safety_outlined
                                      : Icons.warning_amber_outlined,
                                  color: tipo == 'Accidente'
                                      ? scheme.onErrorContainer
                                      : scheme.onTertiaryContainer,
                                ),
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
                                            descripcion,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(
                                              displayStatus,
                                              scheme,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                _statusIcon(displayStatus),
                                                size: 14,
                                                color: _getStatusTextColor(
                                                  displayStatus,
                                                  scheme,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                _friendlyStatus(displayStatus),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color:
                                                          _getStatusTextColor(
                                                            displayStatus,
                                                            scheme,
                                                          ),
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      [
                                        if (createdDate != null)
                                          _formatMetaDate(createdDate)
                                        else
                                          'Fecha no disponible',
                                        if (caseNumber.isNotEmpty) caseNumber,
                                      ].join('  |  '),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              AppMetaChip(
                                icon: Icons.place_outlined,
                                label: lugar,
                                maxWidth: 220,
                              ),
                              AppMetaChip(
                                icon: tipo == 'Accidente'
                                    ? Icons.health_and_safety_outlined
                                    : Icons.report_problem_outlined,
                                label: tipo,
                                maxWidth: 220,
                              ),
                              if (attachmentsPending)
                                AppMetaChip(
                                  icon: Icons.cloud_off_outlined,
                                  label: 'Adjuntos pendientes',
                                  background: scheme.secondaryContainer,
                                  foreground: scheme.onSecondaryContainer,
                                  maxWidth: 220,
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              AppMetaChip(
                                icon: Icons.event_available_outlined,
                                label:
                                    'Reportado: ${_formatMetaDate(createdDate)}',
                                maxWidth: 220,
                              ),
                              if (updatedDate != null &&
                                  (createdDate == null ||
                                      updatedDate.isAfter(
                                        createdDate.add(
                                          const Duration(minutes: 1),
                                        ),
                                      )))
                                AppMetaChip(
                                  icon: Icons.update_outlined,
                                  label:
                                      'Actualizado: ${_formatMetaDate(updatedDate)}',
                                  maxWidth: 220,
                                ),
                              if (closedDate != null)
                                AppMetaChip(
                                  icon: Icons.task_alt_outlined,
                                  label:
                                      'Cerrado: ${_formatMetaDate(closedDate)}',
                                  background: scheme.secondaryContainer,
                                  foreground: scheme.onSecondaryContainer,
                                  maxWidth: 220,
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.timeline_outlined,
                                  size: 18,
                                  color: scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    previewText,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _resolvePlace(Map<String, dynamic> data) {
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
    return (data['lugar'] ?? 'Lugar no especificado').toString();
  }
}
