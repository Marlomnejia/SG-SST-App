import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../services/user_service.dart';
import '../widgets/app_meta_chip.dart';

class SgSstReportGenerationScreen extends StatefulWidget {
  const SgSstReportGenerationScreen({super.key});

  @override
  State<SgSstReportGenerationScreen> createState() =>
      _SgSstReportGenerationScreenState();
}

class _SgSstReportGenerationScreenState
    extends State<SgSstReportGenerationScreen> {
  static const Set<String> _closedReportStatuses = <String>{
    'cerrado',
    'closed',
    'solucionado',
    'resuelto',
    'finalizado',
    'completed',
  };
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UserService _userService = UserService();
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

  _ExportPeriod _selectedPeriod = _ExportPeriod.monthly;
  late DateTime _startDate;
  late DateTime _endDate;
  bool _loading = true;
  bool _exportingExecutivePdf = false;
  bool _exportingTechnicalPdf = false;
  String? _errorMessage;
  _GeneratedSgSstReport? _report;

  @override
  void initState() {
    super.initState();
    _applyExportPeriod(_selectedPeriod, refresh: false);
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final currentUser = await _userService.getCurrentUser();
      final institutionId = currentUser?.institutionId?.trim() ?? '';
      if (institutionId.isEmpty) {
        throw Exception(
          'Este modulo requiere una institucion asignada para consolidar indicadores.',
        );
      }

      final generated = await _buildReport(
        currentUser: currentUser,
        institutionId: institutionId,
        startDate: _startDate,
        endDate: _endDate,
      );

      if (!mounted) return;
      setState(() {
        _report = generated;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<_GeneratedSgSstReport> _buildReport({
    required CurrentUserData? currentUser,
    required String institutionId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final institutionNameFuture = _userService.getInstitutionName(
      institutionId,
    );
    final usersCountFuture = _firestore
        .collection('users')
        .where('institutionId', isEqualTo: institutionId)
        .count()
        .get();
    final reportsFuture = _firestore
        .collection('reports')
        .where('institutionId', isEqualTo: institutionId)
        .get();
    final trainingsFuture = _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection('trainings')
        .get();
    final institutionDocumentsFuture = _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection('documents')
        .get();
    final globalDocumentsFuture = _firestore
        .collection('global_documents')
        .where('isPublished', isEqualTo: true)
        .get();

    final institutionName = await institutionNameFuture;
    final usersCountSnapshot = await usersCountFuture;
    final reportsSnapshot = await reportsFuture;
    final trainingsSnapshot = await trainingsFuture;
    final institutionDocumentsSnapshot = await institutionDocumentsFuture;
    final globalDocumentsSnapshot = await globalDocumentsFuture;

    final filteredReports =
        reportsSnapshot.docs
            .where(
              (doc) => _isWithinRange(
                _extractDate(doc.data()['createdAt']) ??
                    _extractDate(doc.data()['datetime']) ??
                    _extractDate(doc.data()['updatedAt']),
                startDate,
                endDate,
              ),
            )
            .toList()
          ..sort(
            (a, b) => (_extractDate(b.data()['createdAt']) ?? DateTime(2000))
                .compareTo(
                  _extractDate(a.data()['createdAt']) ?? DateTime(2000),
                ),
          );

    final actionPlans = await _loadActionPlansForReports(
      filteredReports,
      institutionId: institutionId,
    );
    final trainingMetrics = await _buildTrainingMetrics(
      trainingDocs: trainingsSnapshot.docs,
      startDate: startDate,
      endDate: endDate,
    );
    final documentMetrics = await _buildDocumentMetrics(
      institutionDocs: institutionDocumentsSnapshot.docs,
      globalDocs: globalDocumentsSnapshot.docs,
      startDate: startDate,
      endDate: endDate,
    );
    final topReportTypes = _computeTopReportTypes(filteredReports);
    final topPlaces = _computeTopPlaces(filteredReports);
    final topOverdueResponsibles = _computeTopOverdueResponsibles(actionPlans);
    final averageClosureHours = _computeAverageClosureHours(filteredReports);

    return _GeneratedSgSstReport(
      institutionId: institutionId,
      institutionName:
          (institutionName == null || institutionName.trim().isEmpty)
          ? 'Institucion sin nombre'
          : institutionName.trim(),
      startDate: startDate,
      endDate: endDate,
      institutionUsers: usersCountSnapshot.count ?? 0,
      generatedByName: currentUser?.displayName?.trim().isNotEmpty == true
          ? currentUser!.displayName!.trim()
          : (currentUser?.email.trim().isNotEmpty == true
                ? currentUser!.email.trim()
                : 'Usuario actual'),
      generatedByRole: _friendlyRole(currentUser?.role),
      reports: filteredReports,
      actionPlans: actionPlans,
      trainingMetrics: trainingMetrics,
      documentMetrics: documentMetrics,
      topReportTypes: topReportTypes,
      topPlaces: topPlaces,
      topOverdueResponsibles: topOverdueResponsibles,
      averageClosureHours: averageClosureHours,
    );
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _loadActionPlansForReports(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> reports,
    {required String institutionId}
  ) async {
    if (reports.isEmpty) {
      return const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    }

    final reportIds = reports.map((doc) => doc.id).toSet().toList();
    final plans = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    const int chunkSize = 10;

    final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    for (int i = 0; i < reportIds.length; i += chunkSize) {
      final chunk = reportIds.sublist(
        i,
        i + chunkSize > reportIds.length ? reportIds.length : i + chunkSize,
      );
      futures.add(
        _firestore
            .collection('planesDeAccion')
            .where('eventoId', whereIn: chunk)
            .get(),
      );
    }
    final snapshots = await Future.wait(futures);
    for (final snapshot in snapshots) {
      plans.addAll(snapshot.docs);
    }

    final scopedPlans = plans.where((plan) {
      if (institutionId.trim().isEmpty) return true;
      final planInstitutionId =
          (plan.data()['institutionId'] ?? '').toString().trim();
      // Compatibilidad legacy: si el plan no tiene institutionId, se conserva
      // porque ya fue ligado por eventoId de reportes filtrados por institucion.
      if (planInstitutionId.isEmpty) return true;
      return planInstitutionId == institutionId;
    }).toList();

    final unique = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final plan in scopedPlans) {
      unique[plan.id] = plan;
    }

    return unique.values.toList()..sort(
      (a, b) => _planSortDate(b.data()).compareTo(_planSortDate(a.data())),
    );
  }

  Future<_TrainingMetrics> _buildTrainingMetrics({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> trainingDocs,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final filtered =
        trainingDocs
            .where(
              (doc) => _isWithinRange(
                _extractDate(doc.data()['publishedAt']) ??
                    _extractDate(doc.data()['createdAt']),
                startDate,
                endDate,
              ),
            )
            .toList()
          ..sort(
            (a, b) =>
                (_extractDate(b.data()['publishedAt']) ??
                        _extractDate(b.data()['createdAt']) ??
                        DateTime(2000))
                    .compareTo(
                      _extractDate(a.data()['publishedAt']) ??
                          _extractDate(a.data()['createdAt']) ??
                          DateTime(2000),
                    ),
          );

    final counters = await Future.wait(
      filtered.map(_buildTrainingCountersForDoc),
    );

    int scheduled = 0;
    int video = 0;
    int published = 0;
    int draft = 0;
    int cancelled = 0;
    int rsvpYes = 0;
    int rsvpNo = 0;
    int rsvpMaybe = 0;
    int attendance = 0;
    int watched = 0;

    for (final item in counters) {
      scheduled += item.scheduledCount;
      video += item.videoCount;
      published += item.publishedCount;
      draft += item.draftCount;
      cancelled += item.cancelledCount;
      rsvpYes += item.confirmedCount;
      rsvpNo += item.declinedCount;
      rsvpMaybe += item.maybeCount;
      attendance += item.attendedCount;
      watched += item.watchedCount;
    }

    return _TrainingMetrics(
      trainings: filtered,
      scheduledCount: scheduled,
      videoCount: video,
      publishedCount: published,
      draftCount: draft,
      cancelledCount: cancelled,
      confirmedCount: rsvpYes,
      declinedCount: rsvpNo,
      maybeCount: rsvpMaybe,
      attendedCount: attendance,
      watchedCount: watched,
    );
  }

  Future<_DocumentMetrics> _buildDocumentMetrics({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> institutionDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> globalDocs,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final filteredInstitution =
        institutionDocs
            .where(
              (doc) => _isWithinRange(
                _extractDate(doc.data()['publishedAt']) ??
                    _extractDate(doc.data()['createdAt']),
                startDate,
                endDate,
              ),
            )
            .toList()
          ..sort(
            (a, b) =>
                (_extractDate(b.data()['publishedAt']) ??
                        _extractDate(b.data()['createdAt']) ??
                        DateTime(2000))
                    .compareTo(
                      _extractDate(a.data()['publishedAt']) ??
                          _extractDate(a.data()['createdAt']) ??
                          DateTime(2000),
                    ),
          );

    final filteredGlobal =
        globalDocs
            .where(
              (doc) => _isWithinRange(
                _extractDate(doc.data()['publishedAt']) ??
                    _extractDate(doc.data()['createdAt']),
                startDate,
                endDate,
              ),
            )
            .toList()
          ..sort(
            (a, b) =>
                (_extractDate(b.data()['publishedAt']) ??
                        _extractDate(b.data()['createdAt']) ??
                        DateTime(2000))
                    .compareTo(
                      _extractDate(a.data()['publishedAt']) ??
                          _extractDate(a.data()['createdAt']) ??
                          DateTime(2000),
                    ),
          );

    final publishedInstitution = filteredInstitution
        .where((doc) => doc.data()['isPublished'] == true)
        .toList();

    final requiredInstitution = publishedInstitution.where((doc) {
      return doc.data()['isRequired'] == true;
    }).length;
    final readsFutures = publishedInstitution.map((doc) {
      return _safeCountQuery(doc.reference.collection('reads'));
    }).toList();
    final readsPerDocument = await Future.wait(readsFutures);
    final totalReads = readsPerDocument.fold<int>(
      0,
      (total, current) => total + current,
    );
    final documentsWithReads = readsPerDocument
        .where((readCount) => readCount > 0)
        .length;

    return _DocumentMetrics(
      institutionDocuments: filteredInstitution,
      globalDocuments: filteredGlobal,
      publishedInstitutionCount: publishedInstitution.length,
      requiredInstitutionCount: requiredInstitution,
      publishedGlobalCount: filteredGlobal.length,
      readsCount: totalReads,
      documentsWithReads: documentsWithReads,
    );
  }

  List<_TopFindingItem> _computeTopReportTypes(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> reports,
  ) {
    final counts = <String, int>{};
    for (final doc in reports) {
      final reportType = (doc.data()['reportType'] ?? '').toString().trim();
      if (reportType.isEmpty) continue;
      counts.update(reportType, (value) => value + 1, ifAbsent: () => 1);
    }
    return _topItemsFromMap(counts);
  }

  List<_TopFindingItem> _computeTopPlaces(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> reports,
  ) {
    final counts = <String, int>{};
    final labels = <String, String>{};
    for (final doc in reports) {
      final data = doc.data();
      final location = data['location'];
      final map = location is Map<String, dynamic>
          ? location
          : const <String, dynamic>{};
      final normalizedStored = (map['placeNormalized'] ?? '').toString().trim();
      final placeName = (map['placeName'] ?? data['lugar'] ?? '')
          .toString()
          .trim();
      final normalized = normalizedStored.isNotEmpty
          ? _normalizePlaceKey(normalizedStored)
          : _normalizePlaceKey(placeName);
      if (normalized.isEmpty) continue;
      counts.update(normalized, (value) => value + 1, ifAbsent: () => 1);
      labels.putIfAbsent(
        normalized,
        () => placeName.isNotEmpty
            ? placeName
            : (normalizedStored.isNotEmpty ? normalizedStored : normalized),
      );
    }
    return _topItemsFromMap(counts, labelResolver: (key) => labels[key] ?? key);
  }

  Future<_TrainingDocCounters> _buildTrainingCountersForDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final type = (data['type'] ?? '').toString().trim();
    final status = (data['status'] ?? '').toString().trim();

    int published = 0;
    int draft = 0;
    int cancelled = 0;
    switch (status) {
      case 'published':
        published = 1;
        break;
      case 'cancelled':
        cancelled = 1;
        break;
      default:
        draft = 1;
        break;
    }

    if (type == 'scheduled') {
      final responsesRef = doc.reference.collection('responses');
      final yesFuture = _safeCountQuery(
        responsesRef.where('response', isEqualTo: 'yes'),
      );
      final noFuture = _safeCountQuery(
        responsesRef.where('response', isEqualTo: 'no'),
      );
      final maybeFuture = _safeCountQuery(
        responsesRef.where('response', isEqualTo: 'maybe'),
      );
      final attendanceFuture = _safeCountQuery(
        doc.reference
            .collection('attendance')
            .where('attended', isEqualTo: true),
      );
      final results = await Future.wait<int>([
        yesFuture,
        noFuture,
        maybeFuture,
        attendanceFuture,
      ]);
      return _TrainingDocCounters(
        scheduledCount: 1,
        videoCount: 0,
        publishedCount: published,
        draftCount: draft,
        cancelledCount: cancelled,
        confirmedCount: results[0],
        declinedCount: results[1],
        maybeCount: results[2],
        attendedCount: results[3],
        watchedCount: 0,
      );
    }

    if (type == 'video') {
      final watchedCount = await _safeCountQuery(
        doc.reference.collection('progress').where('watched', isEqualTo: true),
      );
      return _TrainingDocCounters(
        scheduledCount: 0,
        videoCount: 1,
        publishedCount: published,
        draftCount: draft,
        cancelledCount: cancelled,
        confirmedCount: 0,
        declinedCount: 0,
        maybeCount: 0,
        attendedCount: 0,
        watchedCount: watchedCount,
      );
    }

    return _TrainingDocCounters(
      scheduledCount: 0,
      videoCount: 0,
      publishedCount: published,
      draftCount: draft,
      cancelledCount: cancelled,
      confirmedCount: 0,
      declinedCount: 0,
      maybeCount: 0,
      attendedCount: 0,
      watchedCount: 0,
    );
  }

  Future<int> _safeCountQuery(Query<Map<String, dynamic>> query) async {
    try {
      final aggregate = await query.count().get();
      return aggregate.count ?? 0;
    } catch (_) {
      final snapshot = await query.get();
      return snapshot.size;
    }
  }

  String _normalizePlaceKey(String value) {
    final cleaned = _removeDiacritics(value)
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return '';
    final justSymbolsOrDigits = RegExp(r'^[^a-z]+$').hasMatch(cleaned);
    return justSymbolsOrDigits ? '' : cleaned;
  }

  String _removeDiacritics(String value) {
    return value
        .replaceAll('\u00E1', 'a')
        .replaceAll('\u00E0', 'a')
        .replaceAll('\u00E4', 'a')
        .replaceAll('\u00E2', 'a')
        .replaceAll('\u00C1', 'A')
        .replaceAll('\u00C0', 'A')
        .replaceAll('\u00C4', 'A')
        .replaceAll('\u00C2', 'A')
        .replaceAll('\u00E9', 'e')
        .replaceAll('\u00E8', 'e')
        .replaceAll('\u00EB', 'e')
        .replaceAll('\u00EA', 'e')
        .replaceAll('\u00C9', 'E')
        .replaceAll('\u00C8', 'E')
        .replaceAll('\u00CB', 'E')
        .replaceAll('\u00CA', 'E')
        .replaceAll('\u00ED', 'i')
        .replaceAll('\u00EC', 'i')
        .replaceAll('\u00EF', 'i')
        .replaceAll('\u00EE', 'i')
        .replaceAll('\u00CD', 'I')
        .replaceAll('\u00CC', 'I')
        .replaceAll('\u00CF', 'I')
        .replaceAll('\u00CE', 'I')
        .replaceAll('\u00F3', 'o')
        .replaceAll('\u00F2', 'o')
        .replaceAll('\u00F6', 'o')
        .replaceAll('\u00F4', 'o')
        .replaceAll('\u00D3', 'O')
        .replaceAll('\u00D2', 'O')
        .replaceAll('\u00D6', 'O')
        .replaceAll('\u00D4', 'O')
        .replaceAll('\u00FA', 'u')
        .replaceAll('\u00F9', 'u')
        .replaceAll('\u00FC', 'u')
        .replaceAll('\u00FB', 'u')
        .replaceAll('\u00DA', 'U')
        .replaceAll('\u00D9', 'U')
        .replaceAll('\u00DC', 'U')
        .replaceAll('\u00DB', 'U')
        .replaceAll('\u00F1', 'n')
        .replaceAll('\u00D1', 'N');
  }

  List<_TopFindingItem> _computeTopOverdueResponsibles(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> actionPlans,
  ) {
    final counts = <String, int>{};
    final labels = <String, String>{};
    for (final doc in actionPlans) {
      final data = doc.data();
      if (_planStatus(data) != 'vencido') continue;
      final responsibleUid = (data['responsibleUid'] ?? '').toString().trim();
      final responsibleName =
          (data['responsibleName'] ?? data['asignadoA'] ?? '')
              .toString()
              .trim();
      final key = responsibleUid.isNotEmpty
          ? responsibleUid
          : (responsibleName.isNotEmpty ? responsibleName : 'sin_responsable');
      counts.update(key, (value) => value + 1, ifAbsent: () => 1);
      labels.putIfAbsent(
        key,
        () => responsibleName.isNotEmpty ? responsibleName : 'Sin responsable',
      );
    }
    return _topItemsFromMap(counts, labelResolver: (key) => labels[key] ?? key);
  }

  List<_TopFindingItem> _topItemsFromMap(
    Map<String, int> counts, {
    String Function(String key)? labelResolver,
  }) {
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .take(3)
        .map(
          (entry) => _TopFindingItem(
            label: labelResolver?.call(entry.key) ?? entry.key,
            count: entry.value,
          ),
        )
        .toList();
  }

  double? _computeAverageClosureHours(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> reports,
  ) {
    final durationsInHours = <double>[];

    for (final doc in reports) {
      final data = doc.data();
      final history = _statusHistoryEntries(data);
      final closedAt = _firstClosedStatusAt(history);
      if (closedAt == null) continue;

      final startedAt =
          _firstReportedStatusAt(history) ??
          _extractDate(data['createdAt']) ??
          _extractDate(data['datetime']);
      if (startedAt == null || closedAt.isBefore(startedAt)) continue;

      durationsInHours.add(closedAt.difference(startedAt).inMinutes / 60);
    }

    if (durationsInHours.isEmpty) {
      return null;
    }
    final total = durationsInHours.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item,
    );
    return total / durationsInHours.length;
  }

  List<Map<String, dynamic>> _statusHistoryEntries(Map<String, dynamic> data) {
    final raw = data['statusHistory'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList()
      ..sort((a, b) {
        final aDate = _extractDate(a['changedAt']) ?? DateTime(1900);
        final bDate = _extractDate(b['changedAt']) ?? DateTime(1900);
        return aDate.compareTo(bDate);
      });
  }

  DateTime? _firstReportedStatusAt(List<Map<String, dynamic>> history) {
    for (final item in history) {
      final status = _normalizeReportStatus(item['status']);
      if (status == 'reportado') {
        return _extractDate(item['changedAt']);
      }
    }
    return history.isNotEmpty ? _extractDate(history.first['changedAt']) : null;
  }

  DateTime? _firstClosedStatusAt(List<Map<String, dynamic>> history) {
    for (final item in history) {
      final status = _normalizeReportStatus(item['status']);
      if (_closedReportStatuses.contains(status)) {
        return _extractDate(item['changedAt']);
      }
    }
    return null;
  }

  String _normalizeReportStatus(dynamic value) {
    final normalized = value.toString().trim().toLowerCase();
    if (normalized.contains('revisi')) return 'en_revision';
    if (normalized.contains('proceso')) return 'en_proceso';
    if (normalized.contains('solucion') ||
        normalized.contains('cerrad') ||
        normalized.contains('finaliz') ||
        normalized.contains('resuelt') ||
        normalized == 'closed' ||
        normalized == 'completed') {
      return 'cerrado';
    }
    if (normalized.contains('rechaz')) return 'rechazado';
    if (normalized.contains('report')) return 'reportado';
    return normalized;
  }

  String _friendlyRole(String? role) {
    switch ((role ?? '').trim()) {
      case 'admin':
        return 'Super admin';
      case 'admin_sst':
        return 'Admin SST';
      case 'user':
        return 'Usuario';
      default:
        return (role == null || role.trim().isEmpty) ? 'Usuario' : role.trim();
    }
  }

  // ignore: unused_element
  String _pdfTopFindingsLabel(List<_TopFindingItem> items) {
    if (items.isEmpty) {
      return 'Sin datos';
    }
    return items.map((item) => '${item.label} (${item.count})').join(', ');
  }

  List<String> _pdfTopFindingsLines(List<_TopFindingItem> items) {
    if (items.isEmpty) {
      return const <String>['Sin datos'];
    }
    return items
        .take(3)
        .map((item) => '${_pdfClip(item.label, max: 60)} (${item.count})')
        .toList();
  }

  String _pdfClip(String value, {int max = 96}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return 'N/A';
    if (normalized.length <= max) return normalized;
    return '${normalized.substring(0, max - 1)}...';
  }

  List<String> _buildExecutiveConclusions(_GeneratedSgSstReport report) {
    final conclusions = <String>[];

    if (report.severeReportsCount > 0) {
      conclusions.add(
        'Se recomienda priorizar la investigacion y cierre de los casos graves detectados en el periodo.',
      );
    }
    if (report.overduePlansCount > 0) {
      conclusions.add(
        'Existen planes vencidos; conviene reasignar responsables y ajustar fechas de seguimiento.',
      );
    }
    if (report.documentCoverageRate < 0.6) {
      conclusions.add(
        'La cobertura documental es baja; se recomienda reforzar lectura y socializacion de soportes SST.',
      );
    }
    if (report.trainingMetrics.confirmedCount == 0 &&
        report.trainingMetrics.watchedCount == 0) {
      conclusions.add(
        'La participacion en capacitaciones es limitada; conviene revisar convocatoria y seguimiento.',
      );
    }

    if (conclusions.isEmpty) {
      conclusions.add(
        'El comportamiento general del periodo es estable. Se recomienda mantener el seguimiento preventivo y la verificacion oportuna de cierres.',
      );
    }

    return conclusions.take(3).toList();
  }

  DateTime _planSortDate(Map<String, dynamic> data) {
    return _extractDate(data['dueDate']) ??
        _extractDate(data['fechaLimite']) ??
        _extractDate(data['createdAt']) ??
        _extractDate(data['fechaInicio']) ??
        DateTime(2000);
  }

  DateTime? _extractDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  bool _isWithinRange(DateTime? value, DateTime startDate, DateTime endDate) {
    if (value == null) return false;
    return !value.isBefore(startDate) && !value.isAfter(endDate);
  }

  void _applyExportPeriod(_ExportPeriod period, {bool refresh = true}) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    late final DateTime start;

    switch (period) {
      case _ExportPeriod.monthly:
        start = DateTime(now.year, now.month, 1);
        break;
      case _ExportPeriod.quarterly:
        final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        start = DateTime(now.year, quarterStartMonth, 1);
        break;
      case _ExportPeriod.annual:
        start = DateTime(now.year, 1, 1);
        break;
    }

    setState(() {
      _selectedPeriod = period;
      _startDate = start;
      _endDate = end;
    });

    if (refresh) {
      _loadReport();
    }
  }

  String _exportPeriodLabel(_ExportPeriod period) {
    switch (period) {
      case _ExportPeriod.monthly:
        return 'Mensual';
      case _ExportPeriod.quarterly:
        return 'Trimestral';
      case _ExportPeriod.annual:
        return 'Anual';
    }
  }

  pw.Widget _buildPdfHeader({
    required String title,
    required String institutionName,
    required String periodLabel,
    required DateTime startDate,
    required DateTime endDate,
    required String generatedBy,
    String? subtitle,
  }) {
    final subtitleText = subtitle?.trim() ?? '';
    final periodText =
        '$periodLabel (${_dateFormat.format(startDate)} - ${_dateFormat.format(endDate)})';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        if (subtitleText.isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text(subtitleText, style: const pw.TextStyle(fontSize: 9)),
        ],
        pw.SizedBox(height: 8),
        pw.Text('Institucion: $institutionName'),
        pw.Text('Periodo: $periodText'),
        pw.Text('Generado por: $generatedBy'),
        pw.Text('Fecha de emision: ${_dateTimeFormat.format(DateTime.now())}'),
        pw.SizedBox(height: 8),
        pw.Divider(color: PdfColors.grey500, thickness: 0.8),
      ],
    );
  }

  pw.Widget _buildPdfPageRibbon(String label) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(
        label,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _buildPdfSectionTitle(String title, {String? subtitle}) {
    final subtitleText = subtitle?.trim() ?? '';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        if (subtitleText.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(subtitleText, style: const pw.TextStyle(fontSize: 8.5)),
        ],
        pw.SizedBox(height: 3),
        pw.Divider(color: PdfColors.grey400, thickness: 0.7),
      ],
    );
  }

  pw.Widget _buildStyledPdfTable(
    List<List<String>> data, {
    double fontSize = 8.5,
    Map<int, pw.TableColumnWidth>? columnWidths,
  }) {
    if (data.isEmpty || data.first.isEmpty) {
      return pw.Text('Sin datos disponibles.');
    }
    final totalCols = data.first.length;
    final normalized = data
        .map((row) {
          final current = <String>[];
          for (int index = 0; index < totalCols; index++) {
            final raw = index < row.length ? row[index] : '-';
            current.add(_pdfClip(raw.toString(), max: 96));
          }
          return current;
        })
        .toList(growable: false);

    return pw.TableHelper.fromTextArray(
      data: normalized,
      headerDecoration: null,
      headerStyle: pw.TextStyle(
        color: PdfColors.black,
        fontWeight: pw.FontWeight.bold,
        fontSize: fontSize,
      ),
      cellStyle: pw.TextStyle(fontSize: fontSize, color: PdfColors.black),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      rowDecoration: null,
      oddRowDecoration: null,
      border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.6),
      columnWidths: columnWidths,
      headerAlignments: {
        for (int index = 0; index < totalCols; index++)
          index: pw.Alignment.centerLeft,
      },
      cellAlignments: {
        for (int index = 0; index < totalCols; index++)
          index: pw.Alignment.centerLeft,
      },
    );
  }

  pw.Widget _buildPdfMetricCard({
    required String label,
    required String value,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Text(label, style: const pw.TextStyle(fontSize: 8.5)),
      ],
    );
  }

  pw.Widget _buildPdfInsightList(String title, List<String> items) {
    final lines = items.isEmpty ? const <String>['Sin datos'] : items;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        ...lines.map(
          (item) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Text('- $item', style: const pw.TextStyle(fontSize: 9)),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildPdfSignaturePanel(_GeneratedSgSstReport report) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Bloque de firmas',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text('Institucion: ${report.institutionName}'),
        pw.Text(
          'Generado por: ${report.generatedByName} (${report.generatedByRole})',
        ),
        pw.Text('Fecha de emision: ${_dateTimeFormat.format(DateTime.now())}'),
        pw.SizedBox(height: 12),
        pw.Text('Revisado por: ______________________'),
        pw.SizedBox(height: 8),
        pw.Text('Aprobado por: ______________________'),
      ],
    );
  }

  // ignore: unused_element
  pw.Widget _buildPdfClassificationPanel({
    required String classification,
    required String audience,
    required String validity,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Clasificacion del documento',
          style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text('Tipo: $classification'),
        pw.Text('Destinatario: $audience'),
        pw.Text('Vigencia: $validity'),
      ],
    );
  }

  pw.Widget _buildPdfFooter(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        children: [
          pw.Text(
            'EduSST - Informe SG-SST',
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.Spacer(),
          pw.Text(
            'Pagina ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfCoverFooter(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.white, width: 0.6),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            'EduSST | Seguridad y Salud en el Trabajo',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.white),
          ),
          pw.Spacer(),
          pw.Text(
            'Pagina ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.white),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  pw.Widget _buildTechnicalPdfCover(
    _GeneratedSgSstReport report, {
    required String periodLabel,
    required pw.Context context,
  }) {
    return pw.Container(
      width: double.infinity,
      height: double.infinity,
      padding: const pw.EdgeInsets.all(28),
      decoration: pw.BoxDecoration(
        gradient: const pw.LinearGradient(
          colors: <PdfColor>[PdfColors.teal900, PdfColors.blueGrey800],
          begin: pw.Alignment.topLeft,
          end: pw.Alignment.bottomRight,
        ),
        borderRadius: pw.BorderRadius.circular(18),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.circular(999),
                ),
                child: pw.Text(
                  'EduSST',
                  style: pw.TextStyle(
                    color: PdfColors.teal900,
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Spacer(),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColors.amber100,
                  borderRadius: pw.BorderRadius.circular(999),
                ),
                child: pw.Text(
                  'Uso interno / Auditoria',
                  style: pw.TextStyle(
                    color: PdfColors.amber900,
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          pw.Spacer(),
          pw.Text(
            'Consolidado Tecnico',
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 28,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Sistema de Gestion de Seguridad y Salud en el Trabajo',
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 13),
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(14),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  report.institutionName,
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey900,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Periodo: $periodLabel (${_dateFormat.format(report.startDate)} - ${_dateFormat.format(report.endDate)})',
                  style: const pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.blueGrey800,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Fecha de emision: ${_dateTimeFormat.format(DateTime.now())}',
                  style: const pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.blueGrey800,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Generado por: ${report.generatedByName} (${report.generatedByRole})',
                  style: const pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.blueGrey800,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildPdfMetricCard(
                label: 'Casos del periodo',
                value: '${report.totalReports}',
              ),
              _buildPdfMetricCard(
                label: 'Planes de accion',
                value: '${report.actionPlans.length}',
              ),
              _buildPdfMetricCard(
                label: 'Casos cerrados',
                value: '${report.closedReportsCount}',
              ),
              _buildPdfMetricCard(
                label: 'Tiempo a cierre',
                value: report.averageClosureLabel,
              ),
            ],
          ),
          pw.Spacer(),
          pw.Text(
            'Documento generado para soporte institucional, seguimiento operativo y procesos de auditoria interna.',
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 10),
          ),
          pw.SizedBox(height: 12),
          _buildPdfCoverFooter(context),
        ],
      ),
    );
  }

  // ignore: unused_element
  pw.Widget _buildExecutivePdfCover(
    _GeneratedSgSstReport report, {
    required String periodLabel,
    required pw.Context context,
  }) {
    return pw.Container(
      width: double.infinity,
      height: double.infinity,
      padding: const pw.EdgeInsets.all(26),
      decoration: pw.BoxDecoration(
        color: PdfColors.blueGrey50,
        borderRadius: pw.BorderRadius.circular(18),
        border: pw.Border.all(color: PdfColors.blueGrey200, width: 1.2),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColors.teal800,
                  borderRadius: pw.BorderRadius.circular(999),
                ),
                child: pw.Text(
                  'EduSST',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Spacer(),
              pw.Text(
                'Resumen ejecutivo',
                style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.blueGrey700,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.Spacer(),
          pw.Text(
            'Reporte Ejecutivo',
            style: pw.TextStyle(
              fontSize: 26,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey900,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Consolidado SG-SST para lectura directiva y seguimiento rapido.',
            style: const pw.TextStyle(
              fontSize: 12,
              color: PdfColors.blueGrey700,
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(14),
              border: pw.Border.all(color: PdfColors.blueGrey200),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  report.institutionName,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey900,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Periodo: $periodLabel (${_dateFormat.format(report.startDate)} - ${_dateFormat.format(report.endDate)})',
                  style: const pw.TextStyle(fontSize: 10.5),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Fecha de emision: ${_dateTimeFormat.format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 10.5),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildPdfMetricCard(
                label: 'Casos cerrados',
                value: '${report.closedReportsCount}',
              ),
              _buildPdfMetricCard(
                label: 'Planes vencidos',
                value: '${report.overduePlansCount}',
              ),
              _buildPdfMetricCard(
                label: 'Tiempo a cierre',
                value: report.averageClosureLabel,
              ),
            ],
          ),
          pw.Spacer(),
          pw.Text(
            'Documento de consulta rapida para direccion, comites y seguimiento institucional.',
            style: const pw.TextStyle(
              fontSize: 9.5,
              color: PdfColors.blueGrey700,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: PdfColors.blueGrey200, width: 0.8),
              ),
            ),
            child: pw.Row(
              children: [
                pw.Text(
                  'EduSST | Seguridad y Salud en el Trabajo',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.blueGrey600,
                  ),
                ),
                pw.Spacer(),
                pw.Text(
                  'Pagina ${context.pageNumber} de ${context.pagesCount}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.blueGrey600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportExecutivePdf() async {
    final report = _report;
    if (report == null) {
      _showMessage('Primero carga un consolidado antes de exportar.');
      return;
    }

    setState(() => _exportingExecutivePdf = true);
    try {
      final pdf = pw.Document();
      final periodLabel = _exportPeriodLabel(_selectedPeriod);
      final latestCasesRows = <List<String>>[
        <String>['Caso', 'Fecha', 'Estado', 'Que reporta'],
        ...report.reports.take(3).map((doc) {
          final data = doc.data();
          return <String>[
            (data['caseNumber'] ?? doc.id).toString(),
            _formatDate(
              _extractDate(data['createdAt']) ?? _extractDate(data['datetime']),
            ),
            _friendlyStatus((data['status'] ?? '').toString()),
            _pdfClip((data['reportType'] ?? 'Sin tipo').toString(), max: 44),
          ];
        }),
      ];
      final latestPlansRows = <List<String>>[
        <String>['Plan', 'Responsable', 'Estado', 'Limite'],
        ...report.actionPlans.take(3).map((doc) {
          final data = doc.data();
          return <String>[
            _pdfClip(
              (data['title'] ?? data['descripcion'] ?? 'Plan sin titulo')
                  .toString(),
              max: 42,
            ),
            _pdfClip(
              (data['responsibleName'] ??
                      data['asignadoA'] ??
                      'Sin responsable')
                  .toString(),
              max: 32,
            ),
            _friendlyPlanStatus(_planStatus(data)),
            _formatDate(
              _extractDate(data['dueDate']) ??
                  _extractDate(data['fechaLimite']),
            ),
          ];
        }),
      ];
      final summaryRows = <List<String>>[
        <String>['Indicador', 'Valor'],
        <String>['Casos registrados', '${report.totalReports}'],
        <String>['Casos cerrados', '${report.closedReportsCount}'],
        <String>['Casos graves', '${report.severeReportsCount}'],
        <String>['Tiempo promedio a cierre', report.averageClosureLabel],
        <String>['Planes vencidos', '${report.overduePlansCount}'],
        <String>[
          'Cobertura documental',
          '${(report.documentCoverageRate * 100).toStringAsFixed(1)}%',
        ],
      ];
      final executiveConclusions = _buildExecutiveConclusions(report);

      pdf.addPage(
        pw.MultiPage(
          margin: const pw.EdgeInsets.all(24),
          header: (_) => _buildPdfPageRibbon('Reporte ejecutivo'),
          footer: _buildPdfFooter,
          build: (context) => <pw.Widget>[
            _buildPdfHeader(
              title: 'Reporte Ejecutivo SG-SST',
              subtitle:
                  'Resumen institucional claro y consolidado del periodo.',
              institutionName: report.institutionName,
              periodLabel: periodLabel,
              startDate: report.startDate,
              endDate: report.endDate,
              generatedBy:
                  '${report.generatedByName} (${report.generatedByRole})',
            ),
            pw.SizedBox(height: 12),
            _buildPdfSectionTitle(
              'Resumen ejecutivo',
              subtitle: 'KPIs clave para seguimiento directivo.',
            ),
            pw.SizedBox(height: 8),
            _buildStyledPdfTable(
              summaryRows,
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2),
              },
            ),
            pw.SizedBox(height: 14),
            _buildPdfSectionTitle('Hallazgos principales'),
            pw.SizedBox(height: 8),
            _buildPdfInsightList(
              'Top 3 que estas reportando',
              _pdfTopFindingsLines(report.topReportTypes),
            ),
            pw.SizedBox(height: 8),
            _buildPdfInsightList(
              'Top 3 lugares o areas',
              _pdfTopFindingsLines(report.topPlaces),
            ),
            pw.SizedBox(height: 8),
            _buildPdfInsightList(
              'Top 3 responsables con planes vencidos',
              _pdfTopFindingsLines(report.topOverdueResponsibles),
            ),
            pw.SizedBox(height: 14),
            _buildPdfSectionTitle(
              'Conclusiones y recomendaciones',
              subtitle: 'Sugerencias autogeneradas segun los indicadores.',
            ),
            pw.SizedBox(height: 8),
            _buildPdfInsightList(
              'Recomendaciones sugeridas',
              executiveConclusions,
            ),
            pw.SizedBox(height: 14),
            _buildPdfSectionTitle('Ultimos 3 casos'),
            pw.SizedBox(height: 8),
            _buildStyledPdfTable(latestCasesRows),
            pw.SizedBox(height: 12),
            _buildPdfSectionTitle('Ultimos 3 planes'),
            pw.SizedBox(height: 8),
            _buildStyledPdfTable(latestPlansRows),
            pw.SizedBox(height: 14),
            _buildPdfSignaturePanel(report),
          ],
        ),
      );

      final file = await _writeExportFile(
        extension: 'pdf',
        bytes: await pdf.save(),
      );
      await OpenFilex.open(file.path);
      _showMessage('PDF ejecutivo generado correctamente.');
    } catch (e) {
      _showMessage('No se pudo generar el PDF ejecutivo: $e');
    } finally {
      if (mounted) {
        setState(() => _exportingExecutivePdf = false);
      }
    }
  }

  Future<void> _exportTechnicalPdf() async {
    final report = _report;
    if (report == null) {
      _showMessage('Primero carga un consolidado antes de exportar.');
      return;
    }

    setState(() => _exportingTechnicalPdf = true);
    try {
      final pdf = pw.Document();
      final periodLabel = _exportPeriodLabel(_selectedPeriod);
      final summaryRows = <List<String>>[
        <String>['Indicador', 'Valor'],
        <String>['Casos registrados', '${report.totalReports}'],
        <String>['Incidentes', '${report.incidentsCount}'],
        <String>['Accidentes', '${report.accidentsCount}'],
        <String>['Casos graves', '${report.severeReportsCount}'],
        <String>['Casos cerrados', '${report.closedReportsCount}'],
        <String>['Casos abiertos', '${report.openReportsCount}'],
        <String>['Planes de accion', '${report.actionPlans.length}'],
        <String>['Planes vencidos', '${report.overduePlansCount}'],
        <String>[
          'Tasa de cierre',
          '${(report.closureRate * 100).toStringAsFixed(1)}%',
        ],
        <String>[
          'Cumplimiento documental',
          '${(report.documentCoverageRate * 100).toStringAsFixed(1)}%',
        ],
        <String>['Tiempo promedio a cierre', report.averageClosureLabel],
      ];
      final trainingRows = <List<String>>[
        <String>['Indicador', 'Valor'],
        <String>[
          'Capacitaciones publicadas',
          '${report.trainingMetrics.publishedCount}',
        ],
        <String>['Programadas', '${report.trainingMetrics.scheduledCount}'],
        <String>['Videos', '${report.trainingMetrics.videoCount}'],
        <String>[
          'Confirmaciones positivas',
          '${report.trainingMetrics.confirmedCount}',
        ],
        <String>[
          'Asistencias registradas',
          '${report.trainingMetrics.attendedCount}',
        ],
        <String>['Videos vistos', '${report.trainingMetrics.watchedCount}'],
        <String>[
          'Documentos institucionales publicados',
          '${report.documentMetrics.publishedInstitutionCount}',
        ],
        <String>[
          'Documentos globales vigentes',
          '${report.documentMetrics.publishedGlobalCount}',
        ],
        <String>[
          'Documentos con lectura',
          '${report.documentMetrics.documentsWithReads}',
        ],
      ];

      final latestCases = <List<String>>[
        <String>['Caso', 'Fecha', 'Tipo', 'Estado'],
        ...report.reports.take(20).map((doc) {
          final data = doc.data();
          return <String>[
            (data['caseNumber'] ?? doc.id).toString(),
            _formatDate(
              _extractDate(data['createdAt']) ?? _extractDate(data['datetime']),
            ),
            _pdfClip((data['eventType'] ?? '').toString(), max: 26),
            _friendlyStatus((data['status'] ?? '').toString()),
          ];
        }),
      ];
      final detailedPlans = <List<String>>[
        <String>[
          'Plan',
          'Responsable',
          'Estado',
          'Limite',
          'Avance',
          'Validacion',
        ],
        ...report.actionPlans.take(20).map((doc) {
          final data = doc.data();
          return <String>[
            _pdfClip(
              (data['title'] ?? data['descripcion'] ?? 'Plan sin titulo')
                  .toString(),
              max: 42,
            ),
            _pdfClip(
              (data['responsibleName'] ??
                      data['asignadoA'] ??
                      'Sin responsable')
                  .toString(),
              max: 28,
            ),
            _friendlyPlanStatus(_planStatus(data)),
            _formatDate(
              _extractDate(data['dueDate']) ??
                  _extractDate(data['fechaLimite']),
            ),
            _pdfClip(_planExecutionSummary(data), max: 42),
            _pdfClip(_planValidationSummary(data), max: 42),
          ];
        }),
      ];

      pdf.addPage(
        pw.MultiPage(
          margin: const pw.EdgeInsets.all(24),
          header: (_) => _buildPdfPageRibbon('Reporte tecnico'),
          footer: _buildPdfFooter,
          build: (context) => <pw.Widget>[
            _buildPdfHeader(
              title: 'Consolidado Tecnico SG-SST',
              subtitle:
                  'Informe detallado para seguimiento y auditoria interna.',
              institutionName: report.institutionName,
              periodLabel: periodLabel,
              startDate: report.startDate,
              endDate: report.endDate,
              generatedBy:
                  '${report.generatedByName} (${report.generatedByRole})',
            ),
            pw.SizedBox(height: 12),
            _buildPdfSectionTitle(
              'Resumen de indicadores',
              subtitle: 'Lectura principal del comportamiento del periodo.',
            ),
            pw.SizedBox(height: 8),
            _buildStyledPdfTable(
              summaryRows,
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2),
              },
            ),
            pw.SizedBox(height: 14),
            _buildPdfSectionTitle(
              'Alineacion operativa con Resolucion 0312 de 2019',
              subtitle: 'Puntos de referencia para verificacion interna.',
            ),
            pw.SizedBox(height: 8),
            _buildPdfInsightList('Referencias normativas', [
              'Seguimiento y control de incidentes, accidentes y condiciones reportadas.',
              'Gestion del plan de trabajo anual mediante planes de accion, responsables y fechas.',
              'Medicion de indicadores de gestion para evaluar avance y mejora continua del SG-SST.',
            ]),
            pw.SizedBox(height: 14),
            _buildPdfSectionTitle(
              'Capacitaciones y evidencia',
              subtitle: 'Participacion y soporte documental del periodo.',
            ),
            pw.SizedBox(height: 8),
            _buildStyledPdfTable(
              trainingRows,
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2),
              },
            ),
            pw.SizedBox(height: 14),
            _buildPdfSectionTitle('Hallazgos principales'),
            pw.SizedBox(height: 8),
            _buildPdfInsightList(
              'Top 3 que estas reportando',
              _pdfTopFindingsLines(report.topReportTypes),
            ),
            pw.SizedBox(height: 8),
            _buildPdfInsightList(
              'Top 3 lugares o areas',
              _pdfTopFindingsLines(report.topPlaces),
            ),
            pw.SizedBox(height: 8),
            _buildPdfInsightList(
              'Top 3 responsables con planes vencidos',
              _pdfTopFindingsLines(report.topOverdueResponsibles),
            ),
            pw.SizedBox(height: 14),
            _buildPdfSectionTitle('Ultimos casos del periodo'),
            pw.SizedBox(height: 8),
            _buildStyledPdfTable(latestCases),
            pw.SizedBox(height: 14),
            _buildPdfSectionTitle(
              'Detalle tecnico de planes de accion',
              subtitle: 'Resumen operativo de ejecucion y validacion.',
            ),
            pw.SizedBox(height: 8),
            if (report.actionPlans.isEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 6),
                child: pw.Text(
                  'No hay planes de accion vinculados a los casos del periodo.',
                ),
              )
            else
              _buildStyledPdfTable(
                detailedPlans,
                fontSize: 7.8,
                columnWidths: {
                  0: const pw.FlexColumnWidth(2.6),
                  1: const pw.FlexColumnWidth(1.5),
                  2: const pw.FlexColumnWidth(1.1),
                  3: const pw.FlexColumnWidth(1.2),
                  4: const pw.FlexColumnWidth(2.0),
                  5: const pw.FlexColumnWidth(2.0),
                },
              ),
            pw.SizedBox(height: 14),
            _buildPdfSectionTitle(
              'Metodologia de indicadores',
              subtitle:
                  'Definiciones resumidas de los principales indicadores del consolidado.',
            ),
            pw.SizedBox(height: 8),
            _buildPdfInsightList('Definiciones', [
              'Tasa de cierre: casos cerrados del periodo sobre el total de casos registrados.',
              'Planes en riesgo: planes vencidos abiertos sobre el total de planes vinculados.',
              'Cobertura documental: documentos institucionales con lectura sobre los publicados.',
              'Tiempo promedio a cierre: promedio entre el primer estado reportado y el primer estado cerrado del historial.',
            ]),
            pw.SizedBox(height: 18),
            _buildPdfSignaturePanel(report),
          ],
        ),
      );

      final file = await _writeExportFile(
        extension: 'pdf',
        bytes: await pdf.save(),
      );
      await OpenFilex.open(file.path);
      _showMessage('PDF tecnico generado correctamente.');
    } catch (e) {
      _showMessage('No se pudo generar el PDF tecnico: $e');
    } finally {
      if (mounted) {
        setState(() => _exportingTechnicalPdf = false);
      }
    }
  }

  Future<File> _writeExportFile({
    required String extension,
    String? contents,
    List<int>? bytes,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File(
      '${directory.path}${Platform.pathSeparator}reporte_sgsst_$timestamp.$extension',
    );

    if (bytes != null) {
      await file.writeAsBytes(bytes, flush: true);
      return file;
    }

    await file.writeAsString(contents ?? '', flush: true);
    return file;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'No disponible';
    return _dateFormat.format(date);
  }

  String _formatDateTime(DateTime? date) {
    if (date == null) return 'No disponible';
    return _dateTimeFormat.format(date);
  }

  String _friendlyStatus(String status) {
    final value = status.trim().toLowerCase();
    switch (value) {
      case 'reportado':
        return 'Reportado';
      case 'en_revision':
        return 'En revision';
      case 'en_proceso':
        return 'En proceso';
      case 'cerrado':
      case 'closed':
      case 'solucionado':
      case 'resuelto':
      case 'finalizado':
      case 'completed':
        return 'Cerrado';
      case 'rechazado':
        return 'Rechazado';
      default:
        return status.isEmpty ? 'Sin estado' : status;
    }
  }

  String _planStatus(Map<String, dynamic> data) {
    final raw = (data['status'] ?? data['estado'] ?? 'pendiente')
        .toString()
        .trim()
        .toLowerCase();
    final due =
        _extractDate(data['dueDate']) ?? _extractDate(data['fechaLimite']);
    final isPending = raw == 'pendiente' || raw == 'en_curso';
    if (isPending && due != null && due.isBefore(DateTime.now())) {
      return 'vencido';
    }
    return raw;
  }

  String _friendlyPlanStatus(String status) {
    switch (status) {
      case 'pendiente':
        return 'Pendiente';
      case 'en_curso':
        return 'En curso';
      case 'ejecutado':
        return 'Ejecutado';
      case 'verificado':
        return 'Verificado';
      case 'cerrado':
        return 'Cerrado';
      case 'vencido':
        return 'Vencido';
      default:
        return status.isEmpty ? 'Sin estado' : status;
    }
  }

  int _attachmentCount(dynamic value) {
    if (value is Iterable) {
      return value.length;
    }
    return 0;
  }

  String _planExecutionSummary(Map<String, dynamic> data) {
    final note = (data['executionNote'] ?? '').toString().trim();
    if (note.isNotEmpty) return note;
    final evidence = (data['executionEvidence'] ?? '').toString().trim();
    if (evidence.isNotEmpty) return evidence;
    return 'Sin avance reportado';
  }

  String _planValidationSummary(Map<String, dynamic> data) {
    final verificationStatus = (data['verificationStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final verificationNote = (data['verificationNote'] ?? '').toString().trim();
    if (verificationNote.isNotEmpty) {
      return verificationStatus.isNotEmpty && verificationStatus != 'pendiente'
          ? '${_friendlyPlanStatus(verificationStatus)}: $verificationNote'
          : verificationNote;
    }
    final closureEvidence = (data['closureEvidence'] ?? '').toString().trim();
    if (closureEvidence.isNotEmpty) {
      return closureEvidence;
    }
    if (verificationStatus.isNotEmpty && verificationStatus != 'pendiente') {
      return _friendlyPlanStatus(verificationStatus);
    }
    return 'Pendiente de validacion';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final report = _report;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Generacion de reportes'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadReport,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar consolidado',
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (_loading && report == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_errorMessage != null && report == null) {
            return _EmptyStateCard(
              icon: Icons.analytics_outlined,
              title: 'No se pudo generar el consolidado',
              subtitle: _errorMessage!,
              actionLabel: 'Reintentar',
              onPressed: _loadReport,
            );
          }

          if (report == null) {
            return _EmptyStateCard(
              icon: Icons.analytics_outlined,
              title: 'No hay datos para consolidar',
              subtitle:
                  'Aun no se encontro informacion suficiente para generar un reporte SG-SST.',
              actionLabel: 'Actualizar',
              onPressed: _loadReport,
            );
          }

          return RefreshIndicator(
            onRefresh: _loadReport,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionContainer(
                  title: 'Periodo y exportacion',
                  subtitle: '',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _ExportPeriod.values
                            .map(
                              (period) => ChoiceChip(
                                label: Text(_exportPeriodLabel(period)),
                                selected: _selectedPeriod == period,
                                onSelected: (_) => _applyExportPeriod(period),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Periodo: ${_exportPeriodLabel(_selectedPeriod)} (${_formatDate(_startDate)} - ${_formatDate(_endDate)})',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: _exportingExecutivePdf
                                ? null
                                : _exportExecutivePdf,
                            icon: _exportingExecutivePdf
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('Exportar PDF Ejecutivo'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _exportingTechnicalPdf
                                ? null
                                : _exportTechnicalPdf,
                            icon: _exportingTechnicalPdf
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.description_outlined),
                            label: const Text('Exportar PDF Tecnico'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_loading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(minHeight: 3),
                ],
                const SizedBox(height: 16),
                _SummaryGrid(report: report),
                const SizedBox(height: 16),
                _SectionContainer(
                  title: '3.2.2 Investigacion de incidentes y accidentes',
                  subtitle:
                      'Controla la cantidad de casos, su criticidad y el estado de atencion dentro del periodo seleccionado.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _MetricPill(
                            label: 'Incidentes',
                            value: '${report.incidentsCount}',
                            icon: Icons.warning_amber_outlined,
                          ),
                          _MetricPill(
                            label: 'Accidentes',
                            value: '${report.accidentsCount}',
                            icon: Icons.health_and_safety_outlined,
                          ),
                          _MetricPill(
                            label: 'Graves',
                            value: '${report.severeReportsCount}',
                            icon: Icons.priority_high_outlined,
                            color: scheme.error,
                          ),
                          _MetricPill(
                            label: 'Abiertos',
                            value: '${report.openReportsCount}',
                            icon: Icons.pending_actions_outlined,
                            color: scheme.secondary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (report.reports.isEmpty)
                        Text(
                          'No hay casos registrados en este periodo.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      else
                        ...report.reports
                            .take(5)
                            .map(
                              (doc) => _ReportRow(
                                caseNumber: (doc.data()['caseNumber'] ?? doc.id)
                                    .toString(),
                                description:
                                    (doc.data()['reportType'] ??
                                            doc.data()['description'] ??
                                            'Sin descripcion')
                                        .toString(),
                                status: _friendlyStatus(
                                  (doc.data()['status'] ?? '').toString(),
                                ),
                                dateLabel: _formatDateTime(
                                  _extractDate(doc.data()['createdAt']) ??
                                      _extractDate(doc.data()['datetime']),
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionContainer(
                  title: '2.4.1 Planes de accion y seguimiento',
                  subtitle:
                      'Permite sustentar el plan de trabajo anual, responsables, vencimientos y cierre de acciones correctivas o preventivas.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _MetricPill(
                            label: 'Total',
                            value: '${report.actionPlans.length}',
                            icon: Icons.assignment_outlined,
                          ),
                          _MetricPill(
                            label: 'En seguimiento',
                            value: '${report.openActionPlansCount}',
                            icon: Icons.schedule_outlined,
                            color: scheme.secondary,
                          ),
                          _MetricPill(
                            label: 'Vencidos',
                            value: '${report.overduePlansCount}',
                            icon: Icons.event_busy_outlined,
                            color: scheme.error,
                          ),
                          _MetricPill(
                            label: 'Cerrados',
                            value: '${report.closedActionPlansCount}',
                            icon: Icons.task_alt_outlined,
                            color: scheme.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (report.actionPlans.isEmpty)
                        Text(
                          'No hay planes de accion vinculados a los casos del periodo.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      else
                        ...report.actionPlans.take(5).map((doc) {
                          final data = doc.data();
                          final title =
                              (data['title'] ??
                                      data['descripcion'] ??
                                      'Plan sin titulo')
                                  .toString();
                          return _PlanRow(
                            title: title,
                            responsible:
                                (data['responsibleName'] ??
                                        data['asignadoA'] ??
                                        'Sin responsable')
                                    .toString(),
                            status: _friendlyPlanStatus(_planStatus(data)),
                            dueDate: _formatDate(
                              _extractDate(data['dueDate']) ??
                                  _extractDate(data['fechaLimite']),
                            ),
                            executionSummary: _planExecutionSummary(data),
                            executionAttachmentCount: _attachmentCount(
                              data['executionAttachments'],
                            ),
                            validationSummary: _planValidationSummary(data),
                            validationAttachmentCount: _attachmentCount(
                              data['closureAttachments'],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionContainer(
                  title: 'Capacitacion y participacion',
                  subtitle:
                      'Consolida evidencia de formacion, confirmaciones, asistencias y visualizacion de contenido en linea.',
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _MetricPill(
                        label: 'Publicadas',
                        value: '${report.trainingMetrics.publishedCount}',
                        icon: Icons.school_outlined,
                      ),
                      _MetricPill(
                        label: 'Programadas',
                        value: '${report.trainingMetrics.scheduledCount}',
                        icon: Icons.event_available_outlined,
                      ),
                      _MetricPill(
                        label: 'Videos',
                        value: '${report.trainingMetrics.videoCount}',
                        icon: Icons.ondemand_video_outlined,
                      ),
                      _MetricPill(
                        label: 'Confirmados',
                        value: '${report.trainingMetrics.confirmedCount}',
                        icon: Icons.how_to_reg_outlined,
                        color: scheme.primary,
                      ),
                      _MetricPill(
                        label: 'Asistencias',
                        value: '${report.trainingMetrics.attendedCount}',
                        icon: Icons.fact_check_outlined,
                        color: scheme.secondary,
                      ),
                      _MetricPill(
                        label: 'Videos vistos',
                        value: '${report.trainingMetrics.watchedCount}',
                        icon: Icons.play_circle_outline,
                        color: scheme.tertiary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionContainer(
                  title: 'Documentacion y evidencia',
                  subtitle:
                      'Centraliza la disponibilidad documental, exigencias internas y lectura de soportes institucionales del SG-SST.',
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _MetricPill(
                        label: 'Inst. publicados',
                        value:
                            '${report.documentMetrics.publishedInstitutionCount}',
                        icon: Icons.picture_as_pdf_outlined,
                      ),
                      _MetricPill(
                        label: 'Obligatorios',
                        value:
                            '${report.documentMetrics.requiredInstitutionCount}',
                        icon: Icons.rule_folder_outlined,
                        color: scheme.secondary,
                      ),
                      _MetricPill(
                        label: 'Globales vigentes',
                        value: '${report.documentMetrics.publishedGlobalCount}',
                        icon: Icons.public_outlined,
                        color: scheme.tertiary,
                      ),
                      _MetricPill(
                        label: 'Con lectura',
                        value: '${report.documentMetrics.documentsWithReads}',
                        icon: Icons.visibility_outlined,
                        color: scheme.primary,
                      ),
                      _MetricPill(
                        label: 'Lecturas',
                        value: '${report.documentMetrics.readsCount}',
                        icon: Icons.library_books_outlined,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionContainer(
                  title: 'Hallazgos principales',
                  subtitle:
                      'Resume los patrones recurrentes del periodo para priorizar intervenciones y seguimiento.',
                  child: Column(
                    children: [
                      _TopFindingsBlock(
                        title: 'Top 3 que estas reportando',
                        icon: Icons.assignment_outlined,
                        items: report.topReportTypes,
                      ),
                      const SizedBox(height: 12),
                      _TopFindingsBlock(
                        title: 'Top 3 lugares o areas',
                        icon: Icons.place_outlined,
                        items: report.topPlaces,
                      ),
                      const SizedBox(height: 12),
                      _TopFindingsBlock(
                        title: 'Top 3 responsables con planes vencidos',
                        icon: Icons.person_search_outlined,
                        items: report.topOverdueResponsibles,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionContainer(
                  title: '6.1.1 Indicadores SG-SST',
                  subtitle:
                      'Indicadores operativos para revision gerencial, auditorias internas y seguimiento del cumplimiento.',
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        child: _MetricPill(
                          label: 'Tiempo promedio a cierre',
                          value: report.averageClosureLabel,
                          icon: Icons.av_timer_outlined,
                          color: scheme.primary,
                        ),
                      ),
                      _IndicatorRow(
                        label: 'Tasa de cierre de casos',
                        value:
                            '${(report.closureRate * 100).toStringAsFixed(1)}%',
                        progress: report.closureRate,
                      ),
                      const SizedBox(height: 12),
                      _IndicatorRow(
                        label: 'Planes en riesgo de incumplimiento',
                        value:
                            '${(report.overduePlanRate * 100).toStringAsFixed(1)}%',
                        progress: report.overduePlanRate,
                        progressColor: scheme.error,
                      ),
                      const SizedBox(height: 12),
                      _IndicatorRow(
                        label: 'Cobertura documental con lectura',
                        value:
                            '${(report.documentCoverageRate * 100).toStringAsFixed(1)}%',
                        progress: report.documentCoverageRate,
                        progressColor: scheme.secondary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GeneratedSgSstReport {
  final String institutionId;
  final String institutionName;
  final DateTime startDate;
  final DateTime endDate;
  final int institutionUsers;
  final String generatedByName;
  final String generatedByRole;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> reports;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> actionPlans;
  final _TrainingMetrics trainingMetrics;
  final _DocumentMetrics documentMetrics;
  final List<_TopFindingItem> topReportTypes;
  final List<_TopFindingItem> topPlaces;
  final List<_TopFindingItem> topOverdueResponsibles;
  final double? averageClosureHours;

  const _GeneratedSgSstReport({
    required this.institutionId,
    required this.institutionName,
    required this.startDate,
    required this.endDate,
    required this.institutionUsers,
    required this.generatedByName,
    required this.generatedByRole,
    required this.reports,
    required this.actionPlans,
    required this.trainingMetrics,
    required this.documentMetrics,
    required this.topReportTypes,
    required this.topPlaces,
    required this.topOverdueResponsibles,
    required this.averageClosureHours,
  });

  int get totalReports => reports.length;

  int get incidentsCount => reports.where((doc) {
    final value = (doc.data()['eventType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return value == 'incidente';
  }).length;

  int get accidentsCount => reports.where((doc) {
    final value = (doc.data()['eventType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return value == 'accidente';
  }).length;

  int get severeReportsCount => reports.where((doc) {
    final value = (doc.data()['severity'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return value == 'grave';
  }).length;

  int get closedReportsCount => reports.where((doc) {
    final value = (doc.data()['status'] ?? '').toString();
    return _GeneratedSgSstReport._closedStatuses.contains(
      value.trim().toLowerCase(),
    );
  }).length;

  int get openReportsCount => reports.where((doc) {
    final value = (doc.data()['status'] ?? '').toString().trim().toLowerCase();
    return !_GeneratedSgSstReport._closedStatuses.contains(value) &&
        value != 'rechazado';
  }).length;

  int get overduePlansCount => actionPlans.where((doc) {
    final data = doc.data();
    final raw = (data['status'] ?? data['estado'] ?? 'pendiente')
        .toString()
        .trim()
        .toLowerCase();
    final due = _safeDate(data['dueDate']) ?? _safeDate(data['fechaLimite']);
    final isPending = raw == 'pendiente' || raw == 'en_curso';
    return isPending && due != null && due.isBefore(DateTime.now());
  }).length;

  int get openActionPlansCount => actionPlans.where((doc) {
    final value = (doc.data()['status'] ?? doc.data()['estado'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return value == 'pendiente' || value == 'en_curso' || value == 'vencido';
  }).length;

  int get closedActionPlansCount => actionPlans.where((doc) {
    final value = (doc.data()['status'] ?? doc.data()['estado'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return value == 'cerrado' || value == 'verificado';
  }).length;

  double get closureRate {
    if (totalReports == 0) return 0;
    return closedReportsCount / totalReports;
  }

  double get overduePlanRate {
    if (actionPlans.isEmpty) return 0;
    return overduePlansCount / actionPlans.length;
  }

  double get documentCoverageRate {
    if (documentMetrics.publishedInstitutionCount == 0) return 0;
    return documentMetrics.documentsWithReads /
        documentMetrics.publishedInstitutionCount;
  }

  String get averageClosureLabel {
    if (averageClosureHours == null) {
      return 'N/A';
    }
    if (averageClosureHours! >= 24) {
      return '${(averageClosureHours! / 24).toStringAsFixed(1)} dias';
    }
    return '${averageClosureHours!.toStringAsFixed(1)} h';
  }

  static const Set<String> _closedStatuses = <String>{
    'cerrado',
    'closed',
    'solucionado',
    'resuelto',
    'finalizado',
    'completed',
  };

  static DateTime? _safeDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

class _TrainingMetrics {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> trainings;
  final int scheduledCount;
  final int videoCount;
  final int publishedCount;
  final int draftCount;
  final int cancelledCount;
  final int confirmedCount;
  final int declinedCount;
  final int maybeCount;
  final int attendedCount;
  final int watchedCount;

  const _TrainingMetrics({
    required this.trainings,
    required this.scheduledCount,
    required this.videoCount,
    required this.publishedCount,
    required this.draftCount,
    required this.cancelledCount,
    required this.confirmedCount,
    required this.declinedCount,
    required this.maybeCount,
    required this.attendedCount,
    required this.watchedCount,
  });
}

class _TrainingDocCounters {
  final int scheduledCount;
  final int videoCount;
  final int publishedCount;
  final int draftCount;
  final int cancelledCount;
  final int confirmedCount;
  final int declinedCount;
  final int maybeCount;
  final int attendedCount;
  final int watchedCount;

  const _TrainingDocCounters({
    required this.scheduledCount,
    required this.videoCount,
    required this.publishedCount,
    required this.draftCount,
    required this.cancelledCount,
    required this.confirmedCount,
    required this.declinedCount,
    required this.maybeCount,
    required this.attendedCount,
    required this.watchedCount,
  });
}

class _DocumentMetrics {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> institutionDocuments;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> globalDocuments;
  final int publishedInstitutionCount;
  final int requiredInstitutionCount;
  final int publishedGlobalCount;
  final int readsCount;
  final int documentsWithReads;

  const _DocumentMetrics({
    required this.institutionDocuments,
    required this.globalDocuments,
    required this.publishedInstitutionCount,
    required this.requiredInstitutionCount,
    required this.publishedGlobalCount,
    required this.readsCount,
    required this.documentsWithReads,
  });
}

class _TopFindingItem {
  final String label;
  final int count;

  const _TopFindingItem({required this.label, required this.count});
}

enum _ExportPeriod { monthly, quarterly, annual }

class _SectionContainer extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionContainer({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasSubtitle = subtitle.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (hasSubtitle) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final _GeneratedSgSstReport report;

  const _SummaryGrid({required this.report});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cards = <_SummaryCardData>[
      _SummaryCardData(
        label: 'Casos del periodo',
        value: '${report.totalReports}',
        icon: Icons.fact_check_outlined,
        color: scheme.primary,
      ),
      _SummaryCardData(
        label: 'Casos cerrados',
        value: '${report.closedReportsCount}',
        icon: Icons.task_alt_outlined,
        color: scheme.secondary,
      ),
      _SummaryCardData(
        label: 'Planes vencidos',
        value: '${report.overduePlansCount}',
        icon: Icons.event_busy_outlined,
        color: scheme.error,
      ),
      _SummaryCardData(
        label: 'Tasa de cierre',
        value: '${(report.closureRate * 100).toStringAsFixed(1)}%',
        icon: Icons.trending_up_outlined,
        color: scheme.tertiary,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final columns = constraints.maxWidth < 720 ? 2 : 4;
        final width =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map(
                (item) => SizedBox(
                  width: width,
                  child: _SummaryMetricCard(data: item),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _SummaryCardData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _SummaryMetricCard extends StatelessWidget {
  final _SummaryCardData data;

  const _SummaryMetricCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(data.icon, color: data.color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            data.value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const _MetricPill({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolved = color ?? scheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: resolved.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: resolved.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: resolved, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: resolved,
                ),
              ),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IndicatorRow extends StatelessWidget {
  final String label;
  final String value;
  final double progress;
  final Color? progressColor;

  const _IndicatorRow({
    required this.label,
    required this.value,
    required this.progress,
    this.progressColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                value,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 7,
              color: progressColor ?? scheme.primary,
              backgroundColor: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  final String caseNumber;
  final String description;
  final String status;
  final String dateLabel;

  const _ReportRow({
    required this.caseNumber,
    required this.description,
    required this.status,
    required this.dateLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  caseNumber,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  dateLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppMetaChip(label: status, icon: Icons.timeline_outlined),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  final String title;
  final String responsible;
  final String status;
  final String dueDate;
  final String executionSummary;
  final int executionAttachmentCount;
  final String validationSummary;
  final int validationAttachmentCount;

  const _PlanRow({
    required this.title,
    required this.responsible,
    required this.status,
    required this.dueDate,
    required this.executionSummary,
    required this.executionAttachmentCount,
    required this.validationSummary,
    required this.validationAttachmentCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppMetaChip(label: responsible, icon: Icons.person_outline),
              AppMetaChip(label: status, icon: Icons.flag_outlined),
              AppMetaChip(label: 'Limite $dueDate', icon: Icons.event_outlined),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ejecucion',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  executionSummary,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                AppMetaChip(
                  label: 'Adjuntos: $executionAttachmentCount',
                  icon: Icons.perm_media_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Validacion',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  validationSummary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                AppMetaChip(
                  label: 'Adjuntos: $validationAttachmentCount',
                  icon: Icons.verified_outlined,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopFindingsBlock extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_TopFindingItem> items;

  const _TopFindingsBlock({
    required this.title,
    required this.icon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Text(
              'Sin datos',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            ...items.asMap().entries.map((entry) {
              final index = entry.key + 1;
              final item = entry.value;
              return Padding(
                padding: EdgeInsets.only(bottom: index == items.length ? 0 : 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$index. ${item.label}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 12),
                    AppMetaChip(
                      label: '${item.count}',
                      icon: Icons.bar_chart_outlined,
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onPressed;

  const _EmptyStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 46, color: scheme.primary),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(onPressed: onPressed, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
