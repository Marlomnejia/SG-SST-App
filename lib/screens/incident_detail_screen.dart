import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'report_details_screen.dart';

/// Pantalla de compatibilidad para rutas antiguas.
/// Redirige al detalle unificado del reporte.
class IncidentDetailScreen extends StatelessWidget {
  final DocumentSnapshot eventDocument;

  const IncidentDetailScreen({super.key, required this.eventDocument});

  @override
  Widget build(BuildContext context) {
    return ReportDetailsScreen(documentId: eventDocument.id);
  }
}
