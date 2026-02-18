import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/invitation.dart';
import '../services/invitation_service.dart';
import '../services/user_service.dart';

/// Pantalla para que el admin invite empleados por email
class InviteEmployeeScreen extends StatefulWidget {
  const InviteEmployeeScreen({super.key});

  @override
  State<InviteEmployeeScreen> createState() => _InviteEmployeeScreenState();
}

class _InviteEmployeeScreenState extends State<InviteEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _invitationService = InvitationService();
  final _userService = UserService();

  bool _isLoading = false;
  bool _isSending = false;
  String? _institutionId;
  String? _institutionName;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    try {
      final user = await _userService.getCurrentUser();
      if (user != null) {
        _currentUserId = user.uid;
        _institutionId = user.institutionId;
        // Obtener nombre de institución
        if (_institutionId != null) {
          final institution =
              await _userService.getInstitutionName(_institutionId!);
          _institutionName = institution;
        }
      }
    } catch (e) {
      _showMessage('Error al cargar datos: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendInvitation() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_institutionId == null || _currentUserId == null) {
      _showMessage('Error: No se pudo obtener la información de la institución');
      return;
    }

    setState(() => _isSending = true);

    try {
      final email = _emailController.text.trim().toLowerCase();

      final invitation = await _invitationService.createInvitation(
        email: email,
        institutionId: _institutionId!,
        institutionName: _institutionName ?? 'Tu institución',
        createdBy: _currentUserId!,
      );

      if (mounted) {
        _emailController.clear();
        _showSuccessDialog(invitation);
      }
    } on InvitationException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('Error al enviar invitación: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showSuccessDialog(Invitation invitation) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: const Text('¡Invitación Creada!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Se ha creado la invitación para:\n${invitation.email}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              '¿Deseas abrir tu app de correo para notificar al empleado?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _openMailApp(invitation.email);
            },
            icon: const Icon(Icons.email),
            label: const Text('Enviar Correo'),
          ),
        ],
      ),
    );
  }

  Future<void> _openMailApp(String toEmail) async {
    final subject = Uri.encodeComponent(
        'Invitación a ${_institutionName ?? "nuestra institución"} - SG-SST');
    final body = Uri.encodeComponent(
      'Hola,\n\n'
      'Has sido invitado a unirte a ${_institutionName ?? "nuestra institución"} '
      'en la aplicación SG-SST.\n\n'
      'Para completar tu registro:\n'
      '1. Descarga la app SG-SST\n'
      '2. Inicia sesión con tu cuenta de Google o Microsoft usando este correo ($toEmail)\n'
      '3. La app detectará automáticamente tu invitación\n\n'
      '¡Te esperamos!\n\n'
      'Saludos,\n'
      'Equipo de SG-SST',
    );

    final mailUri = Uri.parse('mailto:$toEmail?subject=$subject&body=$body');

    try {
      if (await canLaunchUrl(mailUri)) {
        await launchUrl(mailUri);
      } else {
        _showMessage('No se pudo abrir la aplicación de correo');
      }
    } catch (e) {
      _showMessage('Error al abrir correo: $e');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invitar Empleados'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Icon(
                    Icons.person_add_alt_1,
                    size: 64,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Invitar nuevo empleado',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Envía una invitación por correo electrónico para que un empleado pueda unirse a tu institución.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Formulario
                  Form(
                    key: _formKey,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              enabled: !_isSending,
                              decoration: const InputDecoration(
                                labelText: 'Correo electrónico del empleado',
                                prefixIcon: Icon(Icons.email_outlined),
                                hintText: 'empleado@ejemplo.com',
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Ingresa el correo electrónico';
                                }
                                final emailRegex = RegExp(
                                  r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
                                );
                                if (!emailRegex.hasMatch(value.trim())) {
                                  return 'Ingresa un correo válido';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: _isSending ? null : _sendInvitation,
                              icon: _isSending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.send),
                              label: Text(
                                  _isSending ? 'Enviando...' : 'Crear Invitación'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: scheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'El empleado deberá iniciar sesión con Google o Microsoft usando el mismo correo para acceder automáticamente.',
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Lista de invitaciones pendientes
                  _buildPendingInvitationsList(scheme),
                ],
              ),
            ),
    );
  }

  Widget _buildPendingInvitationsList(ColorScheme scheme) {
    if (_institutionId == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Invitaciones pendientes',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<Invitation>>(
          stream: _invitationService
              .getInstitutionInvitationsStream(_institutionId!),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (snapshot.hasError) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Error al cargar invitaciones',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              );
            }

            final invitations = snapshot.data ?? [];
            if (invitations.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.mail_outline,
                          size: 48,
                          color: scheme.onSurfaceVariant.withOpacity(0.5),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No hay invitaciones aún',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Card(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: invitations.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final invitation = invitations[index];
                  return _buildInvitationTile(invitation, scheme);
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildInvitationTile(Invitation invitation, ColorScheme scheme) {
    final statusColor = switch (invitation.status) {
      InvitationStatus.pending => Colors.orange,
      InvitationStatus.accepted => Colors.green,
      InvitationStatus.cancelled => Colors.grey,
    };

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: statusColor.withOpacity(0.1),
        child: Icon(
          invitation.status == InvitationStatus.accepted
              ? Icons.check
              : invitation.status == InvitationStatus.cancelled
                  ? Icons.close
                  : Icons.hourglass_empty,
          color: statusColor,
        ),
      ),
      title: Text(invitation.email),
      subtitle: Text(
        '${invitation.status.displayName} • ${_formatDate(invitation.createdAt)}',
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
      ),
      trailing: invitation.status == InvitationStatus.pending
          ? PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'resend') {
                  _openMailApp(invitation.email);
                } else if (value == 'cancel') {
                  await _invitationService.cancelInvitation(invitation.id);
                  _showMessage('Invitación cancelada');
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'resend',
                  child: Row(
                    children: [
                      Icon(Icons.send),
                      SizedBox(width: 8),
                      Text('Reenviar correo'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'cancel',
                  child: Row(
                    children: [
                      Icon(Icons.cancel, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Cancelar', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            )
          : null,
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Hoy';
    } else if (diff.inDays == 1) {
      return 'Ayer';
    } else if (diff.inDays < 7) {
      return 'Hace ${diff.inDays} días';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
