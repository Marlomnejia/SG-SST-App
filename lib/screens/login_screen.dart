import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/institution.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/institution_service.dart';
import 'user_dashboard_screen.dart';
import 'admin_dashboard_screen.dart';
import 'super_admin_dashboard_screen.dart';
import 'reset_password_screen.dart';
import 'register_screen.dart';
import 'register_institution_screen.dart';
import 'social_onboarding_screen.dart';
import 'verification_pending_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _userService = UserService();

  bool _isLoading = false;
  bool _isPasswordObscured = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = await _authService.signInWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (user == null) {
        return;
      }

      if (!user.emailVerified) {
        await user.sendEmailVerification();
        await _authService.signOut();
        _showMessage(
          'Verifica tu correo. Te enviamos un enlace de activacion.',
        );
        return;
      }

      await _routeByRole(user);
    } on FirebaseAuthException catch (e) {
      _showMessage(_mapAuthError(e.code));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loginWithGoogle() async {
    AuthService.socialAuthFlowActive = true;
    setState(() {
      _isLoading = true;
    });

    try {
      final user = await _authService.signInWithGoogle();
      if (user == null) {
        return;
      }
      // Usuario existente - continuar con login normal
      await _routeByRole(user);
    } on SocialUserNotRegisteredException catch (e) {
      // Usuario nuevo de Google - navegar a onboarding
      if (mounted) {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => SocialOnboardingScreen(
              socialData: SocialUserData.fromException(e),
            ),
          ),
        );

        // Si completó el registro exitosamente, hacer login
        if (result == true && mounted) {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await _routeByRole(user);
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      _showMessage(_mapAuthError(e.code));
    } finally {
      AuthService.socialAuthFlowActive = false;
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loginWithMicrosoft() async {
    AuthService.socialAuthFlowActive = true;
    setState(() {
      _isLoading = true;
    });

    try {
      final user = await _authService.signInWithMicrosoft();
      if (user == null) {
        return;
      }
      // Usuario existente - continuar con login normal
      await _routeByRole(user);
    } on SocialUserNotRegisteredException catch (e) {
      // Usuario nuevo de Microsoft - navegar a onboarding
      if (mounted) {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => SocialOnboardingScreen(
              socialData: SocialUserData.fromException(e),
            ),
          ),
        );

        // Si completó el registro exitosamente, hacer login
        if (result == true && mounted) {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await _routeByRole(user);
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      _showMessage(_mapAuthError(e.code));
    } catch (e) {
      _showMessage('Error al iniciar sesión con Microsoft.');
    } finally {
      AuthService.socialAuthFlowActive = false;
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _routeByRole(User user) async {
    final role = await _userService.getUserRole(user.uid);
    if (!mounted) {
      return;
    }
    if (role == null) {
      _showMessage('Tu cuenta no tiene rol asignado.');
      await _authService.signOut();
      return;
    }
    // Super admin (rol global del sistema)
    if (role == 'admin') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SuperAdminDashboardScreen()),
      );
      return;
    }
    // Admin de institución: validar estado
    if (role == 'admin_sst') {
      final institutionId = await _userService.getUserInstitutionId(user.uid);
      if (!mounted) {
        return;
      }
      if (institutionId == null) {
        await _authService.signOut();
        if (!mounted) {
          return;
        }
        _showMessage('No se encontró tu institución.');
        return;
      }
      final institutionService = InstitutionService();
      final inst = await institutionService.getInstitutionById(institutionId);
      if (!mounted) {
        return;
      }
      if (inst == null || inst.status == InstitutionStatus.pending) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => VerificationPendingScreen()),
        );
        return;
      }
      if (inst.status == InstitutionStatus.active) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
        );
        return;
      }
      // rejected u otros estados
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => VerificationPendingScreen()),
      );
      return;
    }
    // user, employee u otros roles van al dashboard de usuario
    {
      // user, employee u otros roles van al dashboard de usuario
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const UserDashboardScreen()),
      );
    }
  }

  String _mapAuthError(String code) {
    switch (code) {
      case 'invalid-email':
        return 'Correo no válido.';
      case 'user-not-found':
        return 'No existe una cuenta con ese correo.';
      case 'wrong-password':
        return 'Contraseña incorrecta.';
      case 'user-disabled':
        return 'La cuenta esta deshabilitada.';
      case 'too-many-requests':
        return 'Demasiados intentos. Intenta mas tarde.';
      case 'account-exists-with-different-credential':
        return 'La cuenta existe con otro metodo de acceso.';
      default:
        return 'Ocurrio un error. Intenta de nuevo.';
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.of(context).size.width;
    final double cardWidth = width > 480 ? 420 : width;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primary.withValues(alpha: 0.10),
                  scheme.tertiary.withValues(alpha: 0.08),
                  scheme.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: -80,
            right: -60,
            child: _buildGlowCircle(scheme.primary, 140),
          ),
          Positioned(
            bottom: -90,
            left: -40,
            child: _buildGlowCircle(scheme.secondary, 180),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: cardWidth),
                  child: Card(
                    elevation: 0,
                    color: scheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: scheme.primary.withValues(
                                        alpha: 0.18,
                                      ),
                                    ),
                                  ),
                                  child: SizedBox(
                                    height: 56,
                                    child: Image.asset(
                                      'assets/logo-loginsst.png',
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Acceso institucional',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                    labelText: 'Correo institucional',
                                    filled: true,
                                    fillColor: scheme.surfaceContainerHighest
                                        .withValues(alpha: 0.6),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Ingresa tu correo.';
                                    }
                                    if (!value.contains('@')) {
                                      return 'Correo no válido.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _isPasswordObscured,
                                  decoration: InputDecoration(
                                    labelText: 'Contraseña',
                                    filled: true,
                                    fillColor: scheme.surfaceContainerHighest
                                        .withValues(alpha: 0.6),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _isPasswordObscured
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _isPasswordObscured =
                                              !_isPasswordObscured;
                                        });
                                      },
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Ingresa tu contraseña.';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: scheme.primaryContainer,
                                foregroundColor: scheme.onPrimaryContainer,
                                elevation: 0,
                              ),
                              onPressed: _isLoading ? null : _login,
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(),
                                    )
                                  : const Text('Iniciar sesion'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Divider(color: scheme.outlineVariant),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                ),
                                child: Text(
                                  'o',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                              Expanded(
                                child: Divider(color: scheme.outlineVariant),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Texto de ayuda para empleados invitados
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(
                                alpha: 0.3,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Si tienes invitación, inicia sesión con el correo al que te llegó.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Botones de redes sociales
                          Row(
                            children: [
                              // Botón de Google
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isLoading
                                      ? null
                                      : _loginWithGoogle,
                                  icon: Container(
                                    height: 20,
                                    width: 20,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(2.0),
                                      child: Image.asset(
                                        'assets/google-g.png',
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  label: const Text('Google'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: scheme.onSurface,
                                    side: BorderSide(
                                      color: scheme.outlineVariant,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Botón de Microsoft
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isLoading
                                      ? null
                                      : _loginWithMicrosoft,
                                  icon: Container(
                                    height: 20,
                                    width: 20,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(2.0),
                                      child: Image.asset(
                                        'assets/microsoft-logo.jpg',
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(
                                              Icons.window,
                                              size: 16,
                                              color: Color(0xFF00A4EF),
                                            ),
                                      ),
                                    ),
                                  ),
                                  label: const Text('Microsoft'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: scheme.onSurface,
                                    side: BorderSide(
                                      color: scheme.outlineVariant,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const ResetPasswordScreen(),
                                      ),
                                    );
                                  },
                            child: const Text('Olvidé mi contraseña'),
                          ),
                          const SizedBox(height: 8),
                          // Botón para registrarse con email/password (empleados invitados)
                          OutlinedButton.icon(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const RegisterScreen(),
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.person_add_outlined),
                            label: const Text('Registrarme con email'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: scheme.primary,
                              side: BorderSide(color: scheme.outline),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                          const Divider(height: 32),
                          Text(
                            '¿Eres administrador de una institución?',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          // Botón: Registrar institución
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const RegisterInstitutionScreen(),
                                      ),
                                    );
                                  },
                            child: const Text('Registrar mi institución'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
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
        color: color.withValues(alpha: 0.18),
      ),
    );
  }
}
