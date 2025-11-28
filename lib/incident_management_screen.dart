
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'incident_detail_screen.dart';

class IncidentManagementScreen extends StatefulWidget {
  const IncidentManagementScreen({super.key});

  @override
  _IncidentManagementScreenState createState() => _IncidentManagementScreenState();
}

class _IncidentManagementScreenState extends State<IncidentManagementScreen> {
  late final Stream<QuerySnapshot> _incidentsStream;

  @override
  void initState() {
    super.initState();
    _incidentsStream = FirebaseFirestore.instance
        .collection('eventos')
        .orderBy('fechaReporte', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Incidentes'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _incidentsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No hay reportes pendientes.'));
          }

          final incidents = snapshot.data!.docs;

          return ListView.builder(
            itemCount: incidents.length,
            itemBuilder: (context, index) {
              final incident = incidents[index];
              final data = incident.data() as Map<String, dynamic>;

              final String tipo = data['tipo'] ?? 'No especificado';
              final String descripcion = data['descripcion'] ?? 'Sin descripción';
              final String reportadoPor = data['reportadoPor_email'] ?? 'Anónimo';
              final Timestamp timestamp = data['fechaReporte'] ?? Timestamp.now();
              final String estado = data['estado'] ?? 'desconocido';
              
              final DateTime fechaReporte = timestamp.toDate();
              final String fechaFormateada = DateFormat('dd/MM/yyyy, hh:mm a').format(fechaReporte);

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: ListTile(
                  leading: Icon(
                    tipo == 'Accidente' ? Icons.warning : Icons.report_problem,
                    color: tipo == 'Accidente' ? Colors.red : Colors.orange,
                  ),
                  title: Text(descripcion, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('$reportadoPor - $fechaFormateada'),
                  trailing: Chip(
                    label: Text(
                      estado,
                      style: const TextStyle(color: Colors.white),
                    ),
                    backgroundColor: _getStatusColor(estado),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => IncidentDetailScreen(eventDocument: incident),
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

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'reportado':
        return Colors.blue;
      case 'en revisión':
        return Colors.orange;
      case 'resuelto':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}

