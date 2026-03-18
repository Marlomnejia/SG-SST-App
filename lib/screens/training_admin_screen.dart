import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/training_module_model.dart';
import '../services/notification_service.dart';
import '../services/training_service.dart';
import '../services/user_service.dart';

class AdminTrainingScreen extends StatefulWidget {
  const AdminTrainingScreen({super.key});

  @override
  State<AdminTrainingScreen> createState() => _AdminTrainingScreenState();
}

class _AdminTrainingScreenState extends State<AdminTrainingScreen> {
  final TrainingService _service = TrainingService();
  final UserService _userService = UserService();
  final NotificationService _notificationService = NotificationService();
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy hh:mm a');
  final TextEditingController _searchController = TextEditingController();
  String _combinedFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('GestiÃ³n de capacitaciones'),
        actions: [
          IconButton(
            tooltip: 'Probar notificacion',
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: _diagnoseNotificationSetup,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _service.streamInstitutionTrainingsForAdmin(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.school_outlined,
                      size: 54,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'AÃºn no hay capacitaciones creadas',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Crea la primera capacitaciÃ³n para tu instituciÃ³n.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _openForm,
                      icon: const Icon(Icons.add),
                      label: const Text('Crear capacitaciÃ³n'),
                    ),
                  ],
                ),
              ),
            );
          }
          final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
            snapshot.data!.docs,
          )..sort(_sortAdminDocs);
          final search = _searchController.text.trim().toLowerCase();
          final filteredDocs = docs.where((doc) {
            final data = doc.data();
            final type = (data['type'] ?? '').toString();
            final status = (data['status'] ?? '').toString();
            final title = (data['title'] ?? '').toString().toLowerCase();
            final topic = (data['topic'] ?? '').toString().toLowerCase();
            final matchSearch =
                search.isEmpty ||
                title.contains(search) ||
                topic.contains(search);
            final bool matchFilter;
            switch (_combinedFilter) {
              case 'published':
                matchFilter = status == 'published';
                break;
              case 'cancelled':
                matchFilter = status == 'cancelled';
                break;
              case 'scheduled':
                matchFilter = type == 'scheduled';
                break;
              case 'video':
                matchFilter = type == 'video';
                break;
              default:
                matchFilter = true;
            }
            return matchFilter && matchSearch;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Buscar por titulo o tema',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.trim().isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Text(
                            'Filtro:',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Todas'),
                            selected: _combinedFilter == 'all',
                            onSelected: (_) =>
                                setState(() => _combinedFilter = 'all'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Publicadas'),
                            selected: _combinedFilter == 'published',
                            onSelected: (_) =>
                                setState(() => _combinedFilter = 'published'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Canceladas'),
                            selected: _combinedFilter == 'cancelled',
                            onSelected: (_) =>
                                setState(() => _combinedFilter = 'cancelled'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Programadas'),
                            selected: _combinedFilter == 'scheduled',
                            onSelected: (_) =>
                                setState(() => _combinedFilter = 'scheduled'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Videos'),
                            selected: _combinedFilter == 'video',
                            onSelected: (_) =>
                                setState(() => _combinedFilter = 'video'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filteredDocs.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.filter_alt_off_outlined,
                                size: 48,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'No hay resultados con esos filtros',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Ajusta estado, tipo o busqueda para ver capacitaciones.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: filteredDocs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final doc = filteredDocs[index];
                          final data = doc.data();
                          final type = (data['type'] ?? 'scheduled').toString();
                          final status = (data['status'] ?? 'published')
                              .toString();
                          final topic = (data['topic'] ?? '').toString().trim();
                          final description = (data['description'] ?? '')
                              .toString()
                              .trim();
                          final isScheduled =
                              type == TrainingType.scheduled.name;
                          final scheduled =
                              (data['scheduled'] as Map<String, dynamic>?) ??
                              {};
                          final startAt = scheduled['startAt'] as Timestamp?;
                          final endAt = scheduled['endAt'] as Timestamp?;
                          final mode = (scheduled['mode'] ?? '').toString();
                          final meetUrl = (scheduled['meetUrl'] ?? '')
                              .toString()
                              .trim();
                          final video =
                              (data['video'] as Map<String, dynamic>?) ?? {};
                          final youtubeUrl = (video['youtubeUrl'] ?? '')
                              .toString()
                              .trim();
                          final publishedAt =
                              (data['publishedAt'] as Timestamp?) ??
                              (data['createdAt'] as Timestamp?);
                          final now = DateTime.now();
                          final isCancelled =
                              status == TrainingStatus.cancelled.name;
                          final timeBadge = _buildTimeStateBadge(
                            context,
                            startAt: startAt?.toDate(),
                            endAt: endAt?.toDate(),
                            now: now,
                          );

                          return Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest.withValues(
                                alpha: 0.38,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _MetaPill(
                                  icon: isScheduled
                                      ? Icons.event_available_outlined
                                      : Icons.ondemand_video_outlined,
                                  label: isScheduled
                                      ? 'SesiÃ³n programada'
                                      : 'Contenido en lÃ­nea',
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        (data['title'] ?? 'Capacitacion')
                                            .toString(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    _StatusBadge(status: status),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (isScheduled && startAt != null)
                                      _MetaPill(
                                        icon: Icons.schedule,
                                        label: _formatAdminDate(
                                          startAt.toDate(),
                                        ),
                                      ),
                                    if (isScheduled && mode.trim().isNotEmpty)
                                      _MetaPill(
                                        icon: mode == 'virtual'
                                            ? Icons.videocam_outlined
                                            : Icons.location_on_outlined,
                                        label: mode == 'virtual'
                                            ? 'Virtual'
                                            : 'Presencial',
                                      ),
                                    if (publishedAt != null)
                                      _MetaPill(
                                        icon: Icons.publish_outlined,
                                        label:
                                            'Publicado: ${DateFormat('dd/MM/yyyy').format(publishedAt.toDate())}',
                                      ),
                                    if (timeBadge != null) timeBadge,
                                  ],
                                ),
                                if (topic.isNotEmpty ||
                                    description.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: scheme.surface.withValues(
                                        alpha: 0.55,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: scheme.outlineVariant.withValues(
                                          alpha: 0.45,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (topic.isNotEmpty)
                                          Text(
                                            'Tema: $topic',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        if (description.isNotEmpty) ...[
                                          if (topic.isNotEmpty)
                                            const SizedBox(height: 6),
                                          Text(
                                            description,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodyMedium,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                                if (isScheduled) ...[
                                  const SizedBox(height: 12),
                                  _ScheduledStatsPanel(
                                    trainingRef: doc.reference,
                                  ),
                                ],
                                const SizedBox(height: 14),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: scheme.surface.withValues(
                                      alpha: 0.45,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: scheme.outlineVariant.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Acciones de gestiÃ³n',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: () => _openForm(
                                              editId: doc.id,
                                              editData: data,
                                            ),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                              size: 18,
                                            ),
                                            label: const Text('Editar'),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: () => _showResponses(
                                              trainingId: doc.id,
                                              institutionId:
                                                  doc
                                                      .reference
                                                      .parent
                                                      .parent
                                                      ?.id ??
                                                  '',
                                            ),
                                            icon: const Icon(
                                              Icons.people_outline,
                                              size: 18,
                                            ),
                                            label: const Text('Confirmaciones'),
                                          ),
                                          if (isScheduled)
                                            OutlinedButton.icon(
                                              onPressed: isCancelled
                                                  ? null
                                                  : () => _showAttendance(
                                                      trainingId: doc.id,
                                                      institutionId:
                                                          doc
                                                              .reference
                                                              .parent
                                                              .parent
                                                              ?.id ??
                                                          '',
                                                    ),
                                              icon: const Icon(
                                                Icons.fact_check_outlined,
                                                size: 18,
                                              ),
                                              label: const Text('Asistencia'),
                                            ),
                                          if (isScheduled && meetUrl.isNotEmpty)
                                            OutlinedButton.icon(
                                              onPressed: isCancelled
                                                  ? null
                                                  : () => _openMeetingLink(
                                                      meetUrl,
                                                    ),
                                              icon: const Icon(
                                                Icons.open_in_new_rounded,
                                                size: 18,
                                              ),
                                              label: const Text(
                                                'Abrir reuniÃ³n',
                                              ),
                                            ),
                                          if (!isScheduled &&
                                              youtubeUrl.isNotEmpty)
                                            OutlinedButton.icon(
                                              onPressed: isCancelled
                                                  ? null
                                                  : () => _openVideoLink(
                                                      youtubeUrl,
                                                    ),
                                              icon: const Icon(
                                                Icons.ondemand_video_outlined,
                                                size: 18,
                                              ),
                                              label: const Text('Abrir video'),
                                            ),
                                          if (status !=
                                              TrainingStatus.cancelled.name)
                                            OutlinedButton.icon(
                                              onPressed: () =>
                                                  _cancelFromList(doc.id),
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                size: 18,
                                              ),
                                              label: const Text('Cancelar'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: scheme.error,
                                                side: BorderSide(
                                                  color: scheme.error
                                                      .withValues(alpha: 0.6),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Crear capacitaciÃ³n'),
      ),
    );
  }

  Future<void> _openForm({
    String? editId,
    Map<String, dynamic>? editData,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _TrainingFormScreen(
          service: _service,
          editId: editId,
          editData: editData,
        ),
      ),
    );
  }

  Future<void> _showResponses({
    required String trainingId,
    required String institutionId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No hay sesion activa.')));
      return;
    }
    String effectiveInstitutionId = institutionId.trim();
    if (effectiveInstitutionId.isEmpty) {
      effectiveInstitutionId =
          ((await _userService.getUserInstitutionId(user.uid)) ?? '').trim();
    }
    if (effectiveInstitutionId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontro institutionId del admin.'),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _buildTrainingBottomSheet(
        _ResponsesSheet(
          trainingId: trainingId,
          institutionId: effectiveInstitutionId,
        ),
      ),
    );
  }

  Future<void> _showAttendance({
    required String trainingId,
    required String institutionId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No hay sesion activa.')));
      return;
    }
    String effectiveInstitutionId = institutionId.trim();
    if (effectiveInstitutionId.isEmpty) {
      effectiveInstitutionId =
          ((await _userService.getUserInstitutionId(user.uid)) ?? '').trim();
    }
    if (effectiveInstitutionId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontro institutionId del admin.'),
        ),
      );
      return;
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _buildTrainingBottomSheet(
        _AttendanceSheet(
          trainingId: trainingId,
          institutionId: effectiveInstitutionId,
        ),
      ),
    );
  }

  Widget _buildTrainingBottomSheet(Widget child) {
    final scheme = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      heightFactor: 0.86,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: Material(color: scheme.surface, child: child),
      ),
    );
  }

  Uri? _normalizeExternalUri(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return null;
    Uri? uri = Uri.tryParse(clean);
    if (uri == null) return null;
    if (!uri.hasScheme || uri.host.isEmpty) {
      uri = Uri.tryParse(
        clean.startsWith('//') ? 'https:$clean' : 'https://$clean',
      );
    }
    if (uri == null || uri.host.isEmpty) return null;
    return uri;
  }

  Future<void> _openMeetingLink(String rawUrl) async {
    final uri = _normalizeExternalUri(rawUrl);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enlace de reuniÃ³n invÃ¡lido.')),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el enlace de reuniÃ³n.'),
        ),
      );
    }
  }

  Future<void> _openVideoLink(String rawUrl) async {
    final uri = _normalizeExternalUri(rawUrl);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('URL de video invalida.')));
      return;
    }
    var ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el video.')),
      );
    }
  }

  Future<void> _diagnoseNotificationSetup() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No hay sesion activa.')));
      return;
    }
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = userDoc.data() ?? {};
    final institutionId = (data['institutionId'] ?? '').toString();
    final notificationsEnabled = (data['notificationsEnabled'] ?? true) == true;
    final myTokens = List<String>.from(data['fcmTokens'] ?? const []);

    int institutionUsers = 0;
    int eligibleUsers = 0;
    int usersWithTokens = 0;
    int institutionTokens = 0;
    int publishedTrainings = 0;

    if (institutionId.trim().isNotEmpty) {
      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: institutionId)
          .get();
      institutionUsers = usersSnap.size;
      const allowedRoles = {'user', 'employee'};
      for (final doc in usersSnap.docs) {
        final userData = doc.data();
        final role = (userData['role'] ?? '').toString().trim();
        if (!allowedRoles.contains(role)) {
          continue;
        }
        final notificationsEnabled =
            (userData['notificationsEnabled'] as bool?) ?? true;
        if (!notificationsEnabled) {
          continue;
        }
        eligibleUsers++;
        final tokens = List<String>.from(userData['fcmTokens'] ?? const []);
        if (tokens.isNotEmpty) {
          usersWithTokens++;
          institutionTokens += tokens.length;
        }
      }

      final trainingsSnap = await FirebaseFirestore.instance
          .collection('institutions')
          .doc(institutionId)
          .collection('trainings')
          .where('status', isEqualTo: 'published')
          .get();
      publishedTrainings = trainingsSnap.size;
    }

    debugPrint('[Notifications][diagnostic] uid=${user.uid}');
    debugPrint('[Notifications][diagnostic] institutionId=$institutionId');
    debugPrint(
      '[Notifications][diagnostic] myNotificationsEnabled=$notificationsEnabled myTokens=${myTokens.length}',
    );
    debugPrint(
      '[Notifications][diagnostic] institutionUsers=$institutionUsers eligibleUsers=$eligibleUsers usersWithTokens=$usersWithTokens totalTokens=$institutionTokens',
    );
    debugPrint(
      '[Notifications][diagnostic] publishedTrainings=$publishedTrainings',
    );

    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Diagnostico de notificaciones'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('institutionId: $institutionId'),
                Text('Tu switch de notificaciones: $notificationsEnabled'),
                Text('Tus tokens FCM: ${myTokens.length}'),
                const SizedBox(height: 8),
                Text('Usuarios en la institucion: $institutionUsers'),
                Text('Usuarios objetivo (user/employee): $eligibleUsers'),
                Text('Usuarios con token: $usersWithTokens'),
                Text('Tokens totales en institucion: $institutionTokens'),
                Text('Capacitaciones publicadas: $publishedTrainings'),
                const SizedBox(height: 10),
                const Text(
                  'Backend: Cloud Functions (training_published, reminders 24h/1h, training_cancelled). Si no estan desplegadas, no llegaran notificaciones.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final ok = await _notificationService.enableForUser(user.uid);
                if (!mounted || !dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'Token actualizado. Revisa logs del diagnostico.'
                          : 'Permiso denegado o token no disponible.',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar token'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _cancelFromList(String trainingId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final role = (await _userService.getUserRole(user.uid)) ?? '';
    final institutionId =
        (await _userService.getUserInstitutionId(user.uid)) ?? '';
    if (institutionId.trim().isEmpty ||
        (role != 'admin_sst' && role != 'admin')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tienes permisos para cancelar.')),
      );
      return;
    }
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancelar capacitaciÃ³n'),
          content: const Text(
            'Se marcara como cancelada y se notificara a los usuarios.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Si, cancelar'),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;

    try {
      await _service.updateInstitutionTraining(trainingId, {
        'status': TrainingStatus.cancelled.name,
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': user.uid,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Capacitacion cancelada.')));
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final code = e.code.toUpperCase();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cancelar ($code): ${e.message ?? ''}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo cancelar: $e')));
    }
  }

  int _sortAdminDocs(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final statusA = (a.data()['status'] ?? 'draft').toString();
    final statusB = (b.data()['status'] ?? 'draft').toString();
    final statusOrder = _statusWeight(
      statusA,
    ).compareTo(_statusWeight(statusB));
    if (statusOrder != 0) return statusOrder;

    final createdAtA = a.data()['createdAt'] as Timestamp?;
    final createdAtB = b.data()['createdAt'] as Timestamp?;
    final dateA =
        createdAtA?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
    final dateB =
        createdAtB?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
    return dateB.compareTo(dateA);
  }

  int _statusWeight(String status) {
    switch (status) {
      case 'draft':
        return 0;
      case 'published':
        return 1;
      case 'cancelled':
        return 2;
      default:
        return 3;
    }
  }

  String _formatAdminDate(DateTime value) {
    final now = DateTime.now();
    if (_isSameDay(value, now)) {
      return 'Hoy ${DateFormat('hh:mm a').format(value)}';
    }
    final tomorrow = now.add(const Duration(days: 1));
    if (_isSameDay(value, tomorrow)) {
      return 'Manana ${DateFormat('hh:mm a').format(value)}';
    }
    return _dateFormat.format(value);
  }

  Widget? _buildTimeStateBadge(
    BuildContext context, {
    required DateTime? startAt,
    required DateTime? endAt,
    required DateTime now,
  }) {
    if (startAt == null) return null;
    if (endAt != null && endAt.isBefore(now)) {
      return const _TinyBadge(label: 'Finalizada', color: Colors.grey);
    }
    final diff = startAt.difference(now);
    if (diff.isNegative) return null;
    if (_isSameDay(startAt, now)) {
      return const _TinyBadge(label: 'Hoy', color: Colors.orange);
    }
    if (diff <= const Duration(hours: 24)) {
      return const _TinyBadge(label: 'Proxima', color: Colors.orange);
    }
    return null;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _TrainingFormScreen extends StatefulWidget {
  final TrainingService service;
  final String? editId;
  final Map<String, dynamic>? editData;
  const _TrainingFormScreen({
    required this.service,
    this.editId,
    this.editData,
  });

  @override
  State<_TrainingFormScreen> createState() => _TrainingFormScreenState();
}

class _TrainingFormScreenState extends State<_TrainingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final UserService _userService = UserService();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _topic = TextEditingController();
  final _place = TextEditingController();
  final _meetUrl = TextEditingController();
  final _youtubeUrl = TextEditingController();
  final _capacity = TextEditingController();
  final _duration = TextEditingController();

  String _type = TrainingType.scheduled.name;
  String _status = TrainingStatus.published.name;
  String _mode = 'presencial';
  bool _requireRsvp = true;
  DateTime _startAt = DateTime.now().add(const Duration(days: 1));
  DateTime _endAt = DateTime.now().add(const Duration(days: 1, hours: 1));
  bool _saving = false;
  bool _cancelling = false;
  bool _autoValidate = false;
  bool _isCancelledTraining = false;
  static const double _fieldGap = 16;
  static const double _sectionGap = 26;

  bool get _isEditing => widget.editId != null;
  bool get _isRangeValid => _endAt.isAfter(_startAt);

  bool get _isYouTubeValid {
    final raw = _youtubeUrl.text.trim();
    if (raw.isEmpty) return false;
    final uri = Uri.tryParse(raw);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host.contains('youtube.com') || host.contains('youtu.be');
  }

  bool get _isMeetingUrlValid {
    final raw = _meetUrl.text.trim();
    if (raw.isEmpty) return false;
    Uri? uri = Uri.tryParse(raw);
    if (uri != null && (uri.host.isEmpty || !uri.hasScheme)) {
      uri = Uri.tryParse(raw.startsWith('//') ? 'https:$raw' : 'https://$raw');
    }
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    if (host.contains('youtube.com') || host.contains('youtu.be')) {
      return false;
    }
    if (host.contains('meet.google.com')) {
      return true;
    }
    if (host.contains('zoom.us') || host.contains('us02web.zoom.us')) {
      return path.contains('/j/') ||
          path.contains('/wc/') ||
          path.contains('/join');
    }
    if (host.contains('teams.microsoft.com')) {
      return path.contains('/meetup-join') || path.contains('/l/meetup-join');
    }
    if (host.contains('webex.com')) {
      return path.contains('/meet') || path.contains('/join');
    }
    if (host.contains('meet.jit.si')) {
      return path.trim().isNotEmpty && path != '/';
    }
    return false;
  }

  Uri? _normalizeExternalUri(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return null;
    Uri? uri = Uri.tryParse(clean);
    if (uri == null) return null;
    if (!uri.hasScheme || uri.host.isEmpty) {
      uri = Uri.tryParse(
        clean.startsWith('//') ? 'https:$clean' : 'https://$clean',
      );
    }
    if (uri == null || uri.host.isEmpty) return null;
    return uri;
  }

  Future<void> _openMeetingPreviewLink() async {
    final uri = _normalizeExternalUri(_meetUrl.text);
    if (uri == null || !_isMeetingUrlValid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enlace de reuniÃ³n invÃ¡lido.')),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el enlace de reuniÃ³n.'),
        ),
      );
    }
  }

  String? get _disabledMessage {
    if (_isCancelledTraining) {
      return 'La capacitaciÃ³n fue cancelada y no admite cambios.';
    }
    if (_saving) return null;
    if (_title.text.trim().isEmpty) return 'Agrega un titulo para continuar.';
    if (_desc.text.trim().isEmpty) return 'Agrega una descripcion breve.';
    if (_topic.text.trim().isEmpty) {
      return 'Agrega un tema para la capacitaciÃ³n.';
    }
    if (_type == TrainingType.scheduled.name) {
      if (!_isRangeValid) {
        return 'La hora de fin debe ser posterior al inicio.';
      }
      if (_mode == 'presencial' && _place.text.trim().isEmpty) {
        return 'Indica el lugar para la modalidad presencial.';
      }
      if (_mode == 'virtual' && _meetUrl.text.trim().isEmpty) {
        return 'Ingresa el enlace de reuniÃ³n para modalidad virtual.';
      }
      if (_mode == 'virtual' && !_isMeetingUrlValid) {
        return 'Usa un enlace vÃ¡lido de reuniÃ³n (Meet, Zoom, Teams, Webex o Jitsi).';
      }
      return null;
    }
    if (_type == TrainingType.video.name) {
      if (_youtubeUrl.text.trim().isEmpty) {
        return 'Ingresa la URL del video de YouTube.';
      }
      if (!_isYouTubeValid) {
        return 'Usa una URL valida de YouTube (youtube.com o youtu.be).';
      }
    }
    return null;
  }

  bool get _canSave {
    if (_saving || _isCancelledTraining) return false;
    if (_title.text.trim().isEmpty) return false;
    if (_desc.text.trim().isEmpty) return false;
    if (_topic.text.trim().isEmpty) return false;

    if (_type == TrainingType.scheduled.name) {
      if (!_isRangeValid) return false;
      if (_mode == 'presencial' && _place.text.trim().isEmpty) return false;
      if (_mode == 'virtual' && _meetUrl.text.trim().isEmpty) return false;
      if (_mode == 'virtual' && !_isMeetingUrlValid) return false;
      return true;
    }

    if (_type == TrainingType.video.name) {
      return _isYouTubeValid;
    }
    return false;
  }

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String label,
    String? hint,
  }) {
    final scheme = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color color) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: color, width: 0.9),
      );
    }

    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: scheme.surface.withValues(alpha: 0.55),
      enabledBorder: border(scheme.outlineVariant.withValues(alpha: 0.65)),
      focusedBorder: border(scheme.primary.withValues(alpha: 0.8)),
      errorBorder: border(scheme.error.withValues(alpha: 0.8)),
      focusedErrorBorder: border(scheme.error),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 36,
                width: 36,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _space() => const SizedBox(height: _fieldGap);

  Widget _buildHeaderCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.10),
            scheme.tertiary.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nueva capacitaciÃ³n',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Configura una capacitaciÃ³n SST para tu instituciÃ³n',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildRsvpRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.65),
          width: 0.9,
        ),
      ),
      child: Row(
        children: [
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.people_alt_outlined, color: scheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Requiere confirmacion',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Los usuarios deberan confirmar asistencia',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _requireRsvp,
            onChanged: (value) => setState(() => _requireRsvp = value),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final data = widget.editData;
    if (data != null) {
      _type = (data['type'] ?? _type).toString();
      final rawStatus = (data['status'] ?? _status).toString();
      if (rawStatus == TrainingStatus.cancelled.name) {
        _status = TrainingStatus.cancelled.name;
        _isCancelledTraining = true;
      } else {
        _status = TrainingStatus.published.name;
      }
      _title.text = (data['title'] ?? '').toString();
      _desc.text = (data['description'] ?? '').toString();
      _topic.text = (data['topic'] ?? '').toString();
      final scheduled = (data['scheduled'] as Map<String, dynamic>?) ?? {};
      final video = (data['video'] as Map<String, dynamic>?) ?? {};
      final s = scheduled['startAt'] as Timestamp?;
      final e = scheduled['endAt'] as Timestamp?;
      if (s != null) _startAt = s.toDate();
      if (e != null) _endAt = e.toDate();
      _mode = (scheduled['mode'] ?? _mode).toString();
      _place.text = (scheduled['place'] ?? '').toString();
      _meetUrl.text = (scheduled['meetUrl'] ?? '').toString();
      final cap = scheduled['capacity'];
      if (cap is int) _capacity.text = cap.toString();
      _requireRsvp = scheduled['requireRsvp'] == true;
      _youtubeUrl.text = (video['youtubeUrl'] ?? '').toString();
      final dur = video['durationMinutes'];
      if (dur is int) _duration.text = dur.toString();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _topic.dispose();
    _place.dispose();
    _meetUrl.dispose();
    _youtubeUrl.dispose();
    _capacity.dispose();
    _duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva capacitaciÃ³n')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: _autoValidate
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              20 + MediaQuery.of(context).viewInsets.bottom,
            ),
            children: [
              _buildHeaderCard(context),
              const SizedBox(height: _sectionGap),
              _buildSection(
                context,
                title: 'Informacion basica',
                subtitle: 'Define los datos generales de la capacitaciÃ³n.',
                icon: Icons.assignment_outlined,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: _fieldDecoration(context, label: 'Tipo *'),
                    items: const [
                      DropdownMenuItem(
                        value: 'scheduled',
                        child: Text('Programada'),
                      ),
                      DropdownMenuItem(value: 'video', child: Text('Video')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _type = value);
                    },
                  ),
                  _space(),
                  TextFormField(
                    controller: _title,
                    onChanged: (_) => setState(() {}),
                    decoration: _fieldDecoration(context, label: 'Titulo *'),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'El titulo es obligatorio.'
                        : null,
                  ),
                  _space(),
                  TextFormField(
                    controller: _desc,
                    maxLines: 3,
                    onChanged: (_) => setState(() {}),
                    decoration: _fieldDecoration(
                      context,
                      label: 'Descripcion *',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'La descripcion es obligatoria.'
                        : null,
                  ),
                  _space(),
                  TextFormField(
                    controller: _topic,
                    onChanged: (_) => setState(() {}),
                    decoration: _fieldDecoration(context, label: 'Tema *'),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'El tema es obligatorio.'
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: _sectionGap),
              if (_type == TrainingType.video.name)
                _buildSection(
                  context,
                  title: 'Contenido',
                  subtitle:
                      'Relaciona el recurso de aprendizaje para usuarios.',
                  icon: Icons.ondemand_video_outlined,
                  children: [
                    TextFormField(
                      controller: _youtubeUrl,
                      onChanged: (_) => setState(() {}),
                      decoration: _fieldDecoration(
                        context,
                        label: 'URL YouTube *',
                        hint: 'https://youtube.com/watch?v=...',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'La URL de YouTube es obligatoria.';
                        }
                        if (!_isYouTubeValid) {
                          return 'Ingresa un enlace valido de YouTube.';
                        }
                        return null;
                      },
                    ),
                    _space(),
                    TextFormField(
                      controller: _duration,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: _fieldDecoration(
                        context,
                        label: 'Duracion en minutos (opcional)',
                      ),
                    ),
                  ],
                )
              else
                _buildSection(
                  context,
                  title: 'Programacion',
                  subtitle: 'Configura fecha, modalidad y logistica.',
                  icon: Icons.event_available_outlined,
                  children: [
                    _DateTimeField(
                      label: 'Inicio *',
                      value: _startAt,
                      onChanged: (value) => setState(() => _startAt = value),
                    ),
                    _space(),
                    _DateTimeField(
                      label: 'Fin *',
                      value: _endAt,
                      minDateTime: _startAt,
                      minErrorMessage:
                          'La fecha/hora de fin debe ser posterior al inicio.',
                      onChanged: (value) => setState(() => _endAt = value),
                    ),
                    if (!_isRangeValid)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'La fecha y hora de fin debe ser posterior al inicio.',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: scheme.error),
                        ),
                      ),
                    _space(),
                    DropdownButtonFormField<String>(
                      initialValue: _mode,
                      decoration: _fieldDecoration(
                        context,
                        label: 'Modalidad *',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'presencial',
                          child: Text('Presencial'),
                        ),
                        DropdownMenuItem(
                          value: 'virtual',
                          child: Text('Virtual'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _mode = value);
                      },
                    ),
                    _space(),
                    if (_mode == 'presencial')
                      TextFormField(
                        controller: _place,
                        onChanged: (_) => setState(() {}),
                        decoration: _fieldDecoration(context, label: 'Lugar *'),
                        validator: (v) {
                          if (_mode == 'presencial' &&
                              (v == null || v.trim().isEmpty)) {
                            return 'El lugar es obligatorio en modalidad presencial.';
                          }
                          return null;
                        },
                      ),
                    if (_mode == 'virtual')
                      TextFormField(
                        controller: _meetUrl,
                        onChanged: (_) => setState(() {}),
                        decoration: _fieldDecoration(
                          context,
                          label: 'Enlace de reuniÃ³n *',
                          hint:
                              'https://meet.google.com/... o enlace de Zoom/Teams',
                        ),
                        validator: (v) {
                          if (_mode == 'virtual' &&
                              (v == null || v.trim().isEmpty)) {
                            return 'La URL de reuniÃ³n es obligatoria en modalidad virtual.';
                          }
                          if (_mode == 'virtual' &&
                              v != null &&
                              v.trim().isNotEmpty &&
                              !_isMeetingUrlValid) {
                            return 'Usa un enlace vÃ¡lido de reuniÃ³n (Meet, Zoom, Teams, Webex o Jitsi).';
                          }
                          return null;
                        },
                      ),
                    if (_mode == 'virtual') ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed:
                              (_meetUrl.text.trim().isEmpty ||
                                  !_isMeetingUrlValid)
                              ? null
                              : _openMeetingPreviewLink,
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: const Text('Abrir enlace'),
                        ),
                      ),
                    ],
                    _space(),
                    TextFormField(
                      controller: _capacity,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: _fieldDecoration(
                        context,
                        label: 'Capacidad (opcional)',
                      ),
                    ),
                    _space(),
                    _buildRsvpRow(context),
                  ],
                ),
              const SizedBox(height: _sectionGap),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  onPressed: (_saving || _cancelling || _isCancelledTraining)
                      ? null
                      : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(),
                        )
                      : const Text('Guardar capacitaciÃ³n'),
                ),
              ),
              if (_isEditing && !_isCancelledTraining) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      side: BorderSide(
                        color: scheme.error.withValues(alpha: 0.7),
                      ),
                      foregroundColor: scheme.error,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _cancelling ? null : _cancelTraining,
                    icon: _cancelling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cancel_outlined),
                    label: const Text('Cancelar capacitaciÃ³n'),
                  ),
                ),
              ],
              if (!_canSave && !_saving)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _disabledMessage ??
                        'Completa los campos obligatorios para habilitar el guardado.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      setState(() => _autoValidate = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa los campos obligatorios')),
      );
      return;
    }
    if (_type == TrainingType.scheduled.name && !_isRangeValid) {
      setState(() => _autoValidate = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La fecha/hora de fin debe ser mayor al inicio.'),
        ),
      );
      return;
    }
    if (!_canSave) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _disabledMessage ??
                'Completa los campos obligatorios para guardar.',
          ),
        ),
      );
      return;
    }

    final adminContext = await _resolveAdminContext();
    if (adminContext == null) return;

    setState(() => _saving = true);
    try {
      final String saveStatus = _isCancelledTraining
          ? TrainingStatus.cancelled.name
          : TrainingStatus.published.name;
      final Map<String, dynamic> base = {
        'type': _type,
        'title': _title.text.trim(),
        'description': _desc.text.trim(),
        'topic': _topic.text.trim(),
        'status': saveStatus,
      };
      final previousStatus =
          (widget.editData?['status'] ?? TrainingStatus.published.name)
              .toString();
      final existingPublishedAt = widget.editData?['publishedAt'];
      if (saveStatus == TrainingStatus.published.name &&
          previousStatus != TrainingStatus.published.name &&
          existingPublishedAt == null) {
        base['publishedAt'] = FieldValue.serverTimestamp();
      }
      if (_type == TrainingType.scheduled.name) {
        base['scheduled'] = ScheduledTrainingData(
          startAt: Timestamp.fromDate(_startAt),
          endAt: Timestamp.fromDate(_endAt),
          mode: _mode,
          place: _mode == 'presencial' ? _place.text.trim() : null,
          meetUrl: _mode == 'virtual' ? _meetUrl.text.trim() : null,
          capacity: int.tryParse(_capacity.text.trim()),
          requireRsvp: _requireRsvp,
        ).toMap();
      } else {
        base['video'] = VideoTrainingData(
          youtubeUrl: _youtubeUrl.text.trim(),
          durationMinutes: int.tryParse(_duration.text.trim()),
        ).toMap();
      }
      _logTrainingAttempt(
        operation: widget.editId == null ? 'create' : 'update',
        userUid: adminContext.user.uid,
        role: adminContext.role,
        institutionId: adminContext.institutionId,
        route:
            'institutions/${adminContext.institutionId}/trainings${widget.editId == null ? '' : '/${widget.editId}'}',
        payload: base,
      );

      if (widget.editId == null) {
        // createdBy lo aÃ±ade el servicio con el uid autenticado.
        final model = TrainingModuleModel(
          type: _type,
          title: _title.text.trim(),
          description: _desc.text.trim(),
          topic: _topic.text.trim(),
          createdBy: '',
          status: saveStatus,
          publishedAt: saveStatus == TrainingStatus.published.name
              ? FieldValue.serverTimestamp()
              : null,
          scheduled: _type == TrainingType.scheduled.name
              ? ScheduledTrainingData(
                  startAt: Timestamp.fromDate(_startAt),
                  endAt: Timestamp.fromDate(_endAt),
                  mode: _mode,
                  place: _mode == 'presencial' ? _place.text.trim() : null,
                  meetUrl: _mode == 'virtual' ? _meetUrl.text.trim() : null,
                  capacity: int.tryParse(_capacity.text.trim()),
                  requireRsvp: _requireRsvp,
                )
              : null,
          video: _type == TrainingType.video.name
              ? VideoTrainingData(
                  youtubeUrl: _youtubeUrl.text.trim(),
                  durationMinutes: int.tryParse(_duration.text.trim()),
                )
              : null,
        );
        await widget.service.createInstitutionTraining(model);
      } else {
        await widget.service.updateInstitutionTraining(widget.editId!, base);
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Capacitacion publicada. Ya es visible para usuarios de la institucion.',
          ),
        ),
      );
    } on FirebaseException catch (e, st) {
      debugPrint(
        'Error Firebase guardando capacitaciÃ³n: ${e.code} ${e.message}',
      );
      debugPrint(st.toString());
      if (!mounted) return;
      final code = e.code.toUpperCase();
      final message = e.message ?? 'Error de Firebase.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar ($code): $message')),
      );
    } catch (e, st) {
      debugPrint('Error guardando capacitaciÃ³n: $e');
      debugPrint(st.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelTraining() async {
    if (widget.editId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancelar capacitaciÃ³n'),
          content: const Text(
            'Esta acciÃ³n marcarÃ¡ la capacitaciÃ³n como cancelada y notificarÃ¡ a usuarios.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Si, cancelar'),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;

    final adminContext = await _resolveAdminContext();
    if (adminContext == null) return;

    setState(() => _cancelling = true);
    try {
      final payload = <String, dynamic>{
        'status': TrainingStatus.cancelled.name,
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': adminContext.user.uid,
      };
      _logTrainingAttempt(
        operation: 'cancel',
        userUid: adminContext.user.uid,
        role: adminContext.role,
        institutionId: adminContext.institutionId,
        route:
            'institutions/${adminContext.institutionId}/trainings/${widget.editId}',
        payload: payload,
      );
      await widget.service.updateInstitutionTraining(widget.editId!, payload);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Capacitacion cancelada.')));
    } on FirebaseException catch (e, st) {
      debugPrint(
        'Error Firebase cancelando capacitaciÃ³n: ${e.code} ${e.message}',
      );
      debugPrint(st.toString());
      if (!mounted) return;
      final code = e.code.toUpperCase();
      final message = e.message ?? 'Error de Firebase.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar ($code): $message')),
      );
    } catch (e, st) {
      debugPrint('Error cancelando capacitaciÃ³n: $e');
      debugPrint(st.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo cancelar: $e')));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<_TrainingAdminContext?> _resolveAdminContext() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No hay sesion activa.')));
      }
      return null;
    }

    final role = (await _userService.getUserRole(user.uid)) ?? '';
    final institutionId =
        (await _userService.getUserInstitutionId(user.uid)) ?? '';

    if (institutionId.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontro institutionId para este usuario.'),
          ),
        );
      }
      return null;
    }

    if (role != 'admin_sst' && role != 'admin') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Rol "$role" sin permisos para guardar capacitaciones.',
            ),
          ),
        );
      }
      return null;
    }

    return _TrainingAdminContext(
      user: user,
      role: role,
      institutionId: institutionId,
    );
  }

  void _logTrainingAttempt({
    required String operation,
    required String userUid,
    required String role,
    required String institutionId,
    required String route,
    required Map<String, dynamic> payload,
  }) {
    debugPrint('[Training][$operation] currentUser.uid: $userUid');
    debugPrint('[Training][$operation] currentUser.role: $role');
    debugPrint('[Training][$operation] institutionId: $institutionId');
    debugPrint('[Training][$operation] firestorePath: $route');
    debugPrint('[Training][$operation] payload: $payload');
    debugPrint(
      '[Training][$operation] firestoreCollection: institutions/$institutionId/trainings',
    );
  }
}

