
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'login_screen.dart';
import 'incident_management_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Administración'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar Sesión',
            onPressed: () async {
              final bool? shouldLogout = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('Confirmar Cierre de Sesión'),
                    content: const Text('¿Estás seguro de que quieres cerrar sesión?'),
                    actions: <Widget>[
                      TextButton(
                        child: const Text('Cancelar'),
                        onPressed: () {
                          Navigator.of(context).pop(false);
                        },
                      ),
                      TextButton(
                        child: const Text('Confirmar'),
                        onPressed: () {
                          Navigator.of(context).pop(true);
                        },
                      ),
                    ],
                  );
                },
              );

              if (shouldLogout == true) {
                await AuthService().signOut();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => LoginScreen()),
                  (Route<dynamic> route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ListView(
          children: [
            _buildManagementCard(
              context,
              leading: const Icon(Icons.assignment_late),
              title: 'Gestión de Incidentes',
              subtitle: 'Revisar y gestionar reportes',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const IncidentManagementScreen()),
                );
              },
            ),
            _buildManagementCard(
              context,
              leading: const Icon(Icons.checklist),
              title: 'Gestión de Inspecciones',
              subtitle: 'Crear y asignar inspecciones',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const InspectionManagementScreen()),
                );
              },
            ),
            _buildManagementCard(
              context,
              leading: const Icon(Icons.school),
              title: 'Módulo de Capacitaciones',
              subtitle: 'Subir y gestionar videos y guías',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TrainingManagementScreen()),
                );
              },
            ),
            _buildManagementCard(
              context,
              leading: const Icon(Icons.bar_chart),
              title: 'Generar Reportes',
              subtitle: 'Exportar datos para auditorías',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ReportGenerationScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManagementCard(BuildContext context, {required Icon leading, required String title, required String subtitle, required VoidCallback onTap}) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: ListTile(
        leading: leading,
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: onTap,
      ),
    );
  }
}


class InspectionManagementScreen extends StatelessWidget {
  const InspectionManagementScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestión de Inspecciones')),
      body: const Center(child: Text('Pantalla de Gestión de Inspecciones')),
    );
  }
}

class TrainingManagementScreen extends StatelessWidget {
  const TrainingManagementScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Módulo de Capacitaciones')),
      body: const Center(child: Text('Pantalla de Módulo de Capacitaciones')),
    );
  }
}

class ReportGenerationScreen extends StatelessWidget {
  const ReportGenerationScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generar Reportes')),
      body: const Center(child: Text('Pantalla de Generación de Reportes')),
    );
  }
}
