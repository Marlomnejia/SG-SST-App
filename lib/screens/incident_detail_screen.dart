import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'full_screen_image_screen.dart';
import 'create_action_plan_screen.dart';

class IncidentDetailScreen extends StatefulWidget {
  final QueryDocumentSnapshot eventDocument;

  const IncidentDetailScreen({super.key, required this.eventDocument});

  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen> {
  String? _selectedStatus;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.eventDocument['estado'];
  }

  Future<void> _updateStatus() async {
    if (_selectedStatus == null || _selectedStatus == widget.eventDocument['estado']) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await widget.eventDocument.reference.update({'estado': _selectedStatus});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Estado actualizado correctamente')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar el estado: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showUpdatePlanStatusDialog(DocumentSnapshot planDoc) {
    final planData = planDoc.data() as Map<String, dynamic>;
    String currentStatus = planData['estado'] ?? 'pendiente';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        String? newStatus = currentStatus;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Actualizar estado del plan'),
              content: DropdownButtonFormField<String>(
                value: newStatus,
                items: ['pendiente', 'realizado']
                    .map((label) => DropdownMenuItem(
                          value: label,
                          child: Text(label),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      newStatus = value;
                    });
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (newStatus != null && newStatus != currentStatus) {
                      planDoc.reference.update({'estado': newStatus});
                    }
                    Navigator.pop(context);
                  },
                  child: const Text('Actualizar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = widget.eventDocument.data() as Map<String, dynamic>;

    final String tipo = data['tipo'] ?? 'No especificado';
    final String descripcion = data['descripcion'] ?? 'Sin descripcion';
    final String reportadoPor = data['reportadoPor_email'] ?? 'Anonimo';
    final Timestamp timestamp = data['fechaReporte'] ?? Timestamp.now();
    final List<dynamic> fotoUrls = data['fotoUrls'] ?? [];
    final List<dynamic> videoUrls = data['videoUrls'] ?? [];
    final String categoria = data['categoria'] ?? 'No especificada';
    final String severidad = data['severidad'] ?? 'No especificada';
    final String lugar = data['lugar'] ?? 'No especificado';
    final Timestamp? fechaEvento = data['fechaEvento'] as Timestamp?;
    final GeoPoint? ubicacionGps = data['ubicacionGps'] as GeoPoint?;
    final String? direccionGps = data['direccionGps'] as String?;

    final DateTime fechaReporte = timestamp.toDate();
    final String fechaFormateada =
        DateFormat('dd/MM/yyyy, hh:mm a').format(fechaReporte);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del reporte'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Chip(
              label: Text(
                tipo.toUpperCase(),
                style: TextStyle(
                  color: tipo == 'Accidente' ? scheme.onError : scheme.onTertiary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: tipo == 'Accidente' ? scheme.error : scheme.tertiary,
            ),
            const SizedBox(height: 16.0),
            Text(
              descripcion,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16.0),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Reportado por'),
              subtitle: Text(reportadoPor),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Fecha del reporte'),
              subtitle: Text(fechaFormateada),
            ),
            if (fechaEvento != null)
              ListTile(
                leading: const Icon(Icons.event),
                title: const Text('Fecha del evento'),
                subtitle:
                    Text(DateFormat('dd/MM/yyyy, hh:mm a').format(fechaEvento.toDate())),
              ),
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: const Text('Lugar / area'),
              subtitle: Text(lugar),
            ),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Categoria'),
              subtitle: Text(categoria),
            ),
            ListTile(
              leading: const Icon(Icons.warning_amber_outlined),
              title: const Text('Severidad'),
              subtitle: Text(severidad),
            ),
            if (ubicacionGps != null || (direccionGps != null && direccionGps.isNotEmpty))
              ListTile(
                leading: const Icon(Icons.my_location),
                title: const Text('Ubicacion GPS'),
                subtitle: Text(
                  (direccionGps != null && direccionGps.isNotEmpty)
                      ? direccionGps
                      : 'Lat: ${ubicacionGps!.latitude.toStringAsFixed(5)}, Lng: ${ubicacionGps.longitude.toStringAsFixed(5)}',
                ),
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Estado actual'),
              subtitle: Text(widget.eventDocument['estado'] ?? 'desconocido'),
            ),
            const Divider(),
            const SizedBox(height: 16.0),
            if (fotoUrls.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fotos adjuntas:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8.0),
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: fotoUrls.length,
                      itemBuilder: (context, index) {
                        final url = fotoUrls[index] as String;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      FullScreenImageScreen(imageUrl: url),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8.0),
                              child: Image.network(
                                url,
                                fit: BoxFit.cover,
                                width: 150,
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(Icons.error);
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24.0),
                ],
              ),
            if (videoUrls.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Videos adjuntos:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8.0),
                  SizedBox(
                    height: 220,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: videoUrls.length,
                      itemBuilder: (context, index) {
                        final url = videoUrls[index] as String;
                        return Padding(
                          padding: const EdgeInsets.only(right: 12.0),
                          child: _NetworkVideoCard(url: url),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24.0),
                ],
              ),
            DropdownButtonFormField<String>(
              value: _selectedStatus,
              decoration: const InputDecoration(
                labelText: 'Actualizar estado',
                border: OutlineInputBorder(),
              ),
              items: ['reportado', 'en revision', 'solucionado']
                  .map((label) => DropdownMenuItem(
                        value: label,
                        child: Text(label),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedStatus = value;
                  });
                }
              },
            ),
            const SizedBox(height: 24.0),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _updateStatus,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                ),
                child: _isSaving
                    ? SizedBox(
                        height: 24,
                        width: 24,
                        child:
                            CircularProgressIndicator(color: scheme.onPrimary),
                      )
                    : const Text('Guardar cambios'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          CreateActionPlanScreen(eventId: widget.eventDocument.id),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                ),
                child: const Text('Crear plan de accion'),
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 10),
            Text(
              'Planes de accion asociados:',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('planesDeAccion')
                  .where('eventoId', isEqualTo: widget.eventDocument.id)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('No hay planes de accion para este evento.'),
                  );
                }

                final planDocs = snapshot.data!.docs;

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: planDocs.length,
                  itemBuilder: (context, index) {
                    final planDoc = planDocs[index];
                    final planData = planDoc.data() as Map<String, dynamic>;
                    final String estado = planData['estado'] ?? 'desconocido';

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      child: ListTile(
                        title: Text(planData['descripcion'] ?? 'Sin descripcion'),
                        subtitle: Text(
                          'Asignado a: ${planData['asignadoA'] ?? 'N/A'}\n'
                          'Limite: ${planData.containsKey('fechaLimite') && planData['fechaLimite'] != null ? DateFormat('dd/MM/yyyy').format((planData['fechaLimite'] as Timestamp).toDate()) : 'No especificada'}',
                        ),
                        trailing: Chip(
                          label: Text(
                            estado,
                            style: TextStyle(
                              color: estado == 'realizado'
                                  ? scheme.onSecondary
                                  : scheme.onTertiary,
                            ),
                          ),
                          backgroundColor:
                              estado == 'realizado' ? scheme.secondary : scheme.tertiary,
                        ),
                        onTap: () => _showUpdatePlanStatusDialog(planDoc),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkVideoCard extends StatefulWidget {
  final String url;

  const _NetworkVideoCard({required this.url});

  @override
  State<_NetworkVideoCard> createState() => _NetworkVideoCardState();
}

class _NetworkVideoCardState extends State<_NetworkVideoCard> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.setLooping(true);
    _controller.setVolume(0);
    _controller.initialize().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio:
                  _controller.value.isInitialized ? _controller.value.aspectRatio : 16 / 9,
              child: _controller.value.isInitialized
                  ? VideoPlayer(_controller)
                  : Container(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                    ),
            ),
            IconButton(
              icon: Icon(
                _controller.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
                size: 52,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  if (_controller.value.isPlaying) {
                    _controller.pause();
                  } else {
                    _controller.play();
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
