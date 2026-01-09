import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../services/training_service.dart';
import 'training_detail_screen.dart';

class CapacitacionesScreen extends StatefulWidget {
  const CapacitacionesScreen({Key? key}) : super(key: key);

  @override
  State<CapacitacionesScreen> createState() => _CapacitacionesScreenState();
}

class _CapacitacionesScreenState extends State<CapacitacionesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TrainingService _trainingService = TrainingService();

  String _statusFilter = 'all';
  String _catalogCategory = 'all';
  String _catalogType = 'all';
  String _catalogDuration = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _trainingService.streamAllTrainings(),
      builder: (context, snapshot) {
        final List<QueryDocumentSnapshot> trainings = snapshot.data?.docs ?? [];
        final Map<String, Map<String, dynamic>> trainingMap = {
          for (final doc in trainings)
            doc.id: doc.data() as Map<String, dynamic>
        };
        final List<QueryDocumentSnapshot> publishedTrainings = trainings
            .where((doc) =>
                (doc.data() as Map<String, dynamic>)['published'] == true)
            .toList();

        final Set<String> categories = {'all'};
        for (final doc in trainings) {
          final data = doc.data() as Map<String, dynamic>;
          final String? category = data['category'] as String?;
          if (category != null && category.trim().isNotEmpty) {
            categories.add(category);
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Capacitaciones'),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Mis capacitaciones'),
                Tab(text: 'Catalogo'),
                Tab(text: 'Certificados'),
                Tab(text: 'Historial'),
              ],
              isScrollable: true,
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildAssignedTrainings(trainingMap),
              _buildCatalog(publishedTrainings, categories.toList()..sort()),
              _buildCertificates(trainingMap),
              _buildHistory(trainingMap),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAssignedTrainings(Map<String, Map<String, dynamic>> trainingMap) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('No hay usuario autenticado.'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _trainingService.streamAssignmentsForUser(user.uid),
      builder: (context, assignmentSnapshot) {
        if (assignmentSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!assignmentSnapshot.hasData || assignmentSnapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No tienes capacitaciones asignadas.'));
        }

        final assignments = assignmentSnapshot.data!.docs;
        final Map<String, Timestamp?> dueDates = {};
        final Set<String> assignedTrainingIds = {};
        for (final assignment in assignments) {
          final data = assignment.data() as Map<String, dynamic>;
          final String? trainingId = data['trainingId'];
          if (trainingId == null) continue;
          assignedTrainingIds.add(trainingId);
          dueDates[trainingId] = data['dueDate'] as Timestamp?;
        }

        final List<MapEntry<String, Map<String, dynamic>>> assignedTrainings =
            assignedTrainingIds
                .where((id) => trainingMap.containsKey(id))
                .map((id) => MapEntry(id, trainingMap[id]!))
                .toList();

        return StreamBuilder<QuerySnapshot>(
          stream: _trainingService.streamAttemptsForUser(user.uid),
          builder: (context, attemptSnapshot) {
            final Map<String, Map<String, dynamic>> latestAttempt = {};
            if (attemptSnapshot.hasData) {
              for (final doc in attemptSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final String trainingId = data['trainingId'] ?? '';
                if (trainingId.isEmpty) continue;
                final Timestamp? completedAt = data['completedAt'] as Timestamp?;
                final Timestamp? current =
                    latestAttempt[trainingId]?['completedAt'] as Timestamp?;
                if (current == null ||
                    (completedAt != null && completedAt.compareTo(current) > 0)) {
                  latestAttempt[trainingId] = data;
                }
              }
            }

            return StreamBuilder<QuerySnapshot>(
              stream: _trainingService.streamCertificatesForUser(user.uid),
              builder: (context, certSnapshot) {
                final Map<String, Timestamp?> latestCertificate = {};
                if (certSnapshot.hasData) {
                  for (final doc in certSnapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final String trainingId = data['trainingId'] ?? '';
                    final Timestamp? issuedAt = data['issuedAt'] as Timestamp?;
                    if (trainingId.isEmpty || issuedAt == null) continue;
                    final Timestamp? current = latestCertificate[trainingId];
                    if (current == null || issuedAt.compareTo(current) > 0) {
                      latestCertificate[trainingId] = issuedAt;
                    }
                  }
                }

                final List<_TrainingListItem> items = [];
                for (final entry in assignedTrainings) {
                  final String trainingId = entry.key;
                  final data = entry.value;
                  final String title = data['title'] ?? 'Capacitacion';
                  final String type = data['mandatory'] == true
                      ? 'Obligatoria'
                      : 'Opcional';
                  final int duration = data['durationMinutes'] ?? 0;
                  final int validityMonths = data['validityMonths'] ?? 12;
                  final Timestamp? dueDate = dueDates[trainingId];

                  final Timestamp? issuedAt = latestCertificate[trainingId];
                  final bool isExpired =
                      _isExpired(issuedAt, validityMonths);
                  final bool isCompleted = issuedAt != null && !isExpired;

                  final bool isOverdue = dueDate != null &&
                      dueDate.toDate().isBefore(DateTime.now()) &&
                      !isCompleted;

                  final Map<String, dynamic>? attempt = latestAttempt[trainingId];
                  final bool hasAttempt = attempt != null;

                  String status = 'Pendiente';
                  if (isExpired) {
                    status = 'Vencida';
                  } else if (isCompleted) {
                    status = 'Completada';
                  } else if (isOverdue) {
                    status = 'Vencida';
                  } else if (hasAttempt) {
                    status = 'En curso';
                  }

                  if (_statusFilter != 'all' && _statusFilter != status) {
                    continue;
                  }

                  int progress = 0;
                  if (isCompleted) {
                    progress = 100;
                  } else if (hasAttempt && !isExpired) {
                    progress = 50;
                  }

                  final String actionLabel = isCompleted || isExpired
                      ? 'Repetir'
                      : hasAttempt
                          ? 'Continuar'
                          : 'Iniciar';

                  items.add(
                    _TrainingListItem(
                      trainingId: trainingId,
                      title: title,
                      type: type,
                      duration: duration,
                      status: status,
                      progress: progress,
                      actionLabel: actionLabel,
                      data: data,
                    ),
                  );
                }

                if (items.isEmpty) {
                  return const Center(child: Text('Sin resultados.'));
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildStatusFilters(),
                    const SizedBox(height: 12),
                    ...items.map(
                      (item) => _TrainingCard(
                        title: item.title,
                        type: item.type,
                        duration: item.duration,
                        status: item.status,
                        progress: item.progress,
                        actionLabel: item.actionLabel,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TrainingDetailScreen(
                                trainingId: item.trainingId,
                                data: item.data,
                              ),
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
    );
  }

  Widget _buildCatalog(
    List<QueryDocumentSnapshot> trainings,
    List<String> categories,
  ) {
    final List<QueryDocumentSnapshot> filtered = trainings.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final String category = data['category'] ?? 'General';
      final String type = data['contentType'] ?? 'text';
      final int duration = data['durationMinutes'] ?? 0;

      if (_catalogCategory != 'all' && category != _catalogCategory) {
        return false;
      }
      if (_catalogType != 'all' && type != _catalogType) {
        return false;
      }
      if (_catalogDuration == 'short' && duration > 10) {
        return false;
      }
      if (_catalogDuration == 'medium' && (duration <= 10 || duration > 20)) {
        return false;
      }
      if (_catalogDuration == 'long' && duration <= 20) {
        return false;
      }

      return true;
    }).toList();

    if (trainings.isEmpty) {
      return const Center(child: Text('No hay capacitaciones publicadas.'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCatalogFilters(categories),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(child: Text('No hay resultados.')),
          )
        else
          ...filtered.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final String title = data['title'] ?? 'Capacitacion';
            final String category = data['category'] ?? 'General';
            final int duration = data['durationMinutes'] ?? 0;
            final String contentType = data['contentType'] ?? 'text';

            return _CatalogCard(
              title: title,
              category: category,
              duration: duration,
              contentType: contentType,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TrainingDetailScreen(
                      trainingId: doc.id,
                      data: data,
                    ),
                  ),
                );
              },
            );
          }),
      ],
    );
  }

  Widget _buildCertificates(Map<String, Map<String, dynamic>> trainingMap) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('No hay usuario autenticado.'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _trainingService.streamCertificatesForUser(user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No tienes certificados.'));
        }

        final certificates = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: certificates.length,
          itemBuilder: (context, index) {
            final data = certificates[index].data() as Map<String, dynamic>;
            final String trainingId = data['trainingId'] ?? '';
            final String version = data['version'] ?? 'v1';
            final Timestamp? issuedAt = data['issuedAt'] as Timestamp?;
            final String title =
                trainingMap[trainingId]?['title'] ?? 'Capacitacion';
            final int validityMonths =
                trainingMap[trainingId]?['validityMonths'] ?? 12;
            final bool expired = _isExpired(issuedAt, validityMonths);

            return Card(
              child: ListTile(
                title: Text(title),
                subtitle: Text(
                  'Version: $version | Fecha: ${_formatDateTime(issuedAt)} | '
                  '${expired ? 'Vencido' : 'Vigente'}',
                ),
                trailing: const Icon(Icons.download),
                onTap: () {
                  _showCertificateActions(
                    trainingTitle: title,
                    version: version,
                    issuedAt: issuedAt,
                    score: data['score'] ?? 0,
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHistory(Map<String, Map<String, dynamic>> trainingMap) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('No hay usuario autenticado.'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _trainingService.streamAttemptsForUser(user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No hay historial.'));
        }

        final attempts = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: attempts.length,
          itemBuilder: (context, index) {
            final data = attempts[index].data() as Map<String, dynamic>;
            final String trainingId = data['trainingId'] ?? '';
            final int score = data['score'] ?? 0;
            final bool passed = data['passed'] == true;
            final Timestamp? completedAt = data['completedAt'] as Timestamp?;
            final String title =
                trainingMap[trainingId]?['title'] ?? 'Capacitacion';

            return Card(
              child: ListTile(
                title: Text(title),
                subtitle: Text(
                  'Resultado: ${passed ? 'Aprobado' : 'Reprobado'} | Nota: $score%',
                ),
                trailing: Text(_formatDateTime(completedAt)),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusFilters() {
    final List<String> filters = [
      'all',
      'Pendiente',
      'En curso',
      'Completada',
      'Vencida',
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: filters.map((filter) {
        final bool selected = _statusFilter == filter;
        final String label = filter == 'all' ? 'Todas' : filter;
        return ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) {
            setState(() {
              _statusFilter = filter;
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildCatalogFilters(List<String> categories) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                value: _catalogCategory,
                decoration: const InputDecoration(labelText: 'Riesgo'),
                items: categories
                    .map((category) => DropdownMenuItem(
                          value: category,
                          child: Text(category == 'all' ? 'Todos' : category),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _catalogCategory = value;
                    });
                  }
                },
              ),
            ),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                value: _catalogType,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Todos')),
                  DropdownMenuItem(value: 'video', child: Text('Video')),
                  DropdownMenuItem(value: 'text', child: Text('Lectura')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _catalogType = value;
                    });
                  }
                },
              ),
            ),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                value: _catalogDuration,
                decoration: const InputDecoration(labelText: 'Duracion'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Todas')),
                  DropdownMenuItem(value: 'short', child: Text('<= 10 min')),
                  DropdownMenuItem(value: 'medium', child: Text('11-20 min')),
                  DropdownMenuItem(value: 'long', child: Text('> 20 min')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _catalogDuration = value;
                    });
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDateTime(Timestamp? timestamp) {
    if (timestamp == null) {
      return 'No disponible';
    }
    return DateFormat('dd/MM/yyyy').format(timestamp.toDate());
  }

  Future<void> _shareCertificate({
    required String trainingTitle,
    required String version,
    required Timestamp? issuedAt,
    required int score,
  }) async {
    final file = await _buildCertificatePdf(
      trainingTitle: trainingTitle,
      version: version,
      issuedAt: issuedAt,
      score: score,
    );

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Certificado SST - $trainingTitle',
    );
  }

  Future<void> _previewCertificate({
    required String trainingTitle,
    required String version,
    required Timestamp? issuedAt,
    required int score,
  }) async {
    final file = await _buildCertificatePdf(
      trainingTitle: trainingTitle,
      version: version,
      issuedAt: issuedAt,
      score: score,
    );
    await OpenFilex.open(file.path);
  }

  Future<File> _buildCertificatePdf({
    required String trainingTitle,
    required String version,
    required Timestamp? issuedAt,
    required int score,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final String date = issuedAt != null
        ? DateFormat('dd/MM/yyyy').format(issuedAt.toDate())
        : 'No disponible';

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(32),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Certificado de Capacitacion',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Text('Programa: $trainingTitle'),
                pw.Text('Version: $version'),
                pw.Text('Fecha: $date'),
                pw.Text('Participante: ${user?.email ?? 'Usuario'}'),
                pw.Text('Resultado: $score%'),
                pw.SizedBox(height: 24),
                pw.Text(
                  'Este certificado acredita la participacion y aprobacion '
                  'de la capacitacion en el sistema SST.',
                ),
              ],
            ),
          );
        },
      ),
    );

    final directory = await getTemporaryDirectory();
    final safeTitle = trainingTitle.replaceAll(' ', '_');
    final file = File('${directory.path}/certificado_${safeTitle}_$version.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  Future<void> _showCertificateActions({
    required String trainingTitle,
    required String version,
    required Timestamp? issuedAt,
    required int score,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('Vista previa'),
                onTap: () async {
                  Navigator.pop(context);
                  await _previewCertificate(
                    trainingTitle: trainingTitle,
                    version: version,
                    issuedAt: issuedAt,
                    score: score,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Compartir'),
                onTap: () async {
                  Navigator.pop(context);
                  await _shareCertificate(
                    trainingTitle: trainingTitle,
                    version: version,
                    issuedAt: issuedAt,
                    score: score,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  bool _isExpired(Timestamp? issuedAt, int validityMonths) {
    if (issuedAt == null) {
      return false;
    }
    final DateTime issuedDate = issuedAt.toDate();
    final DateTime expiresAt = _addMonths(issuedDate, validityMonths);
    return DateTime.now().isAfter(expiresAt);
  }

  DateTime _addMonths(DateTime date, int months) {
    final int year = date.year + ((date.month - 1 + months) ~/ 12);
    final int month = (date.month - 1 + months) % 12 + 1;
    final int day = date.day;
    final int lastDayOfMonth = DateTime(year, month + 1, 0).day;
    return DateTime(
      year,
      month,
      day > lastDayOfMonth ? lastDayOfMonth : day,
      date.hour,
      date.minute,
      date.second,
    );
  }
}

class _TrainingListItem {
  final String trainingId;
  final String title;
  final String type;
  final int duration;
  final String status;
  final int progress;
  final String actionLabel;
  final Map<String, dynamic> data;

  const _TrainingListItem({
    required this.trainingId,
    required this.title,
    required this.type,
    required this.duration,
    required this.status,
    required this.progress,
    required this.actionLabel,
    required this.data,
  });
}

class _TrainingCard extends StatelessWidget {
  final String title;
  final String type;
  final int duration;
  final String status;
  final int progress;
  final String actionLabel;
  final VoidCallback onTap;

  const _TrainingCard({
    required this.title,
    required this.type,
    required this.duration,
    required this.status,
    required this.progress,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(title),
        subtitle: Text('$type | $duration min | $status'),
        trailing: SizedBox(
          width: 92,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$progress%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                actionLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _CatalogCard extends StatelessWidget {
  final String title;
  final String category;
  final int duration;
  final String contentType;
  final VoidCallback onTap;

  const _CatalogCard({
    required this.title,
    required this.category,
    required this.duration,
    required this.contentType,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(title),
        subtitle: Text('$category | ${contentType.toUpperCase()} | $duration min'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
