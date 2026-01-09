import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/profile_service.dart';
import '../services/user_service.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _institutionController = TextEditingController();
  final _campusController = TextEditingController();
  final _phoneController = TextEditingController();
  final _userService = UserService();
  final _authService = AuthService();
  final _profileService = ProfileService();
  final _notificationService = NotificationService();
  final _picker = ImagePicker();

  bool _isSaving = false;
  bool _isEditing = false;
  bool _initialized = false;
  bool _requestedCreate = false;
  bool _notificationsEnabled = true;
  bool _isUploadingPhoto = false;
  bool _notificationRegistered = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _jobTitleController.dispose();
    _institutionController.dispose();
    _campusController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile(String uid) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _isSaving = true;
    });

    try {
      final current = FirebaseAuth.instance.currentUser;
      if (current != null) {
        await current.updateDisplayName(_displayNameController.text.trim());
      }
      await _userService.updateUserProfile(uid, {
        'displayName': _displayNameController.text.trim(),
        'jobTitle': _jobTitleController.text.trim(),
        'institution': _institutionController.text.trim(),
        'campus': _campusController.text.trim(),
        'phone': _phoneController.text.trim(),
      });
      if (mounted) {
        setState(() {
          _isEditing = false;
        });
        _showMessage('Perfil actualizado.');
      }
    } catch (e) {
      _showMessage('No se pudo guardar el perfil.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _showPhotoOptions(User user) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Tomar foto'),
                onTap: () async {
                  Navigator.pop(context);
                  await _updatePhoto(user, ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Elegir de galeria'),
                onTap: () async {
                  Navigator.pop(context);
                  await _updatePhoto(user, ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Eliminar foto'),
                onTap: () async {
                  Navigator.pop(context);
                  await _removePhoto(user);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updatePhoto(User user, ImageSource source) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _isUploadingPhoto = true;
    });

    try {
      final String url =
          await _profileService.uploadProfilePhoto(user.uid, picked);
      await user.updatePhotoURL(url);
      await _userService.updateUserProfile(user.uid, {'photoUrl': url});
      _showMessage('Foto actualizada.');
    } catch (_) {
      _showMessage('No se pudo actualizar la foto.');
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
        });
      }
    }
  }

  Future<void> _removePhoto(User user) async {
    setState(() {
      _isUploadingPhoto = true;
    });
    try {
      await user.updatePhotoURL(null);
      await _userService.updateUserProfile(user.uid, {'photoUrl': ''});
      _showMessage('Foto eliminada.');
    } catch (_) {
      _showMessage('No se pudo eliminar la foto.');
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
        });
      }
    }
  }

  Future<void> _toggleNotifications(String uid, bool value) async {
    setState(() {
      _notificationsEnabled = value;
    });
    try {
      await _userService.setNotificationsEnabled(uid, value);
      if (value) {
        final enabled = await _notificationService.enableForUser(uid);
        if (!enabled) {
          if (mounted) {
            setState(() {
              _notificationsEnabled = false;
            });
          }
          await _userService.setNotificationsEnabled(uid, false);
          _showMessage('Permiso de notificaciones denegado.');
        } else {
          _notificationRegistered = true;
        }
      } else {
        await _notificationService.disableForUser(uid);
        _notificationRegistered = false;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _notificationsEnabled = !value;
        });
      }
      _showMessage('No se pudo actualizar la configuracion.');
    }
  }

  Future<void> _sendPasswordReset(String email) async {
    try {
      await _authService.sendPasswordResetEmail(email);
      _showMessage('Enlace enviado al correo.');
    } catch (_) {
      _showMessage('No se pudo enviar el enlace.');
    }
  }

  Future<void> _sendEmailVerification() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.sendEmailVerification();
      _showMessage('Correo de verificacion enviado.');
    } catch (_) {
      _showMessage('No se pudo enviar la verificacion.');
    }
  }

  bool _isPasswordProvider(User user) {
    return user.providerData.any((provider) => provider.providerId == 'password');
  }

  Future<void> _showChangePasswordDialog(User user) async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    bool obscure = true;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Cambiar contrasena'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: currentController,
                    obscureText: obscure,
                    decoration: const InputDecoration(
                      labelText: 'Contrasena actual',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newController,
                    obscureText: obscure,
                    decoration: const InputDecoration(
                      labelText: 'Nueva contrasena',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    obscureText: obscure,
                    decoration: const InputDecoration(
                      labelText: 'Confirmar nueva contrasena',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: !obscure,
                        onChanged: (value) {
                          setState(() {
                            obscure = !(value ?? false);
                          });
                        },
                      ),
                      const Text('Mostrar'),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final current = currentController.text.trim();
                    final next = newController.text.trim();
                    final confirm = confirmController.text.trim();

                    if (current.isEmpty || next.isEmpty) {
                      _showMessage('Completa los campos.');
                      return;
                    }
                    if (next.length < 6) {
                      _showMessage('La nueva contrasena es muy corta.');
                      return;
                    }
                    if (next != confirm) {
                      _showMessage('Las contrasenas no coinciden.');
                      return;
                    }

                    try {
                      final credential = EmailAuthProvider.credential(
                        email: user.email ?? '',
                        password: current,
                      );
                      await user.reauthenticateWithCredential(credential);
                      await user.updatePassword(next);
                      if (mounted) {
                        Navigator.pop(context);
                      }
                      _showMessage('Contrasena actualizada.');
                    } on FirebaseAuthException catch (e) {
                      if (e.code == 'wrong-password') {
                        _showMessage('Contrasena actual incorrecta.');
                      } else {
                        _showMessage('No se pudo actualizar la contrasena.');
                      }
                    }
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    currentController.dispose();
    newController.dispose();
    confirmController.dispose();
  }

  Future<void> _confirmLogout() async {
    final bool? shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar cierre de sesion'),
          content: const Text('Estas seguro de que quieres cerrar sesion?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      await _authService.signOut();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _loadProfileData(Map<String, dynamic> data, {String? fallbackName}) {
    _displayNameController.text =
        (data['displayName'] ?? '').toString().trim().isNotEmpty
            ? data['displayName']
            : (fallbackName ?? '');
    _jobTitleController.text = data['jobTitle'] ?? '';
    _institutionController.text = data['institution'] ?? '';
    _campusController.text = data['campus'] ?? '';
    _phoneController.text = data['phone'] ?? '';
    _notificationsEnabled = data['notificationsEnabled'] ?? true;
    _initialized = true;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('No hay usuario autenticado.')),
      );
    }

    return StreamBuilder(
      stream: _userService.streamUserProfile(user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final doc = snapshot.data;
        if (doc == null || !doc.exists) {
          if (!_requestedCreate) {
            _requestedCreate = true;
            _userService.createUserProfile(user);
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = doc.data() as Map<String, dynamic>;
        final String email = user.email ?? '';
        final String displayName = _resolveDisplayName(
          data['displayName'],
          user.displayName,
          email,
        );
        if (!_initialized && !_isEditing) {
          _loadProfileData(
            data,
            fallbackName: displayName.isEmpty ? 'Usuario' : displayName,
          );
        }

        final scheme = Theme.of(context).colorScheme;
        final String role = data['role'] ?? 'user';
        final bool emailVerified = user.emailVerified;
        final String initials = displayName.isNotEmpty
            ? displayName.trim().split(' ').map((p) => p[0]).take(2).join()
            : 'U';
        final String? photoUrl = data['photoUrl'] ?? user.photoURL;

        if (_notificationsEnabled && !_notificationRegistered) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final enabled = await _notificationService.enableForUser(user.uid);
            if (mounted) {
              setState(() {
                _notificationRegistered = enabled;
                if (!enabled) {
                  _notificationsEnabled = false;
                }
              });
            }
            if (!enabled) {
              await _userService.setNotificationsEnabled(user.uid, false);
            }
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Perfil y configuracion'),
            actions: [
              IconButton(
                icon: Icon(_isEditing ? Icons.close : Icons.edit),
                tooltip: _isEditing ? 'Cancelar' : 'Editar',
                onPressed: () {
                  setState(() {
                    if (_isEditing) {
                      _loadProfileData(data);
                    }
                    _isEditing = !_isEditing;
                  });
                },
              ),
            ],
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ProfileHeader(
                  initials: initials,
                  displayName: displayName.isEmpty ? 'Usuario' : displayName,
                  email: email,
                  role: role,
                  photoUrl: photoUrl,
                  isUploading: _isUploadingPhoto,
                  onEditPhoto: () => _showPhotoOptions(user),
                ),
                const SizedBox(height: 24),
                _SectionTitle(title: 'Informacion personal'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(labelText: 'Nombre completo'),
                  enabled: _isEditing,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa tu nombre.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _jobTitleController,
                  decoration: const InputDecoration(labelText: 'Cargo'),
                  enabled: _isEditing,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _institutionController,
                  decoration: const InputDecoration(labelText: 'Institucion'),
                  enabled: _isEditing,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _campusController,
                  decoration: const InputDecoration(labelText: 'Sede'),
                  enabled: _isEditing,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Telefono'),
                  enabled: _isEditing,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                if (_isEditing)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : () => _saveProfile(user.uid),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(),
                            )
                          : const Text('Guardar cambios'),
                    ),
                  ),
                const SizedBox(height: 24),
                _SectionTitle(title: 'Configuracion'),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _notificationsEnabled,
                  title: const Text('Notificaciones'),
                  subtitle: const Text('Alertas y novedades del SG-SST'),
                  onChanged: (value) =>
                      _toggleNotifications(user.uid, value),
                ),
                const SizedBox(height: 16),
                _SectionTitle(title: 'Seguridad'),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: Text(emailVerified
                      ? 'Correo verificado'
                      : 'Correo sin verificar'),
                  subtitle: Text(email),
                  trailing: emailVerified
                      ? const Icon(Icons.check, color: Colors.green)
                      : TextButton(
                          onPressed: _sendEmailVerification,
                          child: const Text('Verificar'),
                        ),
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Cambiar contrasena'),
                  subtitle: Text(
                    _isPasswordProvider(user)
                        ? 'Actualiza tu contrasena'
                        : 'No disponible para este tipo de cuenta',
                  ),
                  onTap: _isPasswordProvider(user)
                      ? () => _showChangePasswordDialog(user)
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.lock_reset),
                  title: const Text('Restablecer contrasena'),
                  subtitle: const Text('Envia un enlace al correo'),
                  onTap: email.isEmpty ? null : () => _sendPasswordReset(email),
                ),
                const SizedBox(height: 16),
                _SectionTitle(title: 'Sesion'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _confirmLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar sesion'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Version 1.0.0',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String initials;
  final String displayName;
  final String email;
  final String role;
  final String? photoUrl;
  final VoidCallback onEditPhoto;
  final bool isUploading;

  const _ProfileHeader({
    required this.initials,
    required this.displayName,
    required this.email,
    required this.role,
    this.photoUrl,
    required this.onEditPhoto,
    required this.isUploading,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withOpacity(0.18),
            scheme.surfaceContainerHighest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 46,
                backgroundColor: scheme.primary.withOpacity(0.15),
                backgroundImage: photoUrl != null && photoUrl!.isNotEmpty
                    ? NetworkImage(photoUrl!)
                    : null,
                child: photoUrl == null || photoUrl!.isEmpty
                    ? Text(
                        initials.toUpperCase(),
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 24,
                        ),
                      )
                    : null,
              ),
              Positioned(
                right: -6,
                bottom: -6,
                child: Material(
                  color: scheme.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: isUploading ? null : onEditPhoto,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: isUploading
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 18,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            displayName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            email,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              role == 'admin' ? 'Administrador' : 'Usuario',
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _resolveDisplayName(String? firestoreName, String? authName, String email) {
  final String candidate = (firestoreName ?? '').trim().isNotEmpty
      ? firestoreName!.trim()
      : (authName ?? '').trim();
  if (candidate.isNotEmpty) {
    return candidate;
  }
  if (email.contains('@')) {
    final localPart = email.split('@').first;
    if (localPart.isNotEmpty) {
      return localPart.replaceAll('.', ' ').trim();
    }
  }
  return 'Usuario';
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }
}
