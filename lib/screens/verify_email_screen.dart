import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';

/// Pantalla que se muestra cuando el usuario tiene email no verificado.
/// Permite reenviar el correo de verificación y recargar el estado.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _auth = FirebaseAuth.instance;
  bool _isLoading = false;
  bool _canResend = true;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;
  Timer? _autoCheckTimer;

  String get _userEmail => _auth.currentUser?.email ?? 'tu correo';

  @override
  void initState() {
    super.initState();
    // Auto-verificar cada 3 segundos
    _autoCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkEmailVerified(showMessage: false);
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _autoCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _resendVerificationEmail() async {
    if (!_canResend) return;

    setState(() => _isLoading = true);

    try {
      await _auth.currentUser?.sendEmailVerification();
      _showMessage('Correo de verificación enviado.');
      _startCooldown();
    } on FirebaseAuthException catch (e) {
      _showMessage(_mapError(e.code));
    } catch (e) {
      _showMessage('Error al enviar el correo. Intenta de nuevo.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _startCooldown() {
    setState(() {
      _canResend = false;
      _resendCooldown = 60;
    });

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  /// Verifica si el email ya fue verificado y navega al AuthWrapper
  Future<void> _checkEmailVerified({bool showMessage = true}) async {
    try {
      // Recargar datos del usuario
      await _auth.currentUser?.reload();
      // Obtener referencia actualizada
      final user = _auth.currentUser;

      if (user != null && user.emailVerified) {
        // Cancelar timers antes de navegar
        _cooldownTimer?.cancel();
        _autoCheckTimer?.cancel();
        
        if (showMessage && mounted) {
          _showMessage('¡Email verificado! Redirigiendo...');
        }
        
        // Forzar navegación al AuthWrapper
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthWrapper()),
            (route) => false,
          );
        }
      } else if (showMessage) {
        _showMessage('Aún no has verificado tu email.');
      }
    } catch (e) {
      if (showMessage) {
        _showMessage('Error al verificar. Intenta de nuevo.');
      }
    }
  }

  Future<void> _reloadUser() async {
    setState(() => _isLoading = true);
    await _checkEmailVerified(showMessage: true);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    _cooldownTimer?.cancel();
    _autoCheckTimer?.cancel();
    await _auth.signOut();
  }

  String _mapError(String code) {
    switch (code) {
      case 'too-many-requests':
        return 'Demasiados intentos. Espera un momento.';
      default:
        return 'Error al enviar el correo.';
    }
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
        title: const Text('Verificar Email'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icono
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.mark_email_unread_rounded,
                    size: 72,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 32),

                // Título
                Text(
                  '¡Verifica tu correo electrónico!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Descripción
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                    children: [
                      const TextSpan(
                        text: 'Hemos enviado un correo de verificación a ',
                      ),
                      TextSpan(
                        text: _userEmail,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                      const TextSpan(
                        text:
                            '. Por favor, revisa tu bandeja de entrada y haz clic en el enlace para activar tu cuenta.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Nota de spam
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.amber[700],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Si no lo encuentras, revisa tu carpeta de spam.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.amber[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Botón Recargar
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _reloadUser,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Ya verifiqué mi correo'),
                  ),
                ),
                const SizedBox(height: 12),

                // Botón Reenviar
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: (_isLoading || !_canResend)
                        ? null
                        : _resendVerificationEmail,
                    icon: const Icon(Icons.email_outlined),
                    label: Text(
                      _canResend
                          ? 'Reenviar correo de verificación'
                          : 'Reenviar en $_resendCooldown s',
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Divider
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'o',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 24),

                // Botón Cerrar Sesión
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton.icon(
                    onPressed: _isLoading ? null : _signOut,
                    icon: Icon(Icons.logout, color: scheme.error),
                    label: Text(
                      'Cerrar sesión',
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
