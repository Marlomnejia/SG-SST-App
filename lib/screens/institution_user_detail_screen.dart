import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/user_service.dart';

class InstitutionUserDetailScreen extends StatefulWidget {
  final String userId;
  final String institutionId;
  final String? institutionName;

  const InstitutionUserDetailScreen({
    super.key,
    required this.userId,
    required this.institutionId,
    this.institutionName,
  });

  @override
  State<InstitutionUserDetailScreen> createState() =>
      _InstitutionUserDetailScreenState();
}

class _InstitutionUserDetailScreenState
    extends State<InstitutionUserDetailScreen> {
  final UserService _userService = UserService();
  final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
  late final Future<CurrentUserData?> _viewerFuture;

  @override
  void initState() {
    super.initState();
    _viewerFuture = _userService.getCurrentUser();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del usuario')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userService.streamUserProfile(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _CenteredMessage(
              icon: Icons.error_outline,
              title: 'No se pudo cargar el usuario',
              subtitle: snapshot.error.toString(),
              color: scheme.error,
            );
          }

          final profile = snapshot.data?.data();
          if (profile == null) {
            return const _CenteredMessage(
              icon: Icons.person_off_outlined,
              title: 'Usuario no disponible',
              subtitle:
                  'Este perfil ya no existe o no se puede consultar en este momento.',
            );
          }

          final displayName = (profile['displayName'] ?? 'Usuario').toString();
          final email = (profile['email'] ?? 'Sin correo').toString();
          final role = (profile['role'] ?? 'user').toString();
          final createdAt = profile['createdAt'] as Timestamp?;
          final currentInstitutionId =
              (profile['institutionId'] ?? widget.institutionId)
                  .toString()
                  .trim();

          return FutureBuilder<String?>(
            future: currentInstitutionId.isEmpty
                ? Future.value(null)
                : _userService.getInstitutionName(currentInstitutionId),
            builder: (context, institutionSnap) {
              final fallbackName = widget.institutionName?.trim() ?? '';
              final remoteName = (institutionSnap.data ?? '').trim();
              final institutionName = fallbackName.isNotEmpty
                  ? fallbackName
                  : (remoteName.isNotEmpty ? remoteName : 'Sin institucion');

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _SectionCard(
                    title: 'Informacion principal',
                    icon: Icons.badge_outlined,
                    child: Column(
                      children: [
                        _DetailItem(
                          icon: Icons.mail_outline,
                          label: 'Correo',
                          value: email,
                        ),
                        _DetailItem(
                          icon: Icons.verified_user_outlined,
                          label: 'Rol',
                          value: _roleLabel(role),
                        ),
                        _DetailItem(
                          icon: Icons.school_outlined,
                          label: 'Institucion',
                          value: institutionName,
                        ),
                        _DetailItem(
                          icon: Icons.event_outlined,
                          label: 'Fecha de registro',
                          value: createdAt != null
                              ? _dateTimeFormat.format(createdAt.toDate())
                              : 'Sin fecha',
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<CurrentUserData?>(
                    future: _viewerFuture,
                    builder: (context, viewerSnap) {
                      final viewer = viewerSnap.data;
                      final canManageUser =
                          viewer?.role == 'admin' &&
                          viewer?.uid != widget.userId;

                      if (!canManageUser) {
                        return const SizedBox.shrink();
                      }

                      return _SectionCard(
                        title: 'Acciones de administracion',
                        icon: Icons.admin_panel_settings_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (role == 'admin_sst')
                              OutlinedButton.icon(
                                onPressed: () => _changeRole(
                                  displayName: displayName,
                                  role: role,
                                ),
                                icon: const Icon(Icons.person_outline),
                                label: const Text('Cambiar a Usuario'),
                              )
                            else
                              FilledButton.tonalIcon(
                                onPressed: () => _changeRole(
                                  displayName: displayName,
                                  role: role,
                                ),
                                icon: const Icon(Icons.verified_user_outlined),
                                label: const Text('Asignar como Admin SST'),
                              ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () => _unlinkUser(
                                displayName: displayName,
                                role: role,
                              ),
                              icon: const Icon(Icons.link_off_outlined),
                              label: const Text(
                                'Desvincular de la institucion',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: scheme.error,
                                side: BorderSide(color: scheme.error),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role.trim().toLowerCase()) {
      case 'admin':
        return 'Super admin';
      case 'admin_sst':
        return 'Admin SST';
      default:
        return 'Usuario';
    }
  }

  Future<void> _changeRole({
    required String displayName,
    required String role,
  }) async {
    final makeAdminSst = role != 'admin_sst';
    final confirmed = await _showConfirmationDialog(
      title: makeAdminSst ? 'Asignar rol' : 'Cambiar rol',
      content: makeAdminSst
          ? 'Se asignara a $displayName como Admin SST de esta institucion.'
          : 'Se cambiara el rol de $displayName a Usuario dentro de la institucion.',
      confirmLabel: makeAdminSst ? 'Asignar' : 'Cambiar',
    );
    if (!confirmed) return;

    await _runUserMutation(
      successMessage: makeAdminSst
          ? '$displayName ahora es Admin SST.'
          : '$displayName ahora tiene rol Usuario.',
      operation: () => _userService.updateUserRole(
        widget.userId,
        makeAdminSst ? 'admin_sst' : 'user',
      ),
    );
  }

  Future<void> _unlinkUser({
    required String displayName,
    required String role,
  }) async {
    final confirmed = await _showConfirmationDialog(
      title: 'Desvincular usuario',
      content:
          'Se quitara a $displayName de esta institucion. Si es Admin SST, volvera a rol Usuario.',
      confirmLabel: 'Desvincular',
      isDestructive: true,
    );
    if (!confirmed) return;

    await _runUserMutation(
      successMessage: '$displayName fue desvinculado de la institucion.',
      popAfterSuccess: true,
      operation: () => _userService.unlinkUserFromInstitution(
        widget.userId,
        demoteFromInstitutionAdmin: role == 'admin_sst',
      ),
    );
  }

  Future<void> _runUserMutation({
    required Future<void> Function() operation,
    required String successMessage,
    bool popAfterSuccess = false,
  }) async {
    try {
      await operation();
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));

      if (popAfterSuccess) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo actualizar el usuario: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<bool> _showConfirmationDialog({
    required String title,
    required String content,
    required String confirmLabel,
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: isDestructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    return result == true;
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? color;

  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = color ?? scheme.onSurfaceVariant;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: iconColor),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
