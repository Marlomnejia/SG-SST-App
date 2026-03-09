import 'package:flutter/material.dart';

class ReportIncidentScreen extends StatelessWidget {
  const ReportIncidentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reportar Incidente')),
      body: const Center(child: Text('Pantalla para reportar incidentes.')),
    );
  }
}
