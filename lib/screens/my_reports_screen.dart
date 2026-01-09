import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'report_details_screen.dart'; // Import the details screen

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({Key? key}) : super(key: key);

  @override
  _MyReportsScreenState createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  late Stream<QuerySnapshot> _reportsStream;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _userId = FirebaseAuth.instance.currentUser?.uid;

    if (_userId != null) {
      _reportsStream = FirebaseFirestore.instance
          .collection('eventos')
          .where('reportadoPor_uid', isEqualTo: _userId)
          .orderBy('fechaReporte', descending: true)
          .snapshots();
    }
  }

  Color _getStatusColor(String status, ColorScheme scheme) {
    switch (status.toLowerCase()) {
      case 'en revisión':
        return scheme.primaryContainer;
      case 'solucionado':
        return scheme.secondaryContainer;
      case 'reportado':
      default:
        return scheme.surfaceVariant;
    }
  }

  Color _getStatusTextColor(String status, ColorScheme scheme) {
    switch (status.toLowerCase()) {
      case 'en revisiИn':
        return scheme.onPrimaryContainer;
      case 'solucionado':
        return scheme.onSecondaryContainer;
      case 'reportado':
      default:
        return scheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Reportes Enviados'),
      ),
      body: _userId == null
          ? const Center(child: Text('No se pudo identificar al usuario.'))
          : StreamBuilder<QuerySnapshot>(
              stream: _reportsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('Error al cargar los reportes.'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('Aún no has enviado reportes.'),
                  );
                }

                final reports = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: reports.length,
                  itemBuilder: (context, index) {
                    final report = reports[index];
                    final data = report.data() as Map<String, dynamic>;
                    final tipo = data['tipo'] ?? 'Incidente';
                    final descripcion = data['descripcion'] ?? 'Sin descripción';
                    final estado = data['estado'] ?? 'Desconocido';

                    DateTime? fecha;
                    final fechaData = data['fechaReporte'];
                    if (fechaData is Timestamp) {
                      fecha = fechaData.toDate();
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        leading: Icon(
                          tipo == 'Accidente' ? Icons.warning : Icons.report_problem,
                          color: tipo == 'Accidente' ? scheme.error : scheme.tertiary,
                          size: 40,
                        ),
                        title: Text(
                          descripcion,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          fecha != null
                              ? DateFormat('dd/MM/yyyy, hh:mm a').format(fecha)
                              : 'Fecha no disponible',
                        ),
                        trailing: Chip(
                          label: Text(
                            estado,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _getStatusTextColor(estado, scheme),
                            ),
                          ),
                          backgroundColor: _getStatusColor(estado, scheme),
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ReportDetailsScreen(documentId: report.id),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