class _TrainingAdminContext {
  final User user;
  final String role;
  final String institutionId;

  const _TrainingAdminContext({
    required this.user,
    required this.role,
    required this.institutionId,
  });
}

class _ScheduledStatsPanel extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> trainingRef;
  const _ScheduledStatsPanel({required this.trainingRef});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: trainingRef.collection('responses').snapshots(),
      builder: (context, responseSnap) {
        final responseDocs = responseSnap.data?.docs ?? const [];
        final counts = _ResponseCounts.fromDocs(responseDocs);
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: trainingRef.collection('attendance').snapshots(),
          builder: (context, attendanceSnap) {
            final attendanceDocs = attendanceSnap.data?.docs ?? const [];
            final attendedCount = attendanceDocs
                .where((d) => d.data()['attended'] == true)
                .length;
            final hasLoading =
                responseSnap.connectionState == ConnectionState.waiting ||
                attendanceSnap.connectionState == ConnectionState.waiting;

            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
              child: hasLoading
                  ? Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Cargando resumen...',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Confirmados: ${counts.yes}   No pueden: ${counts.no}   Quizas: ${counts.maybe}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Asistieron: $attendedCount / Confirmados: ${counts.yes}',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }
}

class _ResponseCounts {
  final int yes;
  final int no;
  final int maybe;

