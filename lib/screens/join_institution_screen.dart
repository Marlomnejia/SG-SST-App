import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/institution_service.dart';

class JoinInstitutionScreen extends StatefulWidget {
  const JoinInstitutionScreen({super.key});

  @override
  State<JoinInstitutionScreen> createState() => _JoinInstitutionScreenState();
}

class _JoinInstitutionScreenState extends State<JoinInstitutionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _inviteCodeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _jobTitleController = TextEditingController();

  final _authService = AuthService();
  final _userService = UserService();
  final _institutionService = InstitutionService();

  bool _isLoading = false;
  bool _isValidatingCode = false;
  bool _isPasswordObscured = true;
  
  // Datos de la institución validada
  InstitutionValidationResult? _validatedInstitution;
  String? _codeError;

  @override
  void dispose() {
    _inviteCodeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
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
      _isValidatingCode = true;
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
        _codeError = 'Error al validar el código. Intenta de nuevo.';
      });
    } finally {
      setState(() {
        _isValidatingCode = false;
      });
    }
  }

  Future<void> _register() async {
    // Primero validar el código si no está validado
    if (_validatedInstitution == null) {
      await _validateInviteCode();
      if (_validatedInstitution == null) {
        return;
      }
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Registrar usuario en Firebase Auth
      final user = await _authService.registerWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (user != null) {
        // Actualizar displayName
        await user.updateDisplayName(_nameController.text.trim());

        // Crear perfil en Firestore con institutionId
        await _userService.createUserWithInstitution(
          uid: user.uid,
          email: _emailController.text.trim(),
          displayName: _nameController.text.trim(),
          photoUrl: null,
          institutionId: _validatedInstitution!.institutionId,
          role: 'employee',
        );

        // Actualizar jobTitle
        await _userService.updateUserProfile(user.uid, {
          'jobTitle': _jobTitleController.text.trim(),
        });

        // Cerrar sesión para que verifique email
        await _authService.signOut();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '¡Registro exitoso en ${_validatedInstitution!.institutionName}! '
              'Revisa tu correo para activar la cuenta.',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      _showMessage(_mapAuthError(e.code));
    } on AuthException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('Error al crear la cuenta. Intenta de nuevo.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _mapAuthError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'El correo ya está registrado.';
      case 'invalid-email':
        return 'Correo no válido.';
      case 'weak-password':
        return 'La contraseña es muy débil (mínimo 6 caracteres).';
      case 'operation-not-allowed':
        return 'Operación no permitida.';
      default:
        return 'No se pudo crear la cuenta. Intenta de nuevo.';
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
        title: const Text('Unirse a Institución'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 0,
              color: scheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: scheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Icon(
                        Icons.business_rounded,
                        size: 48,
                        color: scheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Registro de Empleado',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ingresa el código de invitación que te proporcionó tu institución.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 24),

                      // Código de invitación
                      _buildInviteCodeField(scheme),
                      const SizedBox(height: 8),

                      // Mostrar institución validada
                      if (_validatedInstitution != null)
                        _buildInstitutionCard(scheme),

                      const SizedBox(height: 16),

                      // Nombre completo
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nombre completo',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Ingresa tu nombre.';
                          }
                          if (value.trim().length < 3) {
                            return 'El nombre es muy corto.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Cargo
                      TextFormField(
                        controller: _jobTitleController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Cargo / Puesto',
                          prefixIcon: Icon(Icons.work_outline),
                          hintText: 'Ej: Docente, Auxiliar, Operario',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Ingresa tu cargo.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Email
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Ingresa tu correo.';
                          }
                          if (!value.contains('@') || !value.contains('.')) {
                            return 'Correo no válido.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Contraseña
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _isPasswordObscured,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordObscured
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordObscured = !_isPasswordObscured;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingresa una contraseña.';
                          }
                          if (value.length < 6) {
                            return 'Mínimo 6 caracteres.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Confirmar contraseña
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _isPasswordObscured,
                        decoration: const InputDecoration(
                          labelText: 'Confirmar contraseña',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Confirma tu contraseña.';
                          }
                          if (value != _passwordController.text) {
                            return 'Las contraseñas no coinciden.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // Botón de registro
                      SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _register,
                          icon: _isLoading
                              ? const SizedBox.shrink()
                              : const Icon(Icons.person_add),
                          label: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Crear cuenta'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInviteCodeField(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _inviteCodeController,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            UpperCaseTextFormatter(),
          ],
          decoration: InputDecoration(
            labelText: 'Código de invitación',
            prefixIcon: const Icon(Icons.vpn_key_outlined),
            counterText: '',
            hintText: 'ABC123',
            errorText: _codeError,
            suffixIcon: _isValidatingCode
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
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
                    tooltip: 'Validar código',
                  ),
          ),
          onChanged: (_) {
            // Limpiar validación anterior cuando cambie el código
            if (_validatedInstitution != null || _codeError != null) {
              setState(() {
                _validatedInstitution = null;
                _codeError = null;
              });
            }
          },
          onFieldSubmitted: (_) => _validateInviteCode(),
        ),
        if (_validatedInstitution == null && _codeError == null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(
              'Presiona el botón de búsqueda para validar',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
      ],
    );
  }

  Widget _buildInstitutionCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.verified,
              color: Colors.green,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Institución verificada',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  _validatedInstitution!.institutionName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  'NIT: ${_validatedInstitution!.nit}',
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
}

/// Formateador para convertir texto a mayúsculas
class UpperCaseTextFormatter extends TextInputFormatter {
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
