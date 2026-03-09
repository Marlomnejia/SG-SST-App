import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/user_service.dart';

class CreateActionPlanScreen extends StatefulWidget {
  final String eventId;

  const CreateActionPlanScreen({super.key, required this.eventId});

  @override
  State<CreateActionPlanScreen> createState() => _CreateActionPlanScreenState();
}

class _CreateActionPlanScreenState extends State<CreateActionPlanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final UserService _userService = UserService();

  DateTime? _startDate;
  DateTime? _dueDate;
  bool _isSaving = false;
  CurrentUserData? _currentUser;
  Future<CurrentUserData?>? _currentUserFuture;
  String? _responsibleUid;
  String? _responsibleName;
  String _actionType = 'correctiva';
  String _priority = 'media';

  @override
  void initState() {
    super.initState();
    _currentUserFuture = _userService.getCurrentUser();
    _startDate = DateTime.now();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _startDate) {
      setState(() {
        _startDate = picked;
        if (_dueDate != null && _dueDate!.isBefore(picked)) {
          _dueDate = picked;
        }
      });
    }
  }

  Future<void> _selectDueDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _dueDate ??
          _startDate?.add(const Duration(days: 3)) ??
          DateTime.now().add(const Duration(days: 3)),
      firstDate: _startDate ?? DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _dueDate) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _saveActionPlan() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa los campos obligatorios.')),
      );
      return;
    }
    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una fecha de inicio.')),
      );
      return;
    }
    if (_dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una fecha limite.')),
      );
      return;
    }
    if (_dueDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La fecha limite no puede ser anterior al inicio.'),
        ),
      );
      return;
    }
    if (_currentUser == null ||
        _currentUser!.uid.trim().isEmpty ||
        (_currentUser!.institutionId ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo identificar la institución del usuario.'),
        ),
      );
      return;
    }
    if ((_responsibleUid ?? '').trim().isEmpty ||
        (_responsibleName ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un responsable de la accion.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final trimmedTitle = _titleController.text.trim();
      final trimmedDescription = _descriptionController.text.trim();
      final planData = <String, dynamic>{
        'title': trimmedTitle,
        'description': trimmedDescription,
        'actionType': _actionType,
        'priority': _priority,
        'responsibleUid': _responsibleUid,
        'responsibleName': _responsibleName,
        'assignedBy': _currentUser!.uid,
        'institutionId': _currentUser!.institutionId,
        'startDate': Timestamp.fromDate(_startDate!),
        'dueDate': Timestamp.fromDate(_dueDate!),
        'status': 'pendiente',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'originReportId': widget.eventId,
        'verificationNote': null,
        'closureEvidence': null,
        'closureAttachments': <Map<String, dynamic>>[],
        'verificationStatus': 'pendiente',
        'executionNote': null,
        'executionEvidence': null,
        'executionAttachments': <Map<String, dynamic>>[],
        'executionUpdatedAt': null,
        'executionUpdatedBy': null,
        'progressHistory': <Map<String, dynamic>>[],
        'executedAt': null,
        'closedAt': null,
        'closedBy': null,
        // Compatibilidad con vistas legacy
        'tipoAccion': _actionType,
        'prioridad': _priority,
        'descripcion': trimmedDescription,
        'asignadoA': _responsibleName,
        'fechaInicio': Timestamp.fromDate(_startDate!),
        'fechaLimite': Timestamp.fromDate(_dueDate!),
        'estado': 'pendiente',
        'eventoId': widget.eventId,
      };

      await FirebaseFirestore.instance
          .collection('planesDeAccion')
          .add(planData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan de accion guardado correctamente.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar el plan de accion: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _ensureDefaultResponsible(List<_ResponsibleOption> options) {
    if (options.isEmpty) return;
    if (_responsibleUid != null &&
        options.any((option) => option.uid == _responsibleUid)) {
      return;
    }

    _ResponsibleOption? preferred;
    if (_currentUser != null) {
      for (final option in options) {
        if (option.uid == _currentUser!.uid) {
          preferred = option;
          break;
        }
      }
    }
    final selected = preferred ?? options.first;
    _responsibleUid = selected.uid;
    _responsibleName = selected.displayName;
  }

  List<_ResponsibleOption> _mapResponsibleOptions(QuerySnapshot snapshot) {
    return snapshot.docs
        .map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final uid = doc.id;
          final email = (data['email'] ?? '').toString().trim();
          final displayName = (data['displayName'] ?? '').toString().trim();
          final role = (data['role'] ?? 'user').toString().trim();
          final label = displayName.isNotEmpty
              ? displayName
              : (email.isNotEmpty ? email : 'Usuario');
          return _ResponsibleOption(
            uid: uid,
            displayName: label,
            role: role,
            email: email,
          );
        })
        .where((option) => option.uid.trim().isNotEmpty)
        .toList()
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo plan de accion')),
      body: FutureBuilder<CurrentUserData?>(
        future: _currentUserFuture,
        builder: (context, userSnap) {
          if (userSnap.connectionState == ConnectionState.waiting &&
              !userSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          _currentUser = userSnap.data;
          final institutionId = (_currentUser?.institutionId ?? '').trim();
          if (institutionId.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No se encontró una institución asociada al usuario actual.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            );
          }

          return StreamBuilder<QuerySnapshot>(
            stream: _userService.streamUsersByInstitution(institutionId),
            builder: (context, usersSnap) {
              if (usersSnap.connectionState == ConnectionState.waiting &&
                  !usersSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final options = usersSnap.hasData
                  ? _mapResponsibleOptions(usersSnap.data!)
                  : <_ResponsibleOption>[];
              _ensureDefaultResponsible(options);

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Trazabilidad SG-SST',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'El admin SST gestiona el plan y asigna un responsable real para ejecutar la accion correctiva o preventiva.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _SectionCard(
                        title: 'Definicion de la accion',
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _titleController,
                              decoration: const InputDecoration(
                                labelText: 'Titulo de la accion *',
                                hintText: 'Ej: Corregir senalizacion de salida',
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Ingresa un titulo.';
                                }
                                if (value.trim().length < 6) {
                                  return 'Usa un titulo mas descriptivo.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _descriptionController,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                labelText: 'Descripcion de la accion *',
                                hintText:
                                    'Describe que se debe hacer y por que.',
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Describe la accion.';
                                }
                                if (value.trim().length < 10) {
                                  return 'Minimo 10 caracteres.';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _SectionCard(
                        title: 'Clasificacion y prioridad',
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: _actionType,
                              decoration: const InputDecoration(
                                labelText: 'Tipo de accion *',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'correctiva',
                                  child: Text('Correctiva'),
                                ),
                                DropdownMenuItem(
                                  value: 'preventiva',
                                  child: Text('Preventiva'),
                                ),
                                DropdownMenuItem(
                                  value: 'mejora',
                                  child: Text('Mejora'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _actionType = value);
                              },
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _priority,
                              decoration: const InputDecoration(
                                labelText: 'Prioridad *',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'alta',
                                  child: Text('Alta'),
                                ),
                                DropdownMenuItem(
                                  value: 'media',
                                  child: Text('Media'),
                                ),
                                DropdownMenuItem(
                                  value: 'baja',
                                  child: Text('Baja'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _priority = value);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _SectionCard(
                        title: 'Responsable y cronograma',
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: _responsibleUid,
                              decoration: const InputDecoration(
                                labelText: 'Responsable de la accion *',
                                hintText:
                                    'Selecciona quien ejecutara la accion',
                              ),
                              items: options
                                  .map(
                                    (option) => DropdownMenuItem<String>(
                                      value: option.uid,
                                      child: Text(
                                        option.subtitle.isEmpty
                                            ? option.displayName
                                            : '${option.displayName} · ${option.subtitle}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: options.isEmpty
                                  ? null
                                  : (value) {
                                      _ResponsibleOption? selected;
                                      for (final option in options) {
                                        if (option.uid == value) {
                                          selected = option;
                                          break;
                                        }
                                      }
                                      setState(() {
                                        _responsibleUid = selected?.uid;
                                        _responsibleName =
                                            selected?.displayName;
                                      });
                                    },
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Selecciona un responsable.';
                                }
                                return null;
                              },
                            ),
                            if (options.isEmpty) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'No hay usuarios disponibles en la institución para asignar esta acción.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.error,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            ListTile(
                              title: const Text('Fecha de inicio *'),
                              subtitle: Text(
                                _startDate == null
                                    ? 'No seleccionada'
                                    : DateFormat(
                                        'dd/MM/yyyy',
                                      ).format(_startDate!),
                              ),
                              trailing: const Icon(Icons.play_circle_outline),
                              onTap: () => _selectStartDate(context),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: scheme.outlineVariant),
                              ),
                              tileColor: scheme.surface,
                            ),
                            const SizedBox(height: 12),
                            ListTile(
                              title: const Text('Fecha limite *'),
                              subtitle: Text(
                                _dueDate == null
                                    ? 'No seleccionada'
                                    : DateFormat(
                                        'dd/MM/yyyy',
                                      ).format(_dueDate!),
                              ),
                              trailing: const Icon(Icons.calendar_today),
                              onTap: () => _selectDueDate(context),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: scheme.outlineVariant),
                              ),
                              tileColor: scheme.surface,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _isSaving ? null : _saveActionPlan,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isSaving
                              ? SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    color: scheme.onPrimary,
                                  ),
                                )
                              : const Text('Guardar plan'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ResponsibleOption {
  final String uid;
  final String displayName;
  final String role;
  final String email;

  const _ResponsibleOption({
    required this.uid,
    required this.displayName,
    required this.role,
    required this.email,
  });

  String get subtitle {
    switch (role) {
      case 'admin_sst':
        return 'Admin SST';
      case 'admin':
        return 'Super admin';
      default:
        return email;
    }
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
