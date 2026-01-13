import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import 'capacitaciones_screen.dart';
import 'login_screen.dart';
import 'my_reports_screen.dart';
import 'profile_screen.dart';
import 'report_event_screen.dart';

class UserDashboardScreen extends StatefulWidget {
  const UserDashboardScreen({Key? key}) : super(key: key);

  @override
  _UserDashboardScreenState createState() => _UserDashboardScreenState();
}

class _UserDashboardScreenState extends State<UserDashboardScreen> {
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  Future<void> _confirmLogout() async {
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
      await _authService.signOut();
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
    final Color softSurface = scheme.surface;
    final Color softBorder = scheme.outlineVariant;
    final Color background = scheme.surface;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('Panel personal'),
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesion',
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primary.withOpacity(0.08),
                  scheme.tertiary.withOpacity(0.06),
                  scheme.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: -70,
            right: -40,
            child: _buildGlowCircle(scheme.primary, 140),
          ),
          Positioned(
            bottom: -90,
            left: -40,
            child: _buildGlowCircle(scheme.secondary, 180),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildHeroCard(theme, primary, accent),
                const SizedBox(height: 24),
                _buildSectionTitle(context, 'Accesos principales'),
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
                          child: _buildActionCard(
                            context,
                            icon: Icons.add_circle_outline,
                            title: 'Reportar evento',
                            subtitle: 'Incidente o accidente',
                            color: primary,
                            backgroundColor: softSurface,
                            borderColor: softBorder,
                            isPrimary: true,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ReportEventScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _buildActionCard(
                            context,
                            icon: Icons.school_outlined,
                            title: 'Capacitaciones',
                            subtitle: 'Gestion personal',
                            color: scheme.primary,
                            backgroundColor: softSurface,
                            borderColor: softBorder,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const CapacitacionesScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _buildActionCard(
                            context,
                            icon: Icons.assignment_turned_in_outlined,
                            title: 'Mis reportes',
                            subtitle: 'Seguimiento personal',
                            color: scheme.tertiary,
                            backgroundColor: softSurface,
                            borderColor: softBorder,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const MyReportsScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _buildActionCard(
                            context,
                            icon: Icons.person_outline,
                            title: 'Perfil',
                            subtitle: 'Configuracion de cuenta',
                            color: scheme.primary,
                            backgroundColor: softSurface,
                            borderColor: softBorder,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ProfileScreen(),
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
                _buildSectionTitle(context, 'Resumen personal'),
                const SizedBox(height: 12),
                _buildSummaryTile(
                  context,
                  icon: Icons.warning_amber_rounded,
                  title: 'Mis reportes activos',
                  subtitle: 'Consulta el estado de tus reportes.',
                  color: scheme.secondary,
                  backgroundColor: softSurface,
                  borderColor: softBorder,
                ),
                const SizedBox(height: 12),
                _buildSummaryTile(
                  context,
                  icon: Icons.event_available,
                  title: 'Capacitaciones pendientes',
                  subtitle: 'Revisa tus cursos y fechas limite.',
                  color: scheme.primary,
                  backgroundColor: softSurface,
                  borderColor: softBorder,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(ThemeData theme, Color primary, Color accent) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary.withOpacity(0.9),
            theme.colorScheme.tertiary.withOpacity(0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.2),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeroUserRow(theme),
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

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color backgroundColor,
    required Color borderColor,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
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
                    color: color.withOpacity(isPrimary ? 0.18 : 0.12),
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      isPrimary ? 'Empezar ahora' : 'Abrir',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward, size: 16, color: color),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color backgroundColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
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
          Icon(Icons.chevron_right, color: borderColor),
        ],
      ),
    );
  }

  Widget _buildGlowCircle(Color color, double size) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.18),
      ),
    );
  }

  Widget _buildHeroUserRow(ThemeData theme) {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return _buildHeroUserContent(theme, user, null);
    }

    return StreamBuilder(
      stream: _userService.streamUserProfile(user.uid),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        return _buildHeroUserContent(theme, user, data);
      },
    );
  }

  Widget _buildHeroUserContent(
    ThemeData theme,
    User? user,
    Map<String, dynamic>? data,
  ) {
    final displayName = _resolveDisplayName(data: data, user: user);
    final photoUrl = _resolvePhotoUrl(data: data, user: user);
    final greeting = _greetingForHour(DateTime.now().hour);
    final initials = _initialsFrom(displayName);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ProfileScreen(),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Colors.white24,
              backgroundImage:
                  photoUrl == null || photoUrl.isEmpty ? null : NetworkImage(photoUrl),
              child: photoUrl == null || photoUrl.isEmpty
                  ? Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting,',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'Ver perfil',
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }

  String _greetingForHour(int hour) {
    if (hour < 12) {
      return 'Buenos dias';
    }
    if (hour < 18) {
      return 'Buenas tardes';
    }
    return 'Buenas noches';
  }

  String _resolveDisplayName({
    Map<String, dynamic>? data,
    User? user,
  }) {
    final dataName = data?['displayName'] as String?;
    if (dataName != null && dataName.trim().isNotEmpty) {
      return dataName.trim();
    }
    final authName = user?.displayName;
    if (authName != null && authName.trim().isNotEmpty) {
      return authName.trim();
    }
    final email = user?.email;
    if (email != null && email.contains('@')) {
      return email.split('@').first;
    }
    return 'Usuario';
  }

  String? _resolvePhotoUrl({
    Map<String, dynamic>? data,
    User? user,
  }) {
    final dataUrl = data?['photoUrl'] as String?;
    if (dataUrl != null && dataUrl.trim().isNotEmpty) {
      return dataUrl.trim();
    }
    final authUrl = user?.photoURL;
    if (authUrl != null && authUrl.trim().isNotEmpty) {
      return authUrl.trim();
    }
    return null;
  }

  String _initialsFrom(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.map((p) => p[0]).take(2).join();
    if (letters.isEmpty) {
      return 'U';
    }
    return letters.toUpperCase();
  }
}
