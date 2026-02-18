import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/institution.dart';
import '../services/institution_service.dart';

/// Pantalla de revisión detallada de una institución pendiente
class InstitutionReviewScreen extends StatefulWidget {
  final Institution institution;

  const InstitutionReviewScreen({
    super.key,
    required this.institution,
  });

  @override
  State<InstitutionReviewScreen> createState() =>
      _InstitutionReviewScreenState();
}

class _InstitutionReviewScreenState extends State<InstitutionReviewScreen> {
  final _institutionService = InstitutionService();
  bool _isLoading = false;

  Future<void> _approveInstitution() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Aprobación'),
        content: Text(
          '¿Estás seguro de aprobar la institución "${widget.institution.name}"?\n\n'
          'Esta acción habilitará la institución y sus usuarios podrán acceder al sistema.',
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

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      await _institutionService.approveInstitution(widget.institution.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.institution.name} ha sido aprobada'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al aprobar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
        title: const Text('Rechazar Institución'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Estás seguro de rechazar la institución "${widget.institution.name}"?',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Motivo del rechazo (opcional)',
                hintText: 'Ej: Documentación incompleta',
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

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      await _institutionService.rejectInstitution(
        widget.institution.id,
        reason: reasonController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.institution.name} ha sido rechazada'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al rechazar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openDocument(String? url, String documentName) async {
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$documentName no disponible')),
      );
      return;
    }

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir $documentName')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final institution = widget.institution;
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final createdDate = institution.createdAt?.toDate();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar Institución'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header con nombre
                  Card(
                    elevation: 0,
                    color: scheme.primaryContainer.withOpacity(0.3),
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
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              'Pendiente de Aprobación',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: Colors.orange.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Información de la institución
                  _buildSectionCard(
                    context,
                    title: 'Información General',
                    icon: Icons.info_outline,
                    children: [
                      _buildInfoRow('NIT', institution.nit),
                      _buildInfoRow('Tipo', institution.type.displayName),
                      _buildInfoRow('Departamento', institution.department),
                      _buildInfoRow('Ciudad', institution.city),
                      _buildInfoRow('Dirección', institution.address),
                      if (createdDate != null)
                        _buildInfoRow(
                          'Fecha de Solicitud',
                          dateFormat.format(createdDate),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Información de contacto
                  _buildSectionCard(
                    context,
                    title: 'Contacto',
                    icon: Icons.contact_phone_outlined,
                    children: [
                      _buildInfoRow('Email', institution.email),
                      _buildInfoRow(
                        'Teléfono Institución',
                        institution.institutionPhone,
                      ),
                      _buildInfoRow(
                        'Celular Rector',
                        institution.rectorCellPhone,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Documentos
                  _buildSectionCard(
                    context,
                    title: 'Documentos',
                    icon: Icons.folder_outlined,
                    children: [
                      _buildDocumentButton(
                        context,
                        'Cédula del Rector',
                        institution.documents.rectorIdCard,
                        Icons.badge_outlined,
                      ),
                      if (institution.type == InstitutionType.public)
                        _buildDocumentButton(
                          context,
                          'Acta de Posesión',
                          institution.documents.appointmentAct,
                          Icons.description_outlined,
                        ),
                      if (institution.type == InstitutionType.private) ...[
                        _buildDocumentButton(
                          context,
                          'Cámara de Comercio',
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

                  // Botones de acción
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
                  const SizedBox(height: 24),
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
            color: hasDocument ? scheme.outline : scheme.error.withOpacity(0.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}
