import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'institution_user_detail_screen.dart';
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
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  late final Future<CurrentUserData?> _viewerFuture;
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
              : 'Usuarios de la institucion',
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
              child: Text('No se encontro la institucion del administrador.'),
            );
          }

          return _buildUsersBody(institutionId);
        },
      ),
    );
  }

  Widget _buildUsersBody(String institutionId) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Buscar usuario',
              hintText: 'Nombre o correo',
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
                  child: Text('No hay usuarios asociados a esta institucion.'),
                );
              }

              final docs = snapshot.data!.docs.where((doc) {
                if (_query.isEmpty) return true;
                final data = doc.data() as Map<String, dynamic>;
                final displayName = (data['displayName'] ?? '')
                    .toString()
                    .toLowerCase();
                final email = (data['email'] ?? '').toString().toLowerCase();
                return displayName.contains(_query) || email.contains(_query);
              }).toList();

              if (docs.isEmpty) {
                return const Center(
                  child: Text('Sin resultados para la busqueda.'),
                );
              }

              docs.sort((a, b) {
                final da = a.data() as Map<String, dynamic>;
                final db = b.data() as Map<String, dynamic>;
                final pa = _rolePriority((da['role'] ?? '').toString());
                final pb = _rolePriority((db['role'] ?? '').toString());
                if (pa != pb) return pa.compareTo(pb);
                final na = (da['displayName'] ?? '').toString().toLowerCase();
                final nb = (db['displayName'] ?? '').toString().toLowerCase();
                return na.compareTo(nb);
              });

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final displayName = (data['displayName'] ?? 'Usuario')
                      .toString()
                      .trim();
                  final email = (data['email'] ?? 'Sin correo')
                      .toString()
                      .trim();
                  final role = (data['role'] ?? 'user').toString().trim();
                  final createdAt = data['createdAt'] as Timestamp?;

                  return Material(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => InstitutionUserDetailScreen(
                              userId: docs[index].id,
                              institutionId: institutionId,
                              institutionName: widget.institutionName,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                child: Text(
                                  _initial(displayName),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName.isEmpty
                                          ? 'Usuario'
                                          : displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      email,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        _RoleTag(role: role),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            createdAt != null
                                                ? 'Registro: ${_dateFormat.format(createdAt.toDate())}'
                                                : 'Registro: sin fecha',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
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

  int _rolePriority(String role) {
    final normalized = role.trim().toLowerCase();
    if (normalized == 'admin_sst') return 0;
    if (normalized == 'admin') return 1;
    return 2;
  }

  String _initial(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return 'U';
    return clean.characters.first.toUpperCase();
  }
}

class _RoleTag extends StatelessWidget {
  final String role;
  const _RoleTag({required this.role});

  @override
  Widget build(BuildContext context) {
    final normalized = role.trim().toLowerCase();
    final isAdminSst = normalized == 'admin_sst';
    final isAdmin = normalized == 'admin';

    final label = isAdminSst
        ? 'Admin SST'
        : isAdmin
        ? 'Admin'
        : 'Usuario';

    final baseColor = isAdminSst
        ? Theme.of(context).colorScheme.primary
        : isAdmin
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: baseColor.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: baseColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
