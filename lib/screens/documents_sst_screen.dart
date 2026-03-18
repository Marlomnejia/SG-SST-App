import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/sst_document_model.dart';
import '../services/sst_document_service.dart';
import '../services/user_service.dart';
import '../widgets/app_skeleton_box.dart';
import '../widgets/app_meta_chip.dart';
import 'documents_admin_screen.dart';

class DocumentsSstScreen extends StatefulWidget {
  const DocumentsSstScreen({super.key});

  @override
  State<DocumentsSstScreen> createState() => _DocumentsSstScreenState();
}

class _DocumentsSstScreenState extends State<DocumentsSstScreen> {
  final SstDocumentService _service = SstDocumentService();
  final UserService _userService = UserService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

  String _query = '';
  String _selectedCategory = 'Todas';
  Stream<QuerySnapshot<Map<String, dynamic>>>? _globalStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _institutionStream;
  bool _loading = true;
  String? _error;
  String? _role;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = _auth.currentUser?.uid;
      String? role;
      String? institutionId;
      if (uid != null && uid.isNotEmpty) {
        role = await _userService.getUserRole(uid);
        institutionId = await _userService.getUserInstitutionId(uid);
      }
      if (!mounted) return;
      setState(() {
        _role = role;
        _globalStream = _service.streamPublishedGlobalDocuments();
        _institutionStream =
            institutionId == null || institutionId.trim().isEmpty
            ? null
            : _service.streamPublishedInstitutionDocuments();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Documentos SST')),
        body: _buildDocumentsSkeleton(),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Documentos SST')),
        body: _buildErrorState(
          title: 'No se pudieron cargar los documentos',
          subtitle: _error!,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Documentos SST')),
      body: RefreshIndicator(
        onRefresh: _bootstrap,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _globalStream,
          builder: (context, globalSnap) {
            if (globalSnap.hasError) {
              return _buildErrorState(
                title: 'Error al consultar documentos globales',
                subtitle: globalSnap.error.toString(),
              );
            }
            if (globalSnap.connectionState == ConnectionState.waiting &&
                !globalSnap.hasData) {
              return _buildDocumentsSkeleton();
            }

            final globalDocs = globalSnap.data?.docs ?? const [];
            if (_institutionStream == null) {
              return _buildDocumentsList(
                globalDocs: globalDocs,
                institutionDocs:
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
              );
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _institutionStream,
              builder: (context, institutionSnap) {
                if (institutionSnap.hasError) {
                  return _buildErrorState(
                    title: 'Error al consultar documentos institucionales',
                    subtitle: institutionSnap.error.toString(),
                  );
                }
                if (institutionSnap.connectionState ==
                        ConnectionState.waiting &&
                    !institutionSnap.hasData) {
                  return _buildDocumentsSkeleton();
                }

                final institutionDocs = institutionSnap.data?.docs ?? const [];
                return _buildDocumentsList(
                  globalDocs: globalDocs,
                  institutionDocs: institutionDocs,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildDocumentsList({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> globalDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> institutionDocs,
  }) {
    final entries =
        <_DocumentEntry>[
          ...globalDocs.map((doc) => _DocumentEntry(doc: doc, isGlobal: true)),
          ...institutionDocs.map(
            (doc) => _DocumentEntry(doc: doc, isGlobal: false),
          ),
        ]..sort((a, b) {
          final aData = a.doc.data();
          final bData = b.doc.data();
          final aTs =
              (aData['publishedAt'] as Timestamp?) ??
              (aData['createdAt'] as Timestamp?);
          final bTs =
              (bData['publishedAt'] as Timestamp?) ??
              (bData['createdAt'] as Timestamp?);
          final aDate = aTs?.toDate();
          final bDate = bTs?.toDate();
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return bDate.compareTo(aDate);
        });

    final categories = <String>{
      'Todas',
      ...entries
          .map(
            (entry) => (entry.doc.data()['category'] ?? '').toString().trim(),
          )
          .where((value) => value.isNotEmpty),
    }.toList();

    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = entries.where((entry) {
      final data = entry.doc.data();
      final title = (data['title'] ?? '').toString().toLowerCase();
      final description = (data['description'] ?? '').toString().toLowerCase();
      final category = (data['category'] ?? '').toString();
      final matchCategory =
          _selectedCategory == 'Todas' || category == _selectedCategory;
      final matchQuery =
          normalizedQuery.isEmpty ||
          title.contains(normalizedQuery) ||
          description.contains(normalizedQuery);
      return matchCategory && matchQuery;
    }).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _buildFiltersPanel(categories),
        const SizedBox(height: 14),
        if (entries.isEmpty)
          _buildEmptyState(
            icon: Icons.menu_book_outlined,
            iconSize: 72,
            title: 'No hay documentos disponibles',
            subtitle:
                'Tu institución aún no ha publicado normativa SST y no hay documentos generales visibles.',
            actionLabel: _canPublishDocument
                ? 'Publicar primer documento'
                : null,
            onAction: _canPublishDocument
                ? () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const AdminDocumentsScreen(openCreateOnStart: true),
                      ),
                    );
                  }
                : null,
            secondaryActionLabel: 'Actualizar',
            onSecondaryAction: _bootstrap,
          )
        else if (filtered.isEmpty)
          _buildEmptyState(
            icon: Icons.search_off_outlined,
            iconSize: 56,
            title: 'Sin resultados para tu busqueda',
            subtitle: 'Prueba con otro filtro o termino de busqueda.',
            secondaryActionLabel: 'Limpiar filtros',
            onSecondaryAction: () {
              setState(() {
                _query = '';
                _selectedCategory = 'Todas';
              });
            },
          )
        else ...[
          _buildCollectionCaption(filtered.length),
          const SizedBox(height: 12),
          ...filtered.map(_buildDocumentCard),
        ],
      ],
    );
  }

  Widget _buildDocumentCard(_DocumentEntry entry) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final document = SstDocumentModel.fromDoc(entry.doc);
    final displayDate = (document.publishedAt ?? document.createdAt)?.toDate();
    final fileSizeText = document.fileSizeKb > 0
        ? '${document.fileSizeKb} KB'
        : 'Tamano no disponible';
    final accent = entry.isGlobal ? scheme.secondary : scheme.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf_outlined,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppMetaChip(
                        icon: entry.isGlobal
                            ? Icons.public_outlined
                            : Icons.school_outlined,
                        label: entry.isGlobal
                            ? 'Normativa general'
                            : 'Mi institución',
                        background: accent.withValues(alpha: 0.1),
                        foreground: accent,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        document.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      if (document.fileName.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(
                              alpha: 0.28,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                          child: Text(
                            document.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip(document.category, Icons.bookmark_outline),
                          _chip(fileSizeText, Icons.sd_storage_outlined),
                          _chip(
                            displayDate != null
                                ? '${document.isPublished ? 'Publicado' : 'Creado'}: ${_dateFormat.format(displayDate)}'
                                : 'Sin fecha',
                            Icons.calendar_month_outlined,
                          ),
                          if (document.isRequired)
                            _chip('Obligatorio', Icons.priority_high_rounded),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (document.description.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.notes_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        document.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _service.streamMyReadStatus(
                document.id,
                isGlobal: entry.isGlobal,
              ),
              builder: (context, readSnap) {
                final readData = readSnap.data?.data();
                final isRead = readData?['read'] == true;
                final readAt = readData?['readAt'] as Timestamp?;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.42,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Row(
                        children: [
                          _readStateChip(isRead),
                          if (isRead && readAt != null) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Leido: ${DateFormat('dd/MM/yyyy HH:mm').format(readAt.toDate())}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.18,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Acciones del documento',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () => _withTapFeedback(
                                  () => _openUrl(
                                    document.fileUrl,
                                    mode: LaunchMode.inAppBrowserView,
                                  ),
                                ),
                                icon: const Icon(Icons.visibility_outlined),
                                label: const Text('Ver'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _withTapFeedback(
                                  () => _openUrl(
                                    document.fileUrl,
                                    mode: LaunchMode.externalApplication,
                                  ),
                                ),
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('Descargar'),
                              ),
                              OutlinedButton.icon(
                                onPressed: isRead
                                    ? null
                                    : () => _withTapFeedback(
                                        () => _markAsRead(
                                          document.id,
                                          isGlobal: entry.isGlobal,
                                        ),
                                      ),
                                icon: Icon(
                                  isRead
                                      ? Icons.check_circle_outline
                                      : Icons.check_circle,
                                ),
                                label: Text(isRead ? 'Leido' : 'Marcar leido'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersPanel(List<String> categories) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Buscar y filtrar',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Ubica rapidamente documentos por titulo o categoria.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Buscar por titulo',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('documents_filter_$_selectedCategory'),
            initialValue: categories.contains(_selectedCategory)
                ? _selectedCategory
                : 'Todas',
            items: categories
                .map(
                  (value) => DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedCategory = value);
            },
            decoration: const InputDecoration(
              labelText: 'Categoria',
              prefixIcon: Icon(Icons.filter_alt_outlined),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionCaption(int visibleCount) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Documentos disponibles',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                visibleCount == 1
                    ? '1 resultado visible'
                    : '$visibleCount resultados visibles',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        AppMetaChip(
          icon: Icons.schedule_outlined,
          label: 'Recientes primero',
          background: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          foreground: scheme.onSurfaceVariant,
        ),
      ],
    );
  }

  Widget _chip(String label, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return AppMetaChip(
      icon: icon,
      label: label,
      background: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      foreground: scheme.onSurfaceVariant,
    );
  }

  Widget _readStateChip(bool isRead) {
    final color = isRead ? Colors.green : Colors.grey;
    final label = isRead ? 'Leido' : 'Pendiente';
    return AppMetaChip(
      icon: isRead ? Icons.check_circle_rounded : Icons.schedule_outlined,
      label: label,
      background: color.withValues(alpha: 0.15),
      foreground: color,
      fontWeight: FontWeight.w700,
    );
  }

  Future<void> _withTapFeedback(Future<void> Function() action) async {
    HapticFeedback.selectionClick();
    await action();
  }

  Future<void> _markAsRead(String documentId, {required bool isGlobal}) async {
    try {
      await _service.markAsRead(documentId, isGlobal: isGlobal);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Documento marcado como leido.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo marcar como leido: $e')),
      );
    }
  }

  Future<void> _openUrl(String rawUrl, {required LaunchMode mode}) async {
    final uri = await _resolveDocumentUri(rawUrl);
    if (uri == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL de documento invalida.')),
      );
      return;
    }

    try {
      final opened = await launchUrl(uri, mode: mode);
      if (opened) {
        return;
      }

      if (mode == LaunchMode.inAppBrowserView) {
        final fallbackOpened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (fallbackOpened) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Se abrio el documento en una aplicacion externa.'),
            ),
          );
          return;
        }
      }

      await _copyDocumentLink(uri.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo abrir el documento. El enlace fue copiado al portapapeles.',
          ),
        ),
      );
    } catch (_) {
      await _copyDocumentLink(uri.toString());
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo abrir el documento. El enlace fue copiado al portapapeles.',
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

    try {
      if (trimmed.startsWith('gs://')) {
        final downloadUrl = await FirebaseStorage.instance
            .refFromURL(trimmed)
            .getDownloadURL();
        return Uri.tryParse(downloadUrl);
      }

      if (trimmed.startsWith('//')) {
        return Uri.tryParse('https:$trimmed');
      }

      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        return Uri.tryParse(trimmed);
      }

      return Uri.tryParse('https://$trimmed');
    } catch (_) {
      return null;
    }
  }

  Future<void> _copyDocumentLink(String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
    } catch (_) {}
  }

  Widget _buildDocumentsSkeleton() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeletonBox(
                height: 18,
                width: 180,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              SizedBox(height: 10),
              AppSkeletonBox(
                height: 12,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              SizedBox(height: 12),
              AppSkeletonBox(
                height: 28,
                width: 240,
                borderRadius: BorderRadius.all(Radius.circular(999)),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: const Column(
            children: [
              AppSkeletonBox(
                height: 56,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              SizedBox(height: 12),
              AppSkeletonBox(
                height: 56,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ],
          ),
        ),
        ...List.generate(
          3,
          (index) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeletonBox(
                      height: 44,
                      width: 44,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppSkeletonBox(
                            height: 16,
                            width: 180,
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                          SizedBox(height: 8),
                          AppSkeletonBox(
                            height: 12,
                            width: 120,
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                AppSkeletonBox(
                  height: 12,
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                SizedBox(height: 12),
                AppSkeletonBox(
                  height: 36,
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required String title,
    required String subtitle,
    required IconData icon,
    double iconSize = 56,
    String? actionLabel,
    VoidCallback? onAction,
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: iconSize + 20,
            width: iconSize + 20,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: iconSize, color: scheme.outline),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(actionLabel),
            ),
          ],
          if (secondaryActionLabel != null && onSecondaryAction != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onSecondaryAction,
              icon: const Icon(Icons.refresh),
              label: Text(secondaryActionLabel),
            ),
          ],
        ],
      ),
    );
  }

  bool get _canPublishDocument {
    return _role == 'admin' || _role == 'admin_sst';
  }

  Widget _buildErrorState({required String title, required String subtitle}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
      children: [
        Icon(
          Icons.error_outline,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _bootstrap,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      ],
    );
  }
}

class _DocumentEntry {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool isGlobal;

  const _DocumentEntry({required this.doc, required this.isGlobal});
}
