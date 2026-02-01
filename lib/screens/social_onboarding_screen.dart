import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/institution_service.dart';
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

  const SocialOnboardingScreen({
    super.key,
    required this.socialData,
  });

  @override
  State<SocialOnboardingScreen> createState() => _SocialOnboardingScreenState();
}

class _SocialOnboardingScreenState extends State<SocialOnboardingScreen> {
  final _inviteCodeController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _authService = AuthService();
  final _institutionService = InstitutionService();

  bool _isLoading = false;
  bool _showJoinForm = false;
  InstitutionValidationResult? _validatedInstitution;
  String? _codeError;

  @override
  void dispose() {
    _inviteCodeController.dispose();
    _jobTitleController.dispose();
    super.dispose();
  }

  Future<void> _validateInviteCode() async {
    final code = _inviteCodeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _codeError = 'Ingresa el código de invitación.';
        _validatedInstitution = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _codeError = null;
    });

    try {
      final result = await _institutionService.validateInviteCode(code);
      setState(() {
        _validatedInstitution = result;
        _codeError = null;
      });
    } on InviteCodeException catch (e) {
      setState(() {
        _validatedInstitution = null;
        _codeError = e.message;
      });
    } catch (e) {
      setState(() {
        _validatedInstitution = null;
        _codeError = 'Error al validar el código.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _joinInstitution() async {
    if (_validatedInstitution == null) {
      await _validateInviteCode();
      if (_validatedInstitution == null) return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.completeSocialRegistrationWithInviteCode(
        socialUser: widget.socialData.user,
        inviteCode: _inviteCodeController.text.trim(),
        jobTitle: _jobTitleController.text.trim(),
      );

      if (mounted) {
        _showSuccessAndNavigate(
          '¡Bienvenido a ${_validatedInstitution!.institutionName}!',
          'Tu cuenta de ${widget.socialData.providerName} ha sido vinculada correctamente.',
        );
      }
    } on AuthException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('Error al completar el registro. Intenta de nuevo.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToRegisterInstitution() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => RegisterInstitutionScreen(
          socialUserData: widget.socialData,
        ),
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
        icon: const Icon(
          Icons.check_circle,
          color: Colors.green,
          size: 64,
        ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Completar registro'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _isLoading ? null : _cancelAndSignOut,
        ),
      ),
      body: SingleChildScrollView(
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
            Text(
              'Te has autenticado con ${widget.socialData.providerName}.\n¿Cómo deseas continuar?',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Opciones
            if (!_showJoinForm) ...[
              _buildOptionCard(
                scheme: scheme,
                icon: Icons.vpn_key_rounded,
                iconColor: scheme.primary,
                title: 'Unirme a una institución',
                subtitle: 'Tengo un código de invitación de mi empresa',
                onTap: () {
                  setState(() {
                    _showJoinForm = true;
                  });
                },
              ),
              const SizedBox(height: 16),
              _buildOptionCard(
                scheme: scheme,
                icon: Icons.add_business_rounded,
                iconColor: scheme.tertiary,
                title: 'Registrar nueva institución',
                subtitle: 'Soy el administrador de SG-SST de mi empresa',
                onTap: _navigateToRegisterInstitution,
              ),
            ] else ...[
              _buildJoinForm(scheme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSocialProfileCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.5),
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
                ? Icon(
                    Icons.person,
                    size: 32,
                    color: scheme.onPrimaryContainer,
                  )
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
                    color: widget.socialData.providerColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.socialData.providerColor.withOpacity(0.3),
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
        return Image.asset(
          'assets/google-g.png',
          width: size,
          height: size,
        );
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
        onTap: _isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
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

  Widget _buildJoinForm(ColorScheme scheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                IconButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          setState(() {
                            _showJoinForm = false;
                            _validatedInstitution = null;
                            _codeError = null;
                            _inviteCodeController.clear();
                          });
                        },
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    'Unirme a institución',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Campo de código
            TextFormField(
              controller: _inviteCodeController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              enabled: !_isLoading,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                _UpperCaseTextFormatter(),
              ],
              decoration: InputDecoration(
                labelText: 'Código de invitación',
                prefixIcon: const Icon(Icons.vpn_key_outlined),
                counterText: '',
                hintText: 'ABC123',
                errorText: _codeError,
                suffixIcon: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: Icon(
                          _validatedInstitution != null
                              ? Icons.check_circle
                              : Icons.search,
                          color: _validatedInstitution != null
                              ? Colors.green
                              : scheme.primary,
                        ),
                        onPressed: _validateInviteCode,
                      ),
              ),
              onChanged: (_) {
                if (_validatedInstitution != null || _codeError != null) {
                  setState(() {
                    _validatedInstitution = null;
                    _codeError = null;
                  });
                }
              },
              onFieldSubmitted: (_) => _validateInviteCode(),
            ),
            const SizedBox(height: 12),

            // Institución validada
            if (_validatedInstitution != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified, color: Colors.green),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _validatedInstitution!.institutionName,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'NIT: ${_validatedInstitution!.nit}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Campo de cargo
              TextFormField(
                controller: _jobTitleController,
                textCapitalization: TextCapitalization.words,
                enabled: !_isLoading,
                decoration: const InputDecoration(
                  labelText: 'Tu cargo (opcional)',
                  prefixIcon: Icon(Icons.work_outline),
                  hintText: 'Ej: Docente, Auxiliar',
                ),
              ),
              const SizedBox(height: 20),

              // Botón de unirse
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _joinInstitution,
                  icon: _isLoading
                      ? const SizedBox.shrink()
                      : const Icon(Icons.check),
                  label: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Unirme a esta institución'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
