import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sst_document_model.dart';
import '../services/sst_document_service.dart';
import '../services/user_service.dart';
import '../widgets/app_meta_chip.dart';

class AdminDocumentsScreen extends StatefulWidget {
  final bool openCreateOnStart;

  const AdminDocumentsScreen({super.key, this.openCreateOnStart = false});

  @override
  State<AdminDocumentsScreen> createState() => _AdminDocumentsScreenState();
}

class _AdminDocumentsScreenState extends State<AdminDocumentsScreen> {
  final SstDocumentService _service = SstDocumentService();
  final UserService _userService = UserService();
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm');
  Stream<QuerySnapshot<Map<String, dynamic>>>? _stream;
  bool _loading = true;
  String? _error;
  String? _role;
  bool _didAutoOpenForm = false;

  bool get _manageGlobal => _role == 'admin';
  bool get _canManageDocuments => _role == 'admin' || _role == 'admin_sst';
  String get _screenTitle =>
      _manageGlobal ? 'Documentos globales SST' : 'Documentos SST';

  @override
  void initState() {
    super.initState();
    _bootstrap();
    if (widget.openCreateOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _didAutoOpenForm) return;
        _didAutoOpenForm = true;
        _openCreateForm();
      });
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final role = uid == null || uid.isEmpty
          ? null
          : await _userService.getUserRole(uid);
      final stream = _service.streamDocumentsForAdmin(
        isGlobal: role == 'admin',
      );
      if (!mounted) return;
      setState(() {
        _role = role;
        _stream = stream;
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
        appBar: AppBar(title: Text(_screenTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_screenTitle)),
        body: _buildErrorState(
          title: 'No se pudo cargar la gestion de documentos',
          subtitle: _error!,
        ),
      );
    }

    if (!_canManageDocuments) {
      return Scaffold(
        appBar: AppBar(title: Text(_screenTitle)),
        body: _buildErrorState(
          title: 'Sin permisos',
          subtitle: 'Tu rol actual no puede gestionar documentos SST.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_screenTitle)),
      body: RefreshIndicator(
        onRefresh: _bootstrap,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _buildErrorState(
                title: 'Error consultando documentos',
                subtitle: snapshot.error.toString(),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs =
                List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                  snapshot.data?.docs ?? const [],
                )..sort((a, b) {
                  final aData = a.data();
                  final bData = b.data();
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
            if (docs.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _buildScopeHeader(documentCount: 0),
                  const SizedBox(height: 20),
                  _buildEmptyStateCard(),
                ],
              );
            }

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: docs.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _buildScopeHeader(documentCount: docs.length),
                  );
                }
                if (index == 1) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildCollectionCaption(documentCount: docs.length),
                  );
                }

                final model = SstDocumentModel.fromDoc(docs[index - 2]);
                return _buildDocumentCard(model);
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateForm,
        icon: const Icon(Icons.upload_file_outlined),
        label: Text(_manageGlobal ? 'Subir global' : 'Subir documento'),
      ),
    );
  }

  Widget _buildScopeHeader({required int documentCount}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Color accent = _manageGlobal ? scheme.secondary : scheme.primary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.18),
            scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              _manageGlobal
                  ? Icons.library_books_outlined
                  : Icons.folder_special_outlined,
              color: accent,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppMetaChip(
                  icon: _manageGlobal
                      ? Icons.public_outlined
                      : Icons.school_outlined,
                  label: _manageGlobal
                      ? 'Alcance global'
                      : 'Gestión institucional',
                  background: accent.withValues(alpha: 0.12),
                  foreground: accent,
                ),
                const SizedBox(height: 10),
                Text(
                  _manageGlobal
                      ? 'Biblioteca normativa global'
                      : 'Biblioteca documental institucional',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _manageGlobal
                      ? 'Administra la documentación base que verán todas las instituciones.'
                      : 'Gestiona los documentos SST que consultarán los usuarios de tu institución.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _heroPill(
                      label: '$documentCount documento(s)',
                      icon: Icons.description_outlined,
                      color: accent,
                    ),
                    _manageGlobal
                        ? _heroPill(
                            label: 'Control centralizado',
                            icon: Icons.hub_outlined,
                            color: accent,
                          )
                        : _heroPill(
                            label: 'Visible para usuarios',
                            icon: Icons.groups_outlined,
                            color: accent,
                          ),
                    _heroPill(
                      label: 'Actualiza deslizando',
                      icon: Icons.swipe_down_outlined,
                      color: accent,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.52),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accent.withValues(alpha: 0.18)),
                  ),
                  child: Text(
                    _manageGlobal
                        ? 'Aquí centralizas la normativa base y su disponibilidad para todas las instituciones.'
                        : 'Aquí ordenas la biblioteca documental, el estado de publicación y la trazabilidad de lectura.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionCaption({required int documentCount}) {
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
                documentCount == 1
                    ? '1 elemento cargado'
                    : '$documentCount elementos cargados',
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
          label: 'Más recientes primero',
          background: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          foreground: scheme.onSurfaceVariant,
        ),
      ],
    );
  }

  Widget _buildEmptyStateCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = _manageGlobal ? scheme.secondary : scheme.primary;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            height: 68,
            width: 68,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.folder_copy_outlined, size: 34, color: accent),
          ),
          const SizedBox(height: 14),
          Text(
            _manageGlobal
                ? 'Aún no hay documentos globales'
                : 'Aún no hay documentos',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _manageGlobal
                ? 'Sube el primer documento base para todas las instituciones.'
                : 'Sube el primer documento para tu institución.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openCreateForm,
            icon: const Icon(Icons.upload_file),
            label: Text(
              _manageGlobal ? 'Subir documento global' : 'Subir documento',
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroPill({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(SstDocumentModel model) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final displayDate = (model.publishedAt ?? model.createdAt)?.toDate();
    final statusColor = model.isPublished ? Colors.green : scheme.outline;
    final statusLabel = model.isPublished ? 'Publicado' : 'Borrador';
    final accent = _manageGlobal ? scheme.secondary : scheme.primary;

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
                    color: Colors.red.withValues(alpha: 0.14),
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
                        icon: _manageGlobal
                            ? Icons.public_outlined
                            : Icons.school_outlined,
                        label: _manageGlobal ? 'General' : 'Mi institución',
                        background: accent.withValues(alpha: 0.1),
                        foreground: accent,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        model.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
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
                            color: scheme.outlineVariant.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Text(
                          model.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metaChip(model.category, Icons.category_outlined),
                _metaChip('${model.fileSizeKb} KB', Icons.sd_storage_outlined),
                _metaChip(
                  displayDate != null
                      ? '${model.isPublished ? 'Publicado' : 'Creado'}: ${_dateFormat.format(displayDate)}'
                      : 'Sin fecha',
                  Icons.calendar_today_outlined,
                ),
                if (model.isRequired)
                  _metaChip('Obligatorio', Icons.priority_high_rounded),
              ],
            ),
            if (model.description.trim().isNotEmpty) ...[
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
                        model.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
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
            StreamBuilder<int>(
              stream: _service.streamReadCount(
                model.id,
                isGlobal: _manageGlobal,
              ),
              builder: (context, readSnap) {
                final readCount = readSnap.data ?? 0;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.45,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.analytics_outlined,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Lecturas registradas: $readCount',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.18),
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
                      OutlinedButton.icon(
                        onPressed: () => _openEditForm(model),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _togglePublished(model),
                        icon: Icon(
                          model.isPublished
                              ? Icons.visibility_off_outlined
                              : Icons.publish_outlined,
                        ),
                        label: Text(
                          model.isPublished ? 'Despublicar' : 'Publicar',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _confirmDelete(model),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.error,
                          side: BorderSide(
                            color: scheme.error.withValues(alpha: 0.65),
                          ),
                        ),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Eliminar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(String label, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return AppMetaChip(
      icon: icon,
      label: label,
      background: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      foreground: scheme.onSurfaceVariant,
    );
  }

  Future<void> _openCreateForm() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _DocumentFormScreen(service: _service, manageGlobal: _manageGlobal),
      ),
    );
    if (changed == true) {
      await _bootstrap();
    }
  }

  Future<void> _openEditForm(SstDocumentModel model) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _DocumentFormScreen(
          service: _service,
          existing: model,
          manageGlobal: _manageGlobal,
        ),
      ),
    );
    if (changed == true) {
      await _bootstrap();
    }
  }

  Future<void> _togglePublished(SstDocumentModel model) async {
    try {
      await _service.setDocumentPublished(
        documentId: model.id,
        isPublished: !model.isPublished,
        isGlobal: _manageGlobal,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !model.isPublished
                ? 'Documento publicado correctamente.'
                : 'Documento despublicado.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cambiar el estado: $e')),
      );
    }
  }

  Future<void> _confirmDelete(SstDocumentModel model) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Eliminar documento'),
          content: Text('Se eliminara "${model.title}". ¿Deseas continuar?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true) return;

    try {
      await _service.deleteDocument(model.id, isGlobal: _manageGlobal);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Documento eliminado.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    }
  }

  Widget _buildErrorState({required String title, required String subtitle}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      children: [
        Icon(
          Icons.error_outline,
          size: 46,
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

class _DocumentFormScreen extends StatefulWidget {
  final SstDocumentService service;
  final SstDocumentModel? existing;
  final bool manageGlobal;

  const _DocumentFormScreen({
    required this.service,
    this.existing,
    required this.manageGlobal,
  });

  @override
  State<_DocumentFormScreen> createState() => _DocumentFormScreenState();
}

class _DocumentFormScreenState extends State<_DocumentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late SstDocumentCategory _category;
  late bool _isPublished;
  late bool _isRequired;
  PlatformFile? _selectedFile;
  bool _submitting = false;
  double _progress = 0;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    _category = existing != null
        ? SstDocumentCategory.fromValue(existing.category)
        : SstDocumentCategory.normativa;
    _isPublished = existing?.isPublished ?? false;
    _isRequired = existing?.isRequired ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actionLabel = widget.manageGlobal
        ? (_isEditing ? 'Guardar cambios globales' : 'Subir documento global')
        : (_isEditing ? 'Guardar cambios' : 'Subir documento');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.manageGlobal
              ? (_isEditing
                    ? 'Editar documento global'
                    : 'Subir documento global')
              : (_isEditing ? 'Editar documento' : 'Subir documento'),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 46,
                    width: 46,
                    decoration: BoxDecoration(
                      color:
                          (widget.manageGlobal
                                  ? scheme.secondary
                                  : scheme.primary)
                              .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      widget.manageGlobal
                          ? Icons.public_outlined
                          : Icons.folder_special_outlined,
                      color: widget.manageGlobal
                          ? scheme.secondary
                          : scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.manageGlobal
                              ? 'Documento base del sistema'
                              : 'Documento para tu institución',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.manageGlobal
                              ? 'Este archivo podrá ser consultado por usuarios de todas las instituciones cuando esté publicado.'
                              : 'Este archivo se publicará solo para los usuarios asociados a tu institución.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _FormSection(
              title: 'Informacion del documento',
              child: Column(
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Titulo',
                      prefixIcon: Icon(Icons.title_outlined),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'El titulo es obligatorio';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Descripcion',
                      prefixIcon: Icon(Icons.description_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'La descripcion es obligatoria';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<SstDocumentCategory>(
                    key: ValueKey('documents_form_category_${_category.name}'),
                    initialValue: _category,
                    decoration: const InputDecoration(
                      labelText: 'Categoria',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: SstDocumentCategory.values
                        .map(
                          (category) => DropdownMenuItem(
                            value: category,
                            child: Text(category.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _category = value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _FormSection(
              title: 'Archivo PDF',
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.35,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      title: Text(
                        _selectedFile?.name ??
                            widget.existing?.fileName ??
                            'Seleccionar PDF',
                      ),
                      subtitle: Text(
                        _selectedFile != null
                            ? '${(_selectedFile!.size / 1024).ceil()} KB'
                            : 'Tamano maximo: 10 MB',
                      ),
                      trailing: TextButton(
                        onPressed: _submitting ? null : _pickFile,
                        child: Text(
                          _selectedFile == null ? 'Elegir' : 'Cambiar',
                        ),
                      ),
                    ),
                  ),
                  if (!_isEditing)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Debes seleccionar un PDF para crear el documento.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _FormSection(
              title: 'Visibilidad y cumplimiento',
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Publicado'),
                    subtitle: Text(
                      widget.manageGlobal
                          ? 'Visible para todas las instituciones'
                          : 'Visible para usuarios de la institución',
                    ),
                    value: _isPublished,
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _isPublished = value),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Obligatorio'),
                    subtitle: const Text(
                      'Documento requerido para cumplimiento',
                    ),
                    value: _isRequired,
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _isRequired = value),
                  ),
                ],
              ),
            ),
            if (_submitting) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(value: _progress <= 0 ? null : _progress),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submitting ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    try {
      final file = await widget.service.pickPdf();
      if (file == null) return;
      setState(() => _selectedFile = file);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo seleccionar el PDF: $e')),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa los campos obligatorios.')),
      );
      return;
    }
    if (!_isEditing && _selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes seleccionar un archivo PDF.')),
      );
      return;
    }

    setState(() {
      _submitting = true;
      _progress = 0;
    });

    try {
      if (_isEditing) {
        await widget.service.updateDocument(
          documentId: widget.existing!.id,
          title: _titleController.text,
          description: _descriptionController.text,
          category: _category,
          isPublished: _isPublished,
          isRequired: _isRequired,
          isGlobal: widget.manageGlobal,
          replacementFile: _selectedFile,
          onProgress: (value) {
            if (!mounted) return;
            setState(() => _progress = value);
          },
        );
      } else {
        await widget.service.createDocument(
          title: _titleController.text,
          description: _descriptionController.text,
          category: _category,
          file: _selectedFile!,
          isPublished: _isPublished,
          isRequired: _isRequired,
          isGlobal: widget.manageGlobal,
          onProgress: (value) {
            if (!mounted) return;
            setState(() => _progress = value);
          },
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el documento: $e')),
      );
    }
  }
}

class _FormSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _FormSection({required this.title, required this.child});

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
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
