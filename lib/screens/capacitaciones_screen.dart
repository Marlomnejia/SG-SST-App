import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/training_service.dart';
import '../services/user_service.dart';
import '../widgets/app_skeleton_box.dart';
import '../widgets/app_meta_chip.dart';

class CapacitacionesScreen extends StatefulWidget {
  const CapacitacionesScreen({super.key});

  @override
  State<CapacitacionesScreen> createState() => _CapacitacionesScreenState();
}

class _CapacitacionesScreenState extends State<CapacitacionesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TrainingService _service = TrainingService();
  final UserService _userService = UserService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _publishedTrainingsStream;
  bool _ready = false;
  String? _loadError;
  String? _institutionId;
  String? _currentUid;
  bool _showCompletedVideos = false;
  String _scheduledFilter = 'active';
  final Set<String> _savingRsvpTrainingIds = <String>{};
  final Set<String> _submittedRsvpTrainingIds = <String>{};
  final Map<String, String> _localRsvpSelection = <String, String>{};
  static final Map<String, _VideoProgressMetrics> _videoMetricsMemoryCache =
      <String, _VideoProgressMetrics>{};
  static final Map<String, Map<String, _VideoProgressState>>
  _videoProgressMemoryCache = <String, Map<String, _VideoProgressState>>{};
  static final Map<String, Future<_VideoProgressMetrics>>
  _videoMetricsFutureCache = <String, Future<_VideoProgressMetrics>>{};
  static final Map<String, Future<Map<String, _VideoProgressState>>>
  _videoProgressFutureCache =
      <String, Future<Map<String, _VideoProgressState>>>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _bootstrap();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _ready = false;
      _loadError = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No hay sesion activa.');
      }
      final institutionId = await _userService.getUserInstitutionId(user.uid);
      if (institutionId == null || institutionId.trim().isEmpty) {
        throw Exception('Usuario sin institucion asignada.');
      }
      if (!mounted) return;
      setState(() {
        _currentUid = user.uid;
        _institutionId = institutionId;
        _publishedTrainingsStream = _firestore
            .collection('institutions')
            .doc(institutionId)
            .collection('trainings')
            .where('status', isEqualTo: 'published')
            .snapshots()
            .asBroadcastStream();
        _ready = true;
      });
      if (kDebugMode) {
        debugPrint(
          '[Trainings][bootstrap] uid=${user.uid} institutionId=$institutionId',
        );
        debugPrint(
          '[Trainings][bootstrap] queryPath=institutions/$institutionId/trainings status=published',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _ready = false;
      });
    }
  }

  void _retryStreams() {
    _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Capacitaciones')),
        body: _buildErrorState(
          context,
          title: 'No se pudieron cargar las capacitaciones',
          subtitle: 'Verifica tu conexion e intenta nuevamente.',
          onRetry: _retryStreams,
        ),
      );
    }
    if (!_ready) {
      return Scaffold(
        appBar: AppBar(title: const Text('Capacitaciones')),
        body: _buildTrainingsScreenSkeleton(),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Capacitaciones')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _publishedTrainingsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState(
              context,
              title: 'No se pudieron cargar las capacitaciones',
              subtitle: _friendlyStreamError(snapshot.error),
              onRetry: _retryStreams,
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildTrainingsScreenSkeleton();
          }
          final docs = snapshot.data?.docs ?? const [];
          final videoDocs =
              docs
                  .where(
                    (doc) => (doc.data()['type'] ?? '').toString() == 'video',
                  )
                  .toList()
                ..sort(_sortByCreatedAtDesc);

          final scheduledCount = docs
              .where(
                (doc) => (doc.data()['type'] ?? '').toString() == 'scheduled',
              )
              .length;
          if (kDebugMode) {
            debugPrint(
              '[Trainings][user] institutionId=$_institutionId uid=$_currentUid total=${docs.length} scheduled=$scheduledCount video=${videoDocs.length}',
            );
            if (docs.isEmpty) {
              debugPrint(
                '[Trainings][user] No hay resultados. Verifica institutionId y status=published en institutions/$_institutionId/trainings',
              );
            }
          }

          return Column(
            children: [
              FutureBuilder<_VideoProgressMetrics>(
                future: _getVideoProgressMetrics(videoDocs),
                builder: (context, progressSnap) {
                  final cacheKey = _videoCacheKey(videoDocs);
                  final cachedMetrics = _videoMetricsMemoryCache[cacheKey];
                  final metrics =
                      progressSnap.data ??
                      cachedMetrics ??
                      _VideoProgressMetrics(
                        watchedCount: 0,
                        totalCount: videoDocs.length,
                      );
                  return _VideoProgressSummary(
                    watchedCount: metrics.watchedCount,
                    totalCount: metrics.totalCount,
                    loading:
                        progressSnap.connectionState ==
                            ConnectionState.waiting &&
                        !progressSnap.hasData &&
                        cachedMetrics == null,
                  );
                },
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.22),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Proximas'),
                    Tab(text: 'En linea'),
                    Tab(text: 'Historial'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildUpcoming(docs),
                    _buildOnline(docs),
                    _buildHistory(docs),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  DocumentReference<Map<String, dynamic>>? _trainingRef(String trainingId) {
    final institutionId = _institutionId;
    if (institutionId == null || institutionId.trim().isEmpty) return null;
    return _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection('trainings')
        .doc(trainingId);
  }

  String _videoCacheKey(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> videoDocs,
  ) {
    final ids = videoDocs.map((doc) => doc.id).toList()..sort();
    return '${_institutionId ?? ''}|${_currentUid ?? ''}|${ids.join(',')}';
  }

  Future<_VideoProgressMetrics> _getVideoProgressMetrics(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> videoDocs,
  ) {
    final cacheKey = _videoCacheKey(videoDocs);
    final cached = _videoMetricsMemoryCache[cacheKey];
    if (cached != null) {
      return SynchronousFuture<_VideoProgressMetrics>(cached);
    }

    final pending = _videoMetricsFutureCache[cacheKey];
    if (pending != null) {
      return pending;
    }

    final future = _loadVideoProgressMetrics(videoDocs)
        .then((value) {
          _videoMetricsMemoryCache[cacheKey] = value;
          _videoMetricsFutureCache.remove(cacheKey);
          return value;
        })
        .catchError((error) {
          _videoMetricsFutureCache.remove(cacheKey);
          throw error;
        });
    _videoMetricsFutureCache[cacheKey] = future;
    return future;
  }

  Future<Map<String, _VideoProgressState>> _getVideoProgressState(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> videoDocs,
  ) {
    final cacheKey = _videoCacheKey(videoDocs);
    final cached = _videoProgressMemoryCache[cacheKey];
    if (cached != null) {
      return SynchronousFuture<Map<String, _VideoProgressState>>(cached);
    }

    final pending = _videoProgressFutureCache[cacheKey];
    if (pending != null) {
      return pending;
    }

    final future = _loadVideoProgressState(videoDocs)
        .then((value) {
          _videoProgressMemoryCache[cacheKey] = value;
          _videoProgressFutureCache.remove(cacheKey);
          return value;
        })
        .catchError((error) {
          _videoProgressFutureCache.remove(cacheKey);
          throw error;
        });
    _videoProgressFutureCache[cacheKey] = future;
    return future;
  }

  void _optimisticallyMarkVideoAsWatched(String trainingId) {
    final prefix = '${_institutionId ?? ''}|${_currentUid ?? ''}|';
    final now = Timestamp.now();
    final keys = _videoProgressMemoryCache.keys
        .where((key) => key.startsWith(prefix))
        .toList(growable: false);
    for (final key in keys) {
      final value = _videoProgressMemoryCache[key];
      if (value == null || !value.containsKey(trainingId)) continue;
      final updated = Map<String, _VideoProgressState>.from(value);
      updated[trainingId] = _VideoProgressState(watched: true, watchedAt: now);
      _videoProgressMemoryCache[key] = updated;
      final currentMetrics = _videoMetricsMemoryCache[key];
      if (currentMetrics != null) {
        final watchedCount = updated.values
            .where((entry) => entry.watched)
            .length;
        _videoMetricsMemoryCache[key] = _VideoProgressMetrics(
          watchedCount: watchedCount,
          totalCount: currentMetrics.totalCount,
        );
      }
    }
  }

  Future<_VideoProgressMetrics> _loadVideoProgressMetrics(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> videoDocs,
  ) async {
    final uid = _currentUid;
    if (uid == null || uid.trim().isEmpty) {
      return _VideoProgressMetrics(
        watchedCount: 0,
        totalCount: videoDocs.length,
      );
    }
    final futures = <Future<DocumentSnapshot<Map<String, dynamic>>>>[];
    for (final doc in videoDocs) {
      final ref = _trainingRef(doc.id);
      if (ref == null) continue;
      final progressRef = ref.collection('progress').doc(uid);
      if (kDebugMode) {
        debugPrint(
          '[Trainings][progress-summary-read] path=${progressRef.path} trainingId=${doc.id}',
        );
      }
      futures.add(progressRef.get());
    }
    final snapshots = await Future.wait(futures);
    final watchedCount = snapshots.where((snap) {
      final data = snap.data();
      return data != null && data['watched'] == true;
    }).length;
    if (kDebugMode) {
      debugPrint(
        '[Trainings][progress-summary] institutionId=$_institutionId uid=$uid watched=$watchedCount total=${videoDocs.length}',
      );
    }
    return _VideoProgressMetrics(
      watchedCount: watchedCount,
      totalCount: videoDocs.length,
    );
  }

  Future<Map<String, _VideoProgressState>> _loadVideoProgressState(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> videoDocs,
  ) async {
    final uid = _currentUid;
    if (uid == null || uid.trim().isEmpty) {
      return {for (final doc in videoDocs) doc.id: const _VideoProgressState()};
    }

    final entries = await Future.wait(
      videoDocs.map((doc) async {
        final ref = _trainingRef(doc.id);
        if (ref == null) {
          return MapEntry(doc.id, const _VideoProgressState());
        }
        final progressRef = ref.collection('progress').doc(uid);
        if (kDebugMode) {
          debugPrint(
            '[Trainings][progress-list-read] path=${progressRef.path} trainingId=${doc.id} uid=$uid',
          );
        }
        final snap = await progressRef.get();
        final data = snap.data();
        final watched = data?['watched'] == true;
        final watchedAt = data?['watchedAt'] as Timestamp?;
        return MapEntry(
          doc.id,
          _VideoProgressState(watched: watched, watchedAt: watchedAt),
        );
      }),
    );

    return {for (final entry in entries) entry.key: entry.value};
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _myRsvpStream(
    String trainingId,
  ) {
    final ref = _trainingRef(trainingId);
    final uid = _currentUid;
    if (ref == null || uid == null || uid.trim().isEmpty) {
      return const Stream.empty();
    }
    return ref.collection('responses').doc(uid).snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _myAttendanceStream(
    String trainingId,
  ) {
    final ref = _trainingRef(trainingId);
    final uid = _currentUid;
    if (ref == null || uid == null || uid.trim().isEmpty) {
      return const Stream.empty();
    }
    return ref.collection('attendance').doc(uid).snapshots();
  }

  Widget _buildUpcoming(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
  ) {
    final scheduledDocs =
        allDocs
            .where(
              (doc) => (doc.data()['type'] ?? '').toString() == 'scheduled',
            )
            .toList()
          ..sort(_sortScheduledForUser);

    if (scheduledDocs.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.event_busy_outlined,
        title: 'No hay capacitaciones programadas',
        subtitle: 'Cuando tu institucion publique una, aparecera aqui.',
      );
    }

    final now = DateTime.now();
    bool isPastTraining(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      final scheduled =
          (doc.data()['scheduled'] as Map<String, dynamic>?) ?? {};
      final endAt = scheduled['endAt'] as Timestamp?;
      if (endAt == null) return false;
      return endAt.toDate().isBefore(now);
    }

    final activeCount = scheduledDocs
        .where((doc) => !isPastTraining(doc))
        .length;
    final pastCount = scheduledDocs.where(isPastTraining).length;

    final docs = scheduledDocs.where((doc) {
      switch (_scheduledFilter) {
        case 'active':
          return !isPastTraining(doc);
        case 'past':
          return isPastTraining(doc);
        default:
          return true;
      }
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('Activas ($activeCount)'),
                  selected: _scheduledFilter == 'active',
                  onSelected: (_) =>
                      setState(() => _scheduledFilter = 'active'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text('Finalizadas ($pastCount)'),
                  selected: _scheduledFilter == 'past',
                  onSelected: (_) => setState(() => _scheduledFilter = 'past'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text('Todas (${scheduledDocs.length})'),
                  selected: _scheduledFilter == 'all',
                  onSelected: (_) => setState(() => _scheduledFilter = 'all'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: docs.isEmpty
              ? _buildEmptyState(
                  context,
                  icon: Icons.filter_alt_off_outlined,
                  title: 'Sin resultados para este filtro',
                  subtitle: 'Cambia el filtro para ver otras capacitaciones.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (_, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final scheduled =
                        (data['scheduled'] as Map<String, dynamic>?) ?? {};
                    final mode = (scheduled['mode'] ?? 'presencial').toString();
                    final startAt = scheduled['startAt'] as Timestamp?;
                    final endAt = scheduled['endAt'] as Timestamp?;
                    final topic = (data['topic'] ?? '').toString().trim();
                    final description = (data['description'] ?? '')
                        .toString()
                        .trim();
                    final place = (scheduled['place'] ?? '').toString().trim();
                    final meetUrl = (scheduled['meetUrl'] ?? '')
                        .toString()
                        .trim();
                    final requireRsvp = scheduled['requireRsvp'] != false;
                    final rawCapacity = scheduled['capacity'];
                    final capacity = rawCapacity is num
                        ? rawCapacity.toInt()
                        : int.tryParse(rawCapacity?.toString() ?? '');
                    final status = (data['status'] ?? 'published').toString();
                    final publishedAt =
                        (data['publishedAt'] as Timestamp?) ??
                        (data['createdAt'] as Timestamp?);
                    final isCancelled = status == 'cancelled';
                    final rangeText = _formatFriendlyRange(startAt, endAt);
                    final timeBadge = _buildTimeStateBadge(
                      startAt: startAt?.toDate(),
                      endAt: endAt?.toDate(),
                      now: DateTime.now(),
                    );
                    final scheme = Theme.of(context).colorScheme;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      elevation: 0.8,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _MetaBadgeUser(
                              icon: Icons.event_available_outlined,
                              label: 'Sesion programada',
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    (data['title'] ?? 'Capacitacion')
                                        .toString(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                _StatusBadgeUser(status: status),
                              ],
                            ),
                            if (publishedAt != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${status == 'published' ? 'Publicada' : 'Creada'}: ${_formatOptionalDate(publishedAt)}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _MetaBadgeUser(
                                  icon: Icons.schedule,
                                  label: rangeText,
                                ),
                                _MetaBadgeUser(
                                  icon: mode == 'virtual'
                                      ? Icons.videocam_outlined
                                      : Icons.location_on_outlined,
                                  label: mode == 'virtual'
                                      ? 'Virtual'
                                      : 'Presencial',
                                ),
                                _MetaBadgeUser(
                                  icon: requireRsvp
                                      ? Icons.how_to_reg_outlined
                                      : Icons.info_outline,
                                  label: requireRsvp
                                      ? 'Confirmacion requerida'
                                      : 'Confirmacion opcional',
                                ),
                                if (capacity != null && capacity > 0)
                                  _MetaBadgeUser(
                                    icon: Icons.group_outlined,
                                    label: 'Cupos: $capacity',
                                  ),
                                if (timeBadge != null) timeBadge,
                              ],
                            ),
                            if (topic.isNotEmpty || description.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: scheme.outline.withValues(
                                      alpha: 0.14,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (topic.isNotEmpty)
                                      Text(
                                        topic,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    if (description.isNotEmpty) ...[
                                      if (topic.isNotEmpty)
                                        const SizedBox(height: 6),
                                      Text(
                                        description,
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
                            if (meetUrl.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.22),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.link_rounded,
                                          size: 16,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Enlace de la reunion',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelLarge
                                                ?.copyWith(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      meetUrl,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: OutlinedButton.icon(
                                        onPressed: isCancelled
                                            ? null
                                            : () {
                                                HapticFeedback.selectionClick();
                                                _openMeetingLink(meetUrl);
                                              },
                                        icon: const Icon(
                                          Icons.open_in_new_rounded,
                                        ),
                                        label: const Text('Abrir reunion'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else if (place.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.28),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.outline
                                        .withValues(alpha: 0.18),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.place_outlined,
                                      size: 18,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        place,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            StreamBuilder<
                              DocumentSnapshot<Map<String, dynamic>>
                            >(
                              stream: _myRsvpStream(doc.id),
                              builder: (context, rsvpSnap) {
                                final responseData = rsvpSnap.data?.data();
                                final persistedResponse =
                                    (responseData?['response'] ?? '')
                                        .toString()
                                        .trim();
                                final currentResponse =
                                    persistedResponse.isNotEmpty
                                    ? persistedResponse
                                    : (_localRsvpSelection[doc.id] ?? '');
                                final hasResponded =
                                    persistedResponse.isNotEmpty ||
                                    _submittedRsvpTrainingIds.contains(doc.id);
                                final isSavingResponse = _savingRsvpTrainingIds
                                    .contains(doc.id);
                                final canRespond =
                                    !isCancelled &&
                                    !hasResponded &&
                                    !isSavingResponse;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _rsvpButton(
                                          doc.id,
                                          'yes',
                                          'Asistir',
                                          currentResponse,
                                          enabled: canRespond,
                                        ),
                                        _rsvpButton(
                                          doc.id,
                                          'no',
                                          'No puedo',
                                          currentResponse,
                                          enabled: canRespond,
                                        ),
                                        _rsvpButton(
                                          doc.id,
                                          'maybe',
                                          'Quizas',
                                          currentResponse,
                                          enabled: canRespond,
                                        ),
                                      ],
                                    ),
                                    if (hasResponded) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'Tu confirmacion: ${_labelResponse(currentResponse)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                    StreamBuilder<
                                      DocumentSnapshot<Map<String, dynamic>>
                                    >(
                                      stream: _myAttendanceStream(doc.id),
                                      builder: (context, attendanceSnap) {
                                        final attendanceData = attendanceSnap
                                            .data
                                            ?.data();
                                        final attended =
                                            attendanceData?['attended'] == true;
                                        if (!attendanceSnap.hasData ||
                                            attendanceData == null) {
                                          return const SizedBox.shrink();
                                        }
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            top: 6,
                                          ),
                                          child: Text(
                                            attended
                                                ? 'Asistencia validada por administracion.'
                                                : 'Asistencia registrada: no asistio.',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildOnline(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
  ) {
    final docs =
        allDocs
            .where((doc) => (doc.data()['type'] ?? '').toString() == 'video')
            .toList()
          ..sort(_sortByCreatedAtDesc);

    if (docs.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.video_library_outlined,
        title: 'No hay videos publicados',
        subtitle: 'Cuando se publiquen contenidos en linea, los veras aqui.',
      );
    }

    return FutureBuilder<Map<String, _VideoProgressState>>(
      future: _getVideoProgressState(docs),
      builder: (context, progressSnap) {
        final cacheKey = _videoCacheKey(docs);
        final cachedProgress = _videoProgressMemoryCache[cacheKey];
        if (progressSnap.connectionState == ConnectionState.waiting &&
            !progressSnap.hasData &&
            cachedProgress == null) {
          return _buildTrainingsListSkeleton();
        }

        final progressByTraining =
            progressSnap.data ??
            cachedProgress ??
            const <String, _VideoProgressState>{};
        final pendingDocs = docs
            .where((doc) => !(progressByTraining[doc.id]?.watched ?? false))
            .toList();
        final completedDocs =
            docs
                .where((doc) => progressByTraining[doc.id]?.watched == true)
                .toList()
              ..sort(
                (a, b) => _sortCompletedVideosByWatchedAtDesc(
                  a,
                  b,
                  progressByTraining,
                ),
              );

        final children = <Widget>[
          if (pendingDocs.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No tienes videos pendientes. Revisa tus completadas abajo.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...pendingDocs.map(
              (doc) => _buildVideoTrainingCard(
                doc: doc,
                progressState:
                    progressByTraining[doc.id] ?? const _VideoProgressState(),
              ),
            ),
          const SizedBox(height: 6),
          Card(
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: ValueKey('completed_videos_${completedDocs.length}'),
                initiallyExpanded: _showCompletedVideos,
                onExpansionChanged: (expanded) {
                  if (!mounted) return;
                  setState(() => _showCompletedVideos = expanded);
                },
                leading: Icon(
                  Icons.task_alt_rounded,
                  color: Colors.green.shade600,
                ),
                title: Text(
                  'Completadas (${completedDocs.length})',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  completedDocs.isEmpty
                      ? 'Aun no has completado videos'
                      : 'Revisa aqui tus videos finalizados',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  if (completedDocs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('Sin videos completados por ahora.'),
                    )
                  else
                    ...completedDocs.map(
                      (doc) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildVideoTrainingCard(
                          doc: doc,
                          progressState:
                              progressByTraining[doc.id] ??
                              const _VideoProgressState(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ];

        return ListView(padding: const EdgeInsets.all(12), children: children);
      },
    );
  }

  Widget _buildHistory(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
  ) {
    final videoDocs =
        allDocs
            .where((doc) => (doc.data()['type'] ?? '').toString() == 'video')
            .toList()
          ..sort(_sortByCreatedAtDesc);
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
      allDocs,
    )..sort(_sortByCreatedAtDesc);

    return FutureBuilder<Map<String, _VideoProgressState>>(
      future: _getVideoProgressState(videoDocs),
      builder: (context, progressSnap) {
        final cacheKey = _videoCacheKey(videoDocs);
        final cachedProgress = _videoProgressMemoryCache[cacheKey];
        if (progressSnap.connectionState == ConnectionState.waiting &&
            !progressSnap.hasData &&
            cachedProgress == null) {
          return _buildTrainingsListSkeleton();
        }

        final progressByTraining =
            progressSnap.data ??
            cachedProgress ??
            const <String, _VideoProgressState>{};
        final filtered = sorted.where((doc) {
          final type = (doc.data()['type'] ?? '').toString();
          if (type != 'video') return true;
          return progressByTraining[doc.id]?.watched == true;
        }).toList();

        if (filtered.isEmpty) {
          return _buildEmptyState(
            context,
            icon: Icons.history_outlined,
            title: 'Sin historial',
            subtitle:
                'Aun no tienes capacitaciones finalizadas en tu historial.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: filtered.length,
          itemBuilder: (_, index) {
            final doc = filtered[index];
            final data = doc.data();
            final scheme = Theme.of(context).colorScheme;
            final title = (data['title'] ?? 'Capacitacion').toString();
            final type = (data['type'] ?? '').toString();
            final status = (data['status'] ?? 'published').toString();
            final topic = (data['topic'] ?? '').toString().trim();
            final description = (data['description'] ?? '').toString().trim();
            final isScheduled = type == 'scheduled';
            final scheduled =
                (data['scheduled'] as Map<String, dynamic>?) ?? {};
            final video = (data['video'] as Map<String, dynamic>?) ?? {};
            final startAt = scheduled['startAt'] as Timestamp?;
            final endAt = scheduled['endAt'] as Timestamp?;
            final mode = (scheduled['mode'] ?? '').toString();
            final duration = video['durationMinutes'];
            final publishedAt =
                (data['publishedAt'] as Timestamp?) ??
                (data['createdAt'] as Timestamp?);

            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              elevation: 0.8,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: scheme.outline.withValues(alpha: 0.18)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MetaBadgeUser(
                      icon: isScheduled
                          ? Icons.history_toggle_off_outlined
                          : Icons.task_alt_outlined,
                      label: isScheduled
                          ? 'Registro programado'
                          : 'Video completado',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        _StatusBadgeUser(status: status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetaBadgeUser(
                          icon: isScheduled
                              ? Icons.event_available_outlined
                              : Icons.ondemand_video_outlined,
                          label: isScheduled ? 'Programada' : 'Video',
                        ),
                        if (isScheduled)
                          _MetaBadgeUser(
                            icon: Icons.schedule,
                            label: _formatFriendlyRange(startAt, endAt),
                          ),
                        if (isScheduled && mode.trim().isNotEmpty)
                          _MetaBadgeUser(
                            icon: mode == 'virtual'
                                ? Icons.videocam_outlined
                                : Icons.location_on_outlined,
                            label: mode == 'virtual' ? 'Virtual' : 'Presencial',
                          ),
                        if (!isScheduled && duration != null)
                          _MetaBadgeUser(
                            icon: Icons.schedule_outlined,
                            label: '$duration min',
                          ),
                      ],
                    ),
                    if (topic.isNotEmpty || description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.2,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: scheme.outline.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (topic.isNotEmpty)
                              Text(
                                topic,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            if (description.isNotEmpty) ...[
                              if (topic.isNotEmpty) const SizedBox(height: 6),
                              Text(
                                description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (isScheduled) ...[
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: _myRsvpStream(doc.id),
                        builder: (context, rsvpSnap) {
                          final value =
                              (rsvpSnap.data?.data()?['response'] ?? '')
                                  .toString();
                          return Text(
                            value.isEmpty
                                ? 'Confirmacion: sin respuesta'
                                : 'Confirmacion: ${_labelResponse(value)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: _myAttendanceStream(doc.id),
                        builder: (context, attendanceSnap) {
                          final attended =
                              attendanceSnap.data?.data()?['attended'] == true;
                          return Text(
                            attendanceSnap.data?.exists == true
                                ? 'Asistencia: ${attended ? 'Asistio' : 'No asistio'}'
                                : 'Asistencia: pendiente de marcar',
                            style: Theme.of(context).textTheme.bodySmall,
                          );
                        },
                      ),
                    ] else ...[
                      Builder(
                        builder: (context) {
                          final progress =
                              progressByTraining[doc.id] ??
                              const _VideoProgressState();
                          final watchedAt = progress.watchedAt;
                          final url = (video['youtubeUrl'] ?? '').toString();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const _VideoStateChip(watched: true),
                                  if (watchedAt != null)
                                    _MetaBadgeUser(
                                      icon: Icons.event_available_outlined,
                                      label:
                                          'Visto: ${DateFormat('dd/MM/yyyy HH:mm').format(watchedAt.toDate())}',
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ElevatedButton.icon(
                                onPressed: url.trim().isEmpty
                                    ? null
                                    : () {
                                        HapticFeedback.selectionClick();
                                        _openVideo(url);
                                      },
                                icon: const Icon(Icons.ondemand_video_outlined),
                                label: const Text('Ver video'),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 6),
                    if (publishedAt != null)
                      Text(
                        '${status == 'published' ? 'Publicada' : 'Creada'}: ${_formatOptionalDate(publishedAt)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${doc.id}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVideoTrainingCard({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required _VideoProgressState progressState,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final data = doc.data();
    final video = (data['video'] as Map<String, dynamic>?) ?? {};
    final url = (video['youtubeUrl'] ?? '').toString();
    final duration = video['durationMinutes'];
    final topic = (data['topic'] ?? '').toString().trim();
    final status = (data['status'] ?? 'published').toString();
    final publishedAt =
        (data['publishedAt'] as Timestamp?) ??
        (data['createdAt'] as Timestamp?);
    final isCancelled = status == 'cancelled';
    final watched = progressState.watched;
    final watchedAt = progressState.watchedAt;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0.8,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: isCancelled ? null : () => _openVideo(url),
              child: _YoutubeThumbnail(youtubeUrl: url),
            ),
            const SizedBox(height: 12),
            const _MetaBadgeUser(
              icon: Icons.ondemand_video_outlined,
              label: 'Contenido en linea',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    (data['title'] ?? 'Capacitacion en linea').toString(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _StatusBadgeUser(status: status),
              ],
            ),
            if (publishedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                '${status == 'published' ? 'Publicada' : 'Creada'}: ${_formatOptionalDate(publishedAt)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (topic.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                topic,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.14),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (data['description'] ?? '').toString(),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(height: 1.35),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isCancelled
                        ? 'Capacitacion cancelada.'
                        : 'Toca la portada o usa el boton para ver el video.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isCancelled
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _VideoStateChip(watched: watched),
                if (duration != null)
                  _MetaBadgeUser(
                    icon: Icons.schedule_outlined,
                    label: '$duration min',
                  ),
                if (watchedAt != null)
                  _MetaBadgeUser(
                    icon: Icons.event_available_outlined,
                    label:
                        'Visto: ${DateFormat('dd/MM/yyyy HH:mm').format(watchedAt.toDate())}',
                  ),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.14),
                ),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: isCancelled
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            _openVideo(url);
                          },
                    icon: const Icon(Icons.ondemand_video_outlined),
                    label: const Text('Ver video'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isCancelled || watched
                        ? null
                        : () async {
                            HapticFeedback.selectionClick();
                            final success = await _markWatched(doc.id);
                            if (success && mounted) {
                              setState(() {});
                            }
                          },
                    style: watched
                        ? OutlinedButton.styleFrom(
                            foregroundColor: Colors.green.shade700,
                            disabledForegroundColor: Colors.green.shade700,
                            side: BorderSide(
                              color: Colors.green.withValues(alpha: 0.55),
                            ),
                            backgroundColor: Colors.green.withValues(
                              alpha: 0.1,
                            ),
                          )
                        : null,
                    icon: Icon(
                      watched
                          ? Icons.check_circle_rounded
                          : Icons.check_circle_outline,
                    ),
                    label: Text(watched ? 'Completado' : 'Marcar visto'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _sortByCreatedAtDesc(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final aTs = a.data()['createdAt'] as Timestamp?;
    final bTs = b.data()['createdAt'] as Timestamp?;
    final aDate = aTs?.toDate();
    final bDate = bTs?.toDate();
    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return bDate.compareTo(aDate);
  }

  int _sortCompletedVideosByWatchedAtDesc(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
    Map<String, _VideoProgressState> progressByTraining,
  ) {
    final aWatchedAt = progressByTraining[a.id]?.watchedAt?.toDate();
    final bWatchedAt = progressByTraining[b.id]?.watchedAt?.toDate();

    if (aWatchedAt == null && bWatchedAt == null) {
      return _sortByCreatedAtDesc(a, b);
    }
    if (aWatchedAt == null) return 1;
    if (bWatchedAt == null) return -1;

    final watchedCompare = bWatchedAt.compareTo(aWatchedAt);
    if (watchedCompare != 0) return watchedCompare;
    return _sortByCreatedAtDesc(a, b);
  }

  String _friendlyStreamError(Object? error) {
    if (error is FirebaseException) {
      final code = error.code.toLowerCase();
      if (code == 'permission-denied') {
        return 'No tienes permisos para ver estas capacitaciones.';
      }
      if (code == 'failed-precondition') {
        return 'Falta una configuracion en Firestore para esta consulta.';
      }
      return error.message ?? 'Ocurrio un error al cargar datos.';
    }
    return 'Verifica tu conexion e intenta nuevamente.';
  }

  Widget _rsvpButton(
    String trainingId,
    String value,
    String label,
    String current, {
    bool enabled = true,
  }) {
    final selected = current == value;
    return ChoiceChip(
      label: Text(label),
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      selected: selected,
      onSelected: enabled
          ? (_) async {
              HapticFeedback.selectionClick();
              if (mounted) {
                setState(() {
                  _savingRsvpTrainingIds.add(trainingId);
                  _localRsvpSelection[trainingId] = value;
                });
              }
              try {
                await _service.saveRsvp(
                  trainingId: trainingId,
                  response: value,
                );
                if (mounted) {
                  setState(() {
                    _submittedRsvpTrainingIds.add(trainingId);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Confirmacion registrada correctamente.'),
                    ),
                  );
                }
              } on FirebaseException catch (e) {
                if (!mounted) return;
                if (e.code == 'already-exists') {
                  setState(() {
                    _submittedRsvpTrainingIds.add(trainingId);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        e.message ??
                            'Tu confirmacion ya fue registrada y no puede modificarse.',
                      ),
                    ),
                  );
                  return;
                }
                final code = e.code.toUpperCase();
                final message =
                    e.message ?? 'No se pudo registrar tu respuesta.';
                setState(() {
                  _localRsvpSelection.remove(trainingId);
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'No se pudo guardar confirmacion ($code): $message',
                    ),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                setState(() {
                  _localRsvpSelection.remove(trainingId);
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('No se pudo guardar confirmacion: $e'),
                  ),
                );
              } finally {
                if (mounted) {
                  setState(() {
                    _savingRsvpTrainingIds.remove(trainingId);
                  });
                }
              }
            }
          : null,
    );
  }

  Future<bool> _markWatched(String trainingId) async {
    try {
      final institutionId = _institutionId ?? '';
      final uid = _currentUid ?? '';
      if (kDebugMode) {
        debugPrint(
          '[Trainings][progress-write] institutionId=$institutionId trainingId=$trainingId uid=$uid path=institutions/$institutionId/trainings/$trainingId/progress/$uid',
        );
      }
      await _service.markVideoWatched(trainingId);
      _optimisticallyMarkVideoAsWatched(trainingId);
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video marcado como visto.')),
      );
      return true;
    } on FirebaseException catch (e) {
      if (!mounted) return false;
      final code = e.code.toUpperCase();
      final message = e.message ?? 'No se pudo actualizar el progreso.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo marcar como visto ($code): $message'),
        ),
      );
      return false;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo marcar como visto: $e')),
      );
      return false;
    }
  }

  Future<void> _openVideo(String url) async {
    final uri = _resolveExternalUri(url);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('URL de video invalida.')));
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.open_in_browser_outlined),
                  title: const Text('Ver aqui en la app'),
                  subtitle: const Text('Abre el video en una vista interna'),
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    Navigator.pop(sheetContext);
                    await _openUrlWithMode(
                      uri,
                      preferredMode: LaunchMode.inAppWebView,
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.ondemand_video_outlined),
                  title: const Text('Abrir en YouTube'),
                  subtitle: const Text('Abre la app o navegador externo'),
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    Navigator.pop(sheetContext);
                    await _openUrlWithMode(
                      uri,
                      preferredMode: LaunchMode.externalApplication,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openMeetingLink(String url) async {
    final uri = _resolveExternalUri(url);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enlace de reunion invalido.')),
      );
      return;
    }
    await _openUrlWithMode(uri, preferredMode: LaunchMode.externalApplication);
  }

  Future<void> _openUrlWithMode(
    Uri uri, {
    required LaunchMode preferredMode,
  }) async {
    final modesToTry = <LaunchMode>[
      preferredMode,
      if (preferredMode != LaunchMode.inAppWebView) LaunchMode.inAppWebView,
      if (preferredMode != LaunchMode.inAppBrowserView)
        LaunchMode.inAppBrowserView,
      if (preferredMode != LaunchMode.externalApplication)
        LaunchMode.externalApplication,
    ];

    for (final mode in modesToTry) {
      try {
        final launched = await launchUrl(uri, mode: mode);
        if (launched) {
          if (mode == LaunchMode.externalApplication &&
              preferredMode != LaunchMode.externalApplication) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Se abrio el contenido en una aplicacion externa.',
                ),
              ),
            );
          }
          return;
        }
      } catch (_) {
        // Intenta el siguiente modo disponible.
      }
    }

    await _copyExternalLink(uri.toString());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No se pudo abrir el contenido. El enlace fue copiado al portapapeles.',
        ),
      ),
    );
  }

  Uri? _resolveExternalUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Uri.tryParse(trimmed);
    }

    if (trimmed.startsWith('//')) {
      return Uri.tryParse('https:$trimmed');
    }

    return Uri.tryParse('https://$trimmed');
  }

  Future<void> _copyExternalLink(String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
    } catch (_) {
      // Ignora fallos del portapapeles.
    }
  }

  String _labelResponse(String response) {
    switch (response) {
      case 'yes':
        return 'Asistir';
      case 'no':
        return 'No puedo';
      case 'maybe':
        return 'Quizas';
      default:
        return response;
    }
  }

  int _sortScheduledForUser(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final now = DateTime.now();
    final aScheduled = (a.data()['scheduled'] as Map<String, dynamic>?) ?? {};
    final bScheduled = (b.data()['scheduled'] as Map<String, dynamic>?) ?? {};
    final aStart = (aScheduled['startAt'] as Timestamp?)?.toDate();
    final bStart = (bScheduled['startAt'] as Timestamp?)?.toDate();
    final aEnd = (aScheduled['endAt'] as Timestamp?)?.toDate();
    final bEnd = (bScheduled['endAt'] as Timestamp?)?.toDate();

    final bucketCompare = _bucketForUser(
      startAt: aStart,
      endAt: aEnd,
      now: now,
    ).compareTo(_bucketForUser(startAt: bStart, endAt: bEnd, now: now));
    if (bucketCompare != 0) return bucketCompare;

    if (aStart == null && bStart == null) return 0;
    if (aStart == null) return 1;
    if (bStart == null) return -1;
    return aStart.compareTo(bStart);
  }

  int _bucketForUser({
    required DateTime? startAt,
    required DateTime? endAt,
    required DateTime now,
  }) {
    if (startAt == null) return 1;
    if (endAt != null && endAt.isBefore(now)) return 2;
    final diff = startAt.difference(now);
    if (!diff.isNegative && diff <= const Duration(hours: 24)) return 0;
    if (!diff.isNegative) return 1;
    return 2;
  }

  String _formatFriendlyRange(Timestamp? startAt, Timestamp? endAt) {
    if (startAt == null) return 'Fecha por definir';
    final start = startAt.toDate();
    final startText = _formatFriendlyDate(start);
    if (endAt == null) return startText;
    final end = endAt.toDate();
    final endText = DateFormat('HH:mm').format(end);
    return '$startText - $endText';
  }

  String _formatFriendlyDate(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(value.year, value.month, value.day);
    if (date == today) {
      return 'Hoy ${DateFormat('HH:mm').format(value)}';
    }
    if (date == today.add(const Duration(days: 1))) {
      return 'Manana ${DateFormat('HH:mm').format(value)}';
    }
    return DateFormat('dd MMM HH:mm').format(value);
  }

  String _formatOptionalDate(Timestamp? ts) {
    if (ts == null) return 'Sin fecha';
    return DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate());
  }

  Widget? _buildTimeStateBadge({
    required DateTime? startAt,
    required DateTime? endAt,
    required DateTime now,
  }) {
    if (startAt == null) return null;
    if (endAt != null && endAt.isBefore(now)) {
      return const _MetaBadgeUser(
        icon: Icons.check_circle_outline,
        label: 'Finalizada',
        color: Colors.grey,
      );
    }
    final diff = startAt.difference(now);
    if (diff.isNegative) return null;
    if (_isSameDay(startAt, now)) {
      return const _MetaBadgeUser(
        icon: Icons.today_outlined,
        label: 'Hoy',
        color: Colors.orange,
      );
    }
    if (diff <= const Duration(hours: 24)) {
      return const _MetaBadgeUser(
        icon: Icons.notifications_active_outlined,
        label: 'Proxima',
        color: Colors.orange,
      );
    }
    return null;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildTrainingsScreenSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        const AppSkeletonBox(
          height: 118,
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        const SizedBox(height: 10),
        const AppSkeletonBox(
          height: 46,
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        const SizedBox(height: 12),
        ...List.generate(
          3,
          (index) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: AppSkeletonBox(
              height: 182,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrainingsListSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: List.generate(
        3,
        (index) => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: AppSkeletonBox(
            height: 178,
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context, {
    required String title,
    required String subtitle,
    required VoidCallback onRetry,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_outlined, size: 46, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoProgressMetrics {
  final int watchedCount;
  final int totalCount;

  const _VideoProgressMetrics({
    required this.watchedCount,
    required this.totalCount,
  });
}

class _VideoProgressState {
  final bool watched;
  final Timestamp? watchedAt;

  const _VideoProgressState({this.watched = false, this.watchedAt});
}

class _VideoProgressSummary extends StatelessWidget {
  final int watchedCount;
  final int totalCount;
  final bool loading;

  const _VideoProgressSummary({
    required this.watchedCount,
    required this.totalCount,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = totalCount == 0 ? 0.0 : watchedCount / totalCount;
    final remaining = (totalCount - watchedCount).clamp(0, totalCount);
    final percent = totalCount == 0 ? 0 : (progress * 100).round();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Tu progreso en capacitaciones',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (loading)
                SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  totalCount == 0
                      ? 'Aun no hay capacitaciones en linea'
                      : '$watchedCount de $totalCount completadas â€¢ $percent% â€¢ Restantes: $remaining',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (totalCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$percent%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: progress,
              color: scheme.primary,
              backgroundColor: scheme.surfaceContainerHighest.withValues(
                alpha: 0.95,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoStateChip extends StatelessWidget {
  final bool watched;
  const _VideoStateChip({required this.watched});

  @override
  Widget build(BuildContext context) {
    final color = watched ? Colors.green : Colors.grey;
    final label = watched ? 'Visto' : 'Pendiente';
    final icon = watched ? Icons.check_circle_rounded : Icons.schedule_outlined;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadgeUser extends StatelessWidget {
  final String status;
  const _StatusBadgeUser({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late final String label;
    late final Color color;
    switch (status) {
      case 'published':
        label = 'Publicado';
        color = Colors.green;
        break;
      case 'cancelled':
        label = 'Cancelado';
        color = scheme.error;
        break;
      default:
        label = 'Borrador';
        color = scheme.outline;
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
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MetaBadgeUser extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _MetaBadgeUser({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return AppMetaChip(
      icon: icon,
      label: label,
      background: resolved.withValues(alpha: 0.12),
      foreground: resolved,
    );
  }
}

class _YoutubeThumbnail extends StatefulWidget {
  final String youtubeUrl;
  const _YoutubeThumbnail({required this.youtubeUrl});

  @override
  State<_YoutubeThumbnail> createState() => _YoutubeThumbnailState();
}

class _YoutubeThumbnailState extends State<_YoutubeThumbnail> {
  bool _fallback = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final videoId = _extractYoutubeId(widget.youtubeUrl);
    final primaryUrl = videoId == null || videoId.isEmpty
        ? null
        : 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg';
    final fallbackUrl = videoId == null || videoId.isEmpty
        ? null
        : 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
    final currentUrl = _fallback ? fallbackUrl : primaryUrl;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
              child: currentUrl == null
                  ? Center(
                      child: Icon(
                        Icons.ondemand_video_outlined,
                        size: 44,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : Image.network(
                      currentUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) {
                        if (!_fallback && fallbackUrl != null) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _fallback = true);
                          });
                        }
                        return Center(
                          child: Icon(
                            Icons.ondemand_video_outlined,
                            size: 44,
                            color: scheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
            ),
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 34,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _extractYoutubeId(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (host.contains('youtu.be')) {
      if (uri.pathSegments.isNotEmpty) return uri.pathSegments.first;
      return null;
    }
    if (host.contains('youtube.com')) {
      final fromQuery = uri.queryParameters['v'];
      if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
      final segments = uri.pathSegments;
      final embedIndex = segments.indexOf('embed');
      if (embedIndex != -1 && segments.length > embedIndex + 1) {
        return segments[embedIndex + 1];
      }
      final shortsIndex = segments.indexOf('shorts');
      if (shortsIndex != -1 && segments.length > shortsIndex + 1) {
        return segments[shortsIndex + 1];
      }
    }
    return null;
  }
}
