import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'institution_user_detail_screen.dart';
import '../services/training_service.dart';
import '../services/user_service.dart';

class InstitutionUsersScreen extends StatefulWidget {
  final String? institutionId;
  final String? institutionName;

  const InstitutionUsersScreen({
    super.key,
    this.institutionId,
    this.institutionName,
  });

  @override
  State<InstitutionUsersScreen> createState() => _InstitutionUsersScreenState();
}

class _InstitutionUsersScreenState extends State<InstitutionUsersScreen> {
  final UserService _userService = UserService();
  final TrainingService _trainingService = TrainingService();
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  late final Future<CurrentUserData?> _viewerFuture;
  final Map<String, Future<int>> _reportCountFutures = {};
  final Map<String, Future<int>> _completedTrainingCountFutures = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _viewerFuture = _userService.getCurrentUser();
  }

  @override
  Widget build(BuildContext context) {
    final explicitInstitutionId = widget.institutionId?.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.institutionName != null &&
                  widget.institutionName!.trim().isNotEmpty
              ? 'Usuarios de ${widget.institutionName}'
              : 'Usuarios de la institución',
        ),
      ),
      body: FutureBuilder<CurrentUserData?>(
        future: _viewerFuture,
        builder: (context, userSnap) {
          if (userSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final viewer = userSnap.data;
          final institutionId =
              explicitInstitutionId != null && explicitInstitutionId.isNotEmpty
              ? explicitInstitutionId
              : (viewer?.institutionId ?? '');

          if (institutionId.isEmpty) {
            return const Center(
              child: Text('No se encontró la institución del administrador.'),
            );
          }

          return _buildUsersBody(
            institutionId,
            canManageUsers: viewer?.role == 'admin',
            currentViewerUid: viewer?.uid,
          );
        },
      ),
    );
  }

  Widget _buildUsersBody(
    String institutionId, {
    required bool canManageUsers,
    required String? currentViewerUid,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Buscar usuario',
              hintText: 'Nombre, correo o cargo',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              setState(() {
                _query = value.trim().toLowerCase();
              });
            },
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _userService.streamUsersByInstitution(institutionId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(
                  child: Text('No hay usuarios asociados a esta institución.'),
                );
              }

              final docs = snapshot.data!.docs.where((doc) {
                if (_query.isEmpty) return true;
                final data = doc.data() as Map<String, dynamic>;
                final displayName = (data['displayName'] ?? '')
                    .toString()
                    .toLowerCase();
                final email = (data['email'] ?? '').toString().toLowerCase();
                final jobTitle = (data['jobTitle'] ?? '')
                    .toString()
                    .toLowerCase();
                return displayName.contains(_query) ||
                    email.contains(_query) ||
                    jobTitle.contains(_query);
              }).toList();

              if (docs.isEmpty) {
                return const Center(
                  child: Text('Sin resultados para la busqueda.'),
                );
              }

              docs.sort((a, b) {
                final da = (a.data() as Map<String, dynamic>);
                final db = (b.data() as Map<String, dynamic>);
                final ra = (da['role'] ?? '').toString();
                final rb = (db['role'] ?? '').toString();
                if (ra == rb) return 0;
                if (ra == 'admin_sst') return -1;
                if (rb == 'admin_sst') return 1;
                return ra.compareTo(rb);
              });

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final displayName = (data['displayName'] ?? 'Usuario')
                      .toString();
                  final email = (data['email'] ?? 'Sin correo').toString();
                  final role = (data['role'] ?? 'user').toString();
                  final jobTitle = (data['jobTitle'] ?? '').toString();
                  final photoUrl = (data['photoUrl'] ?? '').toString();
                  final notificationsEnabled =
                      (data['notificationsEnabled'] as bool?) ?? true;
                  final registeredTokens = List<String>.from(
                    data['fcmTokens'] ?? const [],
                  );
                  final tokenCount = registeredTokens.length;
                  final notificationReady =
                      notificationsEnabled && tokenCount > 0;
                  final createdAt = data['createdAt'] as Timestamp?;
                  final userId = docs[index].id;
                  final bool isCurrentViewer = userId == currentViewerUid;

                  return Card(
                    elevation: 0,
                    child: ListTile(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => InstitutionUserDetailScreen(
                              userId: userId,
                              institutionId: institutionId,
                              institutionName: widget.institutionName,
                            ),
                          ),
                        );
                      },
                      leading: CircleAvatar(
                        backgroundImage: photoUrl.isNotEmpty
                            ? NetworkImage(photoUrl)
                            : null,
                        child: photoUrl.isEmpty
                            ? Text(
                                displayName.isNotEmpty
                                    ? displayName.characters.first.toUpperCase()
                                    : 'U',
                              )
                            : null,
                      ),
                      title: Text(displayName),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(email),
                          if (jobTitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(jobTitle),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _UserMetaChip(
                                icon: Icons.event_outlined,
                                label: createdAt != null
                                    ? 'Desde ${_dateFormat.format(createdAt.toDate())}'
                                    : 'Sin fecha',
                              ),
                              _UserMetaChip(
                                icon: notificationsEnabled
                                    ? Icons.notifications_active_outlined
                                    : Icons.notifications_off_outlined,
                                label: notificationsEnabled
                                    ? 'Notificaciones activas'
                                    : 'Notificaciones desactivadas',
                                highlighted: notificationsEnabled,
                              ),
                              _UserMetaChip(
                                icon: Icons.key_outlined,
                                label: 'Tokens: $tokenCount',
                                highlighted: tokenCount > 0,
                              ),
                              _UserMetaChip(
                                icon: notificationReady
                                    ? Icons.verified_outlined
                                    : Icons.warning_amber_outlined,
                                label: notificationReady
                                    ? 'Listo para alertas'
                                    : 'Pendiente de configuracion',
                                highlighted: notificationReady,
                              ),
                              FutureBuilder<int>(
                                future: _getReportCountFuture(
                                  userId,
                                  institutionId,
                                ),
                                builder: (context, countSnap) {
                                  final count = countSnap.data;
                                  return _UserMetaChip(
                                    icon: Icons.assignment_outlined,
                                    label: count == null
                                        ? 'Reportes...'
                                        : 'Reportes: $count',
                                  );
                                },
                              ),
                              FutureBuilder<int>(
                                future: _getCompletedTrainingCountFuture(
                                  userId,
                                  institutionId,
                                ),
                                builder: (context, countSnap) {
                                  final count = countSnap.data;
                                  return _UserMetaChip(
                                    icon: Icons.school_outlined,
                                    label: count == null
                                        ? 'Capacitaciones...'
                                        : 'Capacitaciones: $count',
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      isThreeLine: false,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _RoleChip(role: role),
                          if (canManageUsers && !isCurrentViewer) ...[
                            const SizedBox(width: 4),
                            PopupMenuButton<_UserAdminAction>(
                              tooltip: 'Gestionar usuario',
                              onSelected: (action) => _handleAdminAction(
                                action,
                                userId: userId,
                                displayName: displayName,
                                role: role,
                              ),
                              itemBuilder: (context) {
                                final items =
                                    <PopupMenuEntry<_UserAdminAction>>[
                                      if (role == 'admin_sst')
                                        const PopupMenuItem(
                                          value: _UserAdminAction.makeUser,
                                          child: Text('Cambiar a Usuario'),
                                        )
                                      else
                                        const PopupMenuItem(
                                          value: _UserAdminAction
                                              .makeInstitutionAdmin,
                                          child: Text('Asignar como Admin SST'),
                                        ),
                                      const PopupMenuItem(
                                        value: _UserAdminAction.unlink,
                                        child: Text(
                                          'Desvincular de la institución',
                                        ),
                                      ),
                                    ];
                                return items;
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<int> _getReportCountFuture(String userId, String institutionId) {
    final key = '$institutionId::$userId';
    return _reportCountFutures.putIfAbsent(
      key,
      () =>
          _userService.getUserReportCount(userId, institutionId: institutionId),
    );
  }

  Future<int> _getCompletedTrainingCountFuture(
    String userId,
    String institutionId,
  ) {
    final key = '$institutionId::$userId';
    return _completedTrainingCountFutures.putIfAbsent(
      key,
      () => _trainingService.getCompletedTrainingCountForUser(
        institutionId: institutionId,
        userId: userId,
      ),
    );
  }

  Future<void> _handleAdminAction(
    _UserAdminAction action, {
    required String userId,
    required String displayName,
    required String role,
  }) async {
    switch (action) {
      case _UserAdminAction.makeInstitutionAdmin:
        final confirmed = await _showConfirmationDialog(
          title: 'Asignar rol',
          content:
              'Se asignará a $displayName como Admin SST de esta institución.',
          confirmLabel: 'Asignar',
        );
        if (!confirmed) return;

        await _runUserMutation(
          successMessage: '$displayName ahora es Admin SST.',
          operation: () => _userService.updateUserRole(userId, 'admin_sst'),
        );
        break;
      case _UserAdminAction.makeUser:
        final confirmed = await _showConfirmationDialog(
          title: 'Cambiar rol',
          content:
              'Se cambiará el rol de $displayName a Usuario dentro de la institución.',
          confirmLabel: 'Cambiar',
        );
        if (!confirmed) return;

        await _runUserMutation(
          successMessage: '$displayName ahora tiene rol Usuario.',
          operation: () => _userService.updateUserRole(userId, 'user'),
        );
        break;
      case _UserAdminAction.unlink:
        final confirmed = await _showConfirmationDialog(
          title: 'Desvincular usuario',
          content:
              'Se quitará a $displayName de esta institución. Si es Admin SST, volverá a rol Usuario.',
          confirmLabel: 'Desvincular',
          isDestructive: true,
        );
        if (!confirmed) return;

        await _runUserMutation(
          successMessage: '$displayName fue desvinculado de la institución.',
          operation: () => _userService.unlinkUserFromInstitution(
            userId,
            demoteFromInstitutionAdmin: role == 'admin_sst',
          ),
        );
        break;
    }
  }

  Future<void> _runUserMutation({
    required Future<void> Function() operation,
    required String successMessage,
  }) async {
    try {
      await operation();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
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

enum _UserAdminAction { makeInstitutionAdmin, makeUser, unlink }

class _UserMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlighted;

  const _UserMetaChip({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final backgroundColor = highlighted
        ? scheme.primaryContainer.withValues(alpha: 0.7)
        : scheme.surfaceContainerHighest;
    final foregroundColor = highlighted
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foregroundColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String role;
  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bool isAdmin = role == 'admin_sst';
    return Chip(
      label: Text(isAdmin ? 'Admin' : 'Usuario'),
      backgroundColor: isAdmin
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
      labelStyle: TextStyle(
        color: isAdmin ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
