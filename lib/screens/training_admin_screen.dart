import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/training_service.dart';
import 'training_form_screen.dart';

class AdminTrainingScreen extends StatefulWidget {
  const AdminTrainingScreen({super.key});

  @override
  State<AdminTrainingScreen> createState() => _AdminTrainingScreenState();
}

class _AdminTrainingScreenState extends State<AdminTrainingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TrainingService _trainingService = TrainingService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion de capacitaciones'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Capacitaciones'),
            Tab(text: 'Asignaciones'),
            Tab(text: 'Reportes'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTrainingsTab(),
          _buildAssignmentsTab(),
          _buildReportsTab(),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TrainingFormScreen(),
                  ),
                );
                if (result == true && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Capacitacion guardada.')),
                  );
                }
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildTrainingsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _trainingService.streamAllTrainings(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No hay capacitaciones registradas.'));
        }

        final trainings = snapshot.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: trainings.length,
          itemBuilder: (context, index) {
            final doc = trainings[index];
            final data = doc.data() as Map<String, dynamic>;
            final String title = data['title'] ?? 'Capacitacion';
            final String category = data['category'] ?? 'General';
            final bool published = data['published'] ?? false;

            return Card(
              child: ListTile(
                title: Text(title),
                subtitle: Text('$category | ${published ? 'Publicada' : 'Borrador'}'),
                trailing: const Icon(Icons.edit),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TrainingFormScreen(
                        trainingId: doc.id,
                        data: data,
                      ),
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

  Widget _buildAssignmentsTab() {
    return _AssignmentForm(trainingService: _trainingService);
  }

  Widget _buildReportsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('trainingAttempts').snapshots(),
      builder: (context, attemptsSnapshot) {
        if (attemptsSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final Map<String, int> attemptsCount = {};
        final Map<String, int> passedCount = {};
        if (attemptsSnapshot.hasData) {
          for (final doc in attemptsSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final String trainingId = data['trainingId'] ?? '';
            final bool passed = data['passed'] == true;
            if (trainingId.isNotEmpty) {
              attemptsCount[trainingId] = (attemptsCount[trainingId] ?? 0) + 1;
              if (passed) {
                passedCount[trainingId] = (passedCount[trainingId] ?? 0) + 1;
              }
            }
          }
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('certificates').snapshots(),
          builder: (context, certSnapshot) {
            if (certSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final Map<String, int> certificatesCount = {};
            if (certSnapshot.hasData) {
              for (final doc in certSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final String trainingId = data['trainingId'] ?? '';
                if (trainingId.isNotEmpty) {
                  certificatesCount[trainingId] =
                      (certificatesCount[trainingId] ?? 0) + 1;
                }
              }
            }

            return StreamBuilder<QuerySnapshot>(
              stream: _trainingService.streamAllTrainings(),
              builder: (context, trainingSnapshot) {
                if (trainingSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!trainingSnapshot.hasData || trainingSnapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No hay datos para reportes.'));
                }

                final trainings = trainingSnapshot.data!.docs;
                final List<Widget> cards = [];
                for (final doc in trainings) {
                  final data = doc.data() as Map<String, dynamic>;
                  final String title = data['title'] ?? 'Capacitacion';
                  final int totalAttempts = attemptsCount[doc.id] ?? 0;
                  final int totalPassed = passedCount[doc.id] ?? 0;
                  final int totalCerts = certificatesCount[doc.id] ?? 0;
                  final int validityMonths = data['validityMonths'] ?? 12;

                  final int expired = _countExpiredCertificates(
                    certSnapshot.data?.docs ?? [],
                    doc.id,
                    validityMonths,
                  );
                  final int passRate = totalAttempts == 0
                      ? 0
                      : ((totalPassed / totalAttempts) * 100).round();

                  cards.add(
                    Card(
                      child: ListTile(
                        title: Text(title),
                        subtitle: Text(
                          'Intentos: $totalAttempts | Aprobados: $totalPassed | '
                          'Exito: $passRate% | Certificados: $totalCerts | Vencidos: $expired',
                        ),
                      ),
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _exportReportCsv(
                        trainings,
                        certSnapshot.data?.docs ?? [],
                        attemptsCount,
                        passedCount,
                        certificatesCount,
                      ),
                      icon: const Icon(Icons.download),
                      label: const Text('Exportar reporte CSV'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _exportDetailedCsv(
                        trainings,
                        certSnapshot.data?.docs ?? [],
                        attemptsSnapshot.data?.docs ?? [],
                      ),
                      icon: const Icon(Icons.table_view),
                      label: const Text('Exportar detalle CSV'),
                    ),
                    const SizedBox(height: 12),
                    ...cards,
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

Future<void> _exportReportCsv(
  List<QueryDocumentSnapshot> trainings,
  List<QueryDocumentSnapshot> certificates,
  Map<String, int> attemptsCount,
  Map<String, int> passedCount,
  Map<String, int> certificatesCount,
) async {
  final List<List<dynamic>> rows = [
    [
      'Training ID',
      'Titulo',
      'Categoria',
      'Intentos',
      'Aprobados',
      'Exito (%)',
      'Certificados',
      'Vencidos',
    ],
  ];

  for (final doc in trainings) {
    final data = doc.data() as Map<String, dynamic>;
    final String title = data['title'] ?? 'Capacitacion';
    final String category = data['category'] ?? 'General';
    final int totalAttempts = attemptsCount[doc.id] ?? 0;
    final int totalPassed = passedCount[doc.id] ?? 0;
    final int totalCerts = certificatesCount[doc.id] ?? 0;
    final int validityMonths = data['validityMonths'] ?? 12;
    final int expired =
        _countExpiredCertificates(certificates, doc.id, validityMonths);
    final int passRate =
        totalAttempts == 0 ? 0 : ((totalPassed / totalAttempts) * 100).round();

    rows.add([
      doc.id,
      title,
      category,
      totalAttempts,
      totalPassed,
      passRate,
      totalCerts,
      expired,
    ]);
  }

  final csv = const ListToCsvConverter().convert(rows);
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/reporte_capacitaciones.csv');
  await file.writeAsString(csv);

  await Share.shareXFiles(
    [XFile(file.path)],
    text: 'Reporte de capacitaciones',
  );
}

Future<void> _exportDetailedCsv(
  List<QueryDocumentSnapshot> trainings,
  List<QueryDocumentSnapshot> certificates,
  List<QueryDocumentSnapshot> attempts,
) async {
  final Map<String, Map<String, dynamic>> trainingMap = {
    for (final doc in trainings) doc.id: doc.data() as Map<String, dynamic>
  };

  final Set<String> userIds = {};
  for (final doc in certificates) {
    final data = doc.data() as Map<String, dynamic>;
    final String userId = data['userId'] ?? '';
    if (userId.isNotEmpty) userIds.add(userId);
  }
  for (final doc in attempts) {
    final data = doc.data() as Map<String, dynamic>;
    final String userId = data['userId'] ?? '';
    if (userId.isNotEmpty) userIds.add(userId);
  }

  final Map<String, String> userEmails =
      await _fetchUserEmails(userIds.toList());

  final List<List<dynamic>> rows = [
    [
      'Tipo',
      'Training ID',
      'Titulo',
      'Usuario UID',
      'Usuario Email',
      'Fecha',
      'Score',
      'Aprobado',
      'Version',
    ],
  ];

  for (final doc in certificates) {
    final data = doc.data() as Map<String, dynamic>;
    final String trainingId = data['trainingId'] ?? '';
    final String userId = data['userId'] ?? '';
    final String title = trainingMap[trainingId]?['title'] ?? 'Capacitacion';
    final Timestamp? issuedAt = data['issuedAt'] as Timestamp?;
    rows.add([
      'certificado',
      trainingId,
      title,
      userId,
      userEmails[userId] ?? userId,
      issuedAt != null ? issuedAt.toDate().toIso8601String() : '',
      data['score'] ?? '',
      true,
      data['version'] ?? '',
    ]);
  }

  for (final doc in attempts) {
    final data = doc.data() as Map<String, dynamic>;
    final String trainingId = data['trainingId'] ?? '';
    final String userId = data['userId'] ?? '';
    final String title = trainingMap[trainingId]?['title'] ?? 'Capacitacion';
    final Timestamp? completedAt = data['completedAt'] as Timestamp?;
    rows.add([
      'intento',
      trainingId,
      title,
      userId,
      userEmails[userId] ?? userId,
      completedAt != null ? completedAt.toDate().toIso8601String() : '',
      data['score'] ?? '',
      data['passed'] ?? '',
      data['version'] ?? '',
    ]);
  }

  final csv = const ListToCsvConverter().convert(rows);
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/reporte_capacitaciones_detalle.csv');
  await file.writeAsString(csv);

  await Share.shareXFiles(
    [XFile(file.path)],
    text: 'Detalle de capacitaciones',
  );
}

Future<Map<String, String>> _fetchUserEmails(List<String> userIds) async {
  if (userIds.isEmpty) {
    return {};
  }
  final Map<String, String> results = {};
  const int chunkSize = 10;
  for (int i = 0; i < userIds.length; i += chunkSize) {
    final chunk = userIds.sublist(
      i,
      i + chunkSize > userIds.length ? userIds.length : i + chunkSize,
    );
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where(FieldPath.documentId, whereIn: chunk)
        .get();
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final String email = data['email'] ?? '';
      if (email.isNotEmpty) {
        results[doc.id] = email;
      }
    }
  }
  return results;
}

int _countExpiredCertificates(
  List<QueryDocumentSnapshot> certificates,
  String trainingId,
  int validityMonths,
) {
  int count = 0;
  for (final doc in certificates) {
    final data = doc.data() as Map<String, dynamic>;
    if (data['trainingId'] != trainingId) continue;
    final Timestamp? issuedAt = data['issuedAt'] as Timestamp?;
    if (issuedAt == null) continue;
    final DateTime expiresAt = _addMonths(issuedAt.toDate(), validityMonths);
    if (DateTime.now().isAfter(expiresAt)) {
      count++;
    }
  }
  return count;
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

class _AssignmentForm extends StatefulWidget {
  final TrainingService trainingService;

  const _AssignmentForm({required this.trainingService});

  @override
  State<_AssignmentForm> createState() => _AssignmentFormState();
}

class _AssignmentFormState extends State<_AssignmentForm> {
  String? _trainingId;
  String _target = 'all';
  DateTime? _dueDate;
  final _userIdController = TextEditingController();
  bool _isSaving = false;
  bool _autoReassign = false;

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) {
      setState(() {
        _dueDate = picked;
      });
    }
  }

  Future<void> _assign() async {
    if (_trainingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una capacitacion.')),
      );
      return;
    }
    if (_target == 'user' && _userIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa el UID del usuario.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await widget.trainingService.assignTraining(
        trainingId: _trainingId!,
        target: _target == 'all' ? 'all' : _userIdController.text.trim(),
        dueDate: _dueDate,
        autoReassign: _autoReassign,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Asignacion creada.')),
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: widget.trainingService.streamAllTrainings(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final trainings = snapshot.data?.docs ?? [];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              value: _trainingId,
              decoration: const InputDecoration(labelText: 'Capacitacion'),
              items: trainings
                  .map((doc) => DropdownMenuItem(
                        value: doc.id,
                        child: Text((doc.data() as Map<String, dynamic>)['title'] ?? 'Capacitacion'),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _trainingId = value;
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _target,
              decoration: const InputDecoration(labelText: 'Asignar a'),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Todos')),
                DropdownMenuItem(value: 'user', child: Text('Usuario (UID)')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _target = value;
                  });
                }
              },
            ),
            if (_target == 'user') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _userIdController,
                decoration: const InputDecoration(labelText: 'UID del usuario'),
              ),
            ],
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fecha limite (opcional)'),
              subtitle: Text(
                _dueDate == null
                    ? 'Sin fecha'
                    : '${_dueDate!.day.toString().padLeft(2, '0')}/'
                        '${_dueDate!.month.toString().padLeft(2, '0')}/'
                        '${_dueDate!.year}',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDueDate,
            ),
            SwitchListTile(
              value: _autoReassign,
              onChanged: (value) {
                setState(() {
                  _autoReassign = value;
                });
              },
              title: const Text('Reasignar automaticamente si vence'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isSaving ? null : _assign,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(),
                    )
                  : const Text('Asignar capacitacion'),
            ),
          ],
        );
      },
    );
  }
}
