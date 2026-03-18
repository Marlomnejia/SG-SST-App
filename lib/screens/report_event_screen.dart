import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../services/event_service.dart';
import '../services/storage_service.dart';
import 'map_preview_screen.dart';
import 'report_submitted_screen.dart';

class ReportEventScreen extends StatefulWidget {
  const ReportEventScreen({super.key});
  @override
  State<ReportEventScreen> createState() => _ReportEventScreenState();
}

class _Evidence {
  final XFile file;
  final String type;
  VideoPlayerController? vc;
  _Evidence(this.file, this.type, [this.vc]);
}

class _ReportEventScreenState extends State<ReportEventScreen> {
  static const int _maxEvidence = 3;
  static const int _maxVideoBytes = 30 * 1024 * 1024;
  static const _reportTypes = [
    'Condicion insegura',
    'Acto inseguro',
    'Incidente (casi accidente)',
    'Accidente con lesion',
    'Emergencia / evento grave',
    'Riesgo psicosocial',
  ];
  static const _autoDerivedEventTypes = {
    'Condicion insegura',
    'Acto inseguro',
    'Incidente (casi accidente)',
    'Accidente con lesion',
    'Emergencia / evento grave',
    'Riesgo psicosocial',
  };

  final _eventService = EventService();
  final _picker = ImagePicker();
  final _k1 = GlobalKey<FormState>(), _k2 = GlobalKey<FormState>();
  final _desc = TextEditingController();
  final _wit = TextEditingController();
  final _place = TextEditingController();
  final _reference = TextEditingController();
  final _evidence = <_Evidence>[];

  int _step = 0;
  bool _loading = false,
      _locating = false,
      _graveShown = false,
      _hasWitness = false,
      _protocolAcknowledged = false;
  double _progress = 0;
  String _eventType = 'Incidente',
      _reportType = 'Condicion insegura',
      _severity = 'Leve';
  String _affType = 'Yo', _affCount = 'No aplica';
  String? _gpsAddress;
  DateTime? _protocolAcknowledgedAt;
  DateTime _dt = DateTime.now();
  double? _lat, _lng;
  List<String> _recentPlaces = [];

  @override
  void initState() {
    super.initState();
    _loadPlaceSuggestions();
  }

