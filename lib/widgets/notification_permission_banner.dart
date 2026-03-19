import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../services/user_service.dart';

final Set<String> _notificationPromptShownUsers = <String>{};

class NotificationPermissionBanner extends StatefulWidget {
  const NotificationPermissionBanner({super.key});

  @override
  State<NotificationPermissionBanner> createState() =>
      _NotificationPermissionBannerState();
}

class _NotificationPermissionBannerState
    extends State<NotificationPermissionBanner> {
  final UserService _userService = UserService();
  final NotificationService _notificationService = NotificationService();
  bool _isEnabling = false;

  Future<void> _enableNotifications(String uid) async {
    if (_isEnabling) return;
    setState(() => _isEnabling = true);

    try {
      final enabled = await _notificationService.enableForUser(uid);
      if (enabled) {
        await _userService.setNotificationsEnabled(uid, true);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Notificaciones activadas correctamente.'
                : 'No se pudo completar la activacion. Intenta de nuevo.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo activar las notificaciones: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isEnabling = false);
      }
    }
  }

  void _maybeShowPrompt({required String uid, required bool isReady}) {
    if (isReady || _notificationPromptShownUsers.contains(uid)) {
      return;
    }

    _notificationPromptShownUsers.add(uid);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Activa las notificaciones'),
          content: const Text(
            'Para recibir alertas de planes de accion, reportes y capacitaciones, habilita las notificaciones. Puedes continuar con acceso limitado si lo prefieres.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Continuar'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _enableNotifications(uid);
              },
              child: const Text('Habilitar ahora'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userService.streamUserProfile(user.uid),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        if (data == null) {
          return const SizedBox.shrink();
        }

        final notificationsEnabled =
            (data['notificationsEnabled'] as bool?) ?? true;
        final tokenCount = List<String>.from(
          data['fcmTokens'] ?? const <String>[],
        ).length;
        final isReady = notificationsEnabled && tokenCount > 0;
        _maybeShowPrompt(uid: user.uid, isReady: isReady);

        if (isReady) {
          return const SizedBox.shrink();
        }

        final scheme = Theme.of(context).colorScheme;
        final title = notificationsEnabled
            ? 'Completa la activacion de notificaciones'
            : 'Notificaciones desactivadas';
        final subtitle = notificationsEnabled
            ? 'Tu cuenta aun no tiene un token registrado en este dispositivo. Activalas de nuevo para completar el registro.'
            : 'Activalas para recibir recordatorios y alertas importantes del SG-SST.';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.tertiary.withValues(alpha: 0.28)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  notificationsEnabled
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  color: scheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: _isEnabling
                              ? null
                              : () => _enableNotifications(user.uid),
                          child: Text(
                            _isEnabling
                                ? 'Activando...'
                                : notificationsEnabled
                                ? 'Completar activacion'
                                : 'Habilitar ahora',
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _notificationPromptShownUsers.add(user.uid);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Puedes seguir usando la app, pero algunas alertas no llegaran.',
                                ),
                              ),
                            );
                          },
                          child: Text(
                            'Continuar con acceso limitado',
                            style: TextStyle(color: scheme.onTertiaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
