import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/institution.dart';
import '../services/institution_service.dart';
import 'institution_users_screen.dart';

class InstitutionReviewScreen extends StatefulWidget {
  final Institution institution;

  const InstitutionReviewScreen({super.key, required this.institution});

  @override
  State<InstitutionReviewScreen> createState() =>
      _InstitutionReviewScreenState();
}

class _InstitutionReviewScreenState extends State<InstitutionReviewScreen> {
  final InstitutionService _institutionService = InstitutionService();
  bool _isLoading = false;

  Future<void> _approveInstitution() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar aprobacion'),
        content: Text(
          'Estas seguro de aprobar la institucion "${widget.institution.name}"?\n\n'
          'Esta accion habilitara la institucion y sus usuarios podran acceder al sistema.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aprobar'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _institutionService.approveInstitution(widget.institution.id);
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.institution.name} ha sido aprobada'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al aprobar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _rejectInstitution() async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar institucion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estas seguro de rechazar la institucion "${widget.institution.name}"?',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Motivo del rechazo (opcional)',
                hintText: 'Ej: Documentacion incompleta',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _institutionService.rejectInstitution(
        widget.institution.id,
        reason: reasonController.text.trim(),
      );
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.institution.name} ha sido rechazada'),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al rechazar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _suspendInstitution() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suspender institucion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estas seguro de suspender la institucion "${widget.institution.name}"?',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Motivo de suspension (opcional)',
                hintText: 'Ej: revision interna en curso',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Suspender'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _isLoading = true);
    try {
      await _institutionService.suspendInstitution(
        widget.institution.id,
        reason: reasonController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.institution.name} fue suspendida'),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al suspender: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _reactivateInstitution() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reactivar institucion'),
        content: Text(
          'Deseas reactivar la institucion "${widget.institution.name}" para habilitar su operacion?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reactivar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _isLoading = true);
    try {
      await _institutionService.reactivateInstitution(widget.institution.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.institution.name} fue reactivada'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al reactivar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openDocument(String? url, String documentName) async {
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$documentName no disponible')));
      return;
    }

    final uri = await _resolveDocumentUri(url);
    if (uri == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$documentName no tiene un enlace valido')),
      );
      return;
    }

    try {
      final openedInApp = await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      );
      if (openedInApp) {
        return;
      }

      final openedExternal = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (openedExternal) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$documentName se abrio en una aplicacion externa'),
          ),
        );
        return;
      }

      await _copyDocumentLink(uri.toString());
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo abrir $documentName. El enlace fue copiado al portapapeles.',
          ),
        ),
      );
    } catch (_) {
      await _copyDocumentLink(uri.toString());
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo abrir $documentName. El enlace fue copiado al portapapeles.',
          ),
        ),
      );
    }
  }

  Future<Uri?> _resolveDocumentUri(String rawUrl) async {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    if (trimmed.startsWith('gs://')) {
      try {
        final downloadUrl = await FirebaseStorage.instance
            .refFromURL(trimmed)
            .getDownloadURL();
        return Uri.tryParse(downloadUrl);
      } catch (_) {
        return null;
      }
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Uri.tryParse(trimmed);
    }
    if (trimmed.startsWith('//')) {
      return Uri.tryParse('https:$trimmed');
    }
    return Uri.tryParse('https://$trimmed');
  }

  Future<void> _copyDocumentLink(String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final institution = widget.institution;
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final createdDate = institution.createdAt?.toDate();
    final statusMeta = _statusPresentation(institution.status, scheme);

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de la institucion')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 0,
                    color: scheme.primaryContainer.withValues(alpha: 0.22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.business,
                              size: 48,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            institution.name,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: statusMeta.color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              statusMeta.label,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: statusMeta.color,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    context,
                    title: 'Informacion general',
                    icon: Icons.info_outline,
                    children: [
                      _buildInfoRow('NIT', institution.nit),
                      _buildInfoRow('Tipo', institution.type.displayName),
                      _buildInfoRow('Departamento', institution.department),
                      _buildInfoRow('Ciudad', institution.city),
                      _buildInfoRow('Direccion', institution.address),
                      if (institution.inviteCode.isNotEmpty)
                        _buildInfoRow(
                          'Codigo de invitacion',
                          institution.inviteCode,
                        ),
                      _buildInfoRow('Estado', statusMeta.label),
                      if (createdDate != null)
                        _buildInfoRow(
                          'Fecha de solicitud',
                          dateFormat.format(createdDate),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    context,
                    title: 'Contacto',
                    icon: Icons.contact_phone_outlined,
                    children: [
                      _buildInfoRow('Email', institution.email),
                      _buildInfoRow(
                        'Telefono institucion',
                        institution.institutionPhone,
                      ),
                      _buildInfoRow(
                        'Celular rector',
                        institution.rectorCellPhone,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => InstitutionUsersScreen(
                          institutionId: institution.id,
                          institutionName: institution.name,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.group_outlined),
                    label: const Text('Ver usuarios asociados'),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    context,
                    title: 'Documentos',
                    icon: Icons.folder_outlined,
                    children: [
                      _buildDocumentButton(
                        context,
                        'Cedula del rector',
                        institution.documents.rectorIdCard,
                        Icons.badge_outlined,
                      ),
                      if (institution.type == InstitutionType.public)
                        _buildDocumentButton(
                          context,
                          'Acta de posesion',
                          institution.documents.appointmentAct,
                          Icons.description_outlined,
                        ),
                      if (institution.type == InstitutionType.private) ...[
                        _buildDocumentButton(
                          context,
                          'Camara de comercio',
                          institution.documents.chamberOfCommerce,
                          Icons.store_outlined,
                        ),
                        _buildDocumentButton(
                          context,
                          'RUT',
                          institution.documents.rut,
                          Icons.receipt_long_outlined,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 32),
                  if (institution.status == InstitutionStatus.pending) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isLoading ? null : _rejectInstitution,
                            icon: const Icon(Icons.close),
                            label: const Text('Rechazar'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: scheme.error,
                              side: BorderSide(color: scheme.error),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isLoading ? null : _approveInstitution,
                            icon: const Icon(Icons.check),
                            label: const Text('Aprobar'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    _buildStatusInfoCard(context, institution, statusMeta),
                    const SizedBox(height: 12),
                    if (institution.status == InstitutionStatus.active)
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _suspendInstitution,
                        icon: const Icon(Icons.pause_circle_outline),
                        label: const Text('Suspender institucion'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange.shade800,
                          side: BorderSide(color: Colors.orange.shade700),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    if (institution.status == InstitutionStatus.rejected ||
                        institution.status == InstitutionStatus.suspended)
                      FilledButton.icon(
                        onPressed: _isLoading ? null : _reactivateInstitution,
                        icon: const Icon(Icons.restart_alt_outlined),
                        label: const Text('Reactivar institucion'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  _InstitutionStatusPresentation _statusPresentation(
    InstitutionStatus status,
    ColorScheme scheme,
  ) {
    switch (status) {
      case InstitutionStatus.active:
        return _InstitutionStatusPresentation(
          label: 'Institucion activa',
          color: Colors.green.shade700,
        );
      case InstitutionStatus.suspended:
        return _InstitutionStatusPresentation(
          label: 'Institucion suspendida',
          color: Colors.orange.shade700,
        );
      case InstitutionStatus.rejected:
        return _InstitutionStatusPresentation(
          label: 'Institucion rechazada',
          color: scheme.error,
        );
      case InstitutionStatus.pending:
        return _InstitutionStatusPresentation(
          label: 'Pendiente de aprobacion',
          color: Colors.orange.shade700,
        );
    }
  }

  Widget _buildStatusInfoCard(
    BuildContext context,
    Institution institution,
    _InstitutionStatusPresentation statusMeta,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final String message;
    switch (institution.status) {
      case InstitutionStatus.active:
        message =
            'La institucion ya fue aprobada y puede operar normalmente en la plataforma.';
        break;
      case InstitutionStatus.suspended:
        message = institution.suspensionReason?.isNotEmpty == true
            ? 'La institucion esta suspendida temporalmente. Motivo: ${institution.suspensionReason}'
            : 'La institucion esta suspendida temporalmente por control administrativo.';
        break;
      case InstitutionStatus.rejected:
        message = institution.rejectionReason?.isNotEmpty == true
            ? 'Esta solicitud fue rechazada. Motivo: ${institution.rejectionReason}'
            : 'Esta solicitud fue rechazada. Puedes revisar la documentacion registrada.';
        break;
      case InstitutionStatus.pending:
        message =
            'La institucion sigue pendiente de revision por parte del super administrador.';
        break;
    }

    return Card(
      elevation: 0,
      color: statusMeta.color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: statusMeta.color.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: statusMeta.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusMeta.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentButton(
    BuildContext context,
    String name,
    String? url,
    IconData icon,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final hasDocument = url != null && url.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(
        onPressed: hasDocument ? () => _openDocument(url, name) : null,
        icon: Icon(icon),
        label: Row(
          children: [
            Expanded(child: Text(name)),
            Icon(
              hasDocument ? Icons.open_in_new : Icons.not_interested,
              size: 16,
              color: hasDocument ? scheme.primary : scheme.error,
            ),
          ],
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: hasDocument ? scheme.primary : scheme.error,
          side: BorderSide(
            color: hasDocument
                ? scheme.outline
                : scheme.error.withValues(alpha: 0.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}

class _InstitutionStatusPresentation {
  final String label;
  final Color color;

  const _InstitutionStatusPresentation({
    required this.label,
    required this.color,
  });
}