  const _ResponseCounts({
    required this.yes,
    required this.no,
    required this.maybe,
  });

  factory _ResponseCounts.fromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var yes = 0;
    var no = 0;
    var maybe = 0;
    for (final doc in docs) {
      final value = (doc.data()['response'] ?? '').toString();
      if (value == 'yes') yes++;
      if (value == 'no') no++;
      if (value == 'maybe') maybe++;
    }
    return _ResponseCounts(yes: yes, no: no, maybe: maybe);
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late final Color color;
    late final String label;
    switch (status) {
      case 'published':
        color = Colors.green;
        label = 'Publicado';
        break;
      case 'cancelled':
        color = scheme.error;
        label = 'Cancelado';
        break;
      default:
        color = scheme.outline;
        label = 'Borrador';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TinyBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _TinyBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ResponsesSheet extends StatefulWidget {
  final String trainingId;
  final String institutionId;
  const _ResponsesSheet({
    required this.trainingId,
    required this.institutionId,
  });

  @override
  State<_ResponsesSheet> createState() => _ResponsesSheetState();
}

class _ResponsesSheetState extends State<_ResponsesSheet> {
  late final DocumentReference<Map<String, dynamic>> _trainingRef;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _responsesStream;
  Future<Map<String, _AttendanceUserInfo>>? _userInfoFuture;
  Set<String> _userInfoIds = <String>{};

  @override
  void initState() {
    super.initState();
    _trainingRef = FirebaseFirestore.instance
        .collection('institutions')
        .doc(widget.institutionId)
        .collection('trainings')
        .doc(widget.trainingId);
    _responsesStream = _trainingRef.collection('responses').snapshots();
  }

  Future<Map<String, _AttendanceUserInfo>> _getUserInfoFuture(
    List<String> userIds,
  ) {
    final next = userIds.toSet();
    if (_userInfoFuture == null || !_sameIds(_userInfoIds, next)) {
      _userInfoIds = next;
      _userInfoFuture = _loadUserInfo(userIds);
    }
    return _userInfoFuture!;
  }

  bool _sameIds(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final id in a) {
      if (!b.contains(id)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _responsesStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'No se pudieron cargar las confirmaciones.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }
            final docs =
                List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                  snapshot.data?.docs ?? const [],
                )..sort((a, b) {
                  final aTs = a.data()['respondedAt'] as Timestamp?;
                  final bTs = b.data()['respondedAt'] as Timestamp?;
                  final aDate =
                      aTs?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
                  final bDate =
                      bTs?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
                  return bDate.compareTo(aDate);
                });
            if (docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_outline,
                      color: scheme.onSurfaceVariant,
                      size: 42,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Aun no hay confirmaciones',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Las respuestas de los usuarios apareceran aqui.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }

            final userIds = docs
                .map((doc) => (doc.data()['userId'] ?? '').toString())
                .where((id) => id.trim().isNotEmpty)
                .toSet()
                .toList();

            return FutureBuilder<Map<String, _AttendanceUserInfo>>(
              future: _getUserInfoFuture(userIds),
              builder: (context, userSnap) {
                final usersMap = userSnap.data ?? {};
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Confirmaciones',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Listado de respuestas de asistencia.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (userSnap.hasError) ...[
                      const SizedBox(height: 6),
                      Text(
                        'No se pudieron cargar todos los perfiles. Mostrando datos basicos.',
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: scheme.error),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, index) {
                          final data = docs[index].data();
                          final userId = (data['userId'] ?? '').toString();
                          final user = usersMap[userId];
                          final fallbackName = (data['userName'] ?? '')
                              .toString()
                              .trim();
                          final fallbackEmail = (data['userEmail'] ?? '')
                              .toString()
                              .trim();
                          final comment = (data['comment'] ?? '')
                              .toString()
                              .trim();
                          final respondedAt = data['respondedAt'] as Timestamp?;
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.surface.withValues(alpha: 0.58),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.55,
                                ),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: scheme.primary.withValues(
                                    alpha: 0.14,
                                  ),
                                  child: Text(
                                    _initials(user?.name, user?.email),
                                    style: TextStyle(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user?.name.isNotEmpty == true
                                            ? user!.name
                                            : fallbackName.isNotEmpty
                                            ? fallbackName
                                            : 'Usuario',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        user?.email.isNotEmpty == true
                                            ? user!.email
                                            : fallbackEmail.isNotEmpty
                                            ? fallbackEmail
                                            : userId,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      _ResponsePill(
                                        label: _labelResponse(
                                          (data['response'] ?? '').toString(),
                                        ),
                                      ),
                                      if (respondedAt != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Respondio: ${DateFormat('dd/MM/yyyy hh:mm a').format(respondedAt.toDate())}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                      if (comment.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          comment,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<Map<String, _AttendanceUserInfo>> _loadUserInfo(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return {};
    final result = <String, _AttendanceUserInfo>{};
    const chunkSize = 10;
    final chunks = <List<String>>[];
    for (int i = 0; i < userIds.length; i += chunkSize) {
      chunks.add(
        userIds.sublist(
          i,
          i + chunkSize > userIds.length ? userIds.length : i + chunkSize,
        ),
      );
    }
    final snapshots = await Future.wait(
      chunks.map((chunk) async {
        try {
          return await FirebaseFirestore.instance
              .collection('users')
              .where(FieldPath.documentId, whereIn: chunk)
              .get()
              .timeout(const Duration(seconds: 8));
        } on TimeoutException {
          return null;
        } on FirebaseException {
          return null;
        } catch (_) {
          return null;
        }
      }),
    );
    for (final snap
        in snapshots.whereType<QuerySnapshot<Map<String, dynamic>>>()) {
      for (final doc in snap.docs) {
        final data = doc.data();
        result[doc.id] = _AttendanceUserInfo(
          name: (data['displayName'] ?? '').toString().trim(),
          email: (data['email'] ?? '').toString().trim(),
        );
      }
    }
    return result;
  }

  String _initials(String? name, String? email) {
    final cleanName = (name ?? '').trim();
    if (cleanName.isNotEmpty) {
      return cleanName
          .split(' ')
          .where((e) => e.trim().isNotEmpty)
          .take(2)
          .map((e) => e[0].toUpperCase())
          .join();
    }
    final cleanEmail = (email ?? '').trim();
    if (cleanEmail.isNotEmpty) {
      return cleanEmail.substring(0, 1).toUpperCase();
    }
    return 'U';
  }

  String _labelResponse(String value) {
    switch (value) {
      case 'yes':
        return 'Asistir';
      case 'no':
        return 'No puede';
      case 'maybe':
        return 'Quizas';
      default:
        return value.isEmpty ? 'Sin respuesta' : value;
    }
  }
}

class _ResponsePill extends StatelessWidget {
  final String label;
  const _ResponsePill({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color color = scheme.outline;
    if (label == 'Asistir') color = Colors.green;
    if (label == 'No puede') color = scheme.error;
    if (label == 'Quizas') color = Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.36)),
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

class _AttendanceSheet extends StatefulWidget {
  final String trainingId;
  final String institutionId;
  const _AttendanceSheet({
    required this.trainingId,
    required this.institutionId,
  });

  @override
  State<_AttendanceSheet> createState() => _AttendanceSheetState();
}

class _AttendanceSheetState extends State<_AttendanceSheet> {
  final Map<String, bool> _pendingChanges = {};
  final Set<String> _savingUsers = {};
  Future<Map<String, _AttendanceUserInfo>>? _userInfoFuture;
  Set<String> _userInfoIds = <String>{};
  late final DocumentReference<Map<String, dynamic>> _trainingRef;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _responsesStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _attendanceStream;

  @override
  void initState() {
    super.initState();
    _trainingRef = FirebaseFirestore.instance
        .collection('institutions')
        .doc(widget.institutionId)
        .collection('trainings')
        .doc(widget.trainingId);
    _responsesStream = _trainingRef.collection('responses').snapshots();
    _attendanceStream = _trainingRef.collection('attendance').snapshots();
  }

  Future<Map<String, _AttendanceUserInfo>> _getUserInfoFuture(
    List<String> userIds,
  ) {
    final next = userIds.toSet();
    if (_userInfoFuture == null || !_sameIds(_userInfoIds, next)) {
      _userInfoIds = next;
      _userInfoFuture = _loadUserInfo(userIds);
    }
    return _userInfoFuture!;
  }

  bool _sameIds(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final id in a) {
      if (!b.contains(id)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _trainingRef.snapshots(),
        builder: (context, trainingSnap) {
          if (trainingSnap.connectionState == ConnectionState.waiting &&
              !trainingSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (trainingSnap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'No se pudo cargar el detalle de la capacitacion.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }
          final trainingStatus = (trainingSnap.data?.data()?['status'] ?? '')
              .toString();
          final isCancelled = trainingStatus == TrainingStatus.cancelled.name;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _responsesStream,
              builder: (context, responseSnap) {
                if (responseSnap.connectionState == ConnectionState.waiting &&
                    !responseSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (responseSnap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'No se pudieron cargar las confirmaciones.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }
                final responseDocs =
                    List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                      responseSnap.data?.docs ?? const [],
                    )..sort((a, b) {
                      final aTs = a.data()['respondedAt'] as Timestamp?;
                      final bTs = b.data()['respondedAt'] as Timestamp?;
                      final aDate =
                          aTs?.toDate() ??
                          DateTime.fromMillisecondsSinceEpoch(0);
                      final bDate =
                          bTs?.toDate() ??
                          DateTime.fromMillisecondsSinceEpoch(0);
                      return bDate.compareTo(aDate);
                    });
                if (responseDocs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.group_outlined,
                          color: scheme.onSurfaceVariant,
                          size: 44,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'AÃºn no hay confirmaciones',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Cuando los usuarios respondan, podras marcar asistencia aqui.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }

                final userIds = responseDocs
                    .map((e) => (e.data()['userId'] ?? '').toString())
                    .where((id) => id.trim().isNotEmpty)
                    .toSet()
                    .toList();

                return FutureBuilder<Map<String, _AttendanceUserInfo>>(
                  future: _getUserInfoFuture(userIds),
                  builder: (context, userSnap) {
                    final usersMap = userSnap.data ?? {};

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _attendanceStream,
                      builder: (context, attendanceSnap) {
                        final attendanceLoading =
                            attendanceSnap.connectionState ==
                                ConnectionState.waiting &&
                            !attendanceSnap.hasData;
                        final attendanceError = attendanceSnap.hasError;
                        final attendanceDocs = attendanceSnap.data?.docs ?? [];
                        final attendanceMap = <String, bool>{};
                        for (final doc in attendanceDocs) {
                          final map = doc.data();
                          attendanceMap[doc.id] = map['attended'] == true;
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Asistencia',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (attendanceLoading) ...[
                              const SizedBox(height: 6),
                              const LinearProgressIndicator(minHeight: 2),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              'Marca si cada usuario asistio o no asistio.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            if (attendanceError) ...[
                              const SizedBox(height: 6),
                              Text(
                                'No se pudo cargar asistencia previa. Puedes registrar asistencia nuevamente.',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: scheme.error),
                              ),
                            ],
                            if (userSnap.hasError) ...[
                              const SizedBox(height: 6),
                              Text(
                                'No se pudieron cargar todos los perfiles. Mostrando datos basicos.',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: scheme.error),
                              ),
                            ],
                            if (isCancelled) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Capacitacion cancelada: la asistencia esta bloqueada.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.error),
                              ),
                            ],
                            const SizedBox(height: 14),
                            Expanded(
                              child: ListView.separated(
                                itemCount: responseDocs.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (_, index) {
                                  final responseData = responseDocs[index]
                                      .data();
                                  final userId = (responseData['userId'] ?? '')
                                      .toString();
                                  final fallbackName =
                                      (responseData['userName'] ?? '')
                                          .toString()
                                          .trim();
                                  final fallbackEmail =
                                      (responseData['userEmail'] ?? '')
                                          .toString()
                                          .trim();
                                  final response =
                                      (responseData['response'] ?? '')
                                          .toString();
                                  final userInfo = usersMap[userId];
                                  final currentValue =
                                      _pendingChanges[userId] ??
                                      attendanceMap[userId] ??
                                      false;
                                  final isSaving = _savingUsers.contains(
                                    userId,
                                  );

                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: scheme.surface.withValues(
                                        alpha: 0.62,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: scheme.outlineVariant.withValues(
                                          alpha: 0.55,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor: scheme.primary
                                              .withValues(alpha: 0.14),
                                          child: Text(
                                            _initials(
                                              userInfo?.name,
                                              userInfo?.email,
                                            ),
                                            style: TextStyle(
                                              color: scheme.primary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                userInfo?.name.isNotEmpty ==
                                                        true
                                                    ? userInfo!.name
                                                    : fallbackName.isNotEmpty
                                                    ? fallbackName
                                                    : 'Usuario',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                userInfo?.email.isNotEmpty ==
                                                        true
                                                    ? userInfo!.email
                                                    : fallbackEmail.isNotEmpty
                                                    ? fallbackEmail
                                                    : userId,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                'Confirmacion: ${_labelResponse(response)}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              currentValue
                                                  ? 'Asistio'
                                                  : 'No asistio',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelMedium
                                                  ?.copyWith(
                                                    color: currentValue
                                                        ? Colors.green
                                                        : scheme.error,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            isSaving
                                                ? const Padding(
                                                    padding: EdgeInsets.only(
                                                      top: 6,
                                                    ),
                                                    child: SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                    ),
                                                  )
                                                : Switch(
                                                    value: currentValue,
                                                    onChanged: isCancelled
                                                        ? null
                                                        : (value) =>
                                                              _setAttendance(
                                                                userId: userId,
                                                                attended: value,
                                                              ),
                                                  ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<Map<String, _AttendanceUserInfo>> _loadUserInfo(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return {};
    final result = <String, _AttendanceUserInfo>{};
    const chunkSize = 10;
    for (int i = 0; i < userIds.length; i += chunkSize) {
      final chunk = userIds.sublist(
        i,
        i + chunkSize > userIds.length ? userIds.length : i + chunkSize,
      );
      QuerySnapshot<Map<String, dynamic>>? snap;
      try {
        snap = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get()
            .timeout(const Duration(seconds: 10));
      } on TimeoutException {
        continue;
      } on FirebaseException {
        continue;
      } catch (_) {
        continue;
      }
      if (snap.docs.isEmpty) continue;
      for (final doc in snap.docs) {
        final data = doc.data();
        result[doc.id] = _AttendanceUserInfo(
          name: (data['displayName'] ?? '').toString().trim(),
          email: (data['email'] ?? '').toString().trim(),
        );
      }
    }
    return result;
  }

  Future<void> _setAttendance({
    required String userId,
    required bool attended,
  }) async {
    if (userId.trim().isEmpty) return;
    final previousValue = _pendingChanges[userId];
    bool success = false;
    setState(() {
      _pendingChanges[userId] = attended;
      _savingUsers.add(userId);
    });
    try {
      final admin = FirebaseAuth.instance.currentUser;
      if (admin == null) {
        throw FirebaseException(
          plugin: 'firebase_auth',
          code: 'unauthenticated',
          message: 'No hay sesion activa.',
        );
      }
      await _trainingRef
          .collection('attendance')
          .doc(userId)
          .set({
            'userId': userId,
            'attended': attended,
            'markedAt': FieldValue.serverTimestamp(),
            'markedBy': admin.uid,
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 15));
      success = true;
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La operacion tardo demasiado. Revisa tu conexion e intenta de nuevo.',
          ),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final code = e.code.toUpperCase();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo guardar asistencia ($code): ${e.message ?? ''}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar asistencia: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          if (!success) {
            if (previousValue == null) {
              _pendingChanges.remove(userId);
            } else {
              _pendingChanges[userId] = previousValue;
            }
          }
          _savingUsers.remove(userId);
        });
      }
    }
  }

  String _initials(String? name, String? email) {
    final cleanName = (name ?? '').trim();
    if (cleanName.isNotEmpty) {
      return cleanName
          .split(' ')
          .where((e) => e.trim().isNotEmpty)
          .take(2)
          .map((e) => e[0].toUpperCase())
          .join();
    }
    final cleanEmail = (email ?? '').trim();
    if (cleanEmail.isNotEmpty) {
      return cleanEmail.substring(0, 1).toUpperCase();
    }
    return 'U';
  }

  String _labelResponse(String value) {
    switch (value) {
      case 'yes':
        return 'Asistir';
      case 'no':
        return 'No puede';
      case 'maybe':
        return 'Quizas';
      default:
        return value.isEmpty ? 'Sin respuesta' : value;
    }
  }
}

class _AttendanceUserInfo {
  final String name;
  final String email;

  const _AttendanceUserInfo({required this.name, required this.email});
}

class _DateTimeField extends StatelessWidget {
  final String label;
  final DateTime value;
  final DateTime? minDateTime;
  final String? minErrorMessage;
  final ValueChanged<DateTime> onChanged;
  const _DateTimeField({
    required this.label,
    required this.value,
    this.minDateTime,
    this.minErrorMessage,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
        );
        if (date == null || !context.mounted) return;
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(value),
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(alwaysUse24HourFormat: false),
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
        if (time == null) return;
        final selected = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
        if (minDateTime != null && !selected.isAfter(minDateTime!)) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                minErrorMessage ??
                    'La fecha/hora seleccionada debe ser posterior.',
              ),
            ),
          );
          return;
        }
        onChanged(selected);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.65),
            width: 0.9,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('dd/MM/yyyy hh:mm a').format(value),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              height: 34,
              width: 34,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.edit_calendar_outlined,
                color: scheme.primary,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
