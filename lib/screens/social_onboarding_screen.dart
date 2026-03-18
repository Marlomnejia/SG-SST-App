import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/invitation.dart';
import '../services/auth_service.dart';
import '../services/invitation_service.dart';
import 'register_institution_screen.dart';

/// Datos de usuario social para pasar entre pantallas
class SocialUserData {
  final User user;
  final String displayName;
  final String email;
  final String? photoUrl;
  final SocialAuthProvider provider;

  SocialUserData({
    required this.user,
    required this.displayName,
    required this.email,
    required this.provider,
    this.photoUrl,
  });

  factory SocialUserData.fromException(SocialUserNotRegisteredException e) {
    return SocialUserData(
      user: e.user,
      displayName: e.displayName,
      email: e.email,
      photoUrl: e.photoUrl,
      provider: e.provider,
    );
  }

  String get providerName {
    switch (provider) {
      case SocialAuthProvider.google:
        return 'Google';
      case SocialAuthProvider.microsoft:
        return 'Microsoft';
    }
  }

  IconData get providerIcon {
    switch (provider) {
      case SocialAuthProvider.google:
        return Icons.g_mobiledata;
      case SocialAuthProvider.microsoft:
        return Icons.window;
    }
  }

  Color get providerColor {
    switch (provider) {
      case SocialAuthProvider.google:
        return const Color(0xFFDB4437);
      case SocialAuthProvider.microsoft:
        return const Color(0xFF00A4EF);
    }
  }
}

/// Mantener compatibilidad con código existente
typedef GoogleUserData = SocialUserData;

class SocialOnboardingScreen extends StatefulWidget {
  final SocialUserData socialData;

  const SocialOnboardingScreen({super.key, required this.socialData});

  @override
  State<SocialOnboardingScreen> createState() => _SocialOnboardingScreenState();
}

class _SocialOnboardingScreenState extends State<SocialOnboardingScreen> {
  final _jobTitleController = TextEditingController();
  final _authService = AuthService();
  final _invitationService = InvitationService();

