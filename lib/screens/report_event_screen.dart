import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:video_player/video_player.dart';
import '../services/event_service.dart';
import 'map_preview_screen.dart';

class ReportEventScreen extends StatefulWidget {
  const ReportEventScreen({Key? key}) : super(key: key);

  @override
  _ReportEventScreenState createState() => _ReportEventScreenState();
}

class _ReportEventScreenState extends State<ReportEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final EventService _eventService = EventService();
  final ImagePicker _picker = ImagePicker();

  String _selectedType = 'Incidente';
  String _selectedCategory = 'Condicion insegura';
  String _selectedSeverity = 'Leve';
  DateTime? _eventDateTime;
  double? _latitude;
  double? _longitude;
  String? _gpsAddress;
  bool _isLocating = false;
  List<XFile> _selectedImages = [];
  List<XFile> _selectedVideos = [];
  final List<VideoPlayerController> _videoControllers = [];
  bool _isLoading = false;

  Future<void> _pickImageFromCamera() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      setState(() {
        _selectedImages.add(pickedFile);
      });
    }
  }

  Future<void> _pickImagesFromGallery() async {
    final List<XFile> pickedFiles = await _picker.pickMultiImage();
    if (pickedFiles.isNotEmpty) {
      setState(() {
        _selectedImages.addAll(pickedFiles);
      });
    }
  }

  Future<void> _pickVideoFromCamera() async {
    final XFile? pickedFile = await _picker.pickVideo(source: ImageSource.camera);
    if (pickedFile != null) {
      await _addVideo(pickedFile);
    }
  }

  Future<void> _pickVideoFromGallery() async {
    final XFile? pickedFile = await _picker.pickVideo(source: ImageSource.gallery);
    if (pickedFile != null) {
      await _addVideo(pickedFile);
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _removeVideo(int index) {
    setState(() {
      _selectedVideos.removeAt(index);
      _videoControllers[index].dispose();
      _videoControllers.removeAt(index);
    });
  }

  Future<void> _submitReport() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isLoading = true;
      });

      try {
        await _eventService.addEvent(
          _selectedType,
          _descriptionController.text,
          _selectedImages,
          videos: _selectedVideos,
          location: _locationController.text.trim(),
          category: _selectedCategory,
          severity: _selectedSeverity,
          eventDateTime: _eventDateTime,
          latitude: _latitude,
          longitude: _longitude,
          gpsAddress: _gpsAddress,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reporte enviado con exito.'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _descriptionController.clear();
          _locationController.clear();
          _selectedImages.clear();
          _selectedVideos.clear();
          for (final controller in _videoControllers) {
            controller.dispose();
          }
          _videoControllers.clear();
          _eventDateTime = null;
          _latitude = null;
          _longitude = null;
          _gpsAddress = null;
        });
        Navigator.of(context).pop();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar el reporte: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _locationController.dispose();
    for (final controller in _videoControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickEventDateTime() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _eventDateTime ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (date == null) {
      return;
    }
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_eventDateTime ?? DateTime.now()),
    );
    if (time == null) {
      return;
    }
    setState(() {
      _eventDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _captureLocation() async {
    setState(() {
      _isLocating = true;
    });

    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage('Activa la ubicacion del dispositivo.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showMessage('Permiso de ubicacion denegado.');
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      String? address;
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final parts = [
            place.street,
            place.subLocality,
            place.locality,
            place.administrativeArea,
          ].where((value) => value != null && value!.trim().isNotEmpty).toList();
          if (parts.isNotEmpty) {
            address = parts.map((e) => e!).join(', ');
          }
        }
      } catch (_) {
        address = null;
      }

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _gpsAddress = address;
      });
    } catch (e) {
      _showMessage('No se pudo obtener la ubicacion.');
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _addVideo(XFile file) async {
    final controller = VideoPlayerController.file(File(file.path));
    await controller.setVolume(0);
    await controller.initialize();
    controller.setLooping(true);
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() {
      _selectedVideos.add(file);
      _videoControllers.add(controller);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportar evento'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Campos obligatorios *',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              _SectionHeader(
                title: 'Resumen del evento',
                subtitle: 'Registra la informacion basica y el contexto.',
                icon: Icons.assignment_outlined,
              ),
              const SizedBox(height: 12),
              _SectionCard(
                child: Column(
                  children: [
                    _buildSegmentedType(scheme),
                    const SizedBox(height: 16),
                    _buildCategorySeverityRow(),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: 'Lugar / area *',
                        hintText: 'Ej: Sede A, Laboratorio 2',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Ingresa el lugar del evento.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildDateTimeTile(scheme),
                    const SizedBox(height: 12),
                    _buildLocationTile(scheme),
                    if (_latitude != null && _longitude != null) ...[
                      const SizedBox(height: 12),
                      _buildMapPreview(),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionHeader(
                title: 'Descripcion y evidencia',
                subtitle: 'Detalla lo ocurrido y adjunta fotos si aplica.',
                icon: Icons.fact_check_outlined,
              ),
              const SizedBox(height: 12),
              _SectionCard(
                child: Column(
                  children: [
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Descripcion del evento *',
                        hintText: 'Describe detalladamente lo que sucedio...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 5,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Por favor, ingresa una descripcion.';
                        }
                        if (value.trim().length < 10) {
                          return 'Agrega mas detalle (minimo 10 caracteres).';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildMediaActions(),
                    const SizedBox(height: 12),
                    _buildVideoActions(),
                    const SizedBox(height: 16),
                    if (_selectedImages.isNotEmpty) _buildImagePreview(),
                    if (_selectedVideos.isNotEmpty) _buildVideoPreview(),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _isLoading ? null : _submitReport,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(),
                        )
                      : const Text('Enviar reporte'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentedType(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tipo de evento *',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _buildChipOption(
              label: 'Incidente',
              selected: _selectedType == 'Incidente',
              onTap: () => setState(() => _selectedType = 'Incidente'),
              scheme: scheme,
            ),
            _buildChipOption(
              label: 'Accidente',
              selected: _selectedType == 'Accidente',
              onTap: () => setState(() => _selectedType = 'Accidente'),
              scheme: scheme,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategorySeverityRow() {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _selectedCategory,
            decoration: const InputDecoration(
              labelText: 'Categoria *',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'Condicion insegura',
                child: Text('Condicion insegura'),
              ),
              DropdownMenuItem(
                value: 'Acto inseguro',
                child: Text('Acto inseguro'),
              ),
              DropdownMenuItem(
                value: 'Accidente',
                child: Text('Accidente'),
              ),
              DropdownMenuItem(
                value: 'Casi accidente',
                child: Text('Casi accidente'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedCategory = value;
                });
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _selectedSeverity,
            decoration: const InputDecoration(
              labelText: 'Severidad *',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'Leve', child: Text('Leve')),
              DropdownMenuItem(value: 'Moderada', child: Text('Moderada')),
              DropdownMenuItem(value: 'Grave', child: Text('Grave')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedSeverity = value;
                });
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDateTimeTile(ColorScheme scheme) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Fecha y hora del evento (opcional)'),
      subtitle: Text(
        _eventDateTime == null
            ? 'No seleccionada'
            : '${_eventDateTime!.day.toString().padLeft(2, '0')}/'
                '${_eventDateTime!.month.toString().padLeft(2, '0')}/'
                '${_eventDateTime!.year} '
                '${_eventDateTime!.hour.toString().padLeft(2, '0')}:'
                '${_eventDateTime!.minute.toString().padLeft(2, '0')}',
      ),
      trailing: Icon(Icons.calendar_today, color: scheme.primary),
      onTap: _pickEventDateTime,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
    );
  }

  Widget _buildLocationTile(ColorScheme scheme) {
    final String subtitle;
    if (_latitude == null || _longitude == null) {
      subtitle = 'No capturada';
    } else if (_gpsAddress != null && _gpsAddress!.isNotEmpty) {
      subtitle = _gpsAddress!;
    } else {
      subtitle =
          'Lat: ${_latitude!.toStringAsFixed(5)}, Lng: ${_longitude!.toStringAsFixed(5)}';
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Ubicacion GPS (opcional)'),
      subtitle: Text(subtitle),
      trailing: _isLocating
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.my_location, color: scheme.primary),
      onTap: _isLocating ? null : _captureLocation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
    );
  }

  Widget _buildMapPreview() {
    final center = LatLng(_latitude!, _longitude!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vista previa del mapa',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 180,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: center,
                zoom: 16,
              ),
              markers: {
                Marker(
                  markerId: const MarkerId('preview'),
                  position: center,
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
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MapPreviewScreen(
                    latitude: _latitude!,
                    longitude: _longitude!,
                    address: _gpsAddress,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.map_outlined),
            label: const Text('Ver mapa'),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaActions() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.camera_alt),
            label: const Text('Tomar foto'),
            onPressed: _pickImageFromCamera,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.photo_library),
            label: const Text('Galeria'),
            onPressed: _pickImagesFromGallery,
          ),
        ),
      ],
    );
  }

  Widget _buildVideoActions() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.videocam),
            label: const Text('Grabar video'),
            onPressed: _pickVideoFromCamera,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.video_library),
            label: const Text('Video'),
            onPressed: _pickVideoFromGallery,
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreview() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _selectedImages.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemBuilder: (context, index) {
        return Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(_selectedImages[index].path),
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: () => _removeImage(index),
                child: const CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVideoPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Videos adjuntos:',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _selectedVideos.length,
          itemBuilder: (context, index) {
            final file = _selectedVideos[index];
            final controller = _videoControllers[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      child: AspectRatio(
                        aspectRatio: controller.value.isInitialized
                            ? controller.value.aspectRatio
                            : 16 / 9,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (controller.value.isInitialized)
                              VideoPlayer(controller)
                            else
                              Container(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                              ),
                            IconButton(
                              icon: Icon(
                                controller.value.isPlaying
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_fill,
                                size: 48,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                setState(() {
                                  if (controller.value.isPlaying) {
                                    controller.pause();
                                  } else {
                                    controller.play();
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.videocam, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => _removeVideo(index),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildChipOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required ColorScheme scheme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? scheme.onPrimary : scheme.onSurface,
              ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          height: 40,
          width: 40,
          decoration: BoxDecoration(
            color: scheme.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}