  @override
  void dispose() {
    _desc.dispose();
    _wit.dispose();
    _place.dispose();
    _reference.dispose();
    for (final e in _evidence) {
      e.vc?.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPlaceSuggestions() async {
    final values = await _eventService
        .getRecentPlaceSuggestionsForCurrentInstitution();
    if (mounted) setState(() => _recentPlaces = values);
  }

  void _msg(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  void _onReportType(String? v) {
    if (v == null) return;
    setState(() {
      _reportType = v;
      if (_autoDerivedEventTypes.contains(v)) {
        _eventType = _expectedEventType(v);
      }
    });
  }

  void _onSeverity(String v) {
    final wasSameSelection = _severity == v;
    setState(() {
      _severity = v;
      if (v != 'Grave') {
        _protocolAcknowledged = false;
        _protocolAcknowledgedAt = null;
        _graveShown = false;
      } else if (!wasSameSelection) {
        _protocolAcknowledged = false;
        _protocolAcknowledgedAt = null;
      }
    });
    if (v == 'Grave' && !_graveShown && !wasSameSelection) {
      _graveShown = true;
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Severidad grave'),
          content: const Text(
            'Activa el protocolo interno y notifica al responsable SG-SST. Antes de enviar deberas confirmar esta accion.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    }
  }

  String _normalizePlace(String raw) {
    return raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  bool _isValidPlaceName(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.length < 4 || cleaned.length > 100) return false;
    if (!RegExp(r'[A-Za-z0-9]').hasMatch(cleaned)) return false;
    if (RegExp(r'^[^A-Za-z0-9]+$').hasMatch(cleaned)) return false;
    return true;
  }

  bool _v1() {
    if (!(_k1.currentState?.validate() ?? false)) return false;
    if (!_isValidPlaceName(_place.text)) {
      _msg('Ingresa un Lugar / Area valido (4 a 100 caracteres).');
      return false;
    }
    if (_reference.text.trim().length > 120) {
      _msg('Referencia adicional: maximo 120 caracteres.');
      return false;
    }
    return true;
  }

  bool _v2() => _k2.currentState?.validate() ?? false;

  String _currentStepLabel() {
    switch (_step) {
      case 0:
        return 'Define el tipo, la ubicacion y la severidad.';
      case 1:
        return 'Completa fecha, descripcion y personas involucradas.';
      case 2:
        return 'Adjunta evidencia, captura GPS y envia.';
      default:
        return 'Completa la informacion del reporte.';
    }
  }

  Map<String, dynamic> _location() {
    final placeName = _place.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final reference = _reference.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return {
      'placeName': placeName,
      'placeNormalized': _normalizePlace(placeName),
      'reference': reference.isEmpty ? null : reference,
      'gps': (_lat != null && _lng != null) ? {'lat': _lat, 'lng': _lng} : null,
    };
  }

  Map<String, dynamic> _people() => {
    'affectedType': _affType,
    'affectedCount': _affCount,
    'hasWitnesses': _hasWitness,
    'witnesses': _hasWitness ? _wit.text.trim() : null,
    'protocolAcknowledged': _severity == 'Grave'
        ? _protocolAcknowledged
        : false,
    'protocolAcknowledgedAt':
        _severity == 'Grave' && _protocolAcknowledgedAt != null
        ? _protocolAcknowledgedAt!.toIso8601String()
        : null,
  };

  String _expectedEventType(String reportType) {
    switch (reportType) {
      case 'Accidente con lesion':
      case 'Emergencia / evento grave':
        return 'Accidente';
      case 'Condicion insegura':
      case 'Acto inseguro':
      case 'Incidente (casi accidente)':
      case 'Riesgo psicosocial':
        return 'Incidente';
      default:
        return _eventType;
    }
  }

  IconData _eventTypeIcon(String eventType) {
    return eventType == 'Accidente'
        ? Icons.health_and_safety_outlined
        : Icons.warning_amber_outlined;
  }

  Color _eventTypeTone(ColorScheme scheme, String eventType) {
    return eventType == 'Accidente'
        ? scheme.errorContainer.withValues(alpha: 0.7)
        : scheme.surfaceContainerHighest;
  }

  Color _eventTypeOnTone(ColorScheme scheme, String eventType) {
    return eventType == 'Accidente'
        ? scheme.onErrorContainer
        : scheme.onSurfaceVariant;
  }

  Future<bool> _ensureEventTypeConsistency() async {
    final expected = _expectedEventType(_reportType);
    if (_eventType == expected) {
      return true;
    }

    final shouldAutoCorrect = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Seleccion inconsistente'),
        content: const Text(
          'El tipo de evento no coincide con lo que estas reportando. Ajusta la seleccion para continuar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Revisar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Corregir automaticamente'),
          ),
        ],
      ),
    );

    if (shouldAutoCorrect == true && mounted) {
      setState(() => _eventType = expected);
      return true;
    }
    return false;
  }

  Future<bool> _ensureProtocolAcknowledgment() async {
    if (_severity != 'Grave' || _protocolAcknowledged) {
      return true;
    }

    bool confirmed = false;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Confirmacion de protocolo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'La severidad grave requiere activar el protocolo interno, notificar al responsable SG-SST y asegurar atencion inmediata.',
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: confirmed,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (value) =>
                    setDialogState(() => confirmed = value ?? false),
                title: const Text(
                  'Confirmo que debo activar el protocolo interno',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: confirmed
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );

    if (accepted == true && mounted) {
      setState(() {
        _protocolAcknowledged = true;
        _protocolAcknowledgedAt = DateTime.now();
      });
      return true;
    }
    return false;
  }

  Future<bool> _promptAttachmentRetry(String caseNumber) async {
    final retry = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Adjuntos pendientes'),
        content: Text(
          'El reporte $caseNumber se creo correctamente, pero no se pudieron subir algunos adjuntos. Puedes reintentarlo ahora o continuar con adjuntos pendientes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reintentar ahora'),
          ),
        ],
      ),
    );
    return retry == true;
  }

  String _formatDateTime(DateTime value) {
    final dd = value.day.toString().padLeft(2, '0');
    final mm = value.month.toString().padLeft(2, '0');
    final yyyy = value.year.toString();
    final hour24 = value.hour;
    final hour12 = ((hour24 + 11) % 12) + 1;
    final hh = hour12.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    return '$dd/$mm/$yyyy  $hh:$min $period';
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dt,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dt),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(alwaysUse24HourFormat: false),
          child: Localizations.override(
            context: context,
            locale: const Locale('es', 'CO'),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
    if (t == null) return;
    setState(() => _dt = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _pickEvidenceMenu() async {
    if (_evidence.length >= _maxEvidence) {
      return _msg('Maximo $_maxEvidence evidencias.');
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Foto camara'),
              onTap: () {
                Navigator.pop(c);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Foto galeria'),
              onTap: () {
                Navigator.pop(c);
                _pickImages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video camara'),
              onTap: () {
                Navigator.pop(c);
                _pickVideo(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Video galeria'),
              onTap: () {
                Navigator.pop(c);
                _pickVideo(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource s) async {
    final f = await _picker.pickImage(
      source: s,
      imageQuality: 70,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (f == null || !mounted) return;
    setState(() => _evidence.add(_Evidence(f, 'image')));
  }

  Future<void> _pickImages() async {
    final left = _maxEvidence - _evidence.length;
    if (left <= 0) return;
    final files = await _picker.pickMultiImage(
      imageQuality: 70,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (files.isEmpty || !mounted) return;
    setState(
      () =>
          _evidence.addAll(files.take(left).map((f) => _Evidence(f, 'image'))),
    );
  }

  Future<void> _pickVideo(ImageSource s) async {
    final f = await _picker.pickVideo(source: s);
    if (f == null || !mounted) return;
    final size = await File(f.path).length();
    if (size > _maxVideoBytes) return _msg('Video maximo 30MB.');
    final vc = VideoPlayerController.file(File(f.path));
    await vc.initialize();
    vc.pause();
    if (!mounted) return vc.dispose();
    setState(() => _evidence.add(_Evidence(f, 'video', vc)));
  }

  void _removeEvidence(int i) {
    _evidence[i].vc?.dispose();
    setState(() => _evidence.removeAt(i));
  }

  Future<void> _captureGps() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _msg('Activa la ubicacion del dispositivo.');
        return;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        _msg('Permiso de ubicacion denegado.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      String? addr;
      try {
        final pm = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (pm.isNotEmpty) {
          addr =
              [pm.first.street, pm.first.locality, pm.first.administrativeArea]
                  .where((e) => e != null && e.trim().isNotEmpty)
                  .map((e) => e!)
                  .join(', ');
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
          _gpsAddress = addr;
        });
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _submit() async {
    if (!_v1() || !_v2()) return;
    if (!await _ensureEventTypeConsistency()) return;
    if (!mounted) return;
    if (!await _ensureProtocolAcknowledgment()) return;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _progress = 0;
    });
    try {
      final result = await _eventService.submitStructuredReport(
        eventType: _expectedEventType(_reportType),
        reportType: _reportType,
        severity: _severity,
        location: _location(),
        eventDateTime: _dt,
        description: _desc.text.trim(),
        people: _people(),
        latitude: _lat,
        longitude: _lng,
        gpsAddress: _gpsAddress,
        attachments: _evidence
            .map((e) => ReportAttachmentInput(file: e.file, type: e.type))
            .toList(),
        onUploadProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      var attachmentsPending = result.attachmentsPending;
      if (attachmentsPending && _evidence.isNotEmpty && mounted) {
        final retryNow = await _promptAttachmentRetry(result.caseNumber);
        if (retryNow && mounted) {
          try {
            setState(() => _progress = 0);
            await _eventService.retryPendingAttachments(
              reportId: result.reportId,
              attachments: _evidence
                  .map((e) => ReportAttachmentInput(file: e.file, type: e.type))
                  .toList(),
              onUploadProgress: (p) {
                if (mounted) setState(() => _progress = p);
              },
            );
            attachmentsPending = false;
          } catch (retryError) {
            _msg('No se pudieron subir los adjuntos. Quedaron pendientes.');
          }
        }
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ReportSubmittedScreen(
            caseNumber: result.caseNumber,
            attachmentsPending: attachmentsPending,
          ),
        ),
      );
    } catch (e) {
      _msg('Error al enviar: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildProgressHeader(ColorScheme scheme) {
    final completion = (_step + 1) / 3;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paso ${_step + 1} de 3',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _currentStepLabel(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: completion,
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeaderBadge(
                icon: _lat == null || _lng == null
                    ? Icons.location_searching_outlined
                    : Icons.my_location_outlined,
                label: _lat == null || _lng == null
                    ? 'GPS opcional'
                    : 'GPS capturado',
                background: _lat == null || _lng == null
                    ? null
                    : scheme.secondaryContainer,
                foreground: _lat == null || _lng == null
                    ? null
                    : scheme.onSecondaryContainer,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Reportar evento')),
      body: Column(
        children: [
          _buildProgressHeader(scheme),
          Expanded(
            child: Stepper(
              currentStep: _step,
              onStepContinue: _loading
                  ? null
                  : () async {
                      if (_step == 0 && !_v1()) return;
                      if (_step == 1 && !_v2()) return;
                      if (_step < 2) {
                        setState(() => _step++);
                      } else {
                        await _submit();
                      }
                    },
              onStepCancel: _loading
                  ? null
                  : () {
                      if (_step == 0) {
                        Navigator.pop(context);
                      } else {
                        setState(() => _step--);
                      }
                    },
              controlsBuilder: (_, d) => Row(
                children: [
                  FilledButton(
                    onPressed: d.onStepContinue,
                    child: Text(_step == 2 ? 'Enviar reporte' : 'Continuar'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: d.onStepCancel,
                    child: Text(_step == 0 ? 'Cancelar' : 'Atras'),
                  ),
                ],
              ),
              steps: [
                Step(
                  isActive: _step >= 0,
                  title: const Text('Tipo y ubicacion'),
                  subtitle: const Text('Que reportas y donde ocurrio'),
                  content: Form(
                    key: _k1,
                    child: Column(
                      children: [
                        if (_autoDerivedEventTypes.contains(_reportType))
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tipo de evento *',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: scheme.outlineVariant,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  color: scheme.surface,
                                ),
                                child: Row(
                                  children: [
                                    Chip(
                                      avatar: Icon(
                                        _eventTypeIcon(_eventType),
                                        size: 18,
                                        color: _eventTypeOnTone(
                                          scheme,
                                          _eventType,
                                        ),
                                      ),
                                      backgroundColor: _eventTypeTone(
                                        scheme,
                                        _eventType,
                                      ),
                                      side: BorderSide(
                                        color: _eventTypeOnTone(
                                          scheme,
                                          _eventType,
                                        ).withValues(alpha: 0.18),
                                      ),
                                      labelStyle: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: _eventTypeOnTone(
                                              scheme,
                                              _eventType,
                                            ),
                                            fontWeight: FontWeight.w600,
                                          ),
                                      label: Text(_eventType),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Se asigna automaticamente segun lo que estas reportando.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else
                          DropdownButtonFormField<String>(
                            initialValue: _eventType,
                            decoration: const InputDecoration(
                              labelText: 'Tipo de evento *',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Incidente',
                                child: Text('Incidente'),
                              ),
                              DropdownMenuItem(
                                value: 'Accidente',
                                child: Text('Accidente'),
                              ),
                            ],
                            onChanged: (v) => v == null
                                ? null
                                : setState(() => _eventType = v),
                          ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _reportType,
                          decoration: const InputDecoration(
                            labelText: '¿Que estas reportando? *',
                            border: OutlineInputBorder(),
                          ),
                          items: _reportTypes
                              .map(
                                (e) =>
                                    DropdownMenuItem(value: e, child: Text(e)),
                              )
                              .toList(),
                          onChanged: _onReportType,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: ['Leve', 'Moderada', 'Grave']
                              .map(
                                (v) => ChoiceChip(
                                  label: Text(v),
                                  selected: _severity == v,
                                  onSelected: (_) => _onSeverity(v),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _severity == 'Leve'
                              ? 'Leve: sin lesion y control inmediato.'
                              : _severity == 'Moderada'
                              ? 'Moderada: requiere seguimiento.'
                              : 'Grave: riesgo alto, activa protocolo.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        Autocomplete<String>(
                          optionsBuilder: (text) {
                            final query = text.text.trim().toLowerCase();
                            if (query.isEmpty) {
                              return _recentPlaces;
                            }
                            return _recentPlaces.where(
                              (e) => e.toLowerCase().contains(query),
                            );
                          },
                          onSelected: (value) => _place.text = value,
                          fieldViewBuilder:
                              (context, textController, focusNode, onSubmit) {
                                textController.text = _place.text;
                                textController.selection =
                                    TextSelection.fromPosition(
                                      TextPosition(
                                        offset: textController.text.length,
                                      ),
                                    );
                                textController.addListener(
                                  () => _place.text = textController.text,
                                );
                                return TextFormField(
                                  controller: textController,
                                  focusNode: focusNode,
                                  decoration: const InputDecoration(
                                    labelText: 'Lugar / Area *',
                                    hintText:
                                        'Ej: Salon 204, Laboratorio de quimica, Patio, Oficina de coordinacion',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Ingresa el lugar.';
                                    }
                                    if (!_isValidPlaceName(v)) {
                                      return 'Lugar invalido.';
                                    }
                                    return null;
                                  },
                                );
                              },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _reference,
                          maxLength: 120,
                          decoration: const InputDecoration(
                            labelText: 'Referencia adicional (opcional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Step(
                  isActive: _step >= 1,
                  title: const Text('Detalles y personas'),
                  subtitle: const Text('Fecha, descripcion y testigos'),
                  content: Form(
                    key: _k2,
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              Container(
                                height: 40,
                                width: 40,
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.schedule,
                                  color: scheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Fecha y hora del evento *',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatDateTime(_dt),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _pickDate,
                                icon: const Icon(
                                  Icons.edit_calendar_outlined,
                                  size: 18,
                                ),
                                label: const Text('Cambiar'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _desc,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Descripcion del evento *',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => v == null || v.trim().length < 10
                              ? 'Minimo 10 caracteres.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _affType,
                          decoration: const InputDecoration(
                            labelText: 'Persona afectada *',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Yo', child: Text('Yo')),
                            DropdownMenuItem(
                              value: 'Otra persona',
                              child: Text('Otra persona'),
                            ),
                            DropdownMenuItem(
                              value: 'No aplica',
                              child: Text('No aplica'),
                            ),
                          ],
                          onChanged: (v) =>
                              v == null ? null : setState(() => _affType = v),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _affCount,
                          decoration: const InputDecoration(
                            labelText: 'Numero de afectados (opcional)',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'No aplica',
                              child: Text('No aplica'),
                            ),
                            DropdownMenuItem(value: '1', child: Text('1')),
                            DropdownMenuItem(value: '2-5', child: Text('2-5')),
                            DropdownMenuItem(value: '>5', child: Text('>5')),
                          ],
                          onChanged: (v) =>
                              v == null ? null : setState(() => _affCount = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('¿Hubo testigos?'),
                          value: _hasWitness,
                          onChanged: (v) => setState(() => _hasWitness = v),
                        ),
                        if (_hasWitness)
                          TextFormField(
                            controller: _wit,
                            decoration: const InputDecoration(
                              labelText: 'Nombre testigo / nota',
                              hintText: 'Opcional: se registrara despues',
                              border: OutlineInputBorder(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Step(
                  isActive: _step >= 2,
                  title: const Text('Evidencia y GPS'),
                  subtitle: const Text('Adjuntos, ubicacion y envio'),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Evidencias (${_evidence.length}/$_maxEvidence)',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : _pickEvidenceMenu,
                          icon: const Icon(Icons.attach_file),
                          label: const Text('Adjuntar evidencia'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_evidence.isNotEmpty)
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _evidence.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 6,
                                mainAxisSpacing: 6,
                              ),
                          itemBuilder: (_, i) {
                            final e = _evidence[i];
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: e.type == 'image'
                                      ? Image.file(
                                          File(e.file.path),
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: double.infinity,
                                        )
                                      : Container(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                          child:
                                              e.vc != null &&
                                                  e.vc!.value.isInitialized
                                              ? FittedBox(
                                                  fit: BoxFit.cover,
                                                  child: SizedBox(
                                                    width:
                                                        e.vc!.value.size.width,
                                                    height:
                                                        e.vc!.value.size.height,
                                                    child: VideoPlayer(e.vc!),
                                                  ),
                                                )
                                              : const Center(
                                                  child: Icon(
                                                    Icons.videocam_outlined,
                                                  ),
                                                ),
                                        ),
                                ),
                                Positioned(
                                  right: 4,
                                  top: 4,
                                  child: GestureDetector(
                                    onTap: () => _removeEvidence(i),
                                    child: const CircleAvatar(
                                      radius: 10,
                                      backgroundColor: Colors.black54,
                                      child: Icon(
                                        Icons.close,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      const SizedBox(height: 12),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: scheme.outlineVariant),
                        ),
                        child: ListTile(
                          title: const Text('Ubicacion GPS'),
                          subtitle: Text(
                            _lat == null || _lng == null
                                ? 'Estado: no capturada'
                                : 'Estado: capturada',
                          ),
                          trailing: _locating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.my_location_outlined),
                          onTap: _locating ? null : _captureGps,
                        ),
                      ),
                      if (_gpsAddress != null && _gpsAddress!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _gpsAddress!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if (_lat != null && _lng != null)
                        Column(
                          children: [
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                height: 160,
                                child: GoogleMap(
                                  initialCameraPosition: CameraPosition(
                                    target: LatLng(_lat!, _lng!),
                                    zoom: 16,
                                  ),
                                  markers: {
                                    Marker(
                                      markerId: const MarkerId('r'),
                                      position: LatLng(_lat!, _lng!),
                                    ),
                                  },
                                  zoomControlsEnabled: false,
                                  myLocationEnabled: false,
                                  myLocationButtonEnabled: false,
                                  scrollGesturesEnabled: false,
                                  zoomGesturesEnabled: false,
                                  rotateGesturesEnabled: false,
                                  tiltGesturesEnabled: false,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MapPreviewScreen(
                                      latitude: _lat!,
                                      longitude: _lng!,
                                      address: _gpsAddress,
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.map_outlined),
                                label: const Text('Ver mapa'),
                              ),
                            ),
                          ],
                        ),
                      if (_loading) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: _progress),
                        const SizedBox(height: 4),
                        Text(
                          'Subiendo evidencia: ${(_progress * 100).toStringAsFixed(0)}%',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({
    required this.icon,
    required this.label,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final String label;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background ?? scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground ?? scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground ?? scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
