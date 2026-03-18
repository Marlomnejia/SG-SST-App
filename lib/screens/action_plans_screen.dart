import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/storage_service.dart';
import '../widgets/app_meta_chip.dart';
import 'report_details_screen.dart';

class ActionPlansScreen extends StatefulWidget {
  const ActionPlansScreen({super.key});

  @override
  State<ActionPlansScreen> createState() => _ActionPlansScreenState();
}

class _ActionPlansScreenState extends State<ActionPlansScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final StorageService _storageService = StorageService();
  final ImagePicker _picker = ImagePicker();

  static const int _maxExecutionAttachments = 3;
  static const int _maxExecutionVideoBytes = 30 * 1024 * 1024;

  Stream<QuerySnapshot>? _plansStream;
  bool _loading = true;
  String? _error;
  String _role = 'user';
  String? _uid;
  String? _institutionId;
  String? _currentUserLabel;
  _ActionPlanFilter _filter = _ActionPlanFilter.active;

  bool get _isManager => _role == 'admin_sst' || _role == 'admin';

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  Future<void> _loadContext() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _error = 'No hay un usuario autenticado.';
          _loading = false;
        });
        return;
      }

      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final userData = userDoc.data() ?? <String, dynamic>{};
      final role = (userData['role'] ?? 'user').toString().trim();
      final institutionId = (userData['institutionId'] ?? '').toString().trim();
      final displayName = (userData['displayName'] ?? '').toString().trim();
      final email = (userData['email'] ?? currentUser.email ?? '')
          .toString()
          .trim();
      final isManager = role == 'admin_sst' || role == 'admin';

      final Query baseQuery = isManager
          ? _firestore.collection('planesDeAccion')
          : _firestore
                .collection('planesDeAccion')
                .where('responsibleUid', isEqualTo: currentUser.uid);

      setState(() {
        _uid = currentUser.uid;
        _role = role;
        _institutionId = institutionId.isEmpty ? null : institutionId;
        _currentUserLabel = displayName.isNotEmpty
            ? displayName
            : (email.isNotEmpty ? email : 'Responsable');
        _plansStream = baseQuery.snapshots();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'No se pudieron cargar los planes: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = _isManager ? 'Planes de accion' : 'Mis planes';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _buildBody(scheme),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildErrorState(scheme);
    }

    if (_plansStream == null) {
      return const Center(child: Text('No hay datos disponibles.'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _plansStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _buildErrorState(
            scheme,
            message: 'Error al cargar los planes: ${snapshot.error}',
          );
        }

        final docs = (snapshot.data?.docs ?? <QueryDocumentSnapshot>[])
            .where(_canViewPlan)
            .toList();
        docs.sort(_comparePlans);

        final visiblePlans = docs.where(_matchesFilter).toList();
        final activeCount = docs.where((doc) => !_isClosed(doc)).length;
        final overdueCount = docs.where(_isOverdue).length;
        final pendingValidationCount = docs.where(_isPendingValidation).length;
        final closedCount = docs.where(_isClosed).length;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _buildHeaderCard(
                context,
                activeCount: activeCount,
                overdueCount: overdueCount,
                pendingValidationCount: pendingValidationCount,
                closedCount: closedCount,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _availableFilters
                      .map(
                        (filter) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(_filterLabel(filter)),
                            selected: _filter == filter,
                            onSelected: (_) => setState(() => _filter = filter),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            Expanded(
              child: visiblePlans.isEmpty
                  ? _buildEmptyState(context, scheme)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      itemCount: visiblePlans.length,
                      itemBuilder: (context, index) =>
                          _buildPlanCard(context, visiblePlans[index]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeaderCard(
    BuildContext context, {
    required int activeCount,
    required int overdueCount,
    required int pendingValidationCount,
    required int closedCount,
  }) {
    final scheme = Theme.of(context).colorScheme;
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
            _isManager ? 'Seguimiento institucional' : 'Tareas asignadas',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            _isManager
                ? 'Revisa responsables, vencimientos y avance de cada accion.'
                : 'Aqui veras las acciones que te asignaron para ejecutar.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppMetaChip(
                icon: Icons.schedule_outlined,
                label: 'Activos: $activeCount',
                background: scheme.primaryContainer,
                foreground: scheme.onPrimaryContainer,
              ),
              AppMetaChip(
                icon: Icons.event_busy_outlined,
                label: 'Vencidos: $overdueCount',
                background: scheme.errorContainer,
                foreground: scheme.onErrorContainer,
              ),
              if (_isManager)
                AppMetaChip(
                  icon: Icons.fact_check_outlined,
                  label: 'Pend. validacion: $pendingValidationCount',
                  background: scheme.tertiaryContainer,
                  foreground: scheme.onTertiaryContainer,
                ),
              AppMetaChip(
                icon: Icons.check_circle_outline,
                label: 'Cerrados: $closedCount',
                background: scheme.secondaryContainer,
                foreground: scheme.onSecondaryContainer,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ColorScheme scheme, {String? message}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 48),
            const SizedBox(height: 12),
            Text(
              message ?? _error ?? 'No se pudieron cargar los planes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadContext();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_note_outlined,
              size: 56,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 12),
            Text(
              'No hay planes para este filtro.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _isManager
                  ? 'Cuando crees o asignes acciones correctivas apareceran aqui.'
                  : 'Cuando te asignen una accion correctiva o preventiva la veras aqui.',
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

  Widget _buildPlanCard(BuildContext context, QueryDocumentSnapshot doc) {
    final scheme = Theme.of(context).colorScheme;
    final data = doc.data() as Map<String, dynamic>;
    final title = _titleFor(data);
    final description = _descriptionFor(data);
    final status = _normalizedStatus(data);
    final actionType = _formatActionType(
      (data['actionType'] ?? data['tipoAccion'] ?? '').toString(),
    );
    final priority = _formatPriority(
      (data['priority'] ?? data['prioridad'] ?? '').toString(),
    );
    final responsibleName =
        (data['responsibleName'] ?? data['asignadoA'] ?? 'Sin responsable')
            .toString();
    final dueDate = _readDate(data['dueDate'] ?? data['fechaLimite']);
    final startDate = _readDate(data['startDate'] ?? data['fechaInicio']);
    final executionNote = (data['executionNote'] ?? '').toString().trim();
    final executionEvidence = (data['executionEvidence'] ?? '')
        .toString()
        .trim();
    final verificationStatus = (data['verificationStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final verificationNote = (data['verificationNote'] ?? '').toString().trim();
    final closureEvidence = (data['closureEvidence'] ?? '').toString().trim();
    final executionAttachments = _readAttachmentList(
      data['executionAttachments'],
    );
    final closureAttachments = _readAttachmentList(data['closureAttachments']);
    final progressHistory = _readProgressHistory(data['progressHistory']);
    final isMine =
        (_uid ?? '').isNotEmpty &&
        (data['responsibleUid'] ?? '').toString().trim() == _uid;
    final overdue = _isOverdue(doc);
    final needsValidation = _isManager && status == 'ejecutado';
    final requiresAdjustment =
        verificationStatus == 'requiere_ajuste' && status == 'en_curso';
    final hasExecutionDetails =
        executionNote.isNotEmpty ||
        executionEvidence.isNotEmpty ||
        executionAttachments.isNotEmpty;
    final hasValidationDetails =
        verificationNote.isNotEmpty ||
        closureEvidence.isNotEmpty ||
        closureAttachments.isNotEmpty ||
        (verificationStatus.isNotEmpty && verificationStatus != 'pendiente');
    final taskInstruction = description.isNotEmpty ? description : title;
    final latestResponsibleUpdate =
        _readDate(data['executionUpdatedAt']) ??
        (progressHistory.isNotEmpty ? progressHistory.first.updatedAt : null);
    final nextStepForResponsible = _nextStepForResponsible(
      status: status,
      requiresAdjustment: requiresAdjustment,
      hasExecutionDetails: hasExecutionDetails,
    );
    final nextStepForManager = _nextStepForManager(
      status: status,
      requiresAdjustment: requiresAdjustment,
      hasExecutionDetails: hasExecutionDetails,
      needsValidation: needsValidation,
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: scheme.surfaceContainerHighest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
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
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _statusChip(context, status, overdue: overdue),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (actionType.isNotEmpty)
                  AppMetaChip(
                    icon: Icons.rule_folder_outlined,
                    label: actionType,
                  ),
                if (priority.isNotEmpty)
                  AppMetaChip(
                    icon: Icons.flag_outlined,
                    label: priority,
                    background: _priorityBackground(priority, scheme),
                    foreground: _priorityForeground(priority, scheme),
                  ),
                if (dueDate != null && !_isClosedStatus(status))
                  AppMetaChip(
                    icon: Icons.schedule_outlined,
                    label: _dueStatusLabel(
                      dueDate: dueDate,
                      status: status,
                      overdue: overdue,
                    ),
                    background: overdue
                        ? scheme.errorContainer
                        : scheme.surfaceContainerHigh,
                    foreground: overdue
                        ? scheme.onErrorContainer
                        : scheme.onSurfaceVariant,
                  ),
                if (requiresAdjustment)
                  AppMetaChip(
                    icon: Icons.reply_outlined,
                    label: 'Requiere ajuste',
                    background: scheme.tertiaryContainer,
                    foreground: scheme.onTertiaryContainer,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (requiresAdjustment) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.tertiary.withValues(alpha: 0.28),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: scheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'El admin devolvio este plan para ajuste. Revisa la nota de validacion y vuelve a reportar avance.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onTertiaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            _buildDetailPanel(
              context,
              title: _isManager
                  ? 'Seguimiento del responsable'
                  : 'Que debes ejecutar',
              icon: _isManager
                  ? Icons.manage_accounts_outlined
                  : Icons.assignment_turned_in_outlined,
              children: _isManager
                  ? [
                      _infoRow(
                        context,
                        icon: Icons.badge_outlined,
                        label: 'Responsable',
                        value: responsibleName,
                      ),
                      _infoRow(
                        context,
                        icon: Icons.rule_folder_outlined,
                        label: 'Accion asignada',
                        value: taskInstruction,
                      ),
                      _infoRow(
                        context,
                        icon: Icons.update_outlined,
                        label: 'Ultimo reporte',
                        value: latestResponsibleUpdate == null
                            ? 'Sin avances del responsable'
                            : _formatDateTime(latestResponsibleUpdate),
                      ),
                      _infoRow(
                        context,
                        icon: Icons.perm_media_outlined,
                        label: 'Evidencias recibidas',
                        value: executionAttachments.isEmpty
                            ? 'Sin adjuntos'
                            : '${executionAttachments.length} adjunto(s)',
                      ),
                      _infoRow(
                        context,
                        icon: Icons.arrow_forward_outlined,
                        label: 'Siguiente accion admin',
                        value: nextStepForManager,
                      ),
                    ]
                  : [
                      _infoRow(
                        context,
                        icon: Icons.rule_folder_outlined,
                        label: 'Accion requerida',
                        value: taskInstruction,
                      ),
                      _infoRow(
                        context,
                        icon: Icons.track_changes_outlined,
                        label: 'Resultado esperado',
                        value: _expectedOutcome(actionType),
                      ),
                      _infoRow(
                        context,
                        icon: Icons.arrow_forward_outlined,
                        label: 'Siguiente paso',
                        value: nextStepForResponsible,
                      ),
                    ],
            ),
            const SizedBox(height: 6),
            _infoRow(
              context,
              icon: Icons.calendar_today_outlined,
              label: 'Inicio del plan',
              value: startDate == null ? 'Sin fecha' : _formatDate(startDate),
            ),
            const SizedBox(height: 6),
            _infoRow(
              context,
              icon: Icons.event_outlined,
              label: 'Fecha limite',
              value: dueDate == null ? 'Sin fecha' : _formatDate(dueDate),
            ),
            if (dueDate != null && !_isClosedStatus(status)) ...[
              const SizedBox(height: 6),
              _infoRow(
                context,
                icon: Icons.timer_outlined,
                label: 'Tiempo restante',
                value: _dueStatusLabel(
                  dueDate: dueDate,
                  status: status,
                  overdue: overdue,
                ),
              ),
            ],
            if (hasExecutionDetails) ...[
              const SizedBox(height: 10),
              _buildDetailPanel(
                context,
                title: 'Ejecucion reportada',
                icon: Icons.task_alt_outlined,
                children: [
                  if (executionNote.isNotEmpty)
                    _infoRow(
                      context,
                      icon: Icons.sticky_note_2_outlined,
                      label: 'Avance reportado',
                      value: executionNote,
                    ),
                  if (executionEvidence.isNotEmpty)
                    _infoRow(
                      context,
                      icon: Icons.attach_file_outlined,
                      label: 'Soporte del responsable',
                      value: executionEvidence,
                    ),
                  if (executionAttachments.isNotEmpty)
                    _buildAttachmentSection(
                      context,
                      label: 'Evidencias adjuntas',
                      attachments: executionAttachments,
                    ),
                ],
              ),
            ],
            if (hasValidationDetails) ...[
              const SizedBox(height: 10),
              _buildDetailPanel(
                context,
                title: 'Validacion administrativa',
                icon: Icons.fact_check_outlined,
                children: [
                  if (verificationStatus.isNotEmpty &&
                      verificationStatus != 'pendiente')
                    _infoRow(
                      context,
                      icon: Icons.rule_outlined,
                      label: 'Resultado',
                      value: _formatLooseLabel(verificationStatus),
                    ),
                  if (verificationNote.isNotEmpty)
                    _infoRow(
                      context,
                      icon: Icons.notes_outlined,
                      label: 'Nota de validacion',
                      value: verificationNote,
                    ),
                  if (closureEvidence.isNotEmpty)
                    _infoRow(
                      context,
                      icon: Icons.attachment_outlined,
                      label: 'Soporte de validacion',
                      value: closureEvidence,
                    ),
                  if (closureAttachments.isNotEmpty)
                    _buildAttachmentSection(
                      context,
                      label: 'Adjuntos de validacion',
                      attachments: closureAttachments,
                    ),
                ],
              ),
            ],
            if (progressHistory.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Historial de avances',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              ...progressHistory
                  .take(3)
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _progressHistoryItem(context, entry),
                    ),
                  ),
            ],
            if (_isManager) ...[
              const SizedBox(height: 6),
              _infoRow(
                context,
                icon: Icons.assignment_outlined,
                label: 'Caso relacionado',
                value: _originId(data).isEmpty
                    ? 'Sin vinculo'
                    : _originId(data),
              ),
            ],
            if (isMine && !_isClosedStatus(status)) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: () => _showProgressDialog(doc),
                  icon: const Icon(Icons.update_outlined, size: 18),
                  label: Text(
                    requiresAdjustment
                        ? 'Corregir y reenviar'
                        : status == 'ejecutado'
                        ? 'Actualizar avance'
                        : 'Reportar avance',
                  ),
                ),
              ),
            ],
            if (needsValidation) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => _showValidationDialog(doc),
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Validar ejecucion'),
                ),
              ),
            ],
            if (_isManager && _originId(data).isNotEmpty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _openRelatedIncident(_originId(data)),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Abrir caso'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusChip(
    BuildContext context,
    String status, {
    required bool overdue,
  }) {
    final scheme = Theme.of(context).colorScheme;
    if (overdue) {
      return AppMetaChip(
        icon: Icons.event_busy_outlined,
        label: 'Vencido',
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
      );
    }

    switch (status) {
      case 'en_curso':
        return AppMetaChip(
          icon: Icons.play_circle_outline,
          label: 'En curso',
          background: scheme.tertiaryContainer,
          foreground: scheme.onTertiaryContainer,
        );
      case 'ejecutado':
        return AppMetaChip(
          icon: Icons.task_alt_outlined,
          label: 'Ejecutado',
          background: scheme.primaryContainer,
          foreground: scheme.onPrimaryContainer,
        );
      case 'verificado':
        return AppMetaChip(
          icon: Icons.verified_outlined,
          label: 'Verificado',
          background: scheme.secondaryContainer,
          foreground: scheme.onSecondaryContainer,
        );
      case 'cerrado':
        return AppMetaChip(
          icon: Icons.check_circle_outline,
          label: 'Cerrado',
          background: scheme.secondaryContainer,
          foreground: scheme.onSecondaryContainer,
        );
      default:
        return AppMetaChip(
          icon: Icons.schedule_outlined,
          label: 'Pendiente',
          background: scheme.surfaceContainerHigh,
          foreground: scheme.onSurfaceVariant,
        );
    }
  }

  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: value,
                  style: TextStyle(color: scheme.onSurface),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAttachmentSection(
    BuildContext context, {
    required String label,
    required List<_ActionPlanAttachment> attachments,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.perm_media_outlined,
          size: 16,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label:',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int index = 0; index < attachments.length; index++)
                    ActionChip(
                      avatar: Icon(
                        attachments[index].type == 'video'
                            ? Icons.videocam_outlined
                            : Icons.photo_outlined,
                        size: 16,
                      ),
                      label: Text(
                        attachments[index].type == 'video'
                            ? 'Video ${index + 1}'
                            : 'Foto ${index + 1}',
                      ),
                      onPressed: () =>
                          _openAttachmentUrl(attachments[index].url),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailPanel(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final spacedChildren = <Widget>[];
    for (int index = 0; index < children.length; index++) {
      spacedChildren.add(children[index]);
      if (index < children.length - 1) {
        spacedChildren.add(const SizedBox(height: 6));
      }
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...spacedChildren,
        ],
      ),
    );
  }

  Widget _buildProgressAttachmentComposer(
    BuildContext context, {
    required List<_ActionPlanAttachment> existingAttachments,
    required List<ReportAttachmentInput> pendingAttachments,
    required VoidCallback onAdd,
    required void Function(int index) onRemovePending,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final totalAttachments =
        existingAttachments.length + pendingAttachments.length;
    final canAdd = totalAttachments < _maxExecutionAttachments;

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
                  'Evidencias ($totalAttachments/$_maxExecutionAttachments)',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              OutlinedButton.icon(
                onPressed: canAdd ? onAdd : null,
                icon: const Icon(Icons.attach_file_outlined, size: 18),
                label: const Text('Adjuntar'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Las fotos o videos son opcionales, pero ayudan al admin a validar la ejecucion.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (existingAttachments.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int index = 0; index < existingAttachments.length; index++)
                  ActionChip(
                    avatar: Icon(
                      existingAttachments[index].type == 'video'
                          ? Icons.videocam_outlined
                          : Icons.photo_outlined,
                      size: 16,
                    ),
                    label: Text('Actual ${index + 1}'),
                    onPressed: () =>
                        _openAttachmentUrl(existingAttachments[index].url),
                  ),
              ],
            ),
          ],
          if (pendingAttachments.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...pendingAttachments.asMap().entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        entry.value.type == 'video'
                            ? Icons.videocam_outlined
                            : Icons.photo_outlined,
                        size: 18,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.value.file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Quitar',
                        onPressed: () => onRemovePending(entry.key),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<ReportAttachmentInput?> _pickExecutionAttachment({
    required int existingCount,
    required int pendingCount,
  }) async {
    if (existingCount + pendingCount >= _maxExecutionAttachments) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximo 3 evidencias por plan.')),
      );
      return null;
    }

    final option = await showModalBottomSheet<_ExecutionAttachmentOption>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Foto camara'),
              onTap: () => Navigator.pop(
                sheetContext,
                _ExecutionAttachmentOption.photoCamera,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Foto galeria'),
              onTap: () => Navigator.pop(
                sheetContext,
                _ExecutionAttachmentOption.photoGallery,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video camara'),
              onTap: () => Navigator.pop(
                sheetContext,
                _ExecutionAttachmentOption.videoCamera,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Video galeria'),
              onTap: () => Navigator.pop(
                sheetContext,
                _ExecutionAttachmentOption.videoGallery,
              ),
            ),
          ],
        ),
      ),
    );
    if (option == null) return null;

    XFile? file;
    if (option.isVideo) {
      file = await _picker.pickVideo(source: option.source);
      if (file == null) return null;
      final size = await file.length();
      if (size > _maxExecutionVideoBytes) {
        if (!mounted) return null;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Video maximo 30MB.')));
        return null;
      }
    } else {
      file = await _picker.pickImage(
        source: option.source,
        imageQuality: 70,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (file == null) return null;
    }

    return ReportAttachmentInput(file: file, type: option.type);
  }

  List<_ActionPlanAttachment> _readAttachmentList(dynamic value) {
    if (value is! Iterable) return const [];
    return value
        .whereType<Map>()
        .map(
          (item) => _ActionPlanAttachment(
            type: (item['type'] ?? 'image').toString().trim(),
            url: (item['url'] ?? '').toString().trim(),
            path: (item['path'] ?? '').toString().trim(),
            thumbUrl: (item['thumbUrl'] ?? '').toString().trim(),
          ),
        )
        .where((entry) => entry.url.isNotEmpty)
        .toList();
  }

  Future<void> _openAttachmentUrl(String rawUrl) async {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return;

    Uri? uri = Uri.tryParse(trimmed);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La evidencia no tiene un enlace valido.'),
        ),
      );
      return;
    }
    if (uri.scheme.isEmpty) {
      uri = Uri.tryParse('https://$trimmed');
    }
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La evidencia no tiene un enlace valido.'),
        ),
      );
      return;
    }

    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir la evidencia.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la evidencia.')),
      );
    }
  }

  Widget _progressHistoryItem(
    BuildContext context,
    _ActionPlanProgressEntry entry,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final pieces = <String>[
      _progressStatusLabel(entry.status),
      if (entry.updatedAt != null)
        DateFormat('dd/MM/yyyy HH:mm').format(entry.updatedAt!),
      if (entry.updatedByName.isNotEmpty) entry.updatedByName,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pieces.join('  •  '),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (entry.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              entry.note,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurface),
            ),
          ],
          if (entry.evidence.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Soporte: ${entry.evidence}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (entry.attachments.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Adjuntos: ${entry.attachments.length}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showProgressDialog(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final currentStatus = _normalizedStatus(data);
    final noteController = TextEditingController(
      text: (data['executionNote'] ?? '').toString(),
    );
    final evidenceController = TextEditingController(
      text: (data['executionEvidence'] ?? '').toString(),
    );
    final existingAttachments = _readAttachmentList(
      data['executionAttachments'],
    );
    final newAttachments = <ReportAttachmentInput>[];
    var selectedStatus = currentStatus == 'ejecutado'
        ? 'ejecutado'
        : 'en_curso';
    var noteRequiredError = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Actualizar avance'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Estado de ejecucion',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'en_curso',
                        child: Text('En curso'),
                      ),
                      DropdownMenuItem(
                        value: 'ejecutado',
                        child: Text('Ejecutado'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedStatus = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: noteController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Nota de avance',
                      hintText:
                          'Describe que se realizo o que falta para completar la accion.',
                      border: OutlineInputBorder(),
                      errorText:
                          noteRequiredError && selectedStatus == 'ejecutado'
                          ? 'La nota es obligatoria para marcar como ejecutado.'
                          : null,
                    ),
                    onChanged: (value) {
                      if (noteRequiredError &&
                          value.trim().isNotEmpty &&
                          selectedStatus == 'ejecutado') {
                        setDialogState(() => noteRequiredError = false);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: evidenceController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Soporte del responsable (opcional)',
                      hintText: 'Ej: acta, correo o soporte breve.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildProgressAttachmentComposer(
                    context,
                    existingAttachments: existingAttachments,
                    pendingAttachments: newAttachments,
                    onAdd: () async {
                      final picked = await _pickExecutionAttachment(
                        existingCount: existingAttachments.length,
                        pendingCount: newAttachments.length,
                      );
                      if (picked == null || !mounted) return;
                      setDialogState(() => newAttachments.add(picked));
                    },
                    onRemovePending: (index) {
                      setDialogState(() => newAttachments.removeAt(index));
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final requiresNote =
                    selectedStatus == 'ejecutado' &&
                    noteController.text.trim().isEmpty;
                if (requiresNote) {
                  setDialogState(() => noteRequiredError = true);
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    final note = noteController.text.trim();
    final evidence = evidenceController.text.trim();
    noteController.dispose();
    evidenceController.dispose();
    if (confirmed != true) return;

    if (selectedStatus == 'ejecutado' && note.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Agrega una nota breve para que el admin pueda validar la ejecucion.',
          ),
        ),
      );
      return;
    }

    try {
      List<UploadedAttachment> uploadedAttachments = const [];
      if (newAttachments.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Subiendo evidencias del plan...'),
            duration: Duration(seconds: 2),
          ),
        );
        uploadedAttachments = await _storageService
            .uploadActionPlanExecutionAttachments(newAttachments, doc.id);
      }

      final newAttachmentMaps = uploadedAttachments
          .map((item) => item.toMap())
          .toList();
      final payload = <String, dynamic>{
        'status': selectedStatus,
        'estado': selectedStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        'executionNote': note.isEmpty ? null : note,
        'executionEvidence': evidence.isEmpty ? null : evidence,
        'executionUpdatedAt': FieldValue.serverTimestamp(),
        'executionUpdatedBy': _uid,
        'progressHistory': FieldValue.arrayUnion([
          {
            'status': selectedStatus,
            'note': note,
            'evidence': evidence,
            'attachments': newAttachmentMaps,
            'updatedAt': Timestamp.now(),
            'updatedBy': _uid,
            'updatedByName': _currentUserLabel,
          },
        ]),
        'executedAt': selectedStatus == 'ejecutado'
            ? FieldValue.serverTimestamp()
            : FieldValue.delete(),
      };
      if (newAttachmentMaps.isNotEmpty) {
        payload['executionAttachments'] = [
          ...existingAttachments.map((item) => item.toMap()),
          ...newAttachmentMaps,
        ];
      }

      await doc.reference.update(payload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selectedStatus == 'ejecutado'
                ? 'Plan marcado como ejecutado. Queda pendiente de validacion.'
                : 'Avance actualizado correctamente.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar el plan: $e')),
      );
    }
  }

  Future<void> _showValidationDialog(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    String selectedStatus = 'verificado';
    final noteController = TextEditingController(
      text: (data['verificationNote'] ?? '').toString(),
    );
    final evidenceController = TextEditingController(
      text: (data['closureEvidence'] ?? '').toString(),
    );
    final existingAttachments = _readAttachmentList(data['closureAttachments']);
    final newAttachments = <ReportAttachmentInput>[];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Validar plan'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Resultado de validacion',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'verificado',
                        child: Text('Verificado'),
                      ),
                      DropdownMenuItem(
                        value: 'cerrado',
                        child: Text('Cerrado'),
                      ),
                      DropdownMenuItem(
                        value: 'requiere_ajuste',
                        child: Text('Requiere ajuste'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedStatus = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Nota de validacion',
                      hintText: 'Resume la revision realizada.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: evidenceController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Evidencia o soporte',
                      hintText: 'Opcional: acta, foto, observacion o soporte.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildProgressAttachmentComposer(
                    context,
                    existingAttachments: existingAttachments,
                    pendingAttachments: newAttachments,
                    onAdd: () async {
                      final picked = await _pickExecutionAttachment(
                        existingCount: existingAttachments.length,
                        pendingCount: newAttachments.length,
                      );
                      if (picked == null || !mounted) return;
                      setDialogState(() => newAttachments.add(picked));
                    },
                    onRemovePending: (index) {
                      setDialogState(() => newAttachments.removeAt(index));
                    },
                  ),
                ],
              ),
            ),
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

    final note = noteController.text.trim();
    final evidence = evidenceController.text.trim();
    noteController.dispose();
    evidenceController.dispose();
    if (confirmed != true) return;

    if (note.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Agrega una nota para dejar trazabilidad de la validacion.',
          ),
        ),
      );
      return;
    }

    final payload = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      'verificationNote': note,
      'closureEvidence': evidence.isEmpty ? null : evidence,
    };

    if (selectedStatus == 'requiere_ajuste') {
      payload['status'] = 'en_curso';
      payload['estado'] = 'en_curso';
      payload['verificationStatus'] = 'requiere_ajuste';
      payload['closedAt'] = FieldValue.delete();
      payload['closedBy'] = FieldValue.delete();
    } else {
      payload['status'] = selectedStatus;
      payload['estado'] = selectedStatus;
      payload['verificationStatus'] = 'efectiva';
      if (selectedStatus == 'cerrado') {
        payload['closedAt'] = FieldValue.serverTimestamp();
        payload['closedBy'] = _uid;
      } else {
        payload['closedAt'] = FieldValue.delete();
        payload['closedBy'] = FieldValue.delete();
      }
    }

    try {
      if (newAttachments.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Subiendo soportes de validacion...'),
            duration: Duration(seconds: 2),
          ),
        );
        final uploaded = await _storageService
            .uploadActionPlanValidationAttachments(newAttachments, doc.id);
        final newAttachmentMaps = uploaded.map((item) => item.toMap()).toList();
        payload['closureAttachments'] = [
          ...existingAttachments.map((item) => item.toMap()),
          ...newAttachmentMaps,
        ];
      }

      await doc.reference.update(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selectedStatus == 'requiere_ajuste'
                ? 'Plan devuelto a en curso para ajuste.'
                : 'Validacion registrada correctamente.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo validar el plan: $e')));
    }
  }

  Future<void> _openRelatedIncident(String reportId) async {
    final trimmed = reportId.trim();
    if (trimmed.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontro el caso relacionado.')),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReportDetailsScreen(documentId: trimmed),
      ),
    );
  }

  List<_ActionPlanFilter> get _availableFilters {
    if (_isManager) {
      return const [
        _ActionPlanFilter.active,
        _ActionPlanFilter.mine,
        _ActionPlanFilter.pendingValidation,
        _ActionPlanFilter.overdue,
        _ActionPlanFilter.closed,
        _ActionPlanFilter.all,
      ];
    }
    return const [
      _ActionPlanFilter.active,
      _ActionPlanFilter.overdue,
      _ActionPlanFilter.closed,
      _ActionPlanFilter.all,
    ];
  }

  bool _canViewPlan(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final responsibleUid = (data['responsibleUid'] ?? '').toString().trim();
    if (!_isManager) {
      return responsibleUid == (_uid ?? '');
    }
    if (_role == 'admin') {
      return true;
    }
    final planInstitutionId = (data['institutionId'] ?? '').toString().trim();
    if (planInstitutionId.isNotEmpty) {
      return planInstitutionId == (_institutionId ?? '');
    }
    final assignedBy = (data['assignedBy'] ?? '').toString().trim();
    return assignedBy == (_uid ?? '') || responsibleUid == (_uid ?? '');
  }

  int _comparePlans(QueryDocumentSnapshot a, QueryDocumentSnapshot b) {
    final aClosed = _isClosed(a);
    final bClosed = _isClosed(b);
    if (aClosed != bClosed) {
      return aClosed ? 1 : -1;
    }

    if (_isManager) {
      final aPendingValidation = _isPendingValidation(a);
      final bPendingValidation = _isPendingValidation(b);
      if (aPendingValidation != bPendingValidation) {
        return aPendingValidation ? -1 : 1;
      }
    }

    final aOverdue = _isOverdue(a);
    final bOverdue = _isOverdue(b);
    if (aOverdue != bOverdue) {
      return aOverdue ? -1 : 1;
    }

    final aDue = _readDate(
      ((a.data() as Map<String, dynamic>)['dueDate'] ??
          (a.data() as Map<String, dynamic>)['fechaLimite']),
    );
    final bDue = _readDate(
      ((b.data() as Map<String, dynamic>)['dueDate'] ??
          (b.data() as Map<String, dynamic>)['fechaLimite']),
    );
    if (aDue != null && bDue != null) {
      return aDue.compareTo(bDue);
    }
    if (aDue != null) return -1;
    if (bDue != null) return 1;

    final aUpdated = _readDate((a.data() as Map<String, dynamic>)['updatedAt']);
    final bUpdated = _readDate((b.data() as Map<String, dynamic>)['updatedAt']);
    if (aUpdated != null && bUpdated != null) {
      return bUpdated.compareTo(aUpdated);
    }
    return 0;
  }

  bool _matchesFilter(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final status = _normalizedStatus(data);
    switch (_filter) {
      case _ActionPlanFilter.active:
        return !_isClosedStatus(status);
      case _ActionPlanFilter.mine:
        return (data['responsibleUid'] ?? '').toString().trim() == (_uid ?? '');
      case _ActionPlanFilter.pendingValidation:
        return _isPendingValidation(doc);
      case _ActionPlanFilter.overdue:
        return _isOverdue(doc);
      case _ActionPlanFilter.closed:
        return _isClosedStatus(status);
      case _ActionPlanFilter.all:
        return true;
    }
  }

  bool _isOverdue(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final dueDate = _readDate(data['dueDate'] ?? data['fechaLimite']);
    final status = _normalizedStatus(data);
    if (dueDate == null || _isClosedStatus(status) || status == 'ejecutado') {
      return false;
    }
    return dueDate.isBefore(DateTime.now());
  }

  bool _isPendingValidation(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return _normalizedStatus(data) == 'ejecutado';
  }

  bool _isClosed(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return _isClosedStatus(_normalizedStatus(data));
  }

  bool _isClosedStatus(String status) {
    return status == 'cerrado' || status == 'verificado';
  }

  String _normalizedStatus(Map<String, dynamic> data) {
    final raw = (data['status'] ?? data['estado'] ?? 'pendiente').toString();
    final normalized = raw.trim().toLowerCase().replaceAll(' ', '_');
    if (normalized.contains('curso')) return 'en_curso';
    if (normalized.contains('ejecut')) return 'ejecutado';
    if (normalized.contains('verif')) return 'verificado';
    if (normalized.contains('cerr')) return 'cerrado';
    return 'pendiente';
  }

  DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _formatDate(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

  String _formatDateTime(DateTime date) =>
      DateFormat('dd/MM/yyyy HH:mm').format(date);

  String _dueStatusLabel({
    required DateTime dueDate,
    required String status,
    required bool overdue,
  }) {
    if (_isClosedStatus(status)) return 'Plan cerrado';
    if (overdue) {
      final now = DateTime.now();
      final dueOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);
      final nowOnly = DateTime(now.year, now.month, now.day);
      final daysLate = nowOnly.difference(dueOnly).inDays;
      final safeDaysLate = daysLate <= 0 ? 1 : daysLate;
      return '$safeDaysLate dia(s) de atraso';
    }

    final now = DateTime.now();
    final dueOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final nowOnly = DateTime(now.year, now.month, now.day);
    final days = dueOnly.difference(nowOnly).inDays;
    if (days <= 0) return 'Vence hoy';
    if (days == 1) return 'Vence manana';
    return '$days dias restantes';
  }

  String _expectedOutcome(String actionType) {
    final value = actionType.trim().toLowerCase();
    if (value.contains('correctiva')) {
      return 'Corregir el hallazgo y dejar evidencia de la solucion aplicada.';
    }
    if (value.contains('preventiva')) {
      return 'Implementar control para evitar la recurrencia del riesgo.';
    }
    return 'Registrar mejora aplicada y evidencia de su implementacion.';
  }

  String _nextStepForResponsible({
    required String status,
    required bool requiresAdjustment,
    required bool hasExecutionDetails,
  }) {
    if (requiresAdjustment) {
      return 'Ajusta el plan segun la observacion del admin y reporta de nuevo.';
    }
    if (status == 'pendiente') {
      return 'Inicia la ejecucion y registra el primer avance.';
    }
    if (status == 'en_curso') {
      return hasExecutionDetails
          ? 'Completa lo pendiente y marca el plan como ejecutado.'
          : 'Registra avance y agrega evidencia para soporte.';
    }
    if (status == 'ejecutado') {
      return 'Espera validacion del admin SST.';
    }
    return 'Plan finalizado. No tienes acciones pendientes.';
  }

  String _nextStepForManager({
    required String status,
    required bool requiresAdjustment,
    required bool hasExecutionDetails,
    required bool needsValidation,
  }) {
    if (needsValidation) {
      return 'Revisar evidencias del responsable y emitir validacion.';
    }
    if (requiresAdjustment) {
      return 'Esperar correccion del responsable segun observacion enviada.';
    }
    if (status == 'pendiente') {
      return 'Monitorear inicio de la ejecucion por el responsable.';
    }
    if (status == 'en_curso') {
      return hasExecutionDetails
          ? 'Dar seguimiento al avance y fecha limite.'
          : 'Aun no hay reporte del responsable.';
    }
    return 'Plan finalizado o verificado.';
  }

  String _filterLabel(_ActionPlanFilter filter) {
    switch (filter) {
      case _ActionPlanFilter.active:
        return 'En seguimiento';
      case _ActionPlanFilter.mine:
        return 'Asignados a mi';
      case _ActionPlanFilter.pendingValidation:
        return 'Pend. validacion';
      case _ActionPlanFilter.overdue:
        return 'Vencidos';
      case _ActionPlanFilter.closed:
        return 'Cerrados';
      case _ActionPlanFilter.all:
        return 'Todos';
    }
  }

  String _titleFor(Map<String, dynamic> data) {
    final title = (data['title'] ?? '').toString().trim();
    if (title.isNotEmpty) return title;
    final description = (data['description'] ?? data['descripcion'] ?? '')
        .toString()
        .trim();
    if (description.isEmpty) return 'Plan de accion';
    if (description.length <= 46) return description;
    return '${description.substring(0, 46)}...';
  }

  String _descriptionFor(Map<String, dynamic> data) {
    final description = (data['description'] ?? data['descripcion'] ?? '')
        .toString()
        .trim();
    if (description == _titleFor(data)) return '';
    return description;
  }

  String _originId(Map<String, dynamic> data) {
    return (data['originReportId'] ?? data['eventoId'] ?? '').toString().trim();
  }

  String _formatActionType(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'correctiva':
        return 'Correctiva';
      case 'preventiva':
        return 'Preventiva';
      case 'mejora':
        return 'Mejora';
      default:
        return raw.trim();
    }
  }

  String _formatPriority(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'alta':
        return 'Prioridad alta';
      case 'media':
        return 'Prioridad media';
      case 'baja':
        return 'Prioridad baja';
      default:
        return raw.trim();
    }
  }

  String _formatLooseLabel(String raw) {
    final value = raw.trim().replaceAll('_', ' ');
    if (value.isEmpty) return '';
    return value
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Color _priorityBackground(String priority, ColorScheme scheme) {
    final normalized = priority.toLowerCase();
    if (normalized.contains('alta')) return scheme.errorContainer;
    if (normalized.contains('media')) return scheme.tertiaryContainer;
    return scheme.secondaryContainer;
  }

  Color _priorityForeground(String priority, ColorScheme scheme) {
    final normalized = priority.toLowerCase();
    if (normalized.contains('alta')) return scheme.onErrorContainer;
    if (normalized.contains('media')) return scheme.onTertiaryContainer;
    return scheme.onSecondaryContainer;
  }

  List<_ActionPlanProgressEntry> _readProgressHistory(dynamic value) {
    if (value is! Iterable) return const [];

    final entries = value
        .whereType<Map>()
        .map(
          (item) => _ActionPlanProgressEntry(
            status: (item['status'] ?? '').toString().trim(),
            note: (item['note'] ?? '').toString().trim(),
            evidence: (item['evidence'] ?? '').toString().trim(),
            attachments: _readAttachmentList(item['attachments']),
            updatedAt: _readDate(item['updatedAt']),
            updatedByName: (item['updatedByName'] ?? '').toString().trim(),
          ),
        )
        .where((entry) => entry.status.isNotEmpty || entry.note.isNotEmpty)
        .toList();

    entries.sort((a, b) {
      final aDate = a.updatedAt;
      final bDate = b.updatedAt;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return entries;
  }

  String _progressStatusLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'en_curso':
        return 'En curso';
      case 'ejecutado':
        return 'Ejecutado';
      default:
        final value = raw.trim();
        if (value.isEmpty) return 'Actualizacion';
        return value
            .replaceAll('_', ' ')
            .split(' ')
            .where((part) => part.isNotEmpty)
            .map(
              (part) =>
                  '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
            )
            .join(' ');
    }
  }
}

