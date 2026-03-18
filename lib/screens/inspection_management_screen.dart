import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/inspection_service.dart';
import '../services/storage_service.dart';
import '../services/user_service.dart';
import '../widgets/app_meta_chip.dart';
import 'full_screen_image_screen.dart';

class InspectionManagementScreen extends StatefulWidget {
  const InspectionManagementScreen({super.key});

  @override
  State<InspectionManagementScreen> createState() =>
      _InspectionManagementScreenState();
}

class _InspectionManagementScreenState
    extends State<InspectionManagementScreen> {
  final InspectionService _inspectionService = InspectionService();

  Stream<QuerySnapshot<Map<String, dynamic>>>? _inspectionsStream;
  CurrentUserData? _currentUser;
  bool _loading = true;
  String? _error;
  _InspectionFilter _filter = _InspectionFilter.open;

  bool get _isManager {
    final role = (_currentUser?.role ?? '').trim();
    return role == 'admin_sst' || role == 'admin';
  }

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  Future<void> _loadContext() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final currentUser = await _inspectionService.requireCurrentUserData();
      final institutionId = (currentUser.institutionId ?? '').trim();
      final role = (currentUser.role ?? 'user').trim();

      setState(() {
        _currentUser = currentUser;
        _inspectionsStream = _inspectionService.streamInspections(
          institutionId: institutionId,
          role: role,
          uid: currentUser.uid,
        );
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isManager ? 'Gestion de inspecciones' : 'Mis inspecciones';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: _isManager
          ? FloatingActionButton.extended(
              onPressed: _openCreate,
              icon: const Icon(Icons.add_task_outlined),
              label: const Text('Nueva inspeccion'),
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildErrorState(_error!);
    }

    if (_inspectionsStream == null || _currentUser == null) {
      return _buildErrorState('No se pudo cargar el modulo de inspecciones.');
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _inspectionsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _buildErrorState(
            'Error cargando inspecciones: ${snapshot.error}',
          );
        }

        final docs = snapshot.data?.docs ?? const [];
        docs.sort(_sortInspections);

        final filtered = docs.where(_matchesFilter).toList();
        final openCount = docs.where((d) => _isOpen(_statusOf(d))).length;
        final completedCount = docs
            .where((d) => _isCompleted(_statusOf(d)))
            .length;
        final cancelledCount = docs
            .where((d) => _statusOf(d) == 'cancelled')
            .length;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: _buildSummaryCard(
                openCount: openCount,
                completedCount: completedCount,
                cancelledCount: cancelledCount,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _availableFilters.map((filter) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_filterLabel(filter)),
                        selected: _filter == filter,
                        onSelected: (_) {
                          setState(() {
                            _filter = filter;
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        return _buildInspectionCard(filtered[index]);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard({
    required int openCount,
    required int completedCount,
    required int cancelledCount,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isManager
                ? 'Control de inspecciones'
                : 'Seguimiento de inspecciones asignadas',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isManager
                ? 'Programa, ejecuta y cierra inspecciones SST con trazabilidad.'
                : 'Completa tus inspecciones programadas y reporta hallazgos.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppMetaChip(
                icon: Icons.pending_actions_outlined,
                label: 'Abiertas: $openCount',
                background: scheme.primaryContainer,
                foreground: scheme.onPrimaryContainer,
              ),
              AppMetaChip(
                icon: Icons.task_alt_outlined,
                label: 'Completadas: $completedCount',
                background: scheme.secondaryContainer,
                foreground: scheme.onSecondaryContainer,
              ),
              AppMetaChip(
                icon: Icons.cancel_outlined,
                label: 'Canceladas: $cancelledCount',
                background: scheme.errorContainer,
                foreground: scheme.onErrorContainer,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInspectionCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final data = doc.data();

    final title = (data['title'] ?? 'Inspeccion').toString();
    final description = (data['description'] ?? '').toString().trim();
    final status = _statusOf(doc);
    final scheduledAt = _readDate(data['scheduledAt']);
    final dueAt = _readDate(data['dueAt']);
    final assignedTo = (data['assignedToName'] ?? 'Sin asignar').toString();
    final type = (data['inspectionType'] ?? 'General').toString();
    final location = (data['location'] ?? 'Sin ubicacion').toString();
    final completion =
        (data['completion'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final failedItems = _toInt(completion['failedItems']);
    final completedItems = _toInt(completion['completedItems']);
    final totalItems = _toInt(completion['totalItems']);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: scheme.surfaceContainerHighest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => InspectionDetailScreen(
                institutionId: (_currentUser?.institutionId ?? '').trim(),
                inspectionId: doc.id,
                currentUserUid: _currentUser!.uid,
                currentUserRole: (_currentUser?.role ?? 'user').trim(),
              ),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _statusChip(status),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppMetaChip(icon: Icons.fact_check_outlined, label: type),
                  AppMetaChip(
                    icon: Icons.place_outlined,
                    label: location,
                    maxWidth: 200,
                  ),
                  AppMetaChip(
                    icon: Icons.person_outline,
                    label: assignedTo,
                    maxWidth: 170,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.event_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _scheduleLabel(scheduledAt, dueAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              if (_isCompleted(status)) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.rule_folder_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Checklist: $completedItems/$totalItems',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (failedItems > 0) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Hallazgos: $failedItems',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onErrorContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 50),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadContext,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.fact_check_outlined,
              size: 54,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              'No hay inspecciones en esta vista.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _isManager
                  ? 'Crea una nueva inspeccion o cambia el filtro para ver mas resultados.'
                  : 'Cuando te asignen inspecciones apareceran aqui.',
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

  List<_InspectionFilter> get _availableFilters {
    if (_isManager) {
      return const <_InspectionFilter>[
        _InspectionFilter.open,
        _InspectionFilter.inProgress,
        _InspectionFilter.completed,
        _InspectionFilter.findings,
        _InspectionFilter.cancelled,
        _InspectionFilter.overdue,
        _InspectionFilter.all,
      ];
    }
    return const <_InspectionFilter>[
      _InspectionFilter.open,
      _InspectionFilter.inProgress,
      _InspectionFilter.completed,
      _InspectionFilter.findings,
      _InspectionFilter.overdue,
      _InspectionFilter.all,
    ];
  }

  bool _matchesFilter(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final status = _statusOf(doc);
    switch (_filter) {
      case _InspectionFilter.open:
        return status == 'scheduled';
      case _InspectionFilter.inProgress:
        return status == 'in_progress';
      case _InspectionFilter.completed:
        return status == 'completed';
      case _InspectionFilter.findings:
        return status == 'completed_with_findings';
      case _InspectionFilter.cancelled:
        return status == 'cancelled';
      case _InspectionFilter.overdue:
        return _isOverdue(doc);
      case _InspectionFilter.all:
        return true;
    }
  }

  int _sortInspections(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final statusA = _statusPriority(_statusOf(a));
    final statusB = _statusPriority(_statusOf(b));
    if (statusA != statusB) {
      return statusA.compareTo(statusB);
    }

    final dueA = _readDate(a.data()['dueAt']) ?? DateTime(2999);
    final dueB = _readDate(b.data()['dueAt']) ?? DateTime(2999);
    return dueA.compareTo(dueB);
  }

  Future<void> _openCreate() async {
    final institutionId = (_currentUser?.institutionId ?? '').trim();
    if (institutionId.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            InspectionFormScreen(institutionId: institutionId),
      ),
    );
  }

  bool _isOpen(String status) {
    return status == 'scheduled' || status == 'in_progress';
  }

  bool _isCompleted(String status) {
    return status == 'completed' || status == 'completed_with_findings';
  }

  bool _isOverdue(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final status = _statusOf(doc);
    if (status == 'cancelled' || _isCompleted(status)) {
      return false;
    }
    final dueAt = _readDate(doc.data()['dueAt']);
    if (dueAt == null) return false;
    return dueAt.isBefore(DateTime.now());
  }

  int _statusPriority(String status) {
    switch (status) {
      case 'in_progress':
        return 0;
      case 'scheduled':
        return 1;
      case 'completed_with_findings':
        return 2;
      case 'completed':
        return 3;
      case 'cancelled':
        return 4;
      default:
        return 5;
    }
  }

  String _statusOf(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    return InspectionService.normalizeStatus(
      (doc.data()['status'] ?? 'scheduled').toString(),
    );
  }

  DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _scheduleLabel(DateTime? start, DateTime? end) {
    final format = DateFormat('dd/MM/yyyy hh:mm a');
    if (start == null && end == null) {
      return 'Sin fecha';
    }
    if (start != null && end != null) {
      return '${format.format(start)} - ${format.format(end)}';
    }
    if (start != null) {
      return format.format(start);
    }
    return format.format(end!);
  }

  Widget _statusChip(String status) {
    final scheme = Theme.of(context).colorScheme;
    final config = _statusStyle(status, scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: config.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        InspectionService.statusLabel(status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: config.foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _filterLabel(_InspectionFilter filter) {
    switch (filter) {
      case _InspectionFilter.open:
        return 'Programadas';
      case _InspectionFilter.inProgress:
        return 'En ejecucion';
      case _InspectionFilter.completed:
        return 'Completadas';
      case _InspectionFilter.findings:
        return 'Con hallazgos';
      case _InspectionFilter.cancelled:
        return 'Canceladas';
      case _InspectionFilter.overdue:
        return 'Vencidas';
      case _InspectionFilter.all:
        return 'Todas';
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class InspectionFormScreen extends StatefulWidget {
  final String institutionId;
  final DocumentSnapshot<Map<String, dynamic>>? inspectionDoc;

  const InspectionFormScreen({
    super.key,
    required this.institutionId,
    this.inspectionDoc,
  });

  bool get isEdit => inspectionDoc != null;

  @override
  State<InspectionFormScreen> createState() => _InspectionFormScreenState();
}

class _InspectionFormScreenState extends State<InspectionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final InspectionService _inspectionService = InspectionService();
  final UserService _userService = UserService();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  String _inspectionType = 'locativa';
  DateTime _scheduledAt = DateTime.now().add(const Duration(hours: 2));
  DateTime _dueAt = DateTime.now().add(const Duration(hours: 5));
  String? _assignedToUid;
  String? _assignedToName;
  bool _saving = false;

  final List<_ChecklistDraft> _checklistDrafts = <_ChecklistDraft>[];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  void _loadInitialData() {
    final data = widget.inspectionDoc?.data();
    if (data == null) {
      _checklistDrafts.add(_ChecklistDraft());
      return;
    }

    _titleController.text = (data['title'] ?? '').toString();
    _descriptionController.text = (data['description'] ?? '').toString();
    _locationController.text = (data['location'] ?? '').toString();
    _inspectionType = (data['inspectionType'] ?? 'locativa').toString();
    _assignedToUid = (data['assignedToUid'] ?? '').toString().trim();
    _assignedToName = (data['assignedToName'] ?? '').toString().trim();

    final scheduledAt = _readDate(data['scheduledAt']);
    final dueAt = _readDate(data['dueAt']);
    if (scheduledAt != null) {
      _scheduledAt = scheduledAt;
    }
    if (dueAt != null) {
      _dueAt = dueAt;
    }

    final rawChecklist = data['checklist'];
    if (rawChecklist is Iterable) {
      for (final rawItem in rawChecklist) {
        if (rawItem is! Map) continue;
        final map = Map<String, dynamic>.from(rawItem);
        _checklistDrafts.add(
          _ChecklistDraft(
            id: (map['id'] ?? '').toString().trim(),
            title: (map['title'] ?? '').toString(),
            description: (map['description'] ?? '').toString(),
            isRequired: (map['isRequired'] ?? true) == true,
          ),
        );
      }
    }

    if (_checklistDrafts.isEmpty) {
      _checklistDrafts.add(_ChecklistDraft());
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    for (final draft in _checklistDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isEdit ? 'Editar inspeccion' : 'Nueva inspeccion';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: StreamBuilder<QuerySnapshot>(
        stream: _userService.streamUsersByInstitution(widget.institutionId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final userDocs = snapshot.data?.docs ?? const [];
          final assignees =
              userDocs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final name = (data['displayName'] ?? data['email'] ?? 'Usuario')
                    .toString()
                    .trim();
                final email = (data['email'] ?? '').toString().trim();
                return _AssigneeOption(uid: doc.id, name: name, email: email);
              }).toList()..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );

          if ((_assignedToUid ?? '').isEmpty && assignees.isNotEmpty) {
            _assignedToUid = assignees.first.uid;
            _assignedToName = assignees.first.name;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionCard(
                    title: 'Datos principales',
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            labelText: 'Titulo *',
                            hintText: 'Ej: Inspeccion mensual de aulas',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Ingresa un titulo.';
                            }
                            if (value.trim().length < 6) {
                              return 'Usa un titulo mas descriptivo.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _descriptionController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Descripcion',
                            hintText: 'Objetivo o alcance de la inspeccion',
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _inspectionType,
                          decoration: const InputDecoration(
                            labelText: 'Tipo de inspeccion *',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'locativa',
                              child: Text('Locativa'),
                            ),
                            DropdownMenuItem(
                              value: 'equipos',
                              child: Text('Equipos y herramientas'),
                            ),
                            DropdownMenuItem(
                              value: 'bioseguridad',
                              child: Text('Bioseguridad'),
                            ),
                            DropdownMenuItem(
                              value: 'seguimiento',
                              child: Text('Seguimiento de hallazgos'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _inspectionType = value;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _locationController,
                          decoration: const InputDecoration(
                            labelText: 'Lugar / area *',
                            hintText: 'Ej: Bloque B - Laboratorio quimica',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Ingresa la ubicacion.';
                            }
                            if (value.trim().length < 4) {
                              return 'Minimo 4 caracteres.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildAssigneeField(assignees),
                        if (assignees.isEmpty) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'No hay usuarios disponibles en la institucion para asignar.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionCard(
                    title: 'Programacion',
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Fecha y hora programada *'),
                          subtitle: Text(_formatDateTime(_scheduledAt)),
                          trailing: const Icon(Icons.schedule_outlined),
                          onTap: () => _pickDateTime(isScheduled: true),
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Fecha y hora limite *'),
                          subtitle: Text(_formatDateTime(_dueAt)),
                          trailing: const Icon(Icons.event_busy_outlined),
                          onTap: () => _pickDateTime(isScheduled: false),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionCard(
                    title: 'Checklist de inspeccion',
                    child: Column(
                      children: [
                        ..._checklistDrafts.asMap().entries.map((entry) {
                          final index = entry.key;
                          final draft = entry.value;
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == _checklistDrafts.length - 1
                                  ? 0
                                  : 14,
                            ),
                            child: _buildChecklistDraftCard(index, draft),
                          );
                        }),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _checklistDrafts.add(_ChecklistDraft());
                            });
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar criterio'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              widget.isEdit
                                  ? 'Guardar cambios'
                                  : 'Crear inspeccion',
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChecklistDraftCard(int index, _ChecklistDraft draft) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Criterio ${index + 1}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (_checklistDrafts.length > 1)
                IconButton(
                  tooltip: 'Eliminar criterio',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    setState(() {
                      _checklistDrafts.removeAt(index).dispose();
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: draft.titleController,
            decoration: const InputDecoration(
              labelText: 'Titulo del criterio *',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresa el titulo del criterio.';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: draft.descriptionController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Descripcion (opcional)',
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            value: draft.isRequired,
            contentPadding: EdgeInsets.zero,
            title: const Text('Obligatorio'),
            subtitle: const Text('El inspector debe responder este criterio.'),
            onChanged: (value) {
              setState(() {
                draft.isRequired = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAssigneeField(List<_AssigneeOption> assignees) {
    return FormField<String>(
      initialValue: (_assignedToUid ?? '').trim().isEmpty
          ? null
          : _assignedToUid,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Selecciona un inspector.';
        }
        return null;
      },
      builder: (state) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final selected = _selectedAssigneeFrom(assignees);
        final fallbackName = (_assignedToName ?? '').trim();
        final displayName = selected?.name ?? fallbackName;
        final displayEmail = selected?.email ?? '';
        final hasSelection = displayName.isNotEmpty;

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: assignees.isEmpty
              ? null
              : () async {
                  final picked = await _showAssigneePicker(assignees);
                  if (picked == null || !mounted) return;
                  setState(() {
                    _assignedToUid = picked.uid;
                    _assignedToName = picked.name;
                  });
                  state.didChange(picked.uid);
                },
          child: InputDecorator(
            isEmpty: !hasSelection,
            decoration: InputDecoration(
              labelText: 'Inspector asignado *',
              hintText: 'Selecciona inspector',
              suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
              errorText: state.errorText,
            ),
            child: Row(
              children: [
                Container(
                  height: 34,
                  width: 34,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.person_outline,
                    size: 18,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: hasSelection
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (displayEmail.isNotEmpty)
                              Text(
                                displayEmail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        )
                      : Text(
                          'Selecciona inspector',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  _AssigneeOption? _selectedAssigneeFrom(List<_AssigneeOption> assignees) {
    final uid = (_assignedToUid ?? '').trim();
    if (uid.isEmpty) return null;
    for (final option in assignees) {
      if (option.uid == uid) return option;
    }
    return null;
  }

  Future<_AssigneeOption?> _showAssigneePicker(
    List<_AssigneeOption> assignees,
  ) async {
    String query = '';
    return showModalBottomSheet<_AssigneeOption>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final scheme = Theme.of(context).colorScheme;
            final normalizedQuery = query.trim().toLowerCase();
            final filtered = assignees.where((item) {
              if (normalizedQuery.isEmpty) return true;
              return item.name.toLowerCase().contains(normalizedQuery) ||
                  item.email.toLowerCase().contains(normalizedQuery);
            }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.68,
                  child: Column(
                    children: [
                      Text(
                        'Seleccionar inspector',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        autofocus: false,
                        onChanged: (value) {
                          setModalState(() {
                            query = value;
                          });
                        },
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Buscar por nombre o correo',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  'No hay coincidencias.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final option = filtered[index];
                                  final isSelected =
                                      option.uid ==
                                      (_assignedToUid ?? '').trim();
                                  return Material(
                                    color: isSelected
                                        ? scheme.primaryContainer.withValues(
                                            alpha: 0.35,
                                          )
                                        : scheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(14),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () {
                                        Navigator.of(
                                          sheetContext,
                                        ).pop<_AssigneeOption>(option);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 18,
                                              backgroundColor:
                                                  scheme.surfaceContainerHigh,
                                              child: Icon(
                                                Icons.person_outline,
                                                color: scheme.onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    option.name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                  ),
                                                  if (option.email.isNotEmpty)
                                                    Text(
                                                      option.email,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
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
                                            if (isSelected)
                                              Icon(
                                                Icons.check_circle,
                                                color: scheme.primary,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
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
  }

  Future<void> _pickDateTime({required bool isScheduled}) async {
    final initial = isScheduled ? _scheduledAt : _dueAt;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(alwaysUse24HourFormat: false),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (pickedTime == null || !mounted) return;

    final result = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() {
      if (isScheduled) {
        _scheduledAt = result;
        if (_dueAt.isBefore(result)) {
          _dueAt = result.add(const Duration(hours: 1));
        }
      } else {
        if (result.isBefore(_scheduledAt)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'La fecha/hora de finalizacion no puede ser anterior al inicio.',
              ),
            ),
          );
          return;
        }
        _dueAt = result;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa los campos obligatorios.')),
      );
      return;
    }

    if (_dueAt.isBefore(_scheduledAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La fecha limite debe ser posterior a la programada.'),
        ),
      );
      return;
    }

    final assignedUid = (_assignedToUid ?? '').trim();
    final assignedName = (_assignedToName ?? '').trim();
    if (assignedUid.isEmpty || assignedName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona un inspector.')));
      return;
    }

    final checklist = <Map<String, dynamic>>[];
    for (int index = 0; index < _checklistDrafts.length; index++) {
      final draft = _checklistDrafts[index];
      final title = draft.titleController.text.trim();
      if (title.isEmpty) continue;
      checklist.add({
        'id': draft.id.isNotEmpty
            ? draft.id
            : 'item_${index + 1}_${DateTime.now().millisecondsSinceEpoch}',
        'title': title,
        'description': draft.descriptionController.text.trim(),
        'isRequired': draft.isRequired,
        'order': index,
      });
    }

    if (checklist.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrega al menos un criterio en el checklist.'),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      if (widget.isEdit) {
        await _inspectionService.updateInspection(
          institutionId: widget.institutionId,
          inspectionId: widget.inspectionDoc!.id,
          title: _titleController.text,
          description: _descriptionController.text,
          inspectionType: _inspectionType,
          location: _locationController.text,
          scheduledAt: _scheduledAt,
          dueAt: _dueAt,
          assignedToUid: assignedUid,
          assignedToName: assignedName,
          checklist: checklist,
        );
      } else {
        await _inspectionService.createInspection(
          institutionId: widget.institutionId,
          title: _titleController.text,
          description: _descriptionController.text,
          inspectionType: _inspectionType,
          location: _locationController.text,
          scheduledAt: _scheduledAt,
          dueAt: _dueAt,
          assignedToUid: assignedUid,
          assignedToName: assignedName,
          checklist: checklist,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEdit
                ? 'Inspeccion actualizada correctamente.'
                : 'Inspeccion creada correctamente.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la inspeccion: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _formatDateTime(DateTime value) {
    return DateFormat('dd/MM/yyyy hh:mm a').format(value);
  }
}

class InspectionDetailScreen extends StatefulWidget {
  final String institutionId;
  final String inspectionId;
  final String currentUserUid;
  final String currentUserRole;

  const InspectionDetailScreen({
    super.key,
    required this.institutionId,
    required this.inspectionId,
    required this.currentUserUid,
    required this.currentUserRole,
  });

  @override
  State<InspectionDetailScreen> createState() => _InspectionDetailScreenState();
}

class _InspectionDetailScreenState extends State<InspectionDetailScreen> {
  final InspectionService _inspectionService = InspectionService();

  bool _busyAction = false;

  bool get _isManager {
    final role = widget.currentUserRole.trim();
    return role == 'admin_sst' || role == 'admin';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de inspeccion')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('institutions')
            .doc(widget.institutionId)
            .collection('inspections')
            .doc(widget.inspectionId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No se pudo cargar la inspeccion: ${snapshot.error}',
                ),
              ),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('La inspeccion no existe.'));
          }

          final data = snapshot.data!.data() ?? <String, dynamic>{};
          final status = InspectionService.normalizeStatus(
            (data['status'] ?? 'scheduled').toString(),
          );

          final assignedToUid = (data['assignedToUid'] ?? '').toString().trim();
          final isAssigned = assignedToUid == widget.currentUserUid;

          final canExecute =
              (isAssigned || _isManager) &&
              (status == 'scheduled' || status == 'in_progress');
          final canEdit =
              _isManager && (status == 'scheduled' || status == 'in_progress');
          final canCancel =
              _isManager &&
              status != 'cancelled' &&
              status != 'completed' &&
              status != 'completed_with_findings';

          final checklist = _parseChecklist(data['checklist']);
          final result =
              (data['result'] as Map<String, dynamic>?) ??
              const <String, dynamic>{};
          final completion =
              (data['completion'] as Map<String, dynamic>?) ??
              const <String, dynamic>{};

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _buildHeaderCard(data, status),
              const SizedBox(height: 16),
              _buildChecklistCard(checklist, result),
              const SizedBox(height: 16),
              _buildCompletionCard(completion, result),
              const SizedBox(height: 16),
              _buildStatusHistoryCard(data),
              const SizedBox(height: 24),
              if (canExecute || canEdit || canCancel)
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (canExecute)
                      FilledButton.icon(
                        onPressed: _busyAction
                            ? null
                            : () => _openExecution(data, status),
                        icon: const Icon(Icons.play_circle_outline),
                        label: Text(
                          status == 'scheduled'
                              ? 'Iniciar y ejecutar'
                              : 'Continuar ejecucion',
                        ),
                      ),
                    if (canEdit)
                      OutlinedButton.icon(
                        onPressed: _busyAction
                            ? null
                            : () => _openEdit(snapshot.data!),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar'),
                      ),
                    if (canCancel)
                      OutlinedButton.icon(
                        onPressed: _busyAction ? null : _cancelInspection,
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Cancelar'),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard(Map<String, dynamic> data, String status) {
    final scheme = Theme.of(context).colorScheme;
    final title = (data['title'] ?? 'Inspeccion').toString();
    final description = (data['description'] ?? '').toString().trim();
    final type = (data['inspectionType'] ?? '').toString().trim();
    final location = (data['location'] ?? '').toString().trim();
    final assignedTo = (data['assignedToName'] ?? 'Sin asignar').toString();
    final scheduledAt = _readDate(data['scheduledAt']);
    final dueAt = _readDate(data['dueAt']);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _statusChip(status),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              description,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (type.isNotEmpty)
                AppMetaChip(icon: Icons.fact_check_outlined, label: type),
              if (location.isNotEmpty)
                AppMetaChip(
                  icon: Icons.place_outlined,
                  label: location,
                  maxWidth: 210,
                ),
              AppMetaChip(
                icon: Icons.person_outline,
                label: assignedTo,
                maxWidth: 170,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Programada: ${_formatDateTime(scheduledAt)}\nLimite: ${_formatDateTime(dueAt)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistCard(
    List<Map<String, dynamic>> checklist,
    Map<String, dynamic> result,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final itemResults = _itemResultsById(result);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Checklist',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (checklist.isEmpty)
            Text(
              'Sin criterios registrados.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            ...checklist.map((item) {
              final id = (item['id'] ?? '').toString();
              final title = (item['title'] ?? 'Criterio').toString();
              final description = (item['description'] ?? '').toString().trim();
              final required = (item['isRequired'] ?? true) == true;
              final itemResult = itemResults[id];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (required)
                            AppMetaChip(
                              icon: Icons.priority_high_outlined,
                              label: 'Obligatorio',
                              horizontalPadding: 8,
                              verticalPadding: 4,
                              background: scheme.primaryContainer.withValues(
                                alpha: 0.7,
                              ),
                              foreground: scheme.onPrimaryContainer,
                            ),
                        ],
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                      if (itemResult != null) ...[
                        const SizedBox(height: 8),
                        _resultChip((itemResult['result'] ?? '').toString()),
                        if ((itemResult['note'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            (itemResult['note'] ?? '').toString().trim(),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildCompletionCard(
    Map<String, dynamic> completion,
    Map<String, dynamic> result,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final completedItems = _toInt(completion['completedItems']);
    final failedItems = _toInt(completion['failedItems']);
    final naItems = _toInt(completion['naItems']);
    final totalItems = _toInt(completion['totalItems']);

    final submittedAt = _readDate(result['submittedAt']);
    final submittedBy = (result['submittedByName'] ?? '').toString().trim();
    final note = (result['generalNote'] ?? '').toString().trim();
    final evidencesUploadPending =
        (result['evidencesUploadPending'] ?? false) == true;
    final evidencesUploadWarning = (result['evidencesUploadWarning'] ?? '')
        .toString()
        .trim();

    final evidence =
        (result['evidences'] as Iterable?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resultado de la inspeccion',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (totalItems == 0)
            Text(
              'Aun no hay resultado registrado.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppMetaChip(
                  icon: Icons.check_circle_outline,
                  label: 'Cumple: $completedItems',
                  background: scheme.secondaryContainer,
                  foreground: scheme.onSecondaryContainer,
                ),
                AppMetaChip(
                  icon: Icons.warning_amber_outlined,
                  label: 'No cumple: $failedItems',
                  background: scheme.errorContainer,
                  foreground: scheme.onErrorContainer,
                ),
                AppMetaChip(
                  icon: Icons.remove_circle_outline,
                  label: 'No aplica: $naItems',
                ),
              ],
            ),
            if (submittedAt != null || submittedBy.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Registrado por ${submittedBy.isEmpty ? 'Inspector' : submittedBy} ${submittedAt == null ? '' : 'el ${DateFormat('dd/MM/yyyy hh:mm a').format(submittedAt)}'}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (note.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(note, style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (evidencesUploadPending) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: scheme.error.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  evidencesUploadWarning.isEmpty
                      ? 'No se pudieron subir algunas evidencias. Verifica permisos de Storage y reintenta.'
                      : 'Evidencias pendientes por error de subida: $evidencesUploadWarning',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (evidence.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Evidencias',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...evidence.map(_buildEvidenceTile),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildEvidenceTile(Map<String, dynamic> item) {
    final type = (item['type'] ?? '').toString();
    final url = (item['url'] ?? '').toString();

    if (url.isEmpty) {
      return const SizedBox.shrink();
    }

    if (type == 'image') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          borderRadius: BorderRadius.circular(10),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FullScreenImageScreen(imageUrl: url),
                ),
              );
            },
            child: Container(
              height: 160,
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    alignment: Alignment.center,
                    color: Theme.of(context).colorScheme.surface,
                    child: const Text('No se pudo cargar la imagen'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.videocam_outlined),
      title: const Text('Video de evidencia'),
      trailing: const Icon(Icons.open_in_new),
      onTap: () => _openUrl(url),
    );
  }

  Widget _buildStatusHistoryCard(Map<String, dynamic> data) {
    final scheme = Theme.of(context).colorScheme;
    final history =
        (data['statusHistory'] as Iterable?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];

    if (history.isEmpty) {
      return const SizedBox.shrink();
    }

    history.sort((a, b) {
      final da =
          _readDate(a['changedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db =
          _readDate(b['changedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trazabilidad',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ...history.map((entry) {
            final status = InspectionService.statusLabel(
              (entry['status'] ?? '').toString(),
            );
            final changedAt = _readDate(entry['changedAt']);
            final note = (entry['note'] ?? '').toString().trim();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (changedAt != null)
                          Text(
                            DateFormat('dd/MM/yyyy hh:mm a').format(changedAt),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        if (note.isNotEmpty)
                          Text(
                            note,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _openExecution(Map<String, dynamic> data, String status) async {
    if (_busyAction) return;
    setState(() {
      _busyAction = true;
    });

    try {
      if (status == 'scheduled') {
        await _inspectionService.startInspection(
          institutionId: widget.institutionId,
          inspectionId: widget.inspectionId,
        );
      }

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => InspectionExecutionScreen(
            institutionId: widget.institutionId,
            inspectionId: widget.inspectionId,
            inspectionData: data,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir la ejecucion: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyAction = false;
        });
      }
    }
  }

  Future<void> _openEdit(
    DocumentSnapshot<Map<String, dynamic>> inspectionDoc,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => InspectionFormScreen(
          institutionId: widget.institutionId,
          inspectionDoc: inspectionDoc,
        ),
      ),
    );
  }

  Future<void> _cancelInspection() async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancelar inspeccion'),
          content: TextField(
            controller: noteController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Motivo (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Cancelar inspeccion'),
            ),
          ],
        );
      },
    );

    final note = noteController.text.trim();
    noteController.dispose();

    if (confirmed != true) return;

    setState(() {
      _busyAction = true;
    });

    try {
      await _inspectionService.cancelInspection(
        institutionId: widget.institutionId,
        inspectionId: widget.inspectionId,
        note: note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inspeccion cancelada correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo cancelar: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _busyAction = false;
        });
      }
    }
  }

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  List<Map<String, dynamic>> _parseChecklist(dynamic rawChecklist) {
    if (rawChecklist is! Iterable) return const <Map<String, dynamic>>[];
    return rawChecklist
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Map<String, Map<String, dynamic>> _itemResultsById(
    Map<String, dynamic> result,
  ) {
    final rawItems = result['items'];
    if (rawItems is! Iterable) {
      return const <String, Map<String, dynamic>>{};
    }

    final map = <String, Map<String, dynamic>>{};
    for (final item in rawItems.whereType<Map>()) {
      final converted = Map<String, dynamic>.from(item);
      final id = (converted['itemId'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      map[id] = converted;
    }
    return map;
  }

  Widget _statusChip(String status) {
    final scheme = Theme.of(context).colorScheme;
    final config = _statusStyle(status, scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: config.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        InspectionService.statusLabel(status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: config.foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _resultChip(String result) {
    final scheme = Theme.of(context).colorScheme;
    switch (result) {
      case 'cumple':
        return AppMetaChip(
          icon: Icons.check_circle_outline,
          label: 'Cumple',
          background: scheme.secondaryContainer,
          foreground: scheme.onSecondaryContainer,
        );
      case 'no_cumple':
        return AppMetaChip(
          icon: Icons.warning_amber_outlined,
          label: 'No cumple',
          background: scheme.errorContainer,
          foreground: scheme.onErrorContainer,
        );
      case 'no_aplica':
        return AppMetaChip(
          icon: Icons.remove_circle_outline,
          label: 'No aplica',
        );
      default:
        return AppMetaChip(icon: Icons.help_outline, label: 'Sin resultado');
    }
  }

  DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _formatDateTime(DateTime? date) {
    if (date == null) return 'Sin fecha';
    return DateFormat('dd/MM/yyyy hh:mm a').format(date);
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class InspectionExecutionScreen extends StatefulWidget {
  final String institutionId;
  final String inspectionId;
  final Map<String, dynamic> inspectionData;

  const InspectionExecutionScreen({
    super.key,
    required this.institutionId,
    required this.inspectionId,
    required this.inspectionData,
  });

  @override
  State<InspectionExecutionScreen> createState() =>
      _InspectionExecutionScreenState();
}

class _InspectionExecutionScreenState extends State<InspectionExecutionScreen> {
  final InspectionService _inspectionService = InspectionService();
  final TextEditingController _generalNoteController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  static const int _maxEvidences = 3;
  static const int _maxVideoBytes = 30 * 1024 * 1024;

  final List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  final Map<String, String> _resultById = <String, String>{};
  final Map<String, TextEditingController> _noteById =
      <String, TextEditingController>{};
  final List<ReportAttachmentInput> _evidences = <ReportAttachmentInput>[];

  bool _saving = false;
  double? _uploadProgress;

  @override
  void initState() {
    super.initState();
    _loadChecklist();
  }

  @override
  void dispose() {
    _generalNoteController.dispose();
    for (final controller in _noteById.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _loadChecklist() {
    final rawChecklist = widget.inspectionData['checklist'];
    if (rawChecklist is! Iterable) return;

    for (final raw in rawChecklist.whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final id = (item['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      _items.add(item);
      _resultById[id] = '';
      _noteById[id] = TextEditingController();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Ejecutar inspeccion')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (widget.inspectionData['title'] ?? 'Inspeccion').toString(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Registra el resultado por criterio y adjunta evidencia si aplica.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ..._items.map(_buildExecutionItem),
          const SizedBox(height: 16),
          TextField(
            controller: _generalNoteController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Observaciones generales (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _buildEvidenceComposer(),
          if (_uploadProgress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _uploadProgress),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.task_alt_outlined),
              label: Text(_saving ? 'Enviando...' : 'Guardar resultado'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExecutionItem(Map<String, dynamic> item) {
    final id = (item['id'] ?? '').toString();
    final title = (item['title'] ?? 'Criterio').toString();
    final description = (item['description'] ?? '').toString().trim();
    final required = (item['isRequired'] ?? true) == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (required)
                  AppMetaChip(
                    icon: Icons.priority_high_outlined,
                    label: 'Obligatorio',
                    horizontalPadding: 8,
                    verticalPadding: 4,
                  ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _resultById[id]!.isEmpty ? null : _resultById[id],
              decoration: const InputDecoration(
                labelText: 'Resultado *',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'cumple', child: Text('Cumple')),
                DropdownMenuItem(value: 'no_cumple', child: Text('No cumple')),
                DropdownMenuItem(value: 'no_aplica', child: Text('No aplica')),
              ],
              onChanged: (value) {
                setState(() {
                  _resultById[id] = value ?? '';
                });
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteById[id],
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Observacion (obligatoria si No cumple)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEvidenceComposer() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Evidencias (${_evidences.length}/$_maxEvidences)',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: _evidences.length >= _maxEvidences
                    ? null
                    : _pickEvidence,
                icon: const Icon(Icons.attach_file),
                label: const Text('Adjuntar'),
              ),
            ],
          ),
          if (_evidences.isEmpty)
            Text(
              'Sin evidencias adjuntas.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            ..._evidences.asMap().entries.map((entry) {
              final index = entry.key;
              final attachment = entry.value;
              final name = attachment.file.name;
              final isVideo = attachment.type == 'video';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  isVideo ? Icons.videocam_outlined : Icons.image_outlined,
                ),
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(isVideo ? 'Video' : 'Imagen'),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _evidences.removeAt(index);
                    });
                  },
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _pickEvidence() async {
    final option = await showModalBottomSheet<_AttachmentOption>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Foto con camara'),
                onTap: () =>
                    Navigator.pop(context, _AttachmentOption.photoCamera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Foto desde galeria'),
                onTap: () =>
                    Navigator.pop(context, _AttachmentOption.photoGallery),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Video con camara'),
                onTap: () =>
                    Navigator.pop(context, _AttachmentOption.videoCamera),
              ),
              ListTile(
                leading: const Icon(Icons.video_library_outlined),
                title: const Text('Video desde galeria'),
                onTap: () =>
                    Navigator.pop(context, _AttachmentOption.videoGallery),
              ),
            ],
          ),
        );
      },
    );

    if (option == null || !mounted) return;

    XFile? file;
    if (option.isVideo) {
      file = await _picker.pickVideo(source: option.source);
    } else {
      file = await _picker.pickImage(source: option.source, imageQuality: 80);
    }

    if (file == null || !mounted) return;

    if (option.isVideo) {
      final bytes = await File(file.path).length();
      if (bytes > _maxVideoBytes && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El video supera 30 MB. Selecciona uno mas liviano.'),
          ),
        );
        return;
      }
    }

    setState(() {
      _evidences.add(ReportAttachmentInput(file: file!, type: option.type));
    });
  }

  Future<void> _submit() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta inspeccion no tiene checklist.')),
      );
      return;
    }

    final itemResults = <Map<String, dynamic>>[];

    for (final item in _items) {
      final id = (item['id'] ?? '').toString().trim();
      final title = (item['title'] ?? 'Criterio').toString();
      final required = (item['isRequired'] ?? true) == true;
      final result = (_resultById[id] ?? '').trim();
      final note = (_noteById[id]?.text ?? '').trim();

      if (required && result.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Completa el resultado de "$title".')),
        );
        return;
      }

      if (result == 'no_cumple' && note.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Agrega una observacion para el criterio "$title".'),
          ),
        );
        return;
      }

      itemResults.add({
        'itemId': id,
        'title': title,
        'result': result.isEmpty ? 'no_aplica' : result,
        'note': note,
      });
    }

    setState(() {
      _saving = true;
      _uploadProgress = _evidences.isEmpty ? null : 0;
    });

    try {
      final uploadWarning = await _inspectionService.submitInspectionResult(
        institutionId: widget.institutionId,
        inspectionId: widget.inspectionId,
        itemResults: itemResults,
        generalNote: _generalNoteController.text,
        evidences: _evidences,
        onUploadProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _uploadProgress = progress;
          });
        },
      );

      if (!mounted) return;
      final message = uploadWarning == null
          ? 'Resultado de inspeccion guardado.'
          : 'Resultado guardado, pero las evidencias quedaron pendientes por permisos de Storage.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el resultado: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _uploadProgress = null;
        });
      }
    }
  }
}

class _ChecklistDraft {
  final String id;
  final TextEditingController titleController;
  final TextEditingController descriptionController;
  bool isRequired;

  _ChecklistDraft({
    this.id = '',
    String title = '',
    String description = '',
    this.isRequired = true,
  }) : titleController = TextEditingController(text: title),
       descriptionController = TextEditingController(text: description);

  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
  }
}

class _AssigneeOption {
  final String uid;
  final String name;
  final String email;

  const _AssigneeOption({
    required this.uid,
    required this.name,
    required this.email,
  });

  String get label {
    if (email.isEmpty) return name;
    return '$name - $email';
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

enum _InspectionFilter {
  open,
  inProgress,
  completed,
  findings,
  cancelled,
  overdue,
  all,
}

enum _AttachmentOption { photoCamera, photoGallery, videoCamera, videoGallery }

extension on _AttachmentOption {
  ImageSource get source {
    switch (this) {
      case _AttachmentOption.photoCamera:
      case _AttachmentOption.videoCamera:
        return ImageSource.camera;
      case _AttachmentOption.photoGallery:
      case _AttachmentOption.videoGallery:
        return ImageSource.gallery;
    }
  }

  bool get isVideo {
    return this == _AttachmentOption.videoCamera ||
        this == _AttachmentOption.videoGallery;
  }

  String get type => isVideo ? 'video' : 'image';
}

_InspectionStatusStyle _statusStyle(String status, ColorScheme scheme) {
  switch (InspectionService.normalizeStatus(status)) {
    case 'scheduled':
      return _InspectionStatusStyle(
        background: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
      );
    case 'in_progress':
      return _InspectionStatusStyle(
        background: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
      );
    case 'completed':
      return _InspectionStatusStyle(
        background: scheme.secondaryContainer,
        foreground: scheme.onSecondaryContainer,
      );
    case 'completed_with_findings':
      return _InspectionStatusStyle(
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
      );
    case 'cancelled':
      return _InspectionStatusStyle(
        background: scheme.surfaceContainerHigh,
        foreground: scheme.onSurfaceVariant,
      );
    default:
      return _InspectionStatusStyle(
        background: scheme.surfaceContainerHigh,
        foreground: scheme.onSurfaceVariant,
      );
  }
}

class _InspectionStatusStyle {
  final Color background;
  final Color foreground;

  const _InspectionStatusStyle({
    required this.background,
    required this.foreground,
  });
}
