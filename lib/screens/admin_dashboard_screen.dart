import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'incident_management_screen.dart';
import 'training_admin_screen.dart';
import 'invite_employee_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  Future<void> _confirmLogout(BuildContext context) async {
    final bool? shouldLogout = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar cierre de sesion'),
          content: const Text('Estas seguro de que quieres cerrar sesion?'),
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
      if (!context.mounted) {
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Color primary = scheme.primary;
    final Color accent = scheme.secondary;
    final Color background = scheme.surface;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('Panel administrativo'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesion',
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildHeaderCard(theme, primary, accent),
          const SizedBox(height: 20),
          _buildSectionTitle(context, 'Gestion principal'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final int columns = width > 900 ? 3 : 2;
              const double spacing = 12.0;
              final double itemWidth =
                  (width - (columns - 1) * spacing) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _buildManagementTile(
                      context,
                      icon: Icons.assignment_late,
                      title: 'Incidentes',
                      subtitle: 'Revisar y gestionar reportes',
                      color: primary,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const IncidentManagementScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildManagementTile(
                      context,
                      icon: Icons.checklist,
                      title: 'Inspecciones',
                      subtitle: 'Crear y asignar inspecciones',
                      color: accent,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const InspectionManagementScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildManagementTile(
                      context,
                      icon: Icons.school,
                      title: 'Capacitaciones',
                      subtitle: 'Gestion de contenidos',
                      color: scheme.tertiary,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AdminTrainingScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildManagementTile(
                      context,
                      icon: Icons.bar_chart,
                      title: 'Reportes',
                      subtitle: 'Exportar datos para auditorias',
                      color: scheme.primaryContainer,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const ReportGenerationScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildManagementTile(
                      context,
                      icon: Icons.person_add_alt_1,
                      title: 'Invitar Empleados',
                      subtitle: 'Enviar invitaciones por correo',
                      color: scheme.secondary,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const InviteEmployeeScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          _buildSectionTitle(context, 'Resumen operativo'),
          const SizedBox(height: 12),
          _buildInfoCard(
            context,
            icon: Icons.warning_amber_rounded,
            title: 'Incidentes en seguimiento',
            subtitle: 'Revisar reportes recientes y actualizar estados.',
            color: scheme.tertiary,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            context,
            icon: Icons.event_available,
            title: 'Planes de accion',
            subtitle: 'Ver tareas asignadas y fechas limite.',
            color: scheme.secondary,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme, Color primary, Color accent) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.admin_panel_settings_outlined,
                  color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Administracion SG-SST',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Control institucional y seguimiento operativo',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Admin',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
    );
  }

  Widget _buildManagementTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class InspectionManagementScreen extends StatelessWidget {
  const InspectionManagementScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestion de inspecciones')),
      body: const Center(child: Text('Pantalla de gestion de inspecciones')),
    );
  }
}

class TrainingManagementScreen extends StatelessWidget {
  const TrainingManagementScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const AdminTrainingScreen();
  }
}

class ReportGenerationScreen extends StatelessWidget {
  const ReportGenerationScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generar reportes')),
      body: const Center(child: Text('Pantalla de generacion de reportes')),
    );
  }
}