enum _ActionPlanFilter { active, mine, pendingValidation, overdue, closed, all }

class _ActionPlanProgressEntry {
  final String status;
  final String note;
  final String evidence;
  final List<_ActionPlanAttachment> attachments;
  final DateTime? updatedAt;
  final String updatedByName;

  const _ActionPlanProgressEntry({
    required this.status,
    required this.note,
    required this.evidence,
    required this.attachments,
    required this.updatedAt,
    required this.updatedByName,
  });
}

class _ActionPlanAttachment {
  final String type;
  final String url;
  final String path;
  final String thumbUrl;

  const _ActionPlanAttachment({
    required this.type,
    required this.url,
    required this.path,
    required this.thumbUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'url': url,
      'path': path,
      'thumbUrl': thumbUrl.isEmpty ? null : thumbUrl,
    };
  }
}

enum _ExecutionAttachmentOption {
  photoCamera,
  photoGallery,
  videoCamera,
  videoGallery;

  ImageSource get source {
    switch (this) {
      case _ExecutionAttachmentOption.photoCamera:
      case _ExecutionAttachmentOption.videoCamera:
        return ImageSource.camera;
      case _ExecutionAttachmentOption.photoGallery:
      case _ExecutionAttachmentOption.videoGallery:
        return ImageSource.gallery;
    }
  }

  bool get isVideo {
    return this == _ExecutionAttachmentOption.videoCamera ||
        this == _ExecutionAttachmentOption.videoGallery;
  }

  String get type => isVideo ? 'video' : 'image';
}
