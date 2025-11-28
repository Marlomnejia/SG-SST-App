import 'package:flutter/material.dart';

class CapacitacionesScreen extends StatelessWidget {
  const CapacitacionesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Capacitaciones'),
      ),
      body: const Center(
        child: Text('Pantalla de capacitaciones.'),
      ),
    );
  }
}