  bool _isLoading = true;
  bool _isJoining = false;
  Invitation? _foundInvitation;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkForInvitation();
  }

  @override
  void dispose() {
    _jobTitleController.dispose();
    super.dispose();
  }

  /// Busca automáticamente una invitación pendiente para el email del usuario
  Future<void> _checkForInvitation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final invitation = await _invitationService.findPendingInvitationByEmail(
        widget.socialData.email,
      );

      setState(() {
        _foundInvitation = invitation;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al buscar invitación: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _joinWithInvitation() async {
    if (_foundInvitation == null) return;

    setState(() => _isJoining = true);

    try {
      await _authService.completeSocialRegistrationWithInvitation(
        socialUser: widget.socialData.user,
        invitation: _foundInvitation!,
        jobTitle: _jobTitleController.text.trim(),
      );

      if (mounted) {
        _showSuccessAndNavigate(
          '¡Bienvenido a ${_foundInvitation!.institutionName ?? "la institución"}!',
          'Tu cuenta de ${widget.socialData.providerName} ha sido vinculada correctamente.',
        );
      }
    } on AuthException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('Error al completar el registro. Intenta de nuevo.');
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  void _navigateToRegisterInstitution() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            RegisterInstitutionScreen(socialUserData: widget.socialData),
      ),
    );
  }

  Future<void> _cancelAndSignOut() async {
    await _authService.signOut();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _showSuccessAndNavigate(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 64),
        title: Text(title),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(context); // Cerrar diálogo
              Navigator.pop(context, true); // Volver al login con éxito
            },
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Completar registro'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: (_isLoading || _isJoining) ? null : _cancelAndSignOut,
        ),
      ),
      body: _isLoading
          ? _buildLoadingState(scheme)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Perfil social
                  _buildSocialProfileCard(scheme),
                  const SizedBox(height: 32),

                  // Mensaje de bienvenida
                  Text(
                    '¡Hola, ${widget.socialData.displayName.split(' ').first}!',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (_errorMessage != null) ...[
                    _buildErrorState(scheme),
                  ] else if (_foundInvitation != null) ...[
                    _buildInvitationFoundState(scheme),
                  ] else ...[
                    _buildNoInvitationState(scheme),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildLoadingState(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            'Buscando invitación...',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            widget.socialData.email,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvitationFoundState(ColorScheme scheme) {
    return Column(
      children: [
        Text(
          '¡Tienes una invitación pendiente!',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        // Tarjeta de invitación encontrada
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              const Icon(Icons.verified, color: Colors.green, size: 48),
              const SizedBox(height: 12),
              Text(
                _foundInvitation!.institutionName ?? 'Institución',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Te ha invitado a unirte',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Campo de cargo opcional
        TextFormField(
          controller: _jobTitleController,
          textCapitalization: TextCapitalization.words,
          enabled: !_isJoining,
          decoration: const InputDecoration(
            labelText: 'Tu cargo (opcional)',
            prefixIcon: Icon(Icons.work_outline),
            hintText: 'Ej: Docente, Auxiliar',
          ),
        ),
        const SizedBox(height: 24),

        // Botón de unirse
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: _isJoining ? null : _joinWithInvitation,
            icon: _isJoining
                ? const SizedBox.shrink()
                : const Icon(Icons.check),
            label: _isJoining
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Unirme a esta institución'),
          ),
        ),
      ],
    );
  }

  Widget _buildNoInvitationState(ColorScheme scheme) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Icon(Icons.mail_outline, size: 48, color: scheme.error),
              const SizedBox(height: 12),
              Text(
                'No tienes invitaciones vigentes',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.error,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'No encontramos invitaciones pendientes para:\n${widget.socialData.email}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        Text(
          '¿Qué deseas hacer?',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),

        // Opción: Registrar nueva institución
        _buildOptionCard(
          scheme: scheme,
          icon: Icons.add_business_rounded,
          iconColor: scheme.tertiary,
          title: 'Registrar nueva institución',
          subtitle: 'Soy el administrador de SG-SST de mi empresa',
          onTap: _navigateToRegisterInstitution,
        ),
        const SizedBox(height: 12),

        // Opción: Cerrar sesión
        _buildOptionCard(
          scheme: scheme,
          icon: Icons.logout,
          iconColor: scheme.error,
          title: 'Cerrar sesión',
          subtitle: 'Volver a intentar con otra cuenta',
          onTap: _cancelAndSignOut,
        ),
        const SizedBox(height: 24),

        // Nota informativa
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Si tu administrador te ha invitado, asegúrate de usar el mismo correo electrónico.',
                  style: TextStyle(fontSize: 13, color: scheme.onSurface),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(ColorScheme scheme) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(Icons.error_outline, size: 48, color: scheme.error),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _checkForInvitation,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      ],
    );
  }

  Widget _buildSocialProfileCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 32,
            backgroundImage: widget.socialData.photoUrl != null
                ? NetworkImage(widget.socialData.photoUrl!)
                : null,
            backgroundColor: scheme.primaryContainer,
            child: widget.socialData.photoUrl == null
                ? Icon(Icons.person, size: 32, color: scheme.onPrimaryContainer)
                : null,
          ),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Provider badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: widget.socialData.providerColor.withValues(
                      alpha: 0.1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.socialData.providerColor.withValues(
                        alpha: 0.3,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildProviderIcon(widget.socialData.provider, 14),
                      const SizedBox(width: 4),
                      Text(
                        widget.socialData.providerName,
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.socialData.providerColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.socialData.displayName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.socialData.email,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderIcon(SocialAuthProvider provider, double size) {
    switch (provider) {
      case SocialAuthProvider.google:
        return Image.asset('assets/google-g.png', width: size, height: size);
      case SocialAuthProvider.microsoft:
        return Image.asset(
          'assets/microsoft-logo.png',
          width: size,
          height: size,
          errorBuilder: (_, __, ___) => Icon(
            Icons.window,
            size: size,
            color: widget.socialData.providerColor,
          ),
        );
    }
  }

  Widget _buildOptionCard({
    required ColorScheme scheme,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: _isJoining ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
